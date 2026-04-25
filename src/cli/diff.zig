const std = @import("std");

const mem = std.mem;

pub const DiffError = error{
    EmptyDiff,
    MalformedDiff,
    MultipleFiles,
    UnsupportedDiff,
    OutOfMemory,
};

pub const LineKind = enum {
    context,
    removal,
    addition,
};

pub const Line = struct {
    kind: LineKind,
    content: []const u8,
    marker: ?[]const u8 = null,
};

pub const Hunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: []Line,
};

pub const FileDiff = struct {
    header: []const []const u8,
    hunks: []Hunk,

    pub fn deinit(self: FileDiff, allocator: mem.Allocator) void {
        allocator.free(self.header);
        for (self.hunks) |hunk| {
            allocator.free(hunk.lines);
        }
        allocator.free(self.hunks);
    }
};

pub fn parse(allocator: mem.Allocator, input: []const u8) DiffError!FileDiff {
    if (mem.trim(u8, input, " \t\r\n").len == 0) return error.EmptyDiff;

    var header: std.ArrayList([]const u8) = .empty;
    defer header.deinit(allocator);

    var hunks: std.ArrayList(Hunk) = .empty;
    defer {
        for (hunks.items) |hunk| allocator.free(hunk.lines);
        hunks.deinit(allocator);
    }

    var current_lines: std.ArrayList(Line) = .empty;
    defer current_lines.deinit(allocator);

    var current_header: ?HunkHeader = null;
    var seen_file = false;

    var it = mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw_line| {
        if (raw_line.len == 0 and it.peek() == null) break;
        const line = mem.trim(u8, raw_line, "\r");

        if (mem.startsWith(u8, line, "diff --git ")) {
            if (seen_file) return error.MultipleFiles;
            seen_file = true;
            try header.append(allocator, line);
            continue;
        }

        if (!seen_file) return error.MalformedDiff;

        if (mem.startsWith(u8, line, "@@ ")) {
            if (current_header) |h| {
                try appendHunk(allocator, &hunks, h, current_lines.items);
                current_lines.clearRetainingCapacity();
            }
            current_header = try parseHunkHeader(line);
            continue;
        }

        if (current_header == null) {
            if (isUnsupportedHeader(line)) return error.UnsupportedDiff;
            try header.append(allocator, line);
            continue;
        }

        if (line.len == 0) return error.MalformedDiff;
        switch (line[0]) {
            ' ' => try current_lines.append(allocator, .{ .kind = .context, .content = line[1..] }),
            '-' => try current_lines.append(allocator, .{ .kind = .removal, .content = line[1..] }),
            '+' => try current_lines.append(allocator, .{ .kind = .addition, .content = line[1..] }),
            '\\' => {
                if (current_lines.items.len == 0) return error.MalformedDiff;
                current_lines.items[current_lines.items.len - 1].marker = line;
            },
            else => return error.MalformedDiff,
        }
    }

    if (current_header) |h| {
        try appendHunk(allocator, &hunks, h, current_lines.items);
        current_lines.clearRetainingCapacity();
    }

    if (hunks.items.len == 0) return error.UnsupportedDiff;

    const owned_header = try allocator.dupe([]const u8, header.items);
    errdefer allocator.free(owned_header);

    const owned_hunks = try allocator.dupe(Hunk, hunks.items);
    hunks.clearRetainingCapacity();

    return .{
        .header = owned_header,
        .hunks = owned_hunks,
    };
}

fn appendHunk(
    allocator: mem.Allocator,
    hunks: *std.ArrayList(Hunk),
    header: HunkHeader,
    lines: []const Line,
) !void {
    try hunks.append(allocator, .{
        .old_start = header.old_start,
        .old_count = header.old_count,
        .new_start = header.new_start,
        .new_count = header.new_count,
        .lines = try allocator.dupe(Line, lines),
    });
}

const HunkHeader = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
};

fn parseHunkHeader(line: []const u8) DiffError!HunkHeader {
    const end = mem.indexOfPos(u8, line, 3, " @@") orelse return error.MalformedDiff;
    const body = line[3..end];
    var parts = mem.splitScalar(u8, body, ' ');
    const old_part = parts.next() orelse return error.MalformedDiff;
    const new_part = parts.next() orelse return error.MalformedDiff;

    if (old_part.len < 2 or old_part[0] != '-') return error.MalformedDiff;
    if (new_part.len < 2 or new_part[0] != '+') return error.MalformedDiff;

    const old_range = try parseHeaderRange(old_part[1..]);
    const new_range = try parseHeaderRange(new_part[1..]);
    return .{
        .old_start = old_range.start,
        .old_count = old_range.count,
        .new_start = new_range.start,
        .new_count = new_range.count,
    };
}

const HeaderRange = struct {
    start: u32,
    count: u32,
};

fn parseHeaderRange(raw: []const u8) DiffError!HeaderRange {
    if (raw.len == 0) return error.MalformedDiff;
    if (mem.indexOfScalar(u8, raw, ',')) |comma| {
        return .{
            .start = std.fmt.parseInt(u32, raw[0..comma], 10) catch return error.MalformedDiff,
            .count = std.fmt.parseInt(u32, raw[comma + 1 ..], 10) catch return error.MalformedDiff,
        };
    }
    return .{
        .start = std.fmt.parseInt(u32, raw, 10) catch return error.MalformedDiff,
        .count = 1,
    };
}

fn isUnsupportedHeader(line: []const u8) bool {
    return mem.startsWith(u8, line, "Binary files ") or
        mem.eql(u8, line, "GIT binary patch") or
        mem.startsWith(u8, line, "rename from ") or
        mem.startsWith(u8, line, "rename to ") or
        mem.startsWith(u8, line, "copy from ") or
        mem.startsWith(u8, line, "copy to ") or
        mem.startsWith(u8, line, "deleted file mode ") or
        mem.startsWith(u8, line, "old mode ") or
        mem.startsWith(u8, line, "new mode ");
}

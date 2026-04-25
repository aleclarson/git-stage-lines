const std = @import("std");
const args = @import("args.zig");
const diff = @import("diff.zig");
const ranges = @import("ranges.zig");

const mem = std.mem;

pub const BuildResult = struct {
    patch: []const u8,
    selected_changes: u32,
    skipped_changes: u32,

    pub fn deinit(self: BuildResult, allocator: mem.Allocator) void {
        allocator.free(self.patch);
    }
};

const PatchLine = struct {
    tag: u8,
    content: []const u8,
    marker: ?[]const u8,
    old_line: ?u32,
    new_line: ?u32,
};

pub fn build(
    allocator: mem.Allocator,
    parsed: diff.FileDiff,
    selected_ranges: ranges.RangeSet,
    mode: args.Mode,
) !BuildResult {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var selected_changes: u32 = 0;
    var skipped_changes: u32 = 0;
    var selected_delta: i64 = 0;
    var wrote_header = false;

    for (parsed.hunks) |hunk| {
        var hunk_result = try buildHunk(allocator, hunk, selected_ranges, mode, selected_delta);
        defer hunk_result.deinit(allocator);

        selected_changes += hunk_result.selected_changes;
        skipped_changes += hunk_result.skipped_changes;
        selected_delta += hunk_result.delta;

        if (hunk_result.lines.len == 0) continue;

        if (!wrote_header) {
            try writeHeader(&out.writer, parsed.header);
            wrote_header = true;
        }

        try out.writer.print("@@ -{d}", .{hunk_result.old_start});
        if (hunk_result.old_count != 1) try out.writer.print(",{d}", .{hunk_result.old_count});
        try out.writer.print(" +{d}", .{hunk_result.new_start});
        if (hunk_result.new_count != 1) try out.writer.print(",{d}", .{hunk_result.new_count});
        try out.writer.writeAll(" @@\n");

        for (hunk_result.lines) |line| {
            try out.writer.writeByte(line.tag);
            try out.writer.writeAll(line.content);
            try out.writer.writeByte('\n');
            if (line.marker) |marker| {
                try out.writer.writeAll(marker);
                try out.writer.writeByte('\n');
            }
        }
    }

    return .{
        .patch = try out.toOwnedSlice(),
        .selected_changes = selected_changes,
        .skipped_changes = skipped_changes,
    };
}

const HunkBuild = struct {
    lines: []PatchLine,
    old_start: u32 = 0,
    old_count: u32 = 0,
    new_start: u32 = 0,
    new_count: u32 = 0,
    selected_changes: u32 = 0,
    skipped_changes: u32 = 0,
    delta: i64 = 0,

    fn deinit(self: HunkBuild, allocator: mem.Allocator) void {
        allocator.free(self.lines);
    }
};

fn buildHunk(
    allocator: mem.Allocator,
    hunk: diff.Hunk,
    selected_ranges: ranges.RangeSet,
    mode: args.Mode,
    incoming_delta: i64,
) !HunkBuild {
    var lines: std.ArrayList(PatchLine) = .empty;
    defer lines.deinit(allocator);

    var old_cursor = hunk.old_start;
    var new_cursor = addDelta(hunk.old_start, incoming_delta);
    var first_old: ?u32 = null;
    var first_new: ?u32 = null;
    var old_count: u32 = 0;
    var new_count: u32 = 0;
    var selected_changes: u32 = 0;
    var skipped_changes: u32 = 0;
    var delta: i64 = 0;

    var index: usize = 0;
    while (index < hunk.lines.len) {
        const line = hunk.lines[index];
        switch (line.kind) {
            .context => {
                try appendPatchLine(
                    allocator,
                    &lines,
                    .{ .tag = ' ', .content = line.content, .marker = line.marker, .old_line = old_cursor, .new_line = new_cursor },
                    &first_old,
                    &first_new,
                    &old_count,
                    &new_count,
                );
                old_cursor += 1;
                new_cursor += 1;
                index += 1;
            },
            .removal, .addition => {
                const block_start = index;
                var block_end = index;
                while (block_end < hunk.lines.len and hunk.lines[block_end].kind != .context) {
                    block_end += 1;
                }

                var selected = false;
                var scan_old = old_cursor;
                var scan_new = new_cursor;
                for (hunk.lines[block_start..block_end]) |change| {
                    switch (change.kind) {
                        .removal => {
                            if ((mode == .old or mode == .both) and selected_ranges.contains(scan_old)) selected = true;
                            scan_old += 1;
                        },
                        .addition => {
                            if ((mode == .new or mode == .both) and selected_ranges.contains(scan_new)) selected = true;
                            scan_new += 1;
                        },
                        .context => unreachable,
                    }
                }

                if (selected) {
                    selected_changes += 1;
                    for (hunk.lines[block_start..block_end]) |change| {
                        switch (change.kind) {
                            .removal => {
                                try appendPatchLine(
                                    allocator,
                                    &lines,
                                    .{ .tag = '-', .content = change.content, .marker = change.marker, .old_line = old_cursor, .new_line = null },
                                    &first_old,
                                    &first_new,
                                    &old_count,
                                    &new_count,
                                );
                                old_cursor += 1;
                                delta -= 1;
                            },
                            .addition => {
                                try appendPatchLine(
                                    allocator,
                                    &lines,
                                    .{ .tag = '+', .content = change.content, .marker = change.marker, .old_line = null, .new_line = new_cursor },
                                    &first_old,
                                    &first_new,
                                    &old_count,
                                    &new_count,
                                );
                                new_cursor += 1;
                                delta += 1;
                            },
                            .context => unreachable,
                        }
                    }
                } else {
                    skipped_changes += 1;
                    for (hunk.lines[block_start..block_end]) |change| {
                        switch (change.kind) {
                            .removal => {
                                try appendPatchLine(
                                    allocator,
                                    &lines,
                                    .{ .tag = ' ', .content = change.content, .marker = change.marker, .old_line = old_cursor, .new_line = new_cursor },
                                    &first_old,
                                    &first_new,
                                    &old_count,
                                    &new_count,
                                );
                                old_cursor += 1;
                                new_cursor += 1;
                            },
                            .addition => {},
                            .context => unreachable,
                        }
                    }
                }

                index = block_end;
            },
        }
    }

    if (selected_changes == 0) {
        return .{
            .lines = &.{},
            .selected_changes = 0,
            .skipped_changes = skipped_changes,
            .delta = 0,
        };
    }

    return .{
        .lines = try allocator.dupe(PatchLine, lines.items),
        .old_start = first_old orelse hunk.old_start,
        .old_count = old_count,
        .new_start = first_new orelse addDelta(hunk.old_start, incoming_delta),
        .new_count = new_count,
        .selected_changes = selected_changes,
        .skipped_changes = skipped_changes,
        .delta = delta,
    };
}

fn appendPatchLine(
    allocator: mem.Allocator,
    lines: *std.ArrayList(PatchLine),
    line: PatchLine,
    first_old: *?u32,
    first_new: *?u32,
    old_count: *u32,
    new_count: *u32,
) !void {
    if (first_old.* == null) {
        first_old.* = line.old_line orelse line.new_line;
    }
    if (first_new.* == null) {
        first_new.* = line.new_line orelse line.old_line;
    }

    if (line.tag != '+') old_count.* += 1;
    if (line.tag != '-') new_count.* += 1;
    try lines.append(allocator, line);
}

fn writeHeader(writer: *std.Io.Writer, header: []const []const u8) !void {
    for (header) |line| {
        if (mem.startsWith(u8, line, "index ") or
            mem.startsWith(u8, line, "diff --git ") or
            mem.startsWith(u8, line, "--- ") or
            mem.startsWith(u8, line, "+++ ") or
            mem.startsWith(u8, line, "new file mode "))
        {
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }
    }
}

fn addDelta(value: u32, delta: i64) u32 {
    const result = @as(i64, value) + delta;
    if (result <= 0) return 0;
    return @intCast(result);
}

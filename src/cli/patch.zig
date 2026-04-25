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
};

const PickedLine = struct {
    line: u32,
    content: []const u8,
    marker: ?[]const u8,
};

const OutputHunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: []PatchLine,
};

pub fn build(
    allocator: mem.Allocator,
    parsed: diff.FileDiff,
    selection: ranges.Selection,
    mode: args.Mode,
) !BuildResult {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var selected_changes: u32 = 0;
    var skipped_changes: u32 = 0;
    var selected_delta: i64 = 0;
    var wrote_header = false;

    for (parsed.hunks) |hunk| {
        var hunk_result = try buildHunks(allocator, hunk, selection, mode, selected_delta);
        defer hunk_result.deinit(allocator);

        selected_changes += hunk_result.selected_changes;
        skipped_changes += hunk_result.skipped_changes;
        selected_delta += hunk_result.delta;

        if (hunk_result.hunks.len == 0) continue;

        if (!wrote_header) {
            try writeHeader(&out.writer, parsed.header);
            wrote_header = true;
        }

        for (hunk_result.hunks) |output_hunk| {
            try out.writer.print("@@ -{d}", .{output_hunk.old_start});
            if (output_hunk.old_count != 1) try out.writer.print(",{d}", .{output_hunk.old_count});
            try out.writer.print(" +{d}", .{output_hunk.new_start});
            if (output_hunk.new_count != 1) try out.writer.print(",{d}", .{output_hunk.new_count});
            try out.writer.writeAll(" @@\n");

            for (output_hunk.lines) |line| {
                try out.writer.writeByte(line.tag);
                try out.writer.writeAll(line.content);
                try out.writer.writeByte('\n');
                if (line.marker) |marker| {
                    try out.writer.writeAll(marker);
                    try out.writer.writeByte('\n');
                }
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
    hunks: []OutputHunk,
    selected_changes: u32 = 0,
    skipped_changes: u32 = 0,
    delta: i64 = 0,

    fn deinit(self: HunkBuild, allocator: mem.Allocator) void {
        for (self.hunks) |hunk| {
            allocator.free(hunk.lines);
        }
        allocator.free(self.hunks);
    }
};

fn buildHunks(
    allocator: mem.Allocator,
    hunk: diff.Hunk,
    selection: ranges.Selection,
    mode: args.Mode,
    incoming_delta: i64,
) !HunkBuild {
    var deletions: std.ArrayList(PickedLine) = .empty;
    defer deletions.deinit(allocator);

    var additions: std.ArrayList(PickedLine) = .empty;
    defer additions.deinit(allocator);

    var output_hunks: std.ArrayList(OutputHunk) = .empty;
    defer {
        for (output_hunks.items) |output_hunk| allocator.free(output_hunk.lines);
        output_hunks.deinit(allocator);
    }

    const insertion_point = hunk.old_start;
    var old_cursor = hunk.old_start;
    var new_cursor = hunk.new_start;
    var selected_changes: u32 = 0;
    var skipped_changes: u32 = 0;

    var index: usize = 0;
    while (index < hunk.lines.len) {
        const line = hunk.lines[index];
        switch (line.kind) {
            .context => {
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

                var scan_old = old_cursor;
                var scan_new = new_cursor;
                var selected_old_lines: u32 = 0;
                var selected_new_lines: u32 = 0;
                var removal_count: u32 = 0;
                var addition_count: u32 = 0;

                for (hunk.lines[block_start..block_end]) |change| {
                    switch (change.kind) {
                        .removal => {
                            removal_count += 1;
                            if ((mode == .old or mode == .both) and selection.containsOld(scan_old)) {
                                selected_old_lines += 1;
                            }
                            scan_old += 1;
                        },
                        .addition => {
                            addition_count += 1;
                            if ((mode == .new or mode == .both) and selection.containsNew(scan_new)) {
                                selected_new_lines += 1;
                            }
                            scan_new += 1;
                        },
                        .context => unreachable,
                    }
                }

                const mixed_block = removal_count != 0 and addition_count != 0;
                const include_whole_block = !selection.exact and mixed_block and
                    (selected_old_lines != 0 or selected_new_lines != 0);

                for (hunk.lines[block_start..block_end]) |change| {
                    switch (change.kind) {
                        .removal => {
                            const selected = include_whole_block or
                                ((mode == .old or mode == .both) and selection.containsOld(old_cursor));
                            if (selected) {
                                try deletions.append(allocator, .{ .line = old_cursor, .content = change.content, .marker = change.marker });
                                selected_changes += 1;
                            } else if (mode == .old or mode == .both) {
                                skipped_changes += 1;
                            }
                            old_cursor += 1;
                        },
                        .addition => {
                            const selected = include_whole_block or
                                ((mode == .new or mode == .both) and selection.containsNew(new_cursor));
                            if (selected) {
                                try additions.append(allocator, .{ .line = new_cursor, .content = change.content, .marker = change.marker });
                                selected_changes += 1;
                            } else if (mode == .new or mode == .both) {
                                skipped_changes += 1;
                            }
                            new_cursor += 1;
                        },
                        .context => unreachable,
                    }
                }

                index = block_end;
            },
        }
    }

    if (selected_changes == 0) {
        return .{
            .hunks = &.{},
            .selected_changes = 0,
            .skipped_changes = skipped_changes,
            .delta = 0,
        };
    }

    const has_deletions = deletions.items.len != 0;
    const has_additions = additions.items.len != 0;

    if (!has_deletions and has_additions) {
        try output_hunks.append(allocator, try buildAdditionHunk(
            allocator,
            insertion_point,
            addDelta(insertion_point + 1, incoming_delta),
            additions.items,
        ));
    } else if (has_deletions and !has_additions) {
        try appendDeletionHunks(allocator, &output_hunks, deletions.items, incoming_delta);
    } else {
        try output_hunks.append(allocator, try buildMixedHunk(
            allocator,
            deletions.items,
            additions.items,
            incoming_delta,
        ));
    }

    const owned_hunks = try allocator.dupe(OutputHunk, output_hunks.items);
    output_hunks.clearRetainingCapacity();

    return .{
        .hunks = owned_hunks,
        .selected_changes = selected_changes,
        .skipped_changes = skipped_changes,
        .delta = @as(i64, @intCast(additions.items.len)) - @as(i64, @intCast(deletions.items.len)),
    };
}

fn buildAdditionHunk(
    allocator: mem.Allocator,
    old_start: u32,
    new_start: u32,
    additions: []const PickedLine,
) !OutputHunk {
    var lines: std.ArrayList(PatchLine) = .empty;
    defer lines.deinit(allocator);

    for (additions) |addition| {
        try lines.append(allocator, .{
            .tag = '+',
            .content = addition.content,
            .marker = addition.marker,
        });
    }

    return .{
        .old_start = old_start,
        .old_count = 0,
        .new_start = new_start,
        .new_count = @intCast(additions.len),
        .lines = try allocator.dupe(PatchLine, lines.items),
    };
}

fn appendDeletionHunks(
    allocator: mem.Allocator,
    output_hunks: *std.ArrayList(OutputHunk),
    deletions: []const PickedLine,
    incoming_delta: i64,
) !void {
    var start: usize = 0;
    var local_delta = incoming_delta;
    while (start < deletions.len) {
        var end = start + 1;
        while (end < deletions.len and deletions[end].line == deletions[end - 1].line + 1) {
            end += 1;
        }

        const group = deletions[start..end];
        try output_hunks.append(allocator, try buildDeletionHunk(allocator, group, local_delta));
        local_delta -= @intCast(group.len);
        start = end;
    }
}

fn buildDeletionHunk(
    allocator: mem.Allocator,
    deletions: []const PickedLine,
    incoming_delta: i64,
) !OutputHunk {
    var lines: std.ArrayList(PatchLine) = .empty;
    defer lines.deinit(allocator);

    for (deletions) |deletion| {
        try lines.append(allocator, .{
            .tag = '-',
            .content = deletion.content,
            .marker = deletion.marker,
        });
    }

    const old_start = deletions[0].line;
    return .{
        .old_start = old_start,
        .old_count = @intCast(deletions.len),
        .new_start = addDelta(old_start -| 1, incoming_delta),
        .new_count = 0,
        .lines = try allocator.dupe(PatchLine, lines.items),
    };
}

fn buildMixedHunk(
    allocator: mem.Allocator,
    deletions: []const PickedLine,
    additions: []const PickedLine,
    incoming_delta: i64,
) !OutputHunk {
    var lines: std.ArrayList(PatchLine) = .empty;
    defer lines.deinit(allocator);

    for (deletions) |deletion| {
        try lines.append(allocator, .{
            .tag = '-',
            .content = deletion.content,
            .marker = deletion.marker,
        });
    }
    for (additions) |addition| {
        try lines.append(allocator, .{
            .tag = '+',
            .content = addition.content,
            .marker = addition.marker,
        });
    }

    const old_start = deletions[0].line;
    return .{
        .old_start = old_start,
        .old_count = @intCast(deletions.len),
        .new_start = addDelta(old_start, incoming_delta),
        .new_count = @intCast(additions.len),
        .lines = try allocator.dupe(PatchLine, lines.items),
    };
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

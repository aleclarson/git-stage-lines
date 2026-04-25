const std = @import("std");

const mem = std.mem;

pub const DiffViewError = error{
    MalformedDiff,
};

const HunkHeader = struct {
    old_start: u32,
    new_start: u32,
};

pub fn write(writer: *std.Io.Writer, input: []const u8) !void {
    var current_file: ?[]const u8 = null;
    var printed_file: ?[]const u8 = null;
    var old_line: u32 = 0;
    var new_line: u32 = 0;
    var wrote_in_hunk = false;

    var it = mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw_line| {
        if (raw_line.len == 0 and it.peek() == null) break;
        const line = mem.trim(u8, raw_line, "\r");

        if (mem.startsWith(u8, line, "diff --git ")) {
            current_file = null;
            printed_file = null;
            wrote_in_hunk = false;
            continue;
        }

        if (mem.startsWith(u8, line, "+++ b/")) {
            current_file = line["+++ b/".len..];
            continue;
        }

        if (mem.startsWith(u8, line, "--- a/") and current_file == null) {
            current_file = line["--- a/".len..];
            continue;
        }

        if (mem.startsWith(u8, line, "@@ ")) {
            const header = try parseHunkHeader(line);
            old_line = header.old_start;
            new_line = header.new_start;
            if (wrote_in_hunk) try writer.writeByte('\n');
            wrote_in_hunk = false;
            continue;
        }

        if (line.len == 0) continue;
        switch (line[0]) {
            ' ' => {
                old_line += 1;
                new_line += 1;
            },
            '-' => {
                if (!mem.startsWith(u8, line, "--- ")) {
                    try ensureFileHeader(writer, current_file, &printed_file);
                    try writer.print("  -{d}:\t{s}\n", .{ old_line, line[1..] });
                    wrote_in_hunk = true;
                    old_line += 1;
                }
            },
            '+' => {
                if (!mem.startsWith(u8, line, "+++ ")) {
                    try ensureFileHeader(writer, current_file, &printed_file);
                    try writer.print("  +{d}:\t{s}\n", .{ new_line, line[1..] });
                    wrote_in_hunk = true;
                    new_line += 1;
                }
            },
            '\\' => if (wrote_in_hunk) {
                try writer.print("      {s}\n", .{line});
            },
            else => {},
        }
    }
}

fn ensureFileHeader(
    writer: *std.Io.Writer,
    current_file: ?[]const u8,
    printed_file: *?[]const u8,
) !void {
    const file = current_file orelse return error.MalformedDiff;
    if (printed_file.* == null) {
        try writer.print("{s}:\n", .{file});
        printed_file.* = file;
    }
}

fn parseHunkHeader(line: []const u8) DiffViewError!HunkHeader {
    const end = mem.indexOfPos(u8, line, 3, " @@") orelse return error.MalformedDiff;
    const body = line[3..end];
    var parts = mem.splitScalar(u8, body, ' ');
    const old_part = parts.next() orelse return error.MalformedDiff;
    const new_part = parts.next() orelse return error.MalformedDiff;

    if (old_part.len < 2 or old_part[0] != '-') return error.MalformedDiff;
    if (new_part.len < 2 or new_part[0] != '+') return error.MalformedDiff;

    return .{
        .old_start = try parseHeaderStart(old_part[1..]),
        .new_start = try parseHeaderStart(new_part[1..]),
    };
}

fn parseHeaderStart(raw: []const u8) DiffViewError!u32 {
    const head = if (mem.indexOfScalar(u8, raw, ',')) |comma| raw[0..comma] else raw;
    if (head.len == 0) return error.MalformedDiff;
    return std.fmt.parseInt(u32, head, 10) catch return error.MalformedDiff;
}

test "formats changed lines with old and new line numbers" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try write(&output.writer,
        \\diff --git a/file.txt b/file.txt
        \\index f384549..28edfb3 100644
        \\--- a/file.txt
        \\+++ b/file.txt
        \\@@ -1,4 +1,4 @@
        \\ one
        \\-two
        \\+TWO
        \\ three
        \\-four
        \\+FOUR
        \\
    );

    try std.testing.expectEqualStrings(
        "file.txt:\n" ++
            "  -2:\ttwo\n" ++
            "  +2:\tTWO\n" ++
            "  -4:\tfour\n" ++
            "  +4:\tFOUR\n",
        output.written(),
    );
}

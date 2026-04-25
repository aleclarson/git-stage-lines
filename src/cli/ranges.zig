const std = @import("std");

const mem = std.mem;

pub const RangeError = error{
    EmptyRanges,
    InvalidRange,
    InvalidNumber,
    ReversedRange,
    OutOfMemory,
    WriteFailed,
};

pub const Range = struct {
    start: u32,
    end: u32,

    pub fn contains(self: Range, line: u32) bool {
        return line >= self.start and line <= self.end;
    }
};

pub const RangeSet = struct {
    ranges: []Range,
    normalized: []const u8,

    pub fn deinit(self: RangeSet, allocator: mem.Allocator) void {
        allocator.free(self.ranges);
        allocator.free(self.normalized);
    }

    pub fn contains(self: RangeSet, line: u32) bool {
        for (self.ranges) |range| {
            if (range.contains(line)) return true;
        }
        return false;
    }
};

pub fn parse(allocator: mem.Allocator, input: []const u8) RangeError!RangeSet {
    const trimmed = mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRanges;

    var parsed: std.ArrayList(Range) = .empty;
    defer parsed.deinit(allocator);

    var normalized: std.Io.Writer.Allocating = .init(allocator);
    defer normalized.deinit();

    var parts = mem.splitScalar(u8, trimmed, ',');
    var first = true;
    while (parts.next()) |raw_part| {
        const part = mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) return error.InvalidRange;

        const dash_index = mem.indexOfScalar(u8, part, '-');
        const range = if (dash_index) |dash| blk: {
            if (dash == 0 or dash + 1 >= part.len) return error.InvalidRange;
            if (mem.indexOfScalar(u8, part[dash + 1 ..], '-') != null) return error.InvalidRange;

            const start = parseLine(part[0..dash]) catch |err| return err;
            const end = parseLine(part[dash + 1 ..]) catch |err| return err;
            if (start > end) return error.ReversedRange;

            break :blk Range{ .start = start, .end = end };
        } else blk: {
            const line = parseLine(part) catch |err| return err;
            break :blk Range{ .start = line, .end = line };
        };

        try parsed.append(allocator, range);

        if (!first) try normalized.writer.writeByte(',');
        first = false;
        if (range.start == range.end) {
            try normalized.writer.print("{d}", .{range.start});
        } else {
            try normalized.writer.print("{d}-{d}", .{ range.start, range.end });
        }
    }

    if (parsed.items.len == 0) return error.EmptyRanges;

    return .{
        .ranges = try allocator.dupe(Range, parsed.items),
        .normalized = try normalized.toOwnedSlice(),
    };
}

fn parseLine(raw: []const u8) RangeError!u32 {
    if (raw.len == 0) return error.InvalidNumber;
    for (raw) |byte| {
        if (byte < '0' or byte > '9') return error.InvalidNumber;
    }
    const value = std.fmt.parseInt(u32, raw, 10) catch return error.InvalidNumber;
    if (value == 0) return error.InvalidNumber;
    return value;
}

test "parse single and mixed ranges" {
    const allocator = std.testing.allocator;
    var set = try parse(allocator, "10, 15-20,22");
    defer set.deinit(allocator);

    try std.testing.expectEqualSlices(u8, "10,15-20,22", set.normalized);
    try std.testing.expect(set.contains(10));
    try std.testing.expect(set.contains(18));
    try std.testing.expect(!set.contains(21));
}

test "reject invalid ranges" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.EmptyRanges, parse(allocator, ""));
    try std.testing.expectError(error.InvalidNumber, parse(allocator, "0"));
    try std.testing.expectError(error.InvalidNumber, parse(allocator, "1.5"));
    try std.testing.expectError(error.ReversedRange, parse(allocator, "5-3"));
    try std.testing.expectError(error.InvalidRange, parse(allocator, "1,,2"));
}

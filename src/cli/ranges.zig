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

pub const Selection = struct {
    old_ranges: []Range,
    new_ranges: []Range,
    normalized: []const u8,

    pub fn deinit(self: Selection, allocator: mem.Allocator) void {
        allocator.free(self.old_ranges);
        allocator.free(self.new_ranges);
        allocator.free(self.normalized);
    }

    pub fn containsOld(self: Selection, line: u32) bool {
        return containsRange(self.old_ranges, line);
    }

    pub fn containsNew(self: Selection, line: u32) bool {
        return containsRange(self.new_ranges, line);
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

pub fn selectionFromRangeSet(
    allocator: mem.Allocator,
    range_set: RangeSet,
    include_old: bool,
    include_new: bool,
) !Selection {
    return .{
        .old_ranges = if (include_old) try allocator.dupe(Range, range_set.ranges) else &.{},
        .new_ranges = if (include_new) try allocator.dupe(Range, range_set.ranges) else &.{},
        .normalized = try allocator.dupe(u8, range_set.normalized),
    };
}

pub fn parseRefs(allocator: mem.Allocator, input: []const u8) RangeError!Selection {
    const trimmed = mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRanges;

    var old_ranges: std.ArrayList(Range) = .empty;
    defer old_ranges.deinit(allocator);

    var new_ranges: std.ArrayList(Range) = .empty;
    defer new_ranges.deinit(allocator);

    var normalized: std.Io.Writer.Allocating = .init(allocator);
    defer normalized.deinit();

    var parts = mem.splitScalar(u8, trimmed, ',');
    var first = true;
    while (parts.next()) |raw_part| {
        const part = mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) return error.InvalidRange;

        const parsed = try parseRef(part);
        if (parsed.old_side) {
            try old_ranges.append(allocator, parsed.range);
        } else {
            try new_ranges.append(allocator, parsed.range);
        }

        if (!first) try normalized.writer.writeByte(',');
        first = false;
        try writeRef(&normalized.writer, parsed);
    }

    if (old_ranges.items.len == 0 and new_ranges.items.len == 0) return error.EmptyRanges;

    return .{
        .old_ranges = try allocator.dupe(Range, old_ranges.items),
        .new_ranges = try allocator.dupe(Range, new_ranges.items),
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

const ParsedRef = struct {
    old_side: bool,
    range: Range,
};

fn parseRef(input: []const u8) RangeError!ParsedRef {
    if (mem.indexOf(u8, input, "..")) |dots| {
        const start_raw = input[0..dots];
        const end_raw = input[dots + 2 ..];
        if (start_raw.len == 0 or end_raw.len == 0) return error.InvalidRange;

        const old_side = start_raw[0] == '-';
        if ((end_raw[0] == '-') != old_side) return error.InvalidRange;

        const start = if (old_side) try parseSignedOldLine(start_raw) else try parseLine(start_raw);
        const end = if (old_side) try parseSignedOldLine(end_raw) else try parseLine(end_raw);
        if (start > end) return error.ReversedRange;

        return .{ .old_side = old_side, .range = .{ .start = start, .end = end } };
    }

    if (input[0] == '-') {
        const line = try parseSignedOldLine(input);
        return .{ .old_side = true, .range = .{ .start = line, .end = line } };
    }

    if (mem.indexOfScalar(u8, input, '-')) |dash| {
        if (dash == 0 or dash + 1 >= input.len) return error.InvalidRange;
        if (mem.indexOfScalar(u8, input[dash + 1 ..], '-') != null) return error.InvalidRange;

        const start = try parseLine(input[0..dash]);
        const end = try parseLine(input[dash + 1 ..]);
        if (start > end) return error.ReversedRange;

        return .{ .old_side = false, .range = .{ .start = start, .end = end } };
    }

    const line = try parseLine(input);
    return .{ .old_side = false, .range = .{ .start = line, .end = line } };
}

fn parseSignedOldLine(raw: []const u8) RangeError!u32 {
    if (raw.len < 2 or raw[0] != '-') return error.InvalidRange;
    return parseLine(raw[1..]);
}

fn writeRef(writer: *std.Io.Writer, ref: ParsedRef) !void {
    if (ref.old_side) {
        if (ref.range.start == ref.range.end) {
            try writer.print("-{d}", .{ref.range.start});
        } else {
            try writer.print("-{d}..-{d}", .{ ref.range.start, ref.range.end });
        }
    } else if (ref.range.start == ref.range.end) {
        try writer.print("{d}", .{ref.range.start});
    } else {
        try writer.print("{d}-{d}", .{ ref.range.start, ref.range.end });
    }
}

fn containsRange(items: []Range, line: u32) bool {
    for (items) |range| {
        if (range.contains(line)) return true;
    }
    return false;
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

test "parse signed file refs selection" {
    const allocator = std.testing.allocator;
    var selection = try parseRefs(allocator, "-10,12,20-22,-30..-31");
    defer selection.deinit(allocator);

    try std.testing.expectEqualSlices(u8, "-10,12,20-22,-30..-31", selection.normalized);
    try std.testing.expect(selection.containsOld(10));
    try std.testing.expect(selection.containsOld(31));
    try std.testing.expect(!selection.containsOld(12));
    try std.testing.expect(selection.containsNew(12));
    try std.testing.expect(selection.containsNew(21));
    try std.testing.expect(!selection.containsNew(30));
}

test "reject invalid ranges" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.EmptyRanges, parse(allocator, ""));
    try std.testing.expectError(error.InvalidNumber, parse(allocator, "0"));
    try std.testing.expectError(error.InvalidNumber, parse(allocator, "1.5"));
    try std.testing.expectError(error.ReversedRange, parse(allocator, "5-3"));
    try std.testing.expectError(error.InvalidRange, parse(allocator, "1,,2"));
}

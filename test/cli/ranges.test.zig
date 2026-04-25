const std = @import("std");
const cli = @import("cli");

const mem = std.mem;

const args = cli.args;
const diff = cli.diff;
const patch = cli.patch;
const ranges = cli.ranges;

test "normalizes ranges" {
    const allocator = std.testing.allocator;
    var set = try ranges.parse(allocator, "1, 3-5, 8");
    defer set.deinit(allocator);

    try std.testing.expectEqualSlices(u8, "1,3-5,8", set.normalized);
    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(4));
    try std.testing.expect(!set.contains(6));
}

test "rejects invalid ranges" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.EmptyRanges, ranges.parse(allocator, ""));
    try std.testing.expectError(error.InvalidNumber, ranges.parse(allocator, "0"));
    try std.testing.expectError(error.InvalidRange, ranges.parse(allocator, "1-"));
    try std.testing.expectError(error.ReversedRange, ranges.parse(allocator, "9-2"));
}

test "builds patch for selected changed block only" {
    const allocator = std.testing.allocator;
    const diff_text =
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
    ;

    var parsed_diff = try diff.parse(allocator, diff_text);
    defer parsed_diff.deinit(allocator);

    var set = try ranges.parse(allocator, "2");
    defer set.deinit(allocator);

    const built = try patch.build(allocator, parsed_diff, set, args.Mode.new);
    defer built.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), built.selected_changes);
    try std.testing.expectEqual(@as(u32, 1), built.skipped_changes);
    try std.testing.expect(mem.indexOf(u8, built.patch, "-two\n+TWO") != null);
    try std.testing.expect(mem.indexOf(u8, built.patch, "+FOUR") == null);
}

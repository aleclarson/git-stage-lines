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

test "parses file refs shorthand into old and new selections" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{ "git-stage-lines", "src/app.ts:-4,6,8-9", "--json" };
    const parsed = try args.parse(allocator, &argv);
    defer parsed.deinit(allocator);

    const stage = parsed.command.stage;
    try std.testing.expectEqualSlices(u8, "src/app.ts", stage.file);
    try std.testing.expect(stage.json);
    try std.testing.expectEqual(args.Mode.both, stage.mode);
    try std.testing.expectEqualSlices(u8, "-4,6,8-9", stage.selection.normalized);
    try std.testing.expect(stage.selection.containsOld(4));
    try std.testing.expect(!stage.selection.containsOld(6));
    try std.testing.expect(stage.selection.containsNew(6));
    try std.testing.expect(stage.selection.containsNew(9));
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
    var selection = try ranges.selectionFromRangeSet(allocator, set, false, true);
    defer selection.deinit(allocator);

    const built = try patch.build(allocator, parsed_diff, selection, args.Mode.new);
    defer built.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), built.selected_changes);
    try std.testing.expectEqual(@as(u32, 1), built.skipped_changes);
    try std.testing.expect(mem.indexOf(u8, built.patch, "-two\n+TWO") != null);
    try std.testing.expect(mem.indexOf(u8, built.patch, "+FOUR") == null);
}

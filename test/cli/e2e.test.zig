const std = @import("std");

const mem = std.mem;

test "line numbers remain stable across sequential staging" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const binary = binaryPath();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var repo_path_buffer: [128]u8 = undefined;
    const repo_path = try std.fmt.bufPrint(
        &repo_path_buffer,
        ".zig-cache/tmp/{s}",
        .{&tmp.sub_path},
    );

    try run(allocator, io, repo_path, &.{ "git", "init", "-q" });
    try run(allocator, io, repo_path, &.{ "git", "config", "user.name", "Test User" });
    try run(allocator, io, repo_path, &.{ "git", "config", "user.email", "test@example.invalid" });

    try tmp.dir.writeFile(io, .{
        .sub_path = "file.txt",
        .data =
        \\one
        \\three
        \\five
        \\
        ,
    });
    try run(allocator, io, repo_path, &.{ "git", "add", "file.txt" });
    try run(allocator, io, repo_path, &.{ "git", "commit", "-qm", "initial" });

    try tmp.dir.writeFile(io, .{
        .sub_path = "file.txt",
        .data =
        \\one
        \\two
        \\three
        \\four
        \\five
        \\
        ,
    });

    const initial_diff = try capture(allocator, io, repo_path, &.{ binary, "diff", "file.txt" });
    defer allocator.free(initial_diff);
    try std.testing.expect(mem.indexOf(u8, initial_diff, "+2:\ttwo") != null);
    try std.testing.expect(mem.indexOf(u8, initial_diff, "+4:\tfour") != null);

    try run(allocator, io, repo_path, &.{ binary, "file.txt:4", "--json" });
    try run(allocator, io, repo_path, &.{ binary, "file.txt:2", "--json" });

    const cached = try capture(allocator, io, repo_path, &.{ "git", "diff", "--cached", "--", "file.txt" });
    defer allocator.free(cached);
    try std.testing.expect(mem.indexOf(u8, cached, "+two") != null);
    try std.testing.expect(mem.indexOf(u8, cached, "+four") != null);

    const unstaged = try capture(allocator, io, repo_path, &.{ "git", "diff", "--", "file.txt" });
    defer allocator.free(unstaged);
    try std.testing.expectEqualSlices(u8, "", unstaged);
}

fn binaryPath() []const u8 {
    const value = std.c.getenv("GIT_STAGE_LINES_BIN") orelse @panic("GIT_STAGE_LINES_BIN must be set");
    return mem.span(value);
}

fn run(
    allocator: mem.Allocator,
    io: std.Io,
    cwd: []const u8,
    argv: []const []const u8,
) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExitedZero(argv, result);
}

fn capture(
    allocator: mem.Allocator,
    io: std.Io,
    cwd: []const u8,
    argv: []const []const u8,
) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExitedZero(argv, result);
    return result.stdout;
}

fn expectExitedZero(argv: []const []const u8, result: std.process.RunResult) !void {
    switch (result.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{
        argv[0],
        result.stdout,
        result.stderr,
    });
    return error.CommandFailed;
}

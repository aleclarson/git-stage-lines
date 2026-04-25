const std = @import("std");
const args = @import("args.zig");
const diff = @import("diff.zig");
const diff_view = @import("diff_view.zig");
const errors = @import("errors.zig");
const generated = @import("generated.zig");
const json = @import("json.zig");
const patch = @import("patch.zig");

const mem = std.mem;

const CliError = errors.CliError;
const ExitCode = errors.ExitCode;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const argv = try init.minimal.args.toSlice(arena);
    var parsed = args.parse(allocator, argv) catch |err| {
        if (err == error.Help) {
            try stdout.writeAll(args.usage);
            return;
        }
        if (err == error.Version) {
            try stdout.print("git-stage-lines {s}\n", .{args.version});
            return;
        }
        const cli_err = parseErrorToCli(err);
        try emitFailure(allocator, stdout, stderr, false, cli_err, null, null);
        try stdout.flush();
        try stderr.flush();
        std.process.exit(@intFromEnum(cli_err.code));
    };
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .stage => |stage| {
            const result = switch (try runStage(allocator, io, stage)) {
                .success => |success| success,
                .failure => |cli_err| {
                    try emitFailure(allocator, stdout, stderr, stage.json, cli_err, stage.file, stage.selection.normalized);
                    try stdout.flush();
                    try stderr.flush();
                    std.process.exit(@intFromEnum(cli_err.code));
                },
            };
            defer result.deinit(allocator);

            if (stage.json) {
                const body = try json.success(allocator, .{
                    .kind = result.kind,
                    .file = stage.file,
                    .ranges = stage.selection.normalized,
                    .mode = stage.mode,
                    .selected_changes = result.selected_changes,
                    .skipped_changes = result.skipped_changes,
                    .patch_applied = result.patch_applied,
                    .would_apply = result.would_apply,
                    .reason = result.reason,
                    .patch = result.patch,
                });
                defer allocator.free(body);
                try stdout.writeAll(body);
            } else {
                switch (result.kind) {
                    .staged => try stdout.print(
                        "Staged {d} changes from {s} matching lines {s}.\n",
                        .{ result.selected_changes, stage.file, stage.selection.normalized },
                    ),
                    .checked => try stdout.print(
                        "Patch would apply for {d} changes from {s} matching lines {s}.\n",
                        .{ result.selected_changes, stage.file, stage.selection.normalized },
                    ),
                    .@"dry-run" => if (result.patch) |patch_text| {
                        try stdout.writeAll(patch_text);
                    },
                    .noop => try stdout.print(
                        "No matching changes in {s} for lines {s}.\n",
                        .{ stage.file, stage.selection.normalized },
                    ),
                }
            }
        },
        .diff => |diff_options| {
            if (try runDiff(allocator, io, stdout, diff_options)) |cli_err| {
                try emitFailure(allocator, stdout, stderr, false, cli_err, null, null);
                try stdout.flush();
                try stderr.flush();
                std.process.exit(@intFromEnum(cli_err.code));
            }
        },
        .completions => |completion_options| try generated.writeCompletions(stdout, completion_options.shell),
        .man => try generated.writeMan(stdout),
    }
}

const RunSuccess = struct {
    kind: json.SuccessKind,
    selected_changes: u32,
    skipped_changes: u32,
    patch_applied: bool,
    would_apply: ?bool = null,
    reason: ?[]const u8 = null,
    patch: ?[]const u8 = null,

    fn deinit(self: RunSuccess, allocator: mem.Allocator) void {
        if (self.patch) |owned_patch| allocator.free(owned_patch);
    }
};

const RunOutcome = union(enum) {
    success: RunSuccess,
    failure: CliError,
};

const BytesOutcome = union(enum) {
    data: []const u8,
    failure: CliError,
};

fn runStage(allocator: mem.Allocator, io: std.Io, options: args.StageOptions) !RunOutcome {
    if (try ensureGitRepository(allocator, io)) |cli_err| return .{ .failure = cli_err };

    _ = options.context;
    const diff_text = switch (try gitDiffFile(allocator, io, options.file, 0)) {
        .data => |data| data,
        .failure => |cli_err| return .{ .failure = cli_err },
    };
    defer allocator.free(diff_text);

    const parsed_diff = diff.parse(allocator, diff_text) catch |err| {
        return .{ .failure = switch (err) {
            error.EmptyDiff => if (options.allow_empty) return .{ .success = .{
                .kind = .noop,
                .selected_changes = 0,
                .skipped_changes = 0,
                .patch_applied = false,
                .would_apply = true,
                .reason = "no_unstaged_changes",
            } } else .{
                .code = .no_matching_changes,
                .reason = "no_unstaged_changes",
                .message = "file has no unstaged changes",
            },
            error.UnsupportedDiff => .{
                .code = .unsupported,
                .reason = "unsupported_diff",
                .message = "diff contains an unsupported file or change type",
            },
            error.MultipleFiles => .{
                .code = .unsupported,
                .reason = "multiple_files",
                .message = "diff unexpectedly contained more than one file",
            },
            error.MalformedDiff => .{
                .code = .unsupported,
                .reason = "malformed_diff",
                .message = "git produced a diff this tool could not parse",
            },
            error.OutOfMemory => return error.OutOfMemory,
        } };
    };
    defer parsed_diff.deinit(allocator);

    const built = try patch.build(allocator, parsed_diff, options.selection, options.mode);
    defer built.deinit(allocator);

    if (built.selected_changes == 0 or built.patch.len == 0) {
        if (options.allow_empty) {
            return .{ .success = .{
                .kind = .noop,
                .selected_changes = 0,
                .skipped_changes = built.skipped_changes,
                .patch_applied = false,
                .would_apply = true,
                .reason = "no_matching_changes",
            } };
        }
        return .{ .failure = .{
            .code = .no_matching_changes,
            .reason = "range_does_not_overlap_any_change",
            .message = "requested ranges do not overlap any unstaged change",
        } };
    }

    if (try gitApply(allocator, io, built.patch, true)) |cli_err| return .{ .failure = cli_err };

    if (options.dry_run) {
        return .{ .success = .{
            .kind = .@"dry-run",
            .selected_changes = built.selected_changes,
            .skipped_changes = built.skipped_changes,
            .patch_applied = false,
            .would_apply = true,
            .patch = try allocator.dupe(u8, built.patch),
        } };
    }

    if (options.check) {
        return .{ .success = .{
            .kind = .checked,
            .selected_changes = built.selected_changes,
            .skipped_changes = built.skipped_changes,
            .patch_applied = false,
            .would_apply = true,
        } };
    }

    if (try gitApply(allocator, io, built.patch, false)) |cli_err| return .{ .failure = cli_err };
    return .{ .success = .{
        .kind = .staged,
        .selected_changes = built.selected_changes,
        .skipped_changes = built.skipped_changes,
        .patch_applied = true,
        .would_apply = true,
    } };
}

fn runDiff(
    allocator: mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
    options: args.DiffOptions,
) !?CliError {
    if (try ensureGitRepository(allocator, io)) |cli_err| return cli_err;

    const diff_text = switch (try gitDiffFiles(allocator, io, options.files, 0)) {
        .data => |data| data,
        .failure => |cli_err| return cli_err,
    };
    defer allocator.free(diff_text);

    diff_view.write(stdout, diff_text) catch |err| switch (err) {
        error.MalformedDiff => return CliError{
            .code = .unsupported,
            .reason = "malformed_diff",
            .message = "git produced a diff this tool could not parse",
        },
        else => return err,
    };
    return null;
}

fn ensureGitRepository(allocator: mem.Allocator, io: std.Io) !?CliError {
    var result = runGit(allocator, io, &.{ "git", "rev-parse", "--is-inside-work-tree" }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitSpawnFailed => return CliError{
            .code = .git_command,
            .reason = "git_command_failed",
            .message = "failed to run git command",
        },
    };
    defer result.deinit(allocator);
    if (result.exit_code != 0 or !mem.startsWith(u8, result.stdout, "true")) {
        return CliError{
            .code = .user_input,
            .reason = "not_git_repository",
            .message = "current directory is not inside a Git repository",
            .stderr = try allocator.dupe(u8, result.stderr),
        };
    }
    return null;
}

fn gitDiffFile(allocator: mem.Allocator, io: std.Io, file: []const u8, context: u32) !BytesOutcome {
    return gitDiffFiles(allocator, io, &.{file}, context);
}

fn gitDiffFiles(allocator: mem.Allocator, io: std.Io, files: []const []const u8, context: u32) !BytesOutcome {
    const unified = try std.fmt.allocPrint(allocator, "--unified={d}", .{context});
    defer allocator.free(unified);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "diff", "--no-ext-diff", "--no-color", unified, "--" });
    try argv.appendSlice(allocator, files);

    var result = runGit(allocator, io, argv.items) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitSpawnFailed => return .{ .failure = .{
            .code = .git_command,
            .reason = "git_command_failed",
            .message = "failed to run git command",
        } },
    };
    defer result.deinitExceptStdout(allocator);

    if (result.exit_code != 0) {
        return .{ .failure = .{
            .code = .git_command,
            .reason = "git_diff_failed",
            .message = "git diff failed",
            .stderr = try allocator.dupe(u8, result.stderr),
        } };
    }

    return .{ .data = result.stdout };
}

fn gitApply(allocator: mem.Allocator, io: std.Io, patch_text: []const u8, check: bool) !?CliError {
    const patch_path = switch (try temporaryPatchPath(allocator, io)) {
        .data => |data| data,
        .failure => |cli_err| return cli_err,
    };
    defer allocator.free(patch_path);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = patch_path, .data = patch_text });
    defer std.Io.Dir.cwd().deleteFile(io, patch_path) catch {};

    const check_argv: []const []const u8 = &.{ "git", "apply", "--cached", "--unidiff-zero", "--check", patch_path };
    const apply_argv: []const []const u8 = &.{ "git", "apply", "--cached", "--unidiff-zero", patch_path };
    const argv = if (check) check_argv else apply_argv;

    var result = runGit(allocator, io, argv) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitSpawnFailed => return CliError{
            .code = .git_command,
            .reason = "git_command_failed",
            .message = "failed to run git command",
        },
    };
    defer result.deinit(allocator);

    if (result.exit_code != 0) {
        return CliError{
            .code = if (check) .patch_validation else .git_command,
            .reason = if (check) "patch_failed_validation" else "git_apply_failed",
            .message = if (check) "generated patch failed validation" else "git apply failed",
            .stderr = try allocator.dupe(u8, result.stderr),
        };
    }
    return null;
}

fn temporaryPatchPath(allocator: mem.Allocator, io: std.Io) !BytesOutcome {
    var random_source = std.Random.IoSource{ .io = io };
    const random = random_source.interface();
    const name = try std.fmt.allocPrint(allocator, "git-stage-lines-{x}.patch", .{random.int(u64)});
    defer allocator.free(name);

    var result = runGit(allocator, io, &.{ "git", "rev-parse", "--git-path", name }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitSpawnFailed => return .{ .failure = .{
            .code = .git_command,
            .reason = "git_command_failed",
            .message = "failed to run git command",
        } },
    };
    defer result.deinitExceptStdout(allocator);

    if (result.exit_code != 0) {
        return .{ .failure = .{
            .code = .git_command,
            .reason = "git_path_failed",
            .message = "failed to resolve Git metadata path",
            .stderr = try allocator.dupe(u8, result.stderr),
        } };
    }

    return .{ .data = try trimOwned(allocator, result.stdout) };
}

const CommandResult = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: CommandResult, allocator: mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }

    fn deinitExceptStdout(self: *CommandResult, allocator: mem.Allocator) void {
        allocator.free(self.stderr);
        self.stdout = &.{};
    }
};

const RunGitError = error{ OutOfMemory, GitSpawnFailed };

fn runGit(allocator: mem.Allocator, io: std.Io, argv: []const []const u8) RunGitError!CommandResult {
    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(20 * 1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.GitSpawnFailed,
        };
    };

    return .{
        .exit_code = switch (result.term) {
            .exited => |code| code,
            .signal, .stopped, .unknown => 255,
        },
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

fn trimOwned(allocator: mem.Allocator, value: []u8) ![]const u8 {
    defer allocator.free(value);
    const trimmed = mem.trim(u8, value, " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}

fn parseErrorToCli(err: args.ParseError) CliError {
    return switch (err) {
        error.MissingFile => .{ .code = .user_input, .reason = "missing_file", .message = "missing FILE argument" },
        error.MissingRanges => .{ .code = .user_input, .reason = "missing_ranges", .message = "missing RANGES argument" },
        error.MissingShell => .{ .code = .user_input, .reason = "missing_shell", .message = "missing shell argument" },
        error.TooManyPositionals => .{ .code = .user_input, .reason = "too_many_positionals", .message = "expected exactly FILE and RANGES" },
        error.MissingOptionValue => .{ .code = .user_input, .reason = "missing_option_value", .message = "option requires a value" },
        error.UnknownOption => .{ .code = .user_input, .reason = "unknown_option", .message = "unknown option" },
        error.InvalidMode => .{ .code = .user_input, .reason = "invalid_mode", .message = "mode must be new, old, or both" },
        error.InvalidShell => .{ .code = .user_input, .reason = "invalid_shell", .message = "shell must be bash, zsh, or fish" },
        error.InvalidContext => .{ .code = .user_input, .reason = "invalid_context", .message = "context must be an integer between 0 and 1000" },
        error.EmptyRanges => .{ .code = .user_input, .reason = "empty_ranges", .message = "ranges must not be empty" },
        error.InvalidRange => .{ .code = .user_input, .reason = "invalid_range", .message = "ranges must use LINE or START-END forms" },
        error.InvalidNumber => .{ .code = .user_input, .reason = "invalid_range_number", .message = "range lines must be positive integers" },
        error.ReversedRange => .{ .code = .user_input, .reason = "reversed_range", .message = "range start must be less than or equal to range end" },
        error.OutOfMemory => .{ .code = .user_input, .reason = "out_of_memory", .message = "out of memory" },
        error.Help => unreachable,
        error.Version => unreachable,
    };
}

fn emitFailure(
    allocator: mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    use_json: bool,
    err: CliError,
    file: ?[]const u8,
    range_text: ?[]const u8,
) !void {
    if (use_json) {
        const body = try json.failure(allocator, err, file, range_text);
        defer allocator.free(body);
        try stdout.writeAll(body);
    } else {
        try stderr.print("git-stage-lines: {s}\n", .{err.message});
        if (err.stderr) |command_stderr| {
            if (command_stderr.len != 0) try stderr.writeAll(command_stderr);
        }
    }
}

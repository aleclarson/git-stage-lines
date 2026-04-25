pub const ExitCode = enum(u8) {
    success = 0,
    user_input = 1,
    no_matching_changes = 2,
    patch_validation = 3,
    git_command = 4,
    unsupported = 5,
};

pub const CliError = struct {
    code: ExitCode,
    reason: []const u8,
    message: []const u8,
    stderr: ?[]const u8 = null,
};

const std = @import("std");
const ranges = @import("ranges.zig");

const mem = std.mem;

pub const Mode = enum {
    new,
    old,
    both,

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .new => "new",
            .old => "old",
            .both => "both",
        };
    }
};

pub const ParseError = error{
    Help,
    Version,
    MissingFile,
    MissingRanges,
    TooManyPositionals,
    MissingOptionValue,
    MissingShell,
    UnknownOption,
    InvalidMode,
    InvalidShell,
    InvalidRange,
    InvalidNumber,
    ReversedRange,
    EmptyRanges,
    OutOfMemory,
};

pub const Options = struct {
    command: Command,

    pub fn deinit(self: Options, allocator: mem.Allocator) void {
        switch (self.command) {
            .stage => |stage| stage.deinit(allocator),
            .diff => |diff| diff.deinit(allocator),
            .completions => {},
            .man => {},
        }
    }
};

pub const Command = union(enum) {
    stage: StageOptions,
    diff: DiffOptions,
    completions: CompletionsOptions,
    man,
};

pub const Shell = enum {
    bash,
    zsh,
    fish,

    pub fn label(self: Shell) []const u8 {
        return switch (self) {
            .bash => "bash",
            .zsh => "zsh",
            .fish => "fish",
        };
    }
};

pub const CompletionsOptions = struct {
    shell: Shell,
};

pub const StageOptions = struct {
    file: []const u8,
    selection: ranges.Selection,
    mode: Mode = .new,
    dry_run: bool = false,
    json: bool = false,
    check: bool = false,
    allow_empty: bool = false,
    verbose: bool = false,

    pub fn deinit(self: StageOptions, allocator: mem.Allocator) void {
        self.selection.deinit(allocator);
    }
};

pub const DiffOptions = struct {
    files: []const []const u8,

    pub fn deinit(self: DiffOptions, allocator: mem.Allocator) void {
        allocator.free(self.files);
    }
};

pub fn parse(allocator: mem.Allocator, argv: []const [:0]const u8) ParseError!Options {
    if (argv.len > 1 and mem.eql(u8, argv[1], "diff")) {
        return .{ .command = .{ .diff = try parseDiff(allocator, argv[2..]) } };
    }
    if (argv.len > 1 and mem.eql(u8, argv[1], "completions")) {
        return .{ .command = .{ .completions = try parseCompletions(argv[2..]) } };
    }
    if (argv.len > 1 and mem.eql(u8, argv[1], "man")) {
        try parseNoArgs(argv[2..]);
        return .{ .command = .man };
    }
    return .{ .command = .{ .stage = try parseStage(allocator, argv) } };
}

fn parseStage(allocator: mem.Allocator, argv: []const [:0]const u8) ParseError!StageOptions {
    if (argv.len > 1 and isFileRef(argv[1])) {
        return parseStageFileRef(allocator, argv);
    }

    var file: ?[]const u8 = null;
    var raw_ranges: ?[]const u8 = null;
    var mode: Mode = .new;
    var dry_run = false;
    var json = false;
    var check = false;
    var allow_empty = false;
    var verbose = false;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            return error.Help;
        } else if (mem.eql(u8, arg, "--version")) {
            return error.Version;
        } else if (mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (mem.eql(u8, arg, "--check")) {
            check = true;
        } else if (mem.eql(u8, arg, "--allow-empty")) {
            allow_empty = true;
        } else if (mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= argv.len) return error.MissingOptionValue;
            mode = parseMode(argv[i]) orelse return error.InvalidMode;
        } else if (mem.startsWith(u8, arg, "--mode=")) {
            mode = parseMode(arg["--mode=".len..]) orelse return error.InvalidMode;
        } else if (mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else if (file == null) {
            file = arg;
        } else if (raw_ranges == null) {
            raw_ranges = arg;
        } else {
            return error.TooManyPositionals;
        }
    }

    const parsed_file = file orelse return error.MissingFile;
    const parsed_ranges = raw_ranges orelse return error.MissingRanges;
    var range_set = ranges.parse(allocator, parsed_ranges) catch |err| switch (err) {
        error.EmptyRanges => return error.EmptyRanges,
        error.InvalidRange => return error.InvalidRange,
        error.InvalidNumber => return error.InvalidNumber,
        error.ReversedRange => return error.ReversedRange,
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.OutOfMemory,
    };
    defer range_set.deinit(allocator);

    const selection = ranges.selectionFromRangeSet(
        allocator,
        range_set,
        mode == .old or mode == .both,
        mode == .new or mode == .both,
    ) catch return error.OutOfMemory;

    return StageOptions{
        .file = parsed_file,
        .selection = selection,
        .mode = mode,
        .dry_run = dry_run,
        .json = json,
        .check = check,
        .allow_empty = allow_empty,
        .verbose = verbose,
    };
}

fn parseStageFileRef(allocator: mem.Allocator, argv: []const [:0]const u8) ParseError!StageOptions {
    const file_ref = argv[1];
    const colon = mem.lastIndexOfScalar(u8, file_ref, ':') orelse return error.MissingRanges;
    if (colon == 0) return error.MissingFile;
    if (colon + 1 >= file_ref.len) return error.EmptyRanges;

    const file = file_ref[0..colon];
    const raw_refs = file_ref[colon + 1 ..];
    var mode: Mode = .both;
    var dry_run = false;
    var json = false;
    var check = false;
    var allow_empty = false;
    var verbose = false;

    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            return error.Help;
        } else if (mem.eql(u8, arg, "--version")) {
            return error.Version;
        } else if (mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (mem.eql(u8, arg, "--check")) {
            check = true;
        } else if (mem.eql(u8, arg, "--allow-empty")) {
            allow_empty = true;
        } else if (mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= argv.len) return error.MissingOptionValue;
            mode = parseMode(argv[i]) orelse return error.InvalidMode;
        } else if (mem.startsWith(u8, arg, "--mode=")) {
            mode = parseMode(arg["--mode=".len..]) orelse return error.InvalidMode;
        } else if (mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            return error.TooManyPositionals;
        }
    }

    const selection = ranges.parseRefs(allocator, raw_refs) catch |err| switch (err) {
        error.EmptyRanges => return error.EmptyRanges,
        error.InvalidRange => return error.InvalidRange,
        error.InvalidNumber => return error.InvalidNumber,
        error.ReversedRange => return error.ReversedRange,
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.OutOfMemory,
    };

    return .{
        .file = file,
        .selection = selection,
        .mode = mode,
        .dry_run = dry_run,
        .json = json,
        .check = check,
        .allow_empty = allow_empty,
        .verbose = verbose,
    };
}

fn parseDiff(allocator: mem.Allocator, argv: []const [:0]const u8) ParseError!DiffOptions {
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    for (argv) |arg| {
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            return error.Help;
        } else if (mem.eql(u8, arg, "--version")) {
            return error.Version;
        } else if (mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        }
        try files.append(allocator, arg);
    }

    return .{ .files = try allocator.dupe([]const u8, files.items) };
}

fn parseCompletions(argv: []const [:0]const u8) ParseError!CompletionsOptions {
    if (argv.len == 0) return error.MissingShell;
    if (argv.len > 1) return error.TooManyPositionals;

    const shell = parseShell(argv[0]) orelse return error.InvalidShell;
    return .{ .shell = shell };
}

fn parseNoArgs(argv: []const [:0]const u8) ParseError!void {
    for (argv) |arg| {
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            return error.Help;
        } else if (mem.eql(u8, arg, "--version")) {
            return error.Version;
        } else if (mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            return error.TooManyPositionals;
        }
    }
}

fn isFileRef(arg: []const u8) bool {
    const colon = mem.lastIndexOfScalar(u8, arg, ':') orelse return false;
    return colon > 0 and colon + 1 < arg.len;
}

fn parseShell(value: []const u8) ?Shell {
    if (mem.eql(u8, value, "bash")) return .bash;
    if (mem.eql(u8, value, "zsh")) return .zsh;
    if (mem.eql(u8, value, "fish")) return .fish;
    return null;
}

fn parseMode(value: []const u8) ?Mode {
    if (mem.eql(u8, value, "new")) return .new;
    if (mem.eql(u8, value, "old")) return .old;
    if (mem.eql(u8, value, "both")) return .both;
    return null;
}

pub const usage =
    \\usage:
    \\  git-stage-lines FILE RANGES [options]
    \\  git-stage-lines FILE:REFS [options]
    \\  git-stage-lines diff [FILE...]
    \\  git-stage-lines completions bash|zsh|fish
    \\  git-stage-lines man
    \\
    \\Options:
    \\  --mode new|old|both  Select by working-tree, index, or either line numbers
    \\  --dry-run            Print the patch that would be staged
    \\  --check              Validate the selected patch without staging
    \\  --json               Emit machine-readable JSON
    \\  --allow-empty        Treat no matching changes as a successful noop
    \\  --verbose            Include extra human-readable diagnostics
    \\  --version            Show version
    \\  -h, --help           Show this help
    \\
    \\Diff:
    \\  diff [FILE...]       Show unstaged changes with line numbers
    \\
    \\Line Refs:
    \\  diff prints +N and -N refs. Stage +N as FILE:N and -N as FILE:-N.
    \\  Refs stay valid until the working tree changes.
    \\
    \\Agent Workflow:
    \\  git-stage-lines diff FILE
    \\  git-stage-lines FILE:REFS --json
    \\  git diff --cached -- FILE
    \\
    \\Example:
    \\  git-stage-lines diff src/app.ts
    \\  git-stage-lines src/app.ts:12,-18 --json
    \\
    \\Generated Output:
    \\  completions SHELL    Print shell completions
    \\  man                  Print a manual page
    \\
;

pub const version = "0.2.1";

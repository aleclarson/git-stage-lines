const std = @import("std");
const args = @import("args.zig");
const errors = @import("errors.zig");

const mem = std.mem;

pub const SuccessKind = enum {
    staged,
    checked,
    @"dry-run",
    noop,

    fn label(self: SuccessKind) []const u8 {
        return switch (self) {
            .staged => "staged",
            .checked => "checked",
            .@"dry-run" => "dry-run",
            .noop => "noop",
        };
    }
};

pub const Success = struct {
    kind: SuccessKind,
    file: []const u8,
    ranges: []const u8,
    mode: args.Mode,
    selected_changes: u32,
    skipped_changes: u32,
    patch_applied: bool,
    would_apply: ?bool = null,
    reason: ?[]const u8 = null,
    patch: ?[]const u8 = null,
};

pub fn success(allocator: mem.Allocator, value: Success) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{");
    try fieldString(&out.writer, "status", value.kind.label(), false);
    try fieldString(&out.writer, "file", value.file, true);
    try out.writer.writeAll(",\"ranges\":[");
    try writeString(&out.writer, value.ranges);
    try out.writer.writeAll("]");
    try fieldString(&out.writer, "mode", value.mode.label(), true);
    try fieldNumber(&out.writer, "selected_changes", value.selected_changes);
    try fieldNumber(&out.writer, "skipped_changes", value.skipped_changes);
    try fieldBool(&out.writer, "patch_applied", value.patch_applied);
    if (value.would_apply) |would_apply| try fieldBool(&out.writer, "would_apply", would_apply);
    if (value.reason) |reason| try fieldString(&out.writer, "reason", reason, true);
    if (value.patch) |patch| try fieldString(&out.writer, "patch", patch, true);
    try out.writer.writeAll("}\n");

    return try out.toOwnedSlice();
}

pub fn failure(
    allocator: mem.Allocator,
    err: errors.CliError,
    file: ?[]const u8,
    ranges: ?[]const u8,
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try out.writer.writeAll("{");
    try fieldString(&out.writer, "status", "error", false);
    try fieldString(&out.writer, "reason", err.reason, true);
    try fieldString(&out.writer, "message", err.message, true);
    if (file) |path| try fieldString(&out.writer, "file", path, true);
    if (ranges) |range_text| {
        try out.writer.writeAll(",\"ranges\":[");
        try writeString(&out.writer, range_text);
        try out.writer.writeAll("]");
    }
    try fieldNumber(&out.writer, "exit_code", @intFromEnum(err.code));
    if (err.stderr) |stderr| try fieldString(&out.writer, "stderr", stderr, true);
    try out.writer.writeAll("}\n");

    return try out.toOwnedSlice();
}

fn fieldString(writer: *std.Io.Writer, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try writeString(writer, name);
    try writer.writeByte(':');
    try writeString(writer, value);
}

fn fieldNumber(writer: *std.Io.Writer, name: []const u8, value: anytype) !void {
    try writer.writeByte(',');
    try writeString(writer, name);
    try writer.print(":{d}", .{value});
}

fn fieldBool(writer: *std.Io.Writer, name: []const u8, value: bool) !void {
    try writer.writeByte(',');
    try writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn writeString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        if (byte < 0x20) {
            switch (byte) {
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.print("\\u{x:0>4}", .{byte}),
            }
            continue;
        }
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

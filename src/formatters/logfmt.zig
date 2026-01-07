const std = @import("std");
const data_extractor = @import("../data_extractor.zig");

/// Formats log data as logfmt (key=value pairs).
/// Values containing spaces, quotes, or equals signs are quoted.
pub fn format(data: data_extractor.LogData, level: std.log.Level, writer: *std.Io.Writer) !void {
    try writer.print("timestamp={s} level={s} method={s} status={d} duration_ms={d} size={d}", .{
        data.timestamp(),
        @tagName(level),
        @tagName(data.method),
        data.status,
        data.duration_ms,
        data.size,
    });

    try writeFieldGeneric(writer, "path", data.path);
    if (data.client().len > 0) try writeFieldGeneric(writer, "client", data.client());
    if (data.trace_id) |v| try writer.print(" trace_id={s}", .{v});
    if (data.span_id) |v| try writer.print(" span_id={s}", .{v});
    if (data.query) |v| try writeFieldGeneric(writer, "query", v);
    if (data.user_agent) |v| try writeFieldGeneric(writer, "user_agent", v);
    if (data.user_id) |v| try writeFieldGeneric(writer, "user_id", v);
    if (data.request_id) |v| try writeFieldGeneric(writer, "request_id", v);
}

/// Writes a key=value pair, quoting the value if it contains special characters.
fn writeField(writer: *std.Io.Writer, key: []const u8, value: []const u8) !void {
    if (needsQuoting(value)) {
        try writer.print(" {s}=\"", .{key});
        try writeEscaped(writer, value);
        try writer.writeByte('"');
    } else {
        try writer.print(" {s}={s}", .{ key, value });
    }
}

/// Checks if a value needs quoting (contains space, quote, equals, backslash, or newlines).
pub fn needsQuoting(value: []const u8) bool {
    for (value) |c| {
        if (c == ' ' or c == '"' or c == '=' or c == '\\' or c == '\n' or c == '\r') return true;
    }
    return false;
}

/// Writes a string with escaping for quotes, backslashes, and newlines.
pub fn writeEscaped(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '"', '\\' => {
                try writer.writeByte('\\');
                try writer.writeByte(c);
            },
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            else => try writer.writeByte(c),
        }
    }
}

const testing = std.testing;

test "needsQuoting with spaces" {
    try testing.expect(needsQuoting("hello world"));
}

test "needsQuoting with quotes" {
    try testing.expect(needsQuoting("hello\"world"));
}

test "needsQuoting with equals" {
    try testing.expect(needsQuoting("foo=bar"));
}

test "needsQuoting with backslash" {
    try testing.expect(needsQuoting("path\\to\\file"));
}

test "needsQuoting with newline" {
    try testing.expect(needsQuoting("hello\nworld"));
}

test "needsQuoting with carriage return" {
    try testing.expect(needsQuoting("hello\rworld"));
}

test "needsQuoting simple string" {
    try testing.expect(!needsQuoting("simple"));
}

test "needsQuoting empty string" {
    try testing.expect(!needsQuoting(""));
}

test "writeEscaped with quotes" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "hello\"world");
    try testing.expectEqualStrings("hello\\\"world", w.buffered());
}

test "writeEscaped with backslash" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "path\\file");
    try testing.expectEqualStrings("path\\\\file", w.buffered());
}

test "writeEscaped with newline" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "hello\nworld");
    try testing.expectEqualStrings("hello\\nworld", w.buffered());
}

test "writeEscaped with carriage return" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "hello\rworld");
    try testing.expectEqualStrings("hello\\rworld", w.buffered());
}

test "writeEscaped with mixed special chars" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "a\"b\\c\nd\re");
    try testing.expectEqualStrings("a\\\"b\\\\c\\nd\\re", w.buffered());
}

test "writeEscaped normal string" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "normal");
    try testing.expectEqualStrings("normal", w.buffered());
}

/// Formats log data as logfmt using standard writer interface.
pub fn formatWriter(data: data_extractor.LogData, level: std.log.Level, writer: anytype) !void {
    try writer.print("timestamp={s} level={s} method={s} status={d} duration_ms={d} size={d}", .{
        data.timestamp(),
        @tagName(level),
        @tagName(data.method),
        data.status,
        data.duration_ms,
        data.size,
    });

    try writeFieldGeneric(writer, "path", data.path);
    const client = data.client();
    if (client.len > 0) try writeFieldGeneric(writer, "client", client);
    if (data.trace_id) |v| try writer.print(" trace_id={s}", .{v});
    if (data.span_id) |v| try writer.print(" span_id={s}", .{v});
    if (data.query) |v| try writeFieldGeneric(writer, "query", v);
    if (data.user_agent) |v| try writeFieldGeneric(writer, "user_agent", v);
    if (data.user_id) |v| try writeFieldGeneric(writer, "user_id", v);
    if (data.request_id) |v| try writeFieldGeneric(writer, "request_id", v);
}

/// Writes a key=value pair for generic writer, quoting the value if it contains special characters.
fn writeFieldGeneric(writer: anytype, key: []const u8, value: []const u8) !void {
    if (needsQuoting(value)) {
        try writer.print(" {s}=\"", .{key});
        try writeEscapedGeneric(writer, value);
        try writer.writeByte('"');
    } else {
        try writer.print(" {s}={s}", .{ key, value });
    }
}

/// Writes escaped string to generic writer, escaping special characters.
fn writeEscapedGeneric(writer: anytype, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            else => try writer.writeByte(c),
        }
    }
}

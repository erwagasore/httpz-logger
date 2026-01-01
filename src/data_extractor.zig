const std = @import("std");
const httpz = @import("httpz");

const Timestamp = @import("timestamp.zig");

/// Parses W3C traceparent header: 00-<trace_id>-<span_id>-<flags>
/// Returns trace_id (32 hex chars) and span_id (16 hex chars) slices into the header value.
/// Only supports version 00. Future versions may have different formats.
pub fn parseTraceparent(header: []const u8) ?struct { trace_id: []const u8, span_id: []const u8 } {
    // Format: version-trace_id-span_id-flags
    // Example: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
    // Length:  2 + 1 + 32 + 1 + 16 + 1 + 2 = 55
    if (header.len < 55) return null;
    if (!std.mem.eql(u8, header[0..2], "00")) return null; // Only support version 00
    if (header[2] != '-' or header[35] != '-' or header[52] != '-') return null;

    const trace_id = header[3..35]; // 32 hex chars
    const span_id = header[36..52]; // 16 hex chars

    return .{ .trace_id = trace_id, .span_id = span_id };
}

pub const LogData = struct {
    timestamp_buf: [20]u8 = undefined,
    address_buf: [24]u8 = undefined,
    address_len: usize = 0,
    trace_id: ?[]const u8 = null,
    span_id: ?[]const u8 = null,
    method: httpz.Method,
    path: []const u8,
    query: ?[]const u8,
    status: u16,
    size: usize,
    duration_ms: i64,
    user_agent: ?[]const u8,
    user_id: ?[]const u8,
    request_id: ?[]const u8,

    pub fn timestamp(self: *const LogData) []const u8 {
        return &self.timestamp_buf;
    }

    pub fn client(self: *const LogData) []const u8 {
        return self.address_buf[0..self.address_len];
    }
};

pub const ExtractConfig = struct {
    log_query: bool,
    log_user_agent: bool,
    log_client: bool,
    log_trace_id: bool,
    log_span_id: bool,
    log_request_id: bool,
    log_user_id: bool,
};

/// Extracts log data from request/response with timing information.
pub fn extract(req: *httpz.Request, res: *httpz.Response, start: i64, config: ExtractConfig) LogData {
    const trace_ctx = if (config.log_trace_id or config.log_span_id)
        if (req.header("traceparent")) |tp| parseTraceparent(tp) else null
    else
        null;

    var data: LogData = .{
        .trace_id = if (config.log_trace_id) if (trace_ctx) |ctx| ctx.trace_id else null else null,
        .span_id = if (config.log_span_id) if (trace_ctx) |ctx| ctx.span_id else null else null,
        .method = req.method,
        .path = req.url.path,
        .query = if (config.log_query and req.url.query.len > 0) req.url.query else null,
        .status = res.status,
        .size = res.body.len,
        .duration_ms = std.time.milliTimestamp() - start,
        .user_agent = if (config.log_user_agent) req.header("user-agent") else null,
        .user_id = if (config.log_user_id) req.header("x-user-id") orelse req.header("x-user") else null,
        .request_id = if (config.log_request_id) req.header("x-request-id") else null,
    };

    // Format timestamp as ISO 8601
    var ts = Timestamp.now();
    _ = ts.iso8601(&data.timestamp_buf);

    // Format client address
    if (config.log_client) {
        var addr_w: std.Io.Writer = .fixed(&data.address_buf);
        req.address.in.format(&addr_w) catch {};
        data.address_len = addr_w.written;
    }

    return data;
}

const testing = std.testing;

test "parseTraceparent: valid header" {
    const header = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
    const result = parseTraceparent(header);

    try testing.expect(result != null);
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.?.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.?.span_id);
}

test "parseTraceparent: valid header with different values" {
    const header = "00-aaaabbbbccccddddeeeeffffgggghhhh-1234567890abcdef-00";
    const result = parseTraceparent(header);

    try testing.expect(result != null);
    try testing.expectEqualStrings("aaaabbbbccccddddeeeeffffgggghhhh", result.?.trace_id);
    try testing.expectEqualStrings("1234567890abcdef", result.?.span_id);
}

test "parseTraceparent: too short" {
    const result = parseTraceparent("00-abc-def-01");
    try testing.expect(result == null);
}

test "parseTraceparent: empty string" {
    const result = parseTraceparent("");
    try testing.expect(result == null);
}

test "parseTraceparent: missing delimiters" {
    const result = parseTraceparent("00_0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331_01");
    try testing.expect(result == null);
}

test "parseTraceparent: wrong delimiter positions" {
    const result = parseTraceparent("000-af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    try testing.expect(result == null);
}

test "parseTraceparent: unsupported version 01" {
    const result = parseTraceparent("01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    try testing.expect(result == null);
}

test "parseTraceparent: unsupported version ff" {
    const result = parseTraceparent("ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    try testing.expect(result == null);
}

test "parseTraceparent: valid with extra data after flags" {
    const header = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01-extra-stuff";
    const result = parseTraceparent(header);

    try testing.expect(result != null);
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.?.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.?.span_id);
}

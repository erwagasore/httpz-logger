//! HTTP request logging middleware for httpz.
//!
//! A thin extraction layer that logs HTTP request/response data via logz.
//! Supports W3C traceparent header parsing for distributed tracing.
//!
//! ## Usage
//!
//! ```zig
//! const HttpLogger = @import("httpz_logger");
//!
//! // In main(), initialize logz first:
//! try logz.setup(allocator, .{ .level = .Info, .output = .stdout });
//! defer logz.deinit();
//!
//! // Then register the middleware:
//! const logger = try server.middleware(HttpLogger, .{});
//! ```

const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");

/// Configuration for the HTTP logger middleware.
pub const Config = struct {
    /// Minimum log level (cascading).
    /// - .Debug: log all requests
    /// - .Info:  log all requests (default)
    /// - .Warn:  log 4xx and 5xx only
    /// - .Error: log 5xx only
    /// - .None:  disable logging
    level: logz.Level = .Info,

    /// Include query string in logs.
    log_query: bool = true,
    /// Include User-Agent header.
    log_user_agent: bool = true,
    /// Include client IP address.
    log_client: bool = true,
    /// Include trace_id from traceparent header.
    log_trace_id: bool = true,
    /// Include span_id from traceparent header.
    log_span_id: bool = true,
    /// Include X-Request-ID header.
    log_request_id: bool = true,
    /// Include X-User-ID / X-User header.
    log_user_id: bool = true,
};

config: Config,

/// Initialise the middleware with the given configuration.
pub fn init(config: Config) !@This() {
    return .{ .config = config };
}

/// Middleware execution — called by httpz for each request.
pub fn execute(self: *const @This(), req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    const start = std.time.milliTimestamp();
    defer self.log(req, res, std.time.milliTimestamp() - start);
    return executor.next();
}

fn log(self: *const @This(), req: *httpz.Request, res: *httpz.Response, duration_ms: i64) void {
    const lvl = levelFromStatus(res.status);

    // Cascading filter: skip if detected level is below configured minimum.
    if (@intFromEnum(lvl) < @intFromEnum(self.config.level)) return;

    var logger = logz.loggerL(lvl)
        .stringSafe("method", @tagName(req.method))
        .string("path", req.url.path)
        .int("status", res.status)
        .int("size", res.body.len)
        .int("duration_ms", duration_ms);

    if (self.config.log_client) {
        var buf: [64]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        if (req.address.format(&w)) {
            _ = logger.stringSafe("client", w.buffered());
        } else |_| {}
    }

    if (self.config.log_trace_id or self.config.log_span_id) {
        if (req.header("traceparent")) |tp| {
            if (parseTraceparent(tp)) |ctx| {
                if (self.config.log_trace_id) _ = logger.stringSafe("trace_id", ctx.trace_id);
                if (self.config.log_span_id) _ = logger.stringSafe("span_id", ctx.span_id);
            }
        }
    }

    if (self.config.log_query and req.url.query.len > 0) {
        _ = logger.string("query", req.url.query);
    }
    if (self.config.log_user_agent) {
        if (req.header("user-agent")) |ua| _ = logger.string("user_agent", ua);
    }
    if (self.config.log_request_id) {
        if (req.header("x-request-id")) |rid| _ = logger.string("request_id", rid);
    }
    if (self.config.log_user_id) {
        if (req.header("x-user-id") orelse req.header("x-user")) |uid| _ = logger.string("user_id", uid);
    }

    logger.log();
}

/// Maps HTTP status code to log level.
fn levelFromStatus(status: u16) logz.Level {
    if (status >= 500) return .Error;
    if (status >= 400) return .Warn;
    return .Info;
}

/// Parses W3C traceparent header: `00-{trace_id}-{span_id}-{flags}`
///
/// Returns trace_id (32 hex chars) and span_id (16 hex chars),
/// or null if the header is malformed.
pub fn parseTraceparent(header: []const u8) ?struct { trace_id: []const u8, span_id: []const u8 } {
    // Minimum valid: "00-<32>-<16>-<2>" = 55 chars
    if (header.len < 55) return null;
    if (!std.mem.eql(u8, header[0..2], "00")) return null;
    if (header[2] != '-' or header[35] != '-' or header[52] != '-') return null;
    return .{ .trace_id = header[3..35], .span_id = header[36..52] };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "levelFromStatus returns correct levels" {
    // 5xx → Error
    try testing.expectEqual(.Error, levelFromStatus(500));
    try testing.expectEqual(.Error, levelFromStatus(503));
    try testing.expectEqual(.Error, levelFromStatus(599));

    // 4xx → Warn
    try testing.expectEqual(.Warn, levelFromStatus(400));
    try testing.expectEqual(.Warn, levelFromStatus(404));
    try testing.expectEqual(.Warn, levelFromStatus(499));

    // 2xx, 3xx → Info
    try testing.expectEqual(.Info, levelFromStatus(200));
    try testing.expectEqual(.Info, levelFromStatus(201));
    try testing.expectEqual(.Info, levelFromStatus(301));
    try testing.expectEqual(.Info, levelFromStatus(304));
}

test "parseTraceparent with valid header" {
    const header = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
    const result = parseTraceparent(header).?;
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.span_id);
}

test "parseTraceparent rejects short input" {
    try testing.expect(parseTraceparent("") == null);
    try testing.expect(parseTraceparent("00-abc-def-01") == null);
}

test "parseTraceparent rejects wrong version" {
    try testing.expect(parseTraceparent("01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);
    try testing.expect(parseTraceparent("ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);
}

test "parseTraceparent rejects wrong delimiters" {
    try testing.expect(parseTraceparent("00_0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331_01") == null);
}

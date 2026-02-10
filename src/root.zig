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
//! const logger = try server.middleware(HttpLogger, .{
//!     .level = .Info,
//!     .output = .stdout,
//! });
//! ```

const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");

// Re-export types the user needs for configuration.
pub const Level = logz.Level;
pub const Output = logz.Config.Output;
pub const Encoding = logz.Config.Encoding;

/// Configuration for the HTTP logger middleware.
pub const Config = struct {
    /// Minimum log level (cascading).
    /// - .Debug: log all requests
    /// - .Info:  log all requests (default)
    /// - .Warn:  log 4xx and 5xx only
    /// - .Error: log 5xx only
    /// - .None:  disable logging
    level: Level = .Info,

    /// Where to write log output.
    output: Output = .stdout,

    /// Log encoding format.
    encoding: Encoding = .logfmt,

    /// Number of pre-allocated log buffers.
    pool_size: usize = 32,

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

/// Initialise the middleware — sets up the logging backend automatically.
pub fn init(config: Config, mc: httpz.MiddlewareConfig) !@This() {
    try logz.setup(mc.allocator, .{
        .level = config.level,
        .output = config.output,
        .encoding = config.encoding,
        .pool_size = config.pool_size,
    });
    return .{ .config = config };
}

/// Tear down the logging backend.
pub fn deinit(_: *@This()) void {
    logz.deinit();
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
fn levelFromStatus(status: u16) Level {
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

// -- levelFromStatus ---------------------------------------------------------

test "levelFromStatus: 1xx and 2xx map to Info" {
    try testing.expectEqual(.Info, levelFromStatus(100));
    try testing.expectEqual(.Info, levelFromStatus(200));
    try testing.expectEqual(.Info, levelFromStatus(201));
    try testing.expectEqual(.Info, levelFromStatus(204));
    try testing.expectEqual(.Info, levelFromStatus(299));
}

test "levelFromStatus: 3xx maps to Info" {
    try testing.expectEqual(.Info, levelFromStatus(301));
    try testing.expectEqual(.Info, levelFromStatus(304));
    try testing.expectEqual(.Info, levelFromStatus(399));
}

test "levelFromStatus: 4xx maps to Warn" {
    try testing.expectEqual(.Warn, levelFromStatus(400));
    try testing.expectEqual(.Warn, levelFromStatus(401));
    try testing.expectEqual(.Warn, levelFromStatus(403));
    try testing.expectEqual(.Warn, levelFromStatus(404));
    try testing.expectEqual(.Warn, levelFromStatus(422));
    try testing.expectEqual(.Warn, levelFromStatus(429));
    try testing.expectEqual(.Warn, levelFromStatus(499));
}

test "levelFromStatus: 5xx maps to Error" {
    try testing.expectEqual(.Error, levelFromStatus(500));
    try testing.expectEqual(.Error, levelFromStatus(502));
    try testing.expectEqual(.Error, levelFromStatus(503));
    try testing.expectEqual(.Error, levelFromStatus(504));
    try testing.expectEqual(.Error, levelFromStatus(599));
}

// -- parseTraceparent --------------------------------------------------------

test "parseTraceparent: valid header" {
    const tp = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
    const result = parseTraceparent(tp).?;
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.span_id);
}

test "parseTraceparent: all-zero ids are valid" {
    const tp = "00-00000000000000000000000000000000-0000000000000000-00";
    const result = parseTraceparent(tp).?;
    try testing.expectEqualStrings("00000000000000000000000000000000", result.trace_id);
    try testing.expectEqualStrings("0000000000000000", result.span_id);
}

test "parseTraceparent: sampled flag 00 is valid" {
    const result = parseTraceparent("00-aaf7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00");
    try testing.expect(result != null);
}

test "parseTraceparent: extra trailing data is accepted" {
    const tp = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01-extra-stuff";
    const result = parseTraceparent(tp).?;
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.span_id);
}

test "parseTraceparent: rejects empty string" {
    try testing.expect(parseTraceparent("") == null);
}

test "parseTraceparent: rejects too-short input" {
    try testing.expect(parseTraceparent("00-abc-def-01") == null);
    try testing.expect(parseTraceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b716920333") == null);
}

test "parseTraceparent: rejects wrong version" {
    try testing.expect(parseTraceparent("01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);
    try testing.expect(parseTraceparent("ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);
}

test "parseTraceparent: rejects wrong delimiters" {
    try testing.expect(parseTraceparent("00_0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331_01") == null);
    try testing.expect(parseTraceparent("00-0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331-01") == null);
    try testing.expect(parseTraceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331_01") == null);
}

// -- Middleware integration --------------------------------------------------

const log_path = "/tmp/httpz-logger-test.log";

/// Set up logz directly for integration tests (bypasses init which needs httpz server).
fn setupLogz() void {
    setupLogzWith(.logfmt);
}

fn setupLogzWith(encoding: Encoding) void {
    logz.setup(testing.allocator, .{
        .level = .Debug,
        .output = .{ .file = log_path },
        .encoding = encoding,
        .pool_size = 2,
    }) catch unreachable;
}

/// Read the log file contents. Caller owns the returned slice.
fn readLog() ![]u8 {
    return std.fs.cwd().readFileAlloc(testing.allocator, log_path, 8192);
}

/// Delete the log file (ignore if missing).
fn cleanLog() void {
    std.fs.cwd().deleteFile(log_path) catch {};
}

fn initHt() httpz.testing.Testing {
    return httpz.testing.init(.{});
}

const NoopExecutor = struct {
    pub fn next(_: *NoopExecutor) !void {}
};

test "middleware: logs basic GET request" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/hello");
    ht.res.status = 200;
    ht.res.body = "OK";

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "method=GET") != null);
    try testing.expect(std.mem.indexOf(u8, output, "path=/hello") != null);
    try testing.expect(std.mem.indexOf(u8, output, "status=200") != null);
    try testing.expect(std.mem.indexOf(u8, output, "size=2") != null);
}

test "middleware: level filter skips 200 when config is .Error" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/ok");
    ht.res.status = 200;

    const mw = @This(){ .config = .{ .level = .Error } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = readLog() catch "";
    defer if (output.len > 0) testing.allocator.free(output);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "middleware: level filter logs 500 when config is .Error" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/fail");
    ht.res.status = 500;
    ht.res.body = "Internal Server Error";

    const mw = @This(){ .config = .{ .level = .Error } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "status=500") != null);
    try testing.expect(std.mem.indexOf(u8, output, "path=/fail") != null);
}

test "middleware: level filter logs 404 when config is .Warn" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/missing");
    ht.res.status = 404;
    ht.res.body = "Not Found";

    const mw = @This(){ .config = .{ .level = .Warn } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "status=404") != null);
}

test "middleware: traceparent header is extracted" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/traced");
    ht.header("traceparent", "00-aaf7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    ht.res.status = 200;

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "trace_id=aaf7651916cd43dd8448eb211c80319c") != null);
    try testing.expect(std.mem.indexOf(u8, output, "span_id=b7ad6b7169203331") != null);
}

test "middleware: traceparent disabled in config" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/no-trace");
    ht.header("traceparent", "00-aaf7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    ht.res.status = 200;

    const mw = @This(){ .config = .{ .log_trace_id = false, .log_span_id = false } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "trace_id=") == null);
    try testing.expect(std.mem.indexOf(u8, output, "span_id=") == null);
}

test "middleware: user-agent logged when enabled" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/ua");
    ht.header("user-agent", "TestBot/1.0");
    ht.res.status = 200;

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "user_agent=TestBot/1.0") != null);
}

test "middleware: user-agent omitted when disabled" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/no-ua");
    ht.header("user-agent", "TestBot/1.0");
    ht.res.status = 200;

    const mw = @This(){ .config = .{ .log_user_agent = false } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "user_agent=") == null);
}

test "middleware: query string logged" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/search?q=zig&page=1");
    ht.res.status = 200;

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "path=/search") != null);
    try testing.expect(std.mem.indexOf(u8, output, "q=zig&page=1") != null);
}

test "middleware: x-request-id and x-user-id headers" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/api");
    ht.header("x-request-id", "req-abc-123");
    ht.header("x-user-id", "user-42");
    ht.res.status = 200;

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "request_id=req-abc-123") != null);
    try testing.expect(std.mem.indexOf(u8, output, "user_id=user-42") != null);
}

test "middleware: .None level disables all logging" {
    cleanLog();
    setupLogz();
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/silent");
    ht.res.status = 500;

    const mw = @This(){ .config = .{ .level = .None } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = readLog() catch "";
    defer if (output.len > 0) testing.allocator.free(output);
    try testing.expectEqual(@as(usize, 0), output.len);
}

// -- JSON encoding -----------------------------------------------------------

test "middleware: json encoding logs basic request" {
    cleanLog();
    setupLogzWith(.json);
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/api/data");
    ht.res.status = 200;
    ht.res.body = "OK";

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "\"method\":\"GET\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"path\":\"/api/data\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"status\":200") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"size\":2") != null);
}

test "middleware: json encoding includes traceparent fields" {
    cleanLog();
    setupLogzWith(.json);
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/traced");
    ht.header("traceparent", "00-aaf7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
    ht.res.status = 200;

    const mw = @This(){ .config = .{} };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = try readLog();
    defer testing.allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "\"trace_id\":\"aaf7651916cd43dd8448eb211c80319c\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"span_id\":\"b7ad6b7169203331\"") != null);
}

test "middleware: json encoding respects level filter" {
    cleanLog();
    setupLogzWith(.json);
    defer logz.deinit();

    var ht = initHt();
    defer ht.deinit();

    ht.url("/ok");
    ht.res.status = 200;

    const mw = @This(){ .config = .{ .level = .Error } };
    var exec = NoopExecutor{};
    try mw.execute(ht.req, ht.res, &exec);

    const output = readLog() catch "";
    defer if (output.len > 0) testing.allocator.free(output);
    try testing.expectEqual(@as(usize, 0), output.len);
}

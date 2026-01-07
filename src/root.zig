//! HTTP request logging middleware for httpz web framework.
//!
//! This middleware automatically logs HTTP requests and responses with configurable
//! formatting, field selection, and performance optimizations.
//!
//! Features:
//! - Multiple output formats (logfmt, JSON)
//! - OpenTelemetry trace context support
//! - Configurable field selection for privacy
//! - Performance optimizations (timestamp caching, smart buffering)
//! - Automatic log level selection based on status codes

const std = @import("std");
const httpz = @import("httpz");

const constants = @import("constants.zig");
const log_level = @import("log_level.zig");
const data_extractor = @import("data_extractor.zig");
const json_formatter = @import("formatters/json.zig");
const logfmt_formatter = @import("formatters/logfmt.zig");

/// Output format for log entries.
pub const Format = enum {
    /// JSON format for structured logging systems
    json,
    /// Logfmt format (key=value pairs) for traditional logging
    logfmt,
};

/// Configuration options for the HTTP logger middleware.
pub const Config = struct {
    /// Output format: .json or .logfmt (default: .logfmt)
    format: Format = .logfmt,

    /// Minimum HTTP status code to log (0 = log all)
    min_status: u16 = 0,

    /// Minimum log level to emit (.debug, .info, .warn, .err)
    min_level: std.log.Level = .info,

    /// Include query string in logs (may contain sensitive data)
    log_query: bool = true,

    /// Include User-Agent header
    log_user_agent: bool = true,

    /// Include client IP address and port
    log_client: bool = true,

    /// Include OpenTelemetry trace ID from traceparent header
    log_trace_id: bool = true,

    /// Include OpenTelemetry span ID from traceparent header
    log_span_id: bool = true,

    /// Include X-Request-ID header for request correlation
    log_request_id: bool = true,

    /// Include X-User-ID header for user tracking
    log_user_id: bool = true,

    /// Maximum buffer size for log entries (bytes). Larger logs will be truncated.
    buffer_size: usize = constants.Buffer.DEFAULT_SIZE,

    /// Log formatting/buffer errors to stderr for debugging
    log_errors_to_stderr: bool = true,
};

config: Config,
timestamp_cache: data_extractor.TimestampCache,

/// Initialize a new HTTP logger middleware instance.
///
/// Example:
/// ```zig
/// const logger = try server.middleware(HttpLogger, .{
///     .format = .json,
///     .min_status = 400,  // Only log errors
/// });
/// ```
pub fn init(config: Config) !@This() {
    return .{
        .config = config,
        .timestamp_cache = .{},
    };
}

/// Middleware execution function called by httpz for each request.
/// This function wraps the request handler and logs the response after execution.
pub fn execute(self: *@This(), req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    const start = std.time.milliTimestamp();
    defer self.log(req, res, start);
    return executor.next();
}

fn log(self: *@This(), req: *httpz.Request, res: *httpz.Response, start: i64) void {
    const cfg = self.config;

    if (res.status < cfg.min_status) return;

    const level = log_level.fromStatus(res.status);

    // Filter by minimum log level
    if (@intFromEnum(level) > @intFromEnum(cfg.min_level)) return;

    const data = data_extractor.extractWithCache(req, res, start, .{
        .log_query = cfg.log_query,
        .log_user_agent = cfg.log_user_agent,
        .log_client = cfg.log_client,
        .log_trace_id = cfg.log_trace_id,
        .log_span_id = cfg.log_span_id,
        .log_request_id = cfg.log_request_id,
        .log_user_id = cfg.log_user_id,
    }, &self.timestamp_cache);

    // Stack-allocate buffer up to threshold, heap-allocate for larger sizes
    if (cfg.buffer_size <= constants.Buffer.STACK_THRESHOLD) {
        var stack_buf: [constants.Buffer.STACK_THRESHOLD]u8 = undefined;
        const buf = stack_buf[0..cfg.buffer_size];
        self.formatAndLog(data, level, buf);
    } else {
        // For large buffers, use heap allocation
        const allocator = std.heap.page_allocator;
        const buf = allocator.alloc(u8, cfg.buffer_size) catch {
            if (cfg.log_errors_to_stderr) {
                std.debug.print("httpz_logger: Failed to allocate buffer of size {d}\n", .{cfg.buffer_size});
            }
            return;
        };
        defer allocator.free(buf);
        self.formatAndLog(data, level, buf);
    }
}

fn formatAndLog(self: *const @This(), data: data_extractor.LogData, level: std.log.Level, buf: []u8) void {
    const cfg = self.config;
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();

    const format_result = switch (cfg.format) {
        .json => json_formatter.formatWriter(data, level, writer),
        .logfmt => logfmt_formatter.formatWriter(data, level, writer),
    };

    if (format_result) |_| {
        const output = stream.getWritten();

        // Check if we hit the buffer limit
        if (stream.pos == buf.len and cfg.log_errors_to_stderr) {
            // Log was likely truncated
            log_level.dispatch(level, output);
            std.debug.print("httpz_logger: Log entry truncated (buffer size: {d})\n", .{cfg.buffer_size});
        } else {
            log_level.dispatch(level, output);
        }
    } else |err| {
        if (cfg.log_errors_to_stderr) {
            std.debug.print("httpz_logger: Failed to format log: {}\n", .{err});
        }
    }
}

// Reference all submodules to include their tests
test {
    _ = @import("timestamp.zig");
    _ = @import("log_level.zig");
    _ = @import("data_extractor.zig");
    _ = @import("formatters/json.zig");
    _ = @import("formatters/logfmt.zig");
    _ = @import("tests/timestamp_fuzz.zig");
    _ = @import("tests/formatter_fuzz.zig");
    // Integration tests would require a full httpz server setup
    // For now, our unit and property tests provide good coverage
}

// Additional module tests
test {
    _ = @import("constants.zig");
    _ = @import("errors.zig");
    _ = @import("type_safety.zig");
    _ = @import("memory.zig");
}

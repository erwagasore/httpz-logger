const std = @import("std");
const httpz = @import("httpz");

const log_level = @import("log_level.zig");
const data_extractor = @import("data_extractor.zig");
const json_formatter = @import("formatters/json.zig");
const logfmt_formatter = @import("formatters/logfmt.zig");

pub const Format = enum { json, logfmt };

pub const Config = struct {
    format: Format = .logfmt,
    min_status: u16 = 0,
    min_level: std.log.Level = .info,
    log_query: bool = true,
    log_user_agent: bool = true,
    log_client: bool = true,
    log_trace_id: bool = true,
    log_span_id: bool = true,
    log_request_id: bool = true,
    log_user_id: bool = true,
};

config: Config,

pub fn init(config: Config) !@This() {
    return .{ .config = config };
}

pub fn execute(self: *const @This(), req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    const start = std.time.milliTimestamp();
    defer self.log(req, res, start);
    return executor.next();
}

fn log(self: *const @This(), req: *httpz.Request, res: *httpz.Response, start: i64) void {
    const cfg = self.config;

    if (res.status < cfg.min_status) return;

    const level = log_level.fromStatus(res.status);

    // Filter by minimum log level
    if (@intFromEnum(level) > @intFromEnum(cfg.min_level)) return;

    const data = data_extractor.extract(req, res, start, .{
        .log_query = cfg.log_query,
        .log_user_agent = cfg.log_user_agent,
        .log_client = cfg.log_client,
        .log_trace_id = cfg.log_trace_id,
        .log_span_id = cfg.log_span_id,
        .log_request_id = cfg.log_request_id,
        .log_user_id = cfg.log_user_id,
    });

    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    switch (cfg.format) {
        .json => json_formatter.format(data, level, &w) catch return,
        .logfmt => logfmt_formatter.format(data, level, &w) catch return,
    }

    log_level.dispatch(level, w.buffered());
}

// Reference all submodules to include their tests
test {
    _ = @import("timestamp.zig");
    _ = @import("log_level.zig");
    _ = @import("data_extractor.zig");
    _ = @import("formatters/json.zig");
    _ = @import("formatters/logfmt.zig");
}

const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const HttpLogger = @import("httpz_logger");

const PORT = 8080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialise logz (required before using httpz-logger).
    try logz.setup(allocator, .{
        .level = .Debug,
        .output = .stdout,
    });
    defer logz.deinit();

    var server = try httpz.Server(void).init(allocator, .{ .port = PORT }, {});
    defer server.deinit();
    defer server.stop();

    // Register the logging middleware at the server level so it
    // also covers unmatched routes (404s).
    const logger = try server.middleware(HttpLogger, .{ .level = .Info });

    var router = try server.router(.{ .middlewares = &.{logger} });

    router.get("/", index, .{});
    router.get("/health", health, .{});
    router.get("/error", triggerError, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = "Hello, World!";
}

fn health(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = "OK";
}

fn triggerError(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 500;
    res.body = "Internal Server Error";
}

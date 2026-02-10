const std = @import("std");
const httpz = @import("httpz");
const HttpLogger = @import("httpz_logger");

const PORT = 8080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(void).init(allocator, .{ .port = PORT }, {});
    defer server.deinit();
    defer server.stop();

    // One line — logging is ready. No logz setup needed.
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

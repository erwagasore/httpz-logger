# httpz-logger

Request logging middleware for [httpz](https://github.com/karlseguin/http.zig) with distributed tracing support.

Built on [logz](https://github.com/karlseguin/log.zig) for high-performance structured logging.

## Quickstart

```bash
git clone git@github.com:erwagasore/httpz-logger.git
cd httpz-logger
zig build              # build library + example
zig build test         # run unit tests
zig build run          # run example server on :8080
```

### As a dependency

Add to `build.zig.zon`:

```zig
.httpz_logger = .{
    .url = "git+https://github.com/erwagasore/httpz-logger#main",
    .hash = "...",
},
```

Add to `build.zig`:

```zig
const httpz_logger = b.dependency("httpz_logger", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("httpz_logger", httpz_logger.module("httpz_logger"));
```

## Usage

```zig
const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const HttpLogger = @import("httpz_logger");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialise logz first (required).
    try logz.setup(allocator, .{ .level = .Info, .output = .stdout });
    defer logz.deinit();

    var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
    defer server.deinit();
    defer server.stop();

    // Register the middleware.
    const logger = try server.middleware(HttpLogger, .{});

    var router = try server.router(.{});
    router.middlewares = &.{logger};
    router.get("/", handleIndex, .{});

    try server.listen();
}
```

## Output

Encoding is controlled by logz — the middleware is format-agnostic.

**logfmt** (default):
```
@ts=1735689600000 @l=INFO method=GET path=/api/users status=200 size=45 duration_ms=12 trace_id=0af7651916cd43dd8448eb211c80319c span_id=b7ad6b7169203331
```

**JSON** (`logz.setup(allocator, .{ .encoding = .json })`):
```json
{"@ts":1735689600000,"@l":"INFO","method":"GET","path":"/api/users","status":200,"size":45,"duration_ms":12,"trace_id":"0af7651916cd43dd8448eb211c80319c","span_id":"b7ad6b7169203331"}
```

## Configuration

```zig
const logger = try server.middleware(HttpLogger, .{
    .level = .Warn,           // Only log 4xx and 5xx
    .log_query = true,        // Include query string
    .log_user_agent = false,  // Exclude User-Agent
    .log_client = true,       // Include client IP
    .log_trace_id = true,     // Include trace_id from traceparent
    .log_span_id = true,      // Include span_id from traceparent
    .log_request_id = true,   // Include X-Request-ID header
    .log_user_id = true,      // Include X-User-ID header
});
```

### Log Levels (Cascading)

| Level | What Gets Logged |
|-------|------------------|
| `.Debug` | All requests |
| `.Info` | All requests (default) |
| `.Warn` | 4xx and 5xx only |
| `.Error` | 5xx only |
| `.None` | Nothing |

## Distributed Tracing

Automatically extracts trace context from W3C `traceparent` headers:

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
```

Enables log correlation in Grafana Loki, Jaeger, Datadog, etc.

## Structure

See [AGENTS.md](AGENTS.md#repo-map) for the full repo map.

## License

MIT

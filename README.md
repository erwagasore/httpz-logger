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
const HttpLogger = @import("httpz_logger");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
    defer server.deinit();
    defer server.stop();

    // One line — logging is ready.
    const logger = try server.middleware(HttpLogger, .{});

    var router = try server.router(.{ .middlewares = &.{logger} });
    router.get("/", handleIndex, .{});

    try server.listen();
}
```

No logz import, no logz setup — the middleware handles it.

## Output

**logfmt** (default):
```
@ts=1735689600000 @l=INFO method=GET path=/api/users status=200 size=45 duration_ms=12 trace_id=0af7651916cd43dd8448eb211c80319c span_id=b7ad6b7169203331
```

**JSON** (`.encoding = .json`):
```json
{"@ts":1735689600000,"@l":"INFO","method":"GET","path":"/api/users","status":200,"size":45,"duration_ms":12,"trace_id":"0af7651916cd43dd8448eb211c80319c","span_id":"b7ad6b7169203331"}
```

## Configuration

```zig
const logger = try server.middleware(HttpLogger, .{
    .level = .Warn,           // Only log 4xx and 5xx
    .output = .stderr,        // Write to stderr (default: .stdout)
    .encoding = .json,        // JSON output (default: .logfmt)
    .log_query = true,        // Include query string
    .log_user_agent = false,  // Exclude User-Agent
    .log_client = true,       // Include client IP
    .log_trace_id = true,     // Include trace_id from traceparent
    .log_span_id = true,      // Include span_id from traceparent
    .log_request_id = true,   // Include X-Request-ID header
    .log_user_id = true,      // Include X-User-ID header
    .pool_size = 64,          // Pre-allocated log buffers (default: 32)
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

### Output Destinations

| Value | Description |
|-------|-------------|
| `.stdout` | Standard output (default) |
| `.stderr` | Standard error |
| `.{ .file = "/var/log/app.log" }` | Write to file |

## Middleware Ordering

Place the logger **early** in the chain — after CORS, before auth and other
middleware. The `defer`-based design captures the final response status regardless
of where in the chain the response was decided.

```zig
const cors = try server.middleware(httpz.middleware.Cors, .{ .origin = "*" });
const logger = try server.middleware(HttpLogger, .{});
const auth = try server.middleware(AuthMiddleware, .{});

var router = try server.router(.{ .middlewares = &.{ cors, logger, auth } });
```

| Position | Middleware | Why |
|----------|-----------|-----|
| 1st | CORS | Short-circuits preflight noise before the logger |
| 2nd | **Logger** | Sees everything except preflights |
| 3rd+ | Auth, rate limiter, etc. | Rejections are still captured by the logger |

If the logger is placed **last**, requests rejected by upstream middleware
(401, 403, 429) are never logged — the logger's `execute` is never called.

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

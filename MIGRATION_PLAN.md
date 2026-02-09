# httpz-logger v2: Fresh Implementation Plan

## Context

This document outlines a complete rewrite of httpz-logger. The repository will be re-initialized, starting fresh with lessons learned from v1.

---

## Historical Reference: v1 Architecture

The original implementation (~1200 lines) included:

### Files (v1)
| File | Lines | Purpose |
|------|-------|---------|
| `src/root.zig` | 402 | Main middleware, buffer management, log dispatch |
| `src/data_extractor.zig` | 444 | Request/response data extraction, JSON/logfmt formatting |
| `src/timestamp.zig` | 185 | ISO 8601 timestamp formatting with caching |
| `src/constants.zig` | 171 | Buffer sizes, time constants, traceparent offsets |

### Features (v1)
- Custom JSON and logfmt formatters
- Thread-local buffers (2KB primary + 8KB fallback)
- ISO 8601 timestamps with per-second caching
- W3C traceparent header parsing
- Configurable field extraction
- Status-based log level detection

### Limitations Identified (v1)
1. Reinvented logging infrastructure that logz already provides
2. Custom buffer management added complexity
3. ISO 8601 timestamps less standard than epoch milliseconds
4. `init()` returned error union but could never fail
5. `min_status` and `min_level` were redundant
6. Nested config (`fields.log_*`) was awkward
7. No output destination flexibility (only `std.log`)
8. No metrics for monitoring buffer exhaustion

### Key Insight
HTTP logging middleware should focus on **what** to log (extracting HTTP-specific data), not **how** to log (formatting, buffering, output). This is the dominant pattern in Go (chi + zerolog), Rust (axum + tracing), and Node.js (express + pino).

---

## v2 Architecture

### Design Principles

1. **Delegate logging to logz** - focus only on HTTP concerns
2. **Single file implementation** - minimal surface area
3. **Flat configuration** - no nested structs
4. **Cascading log levels** - one setting controls filtering
5. **Keep traceparent parsing** - this is the HTTP-specific value-add

### Dependencies

| Dependency | Purpose |
|------------|---------|
| `httpz` | HTTP framework (existing) |
| `logz` | Structured logging (new) |

### Project Structure

```
httpz-logger/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── src/
│   └── root.zig          # Single source file (~100 lines)
├── examples/
│   └── basic_server.zig  # Runnable example
├── build.zig
├── build.zig.zon
├── .gitignore
├── .editorconfig
├── LICENSE
└── README.md
```

---

## Implementation

### `build.zig.zon`

```zig
.{
    .name = .httpz_logger,
    .version = "0.3.0",
    .minimum_zig_version = "0.15.0",
    .dependencies = .{
        .httpz = .{
            .url = "git+https://github.com/karlseguin/http.zig?ref=dev#cf8fc80b3745257497e83af913c84fe645b30086",
            .hash = "httpz-0.0.0-PNVzrLXyBgAs425jxkppDbrck8Tv8HyEYCqC60IUQqOQ",
        },
        .logz = .{
            .url = "git+https://github.com/karlseguin/log.zig#master",
            .hash = "...",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

### `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const httpz = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const logz = b.dependency("logz", .{ .target = target, .optimize = optimize });

    _ = b.addModule("httpz_logger", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "httpz", .module = httpz.module("httpz") },
            .{ .name = "logz", .module = logz.module("logz") },
        },
    });

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz.module("httpz") },
                .{ .name = "logz", .module = logz.module("logz") },
            },
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

### `src/root.zig`

```zig
//! HTTP request logging middleware for httpz.
//!
//! A thin extraction layer that logs HTTP request/response data via logz.
//! Supports W3C traceparent header parsing for distributed tracing.
//!
//! ## Usage
//!
//! ```zig
//! // In main(), initialize logz first
//! try logz.setup(allocator, .{ .level = .Info, .output = .stdout });
//! defer logz.deinit();
//!
//! // Then use the middleware
//! const logger = server.middleware(HttpLogger, .{});
//! ```

const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");

/// Configuration for the HTTP logger middleware.
pub const Config = struct {
    /// Minimum log level (cascading).
    /// - .Debug: log all requests
    /// - .Info: log all requests (default)
    /// - .Warn: log 4xx and 5xx only
    /// - .Error: log 5xx only
    /// - .None: disable logging
    level: logz.Level = .Info,

    /// Include query string in logs
    log_query: bool = true,
    /// Include User-Agent header in logs
    log_user_agent: bool = true,
    /// Include client IP address in logs
    log_client: bool = true,
    /// Include trace_id from traceparent header
    log_trace_id: bool = true,
    /// Include span_id from traceparent header
    log_span_id: bool = true,
    /// Include X-Request-ID header in logs
    log_request_id: bool = true,
    /// Include X-User-ID header in logs
    log_user_id: bool = true,
};

config: Config,

/// Initialize the middleware with the given configuration.
pub fn init(config: Config) @This() {
    return .{ .config = config };
}

/// Middleware execution - called by httpz for each request.
pub fn execute(self: *@This(), req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    const start = std.time.milliTimestamp();
    defer self.log(req, res, std.time.milliTimestamp() - start);
    return executor.next();
}

fn log(self: *const @This(), req: *httpz.Request, res: *httpz.Response, duration_ms: i64) void {
    const level = levelFromStatus(res.status);

    // Cascading filter: skip if detected level is below configured minimum
    if (@intFromEnum(level) < @intFromEnum(self.config.level)) return;

    var logger = logz.loggerL(level)
        .string("method", @tagName(req.method))
        .string("path", req.url.path)
        .int("status", res.status)
        .int("size", res.body.len)
        .int("duration_ms", duration_ms);

    if (self.config.log_client) {
        var buf: [64]u8 = undefined;
        var writer = std.io.fixedBufferStream(&buf);
        if (req.address.format(writer.writer())) {
            _ = logger.string("client", writer.getWritten());
        }
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

/// Parses W3C traceparent header: 00-{trace_id}-{span_id}-{flags}
/// Returns trace_id (32 hex chars) and span_id (16 hex chars).
pub fn parseTraceparent(header: []const u8) ?struct { trace_id: []const u8, span_id: []const u8 } {
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
    // 5xx -> Error
    try testing.expectEqual(logz.Level.Error, levelFromStatus(500));
    try testing.expectEqual(logz.Level.Error, levelFromStatus(503));
    try testing.expectEqual(logz.Level.Error, levelFromStatus(599));

    // 4xx -> Warn
    try testing.expectEqual(logz.Level.Warn, levelFromStatus(400));
    try testing.expectEqual(logz.Level.Warn, levelFromStatus(404));
    try testing.expectEqual(logz.Level.Warn, levelFromStatus(499));

    // 2xx, 3xx -> Info
    try testing.expectEqual(logz.Level.Info, levelFromStatus(200));
    try testing.expectEqual(logz.Level.Info, levelFromStatus(201));
    try testing.expectEqual(logz.Level.Info, levelFromStatus(301));
    try testing.expectEqual(logz.Level.Info, levelFromStatus(304));
}

test "parseTraceparent with valid header" {
    const header = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
    const result = parseTraceparent(header);
    try testing.expect(result != null);
    try testing.expectEqualStrings("0af7651916cd43dd8448eb211c80319c", result.?.trace_id);
    try testing.expectEqualStrings("b7ad6b7169203331", result.?.span_id);
}

test "parseTraceparent with invalid headers" {
    // Too short
    try testing.expect(parseTraceparent("") == null);
    try testing.expect(parseTraceparent("00-abc-def-01") == null);

    // Wrong version
    try testing.expect(parseTraceparent("01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);
    try testing.expect(parseTraceparent("ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") == null);

    // Wrong delimiters
    try testing.expect(parseTraceparent("00_0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331_01") == null);
}
```

### `examples/basic_server.zig`

```zig
const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const HttpLogger = @import("httpz_logger");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logz
    try logz.setup(allocator, .{
        .level = .Debug,
        .pool_size = 100,
        .output = .stdout,
    });
    defer logz.deinit();

    // Create server
    var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
    defer server.deinit();

    // Add logging middleware
    const logger = server.middleware(HttpLogger, .{
        .level = .Info,
    });

    // Setup routes
    var router = try server.router(.{ .middlewares = &.{logger} });
    router.get("/", index, .{});
    router.get("/health", health, .{});
    router.get("/error", triggerError, .{});

    std.debug.print("Server listening on http://localhost:8080\n", .{});
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
```

---

## README.md

```markdown
# httpz-logger

Request logging middleware for [httpz](https://github.com/karlseguin/http.zig) with OpenTelemetry support.

Built on [logz](https://github.com/karlseguin/log.zig) for high-performance structured logging.

## Features

- Structured logging via logz (logfmt or JSON)
- W3C traceparent header parsing for distributed tracing
- Cascading log levels (filter by severity)
- Configurable field extraction
- Zero-allocation design (uses logz's buffer pool)

## Output

```
@ts=1735689600000 @l=INFO method=GET path=/api/users status=200 size=45 duration_ms=12 trace_id=0af7651916cd43dd8448eb211c80319c span_id=b7ad6b7169203331
```

## Installation

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

    // Initialize logz first (required)
    try logz.setup(allocator, .{
        .level = .Info,
        .pool_size = 100,
        .output = .stdout,
    });
    defer logz.deinit();

    var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
    defer server.deinit();

    // Add middleware
    const logger = server.middleware(HttpLogger, .{});

    var router = try server.router(.{ .middlewares = &.{logger} });
    router.get("/", handleIndex, .{});

    try server.listen();
}
```

## Configuration

```zig
const logger = server.middleware(HttpLogger, .{
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

## OpenTelemetry Support

Automatically extracts trace context from W3C `traceparent` header:

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
```

Enables log correlation in Grafana Loki, Jaeger, Datadog, etc.

## License

MIT
```

---

## Configuration Files

### `.gitignore`

```
.zig-cache/
zig-out/
```

### `.editorconfig`

```
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8

[*.zig]
indent_style = space
indent_size = 4
```

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Cache Zig dependencies
        uses: actions/cache@v4
        with:
          path: |
            ~/.cache/zig
            .zig-cache
          key: ${{ runner.os }}-zig-${{ hashFiles('build.zig.zon') }}
          restore-keys: |
            ${{ runner.os }}-zig-

      - name: Check formatting
        run: zig fmt --check .

      - name: Build
        run: zig build --summary all

      - name: Run tests
        run: zig build test --summary all
```

---

## Implementation Checklist

```
[ ] Initialize new git repository
[ ] Create .gitignore
[ ] Create .editorconfig
[ ] Create LICENSE (MIT)
[ ] Create build.zig.zon with httpz and logz dependencies
[ ] Create build.zig
[ ] Create src/root.zig
[ ] Run `zig build` to verify compilation
[ ] Run `zig build test` to verify tests pass
[ ] Run `zig fmt .` to format code
[ ] Create examples/basic_server.zig
[ ] Create README.md
[ ] Create .github/workflows/ci.yml
[ ] Initial commit
[ ] Push to GitHub
[ ] Tag v0.3.0
```

---

## Comparison: v1 vs v2

| Aspect | v1 | v2 |
|--------|----|----|
| Source files | 4 | 1 |
| Lines of code | ~1200 | ~100 |
| Dependencies | httpz | httpz, logz |
| Buffer management | Custom | logz |
| Output formats | Custom | logz |
| Timestamp | ISO 8601 | Epoch ms |
| Configuration | Nested | Flat |
| Level filtering | min_status + min_level | Single cascading level |
| Metrics | None | Via logz |
| Output destinations | std.log only | stdout, stderr, file, custom |

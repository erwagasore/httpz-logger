# Changelog

## [Unreleased]

### Fixes

- Update httpz to revision `01dc094` for compatibility with the latest middleware ecosystem.

## [2.0.1] — 2026-04-29

### Other

- Switch logz dependency back to upstream `karlseguin/log.zig` now that the Zig 0.16 timestamp fix has merged

## [2.0.0] — 2026-04-28

### Breaking Changes

- Require Zig 0.16.x and update httpz-logger to the Zig 0.16 `std.process.Init` and `std.Io` APIs
- Require `Config.io` when automatic logz setup is enabled so logz can write output and timestamps via Zig 0.16 I/O

### Other

- Update httpz to latest `master` for Zig 0.16
- Temporarily point logz to the forked Zig 0.16 timestamp fix branch pending upstream merge

## [1.0.2] — 2026-02-14

### Other

- Simplify client address logging using logz's `fmt` method instead of manual stack buffer
- Remove completed migration plan and update repo map

## [1.0.1] — 2026-02-10

### Fixes

- Log correct HTTP status on handler errors — set 500 when status is still default, preserve explicit error status (e.g. 503)
- Document recommended middleware ordering: CORS → Logger → Auth

## [1.0.0] — 2026-02-10

### Breaking Changes

- `init` now takes `(Config, httpz.MiddlewareConfig)` — logz is set up automatically; users no longer need to import or configure logz directly

### Features

- Middleware handles full logging backend lifecycle (setup and teardown)
- Re-exported `Level`, `Output`, `Encoding` types for self-contained configuration
- Config absorbs `output`, `encoding`, and `pool_size` settings

### Other

- 26 tests: expanded unit tests and added integration tests for both logfmt and JSON encodings

## [0.1.0] — 2026-02-09

### Features

- HTTP request logging middleware for httpz backed by logz
- Flat configuration with cascading log levels (Debug → None)
- W3C traceparent header parsing for distributed tracing
- Configurable field extraction (query, user-agent, client IP, request/user IDs)
- Runnable example server

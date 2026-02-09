//! HTTP request logging middleware for httpz.
//!
//! A thin extraction layer that logs HTTP request/response data via logz.
//! Supports W3C traceparent header parsing for distributed tracing.

const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");

test {
    _ = std.testing.refAllDecls(@This());
}

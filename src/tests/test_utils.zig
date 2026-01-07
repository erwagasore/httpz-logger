//! Common test utilities for fuzz testing.
//!
//! Provides reusable fuzzing utilities and helper functions
//! for property-based testing across the codebase.

const std = @import("std");
const constants = @import("../constants.zig");

/// Fuzzer for generating random test data
pub const Fuzzer = struct {
    rng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Fuzzer {
        return .{
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    pub fn randomString(self: *Fuzzer, buf: []u8) []u8 {
        const random = self.rng.random();
        const len = random.intRangeAtMost(usize, 0, buf.len);
        for (buf[0..len]) |*c| {
            c.* = random.int(u8);
        }
        return buf[0..len];
    }

    pub fn randomPrintableString(self: *Fuzzer, buf: []u8) []u8 {
        const random = self.rng.random();
        const len = random.intRangeAtMost(usize, 0, buf.len);
        for (buf[0..len]) |*c| {
            // Generate printable ASCII (32-126) plus some special chars
            c.* = switch (random.intRangeAtMost(u8, 0, 10)) {
                0 => '\n',
                1 => '\r',
                2 => '\t',
                3 => '"',
                4 => '\\',
                else => random.intRangeAtMost(u8, 32, 126),
            };
        }
        return buf[0..len];
    }

    pub fn randomHexString(self: *Fuzzer, buf: []u8) []u8 {
        const hex_chars = "0123456789abcdef";
        const random = self.rng.random();
        for (buf) |*c| {
            const idx = random.intRangeAtMost(usize, 0, hex_chars.len - 1);
            c.* = hex_chars[idx];
        }
        return buf;
    }

    pub fn randomMethod(self: *Fuzzer) []const u8 {
        const methods = [_][]const u8{ "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH", "CONNECT", "TRACE" };
        const random = self.rng.random();
        return methods[random.intRangeAtMost(usize, 0, methods.len - 1)];
    }

    pub fn randomStatusCode(self: *Fuzzer) u16 {
        const random = self.rng.random();
        return switch (random.intRangeAtMost(u8, 0, 5)) {
            0 => random.intRangeAtMost(u16, constants.StatusCode.INFO_MIN, constants.StatusCode.INFO_MAX),
            1 => random.intRangeAtMost(u16, constants.StatusCode.SUCCESS_MIN, constants.StatusCode.SUCCESS_MAX),
            2 => random.intRangeAtMost(u16, constants.StatusCode.REDIRECT_MIN, constants.StatusCode.REDIRECT_MAX),
            3 => random.intRangeAtMost(u16, constants.StatusCode.CLIENT_ERROR_MIN, constants.StatusCode.CLIENT_ERROR_MAX),
            4 => random.intRangeAtMost(u16, constants.StatusCode.SERVER_ERROR_MIN, constants.StatusCode.SERVER_ERROR_MAX),
            else => random.intRangeAtMost(u16, 100, 599),
        };
    }

    pub fn randomLogLevel(self: *Fuzzer) std.log.Level {
        const random = self.rng.random();
        return switch (random.intRangeAtMost(u8, 0, 3)) {
            0 => .debug,
            1 => .info,
            2 => .warn,
            else => .err,
        };
    }
};

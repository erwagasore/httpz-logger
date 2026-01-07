//! Compile-time type safety checks and validation.

const std = @import("std");
const constants = @import("constants.zig");

/// Compile-time assertions to ensure type safety
pub fn validateTypes() void {
    comptime {
        // Ensure timestamp buffer is exactly 20 bytes for ISO8601 format
        std.debug.assert(@sizeOf([20]u8) == 20);

        // Ensure buffer constants are powers of 2 for alignment
        std.debug.assert(@popCount(@as(u32, constants.Buffer.SMALL)) == 1);
        std.debug.assert(@popCount(@as(u32, constants.Buffer.MEDIUM)) == 1);
        std.debug.assert(@popCount(@as(u32, constants.Buffer.LARGE)) == 1);
        std.debug.assert(@popCount(@as(u32, constants.Buffer.STACK_THRESHOLD)) == 1);

        // Ensure status code ranges are valid
        std.debug.assert(constants.StatusCode.INFO_MIN < constants.StatusCode.INFO_MAX);
        std.debug.assert(constants.StatusCode.SUCCESS_MIN < constants.StatusCode.SUCCESS_MAX);
        std.debug.assert(constants.StatusCode.REDIRECT_MIN < constants.StatusCode.REDIRECT_MAX);
        std.debug.assert(constants.StatusCode.CLIENT_ERROR_MIN < constants.StatusCode.CLIENT_ERROR_MAX);
        std.debug.assert(constants.StatusCode.SERVER_ERROR_MIN < constants.StatusCode.SERVER_ERROR_MAX);

        // Ensure time constants are positive
        std.debug.assert(constants.Time.SECONDS_PER_DAY > 0);
        std.debug.assert(constants.Time.DAYS_PER_YEAR > 0);
        std.debug.assert(constants.Time.EPOCH_YEAR > 0);
        std.debug.assert(constants.Time.MAX_YEAR > constants.Time.EPOCH_YEAR);
    }
}

// Run validations at compile time
comptime {
    validateTypes();
}

//! Fuzz tests for timestamp module.

const std = @import("std");
const testing = std.testing;
const constants = @import("../constants.zig");
const Timestamp = @import("../timestamp.zig");
const test_utils = @import("test_utils.zig");

test "fuzz: timestamp year calculation edge cases" {
    var fuzzer = test_utils.Fuzzer.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < constants.Test.FUZZ_ITERATIONS) : (i += 1) {
        const base_year = fuzzer.rng.random().intRangeAtMost(i32, constants.Time.EPOCH_YEAR, 2100);
        const day_offset = fuzzer.rng.random().intRangeAtMost(i32, -30, 30);
        const year_days: i64 = @as(i64, base_year - constants.Time.EPOCH_YEAR) * constants.Time.DAYS_PER_YEAR;
        const ts_value = year_days *% constants.Time.SECONDS_PER_DAY +% day_offset *% constants.Time.SECONDS_PER_DAY;

        var ts = Timestamp.init(ts_value);
        const year = ts.year();
        const month = ts.month();
        const day = ts.dayOfMonth();

        try testing.expect(year >= constants.Time.EPOCH_YEAR and year <= constants.Time.MAX_YEAR);
        try testing.expect(month >= 1 and month <= 12);
        try testing.expect(day >= 1 and day <= 31);

        var buf: [20]u8 = undefined;
        const formatted = ts.iso8601(&buf);
        try testing.expect(formatted.len > 0);
    }
}

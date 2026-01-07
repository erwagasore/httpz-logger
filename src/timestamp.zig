const std = @import("std");
const constants = @import("constants.zig");

const Self = @This();

/// Seconds per minute
const SECS_PER_MIN: i64 = 60;
/// Seconds per hour
const SECS_PER_HOUR: i64 = 60 * SECS_PER_MIN;
/// Seconds per day
const SECS_PER_DAY: i64 = constants.Time.SECONDS_PER_DAY;

/// Days in each month (non-leap year)
const DAYS_IN_MONTH = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

timestamp: i64,

// Cached date components (computed once)
cached_year: u16 = 0,
cached_day_of_year: u16 = 0,
cached: bool = false,

pub fn now() Self {
    return .{ .timestamp = std.time.timestamp() };
}

pub fn init(ts: i64) Self {
    return .{ .timestamp = ts };
}

/// Formats timestamp as ISO 8601: "YYYY-MM-DDTHH:MM:SSZ"
pub fn iso8601(self: *Self, buf: *[20]u8) []const u8 {
    self.ensureCached();
    const md = monthAndDay(self.cached_year, self.cached_day_of_year);

    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        self.cached_year,
        md.month,
        md.day,
        self.hour(),
        self.minute(),
        self.second(),
    }) catch unreachable;
    return buf;
}

pub fn year(self: *Self) u16 {
    self.ensureCached();
    return self.cached_year;
}

pub fn month(self: *Self) u8 {
    self.ensureCached();
    return monthAndDay(self.cached_year, self.cached_day_of_year).month;
}

pub fn dayOfMonth(self: *Self) u8 {
    self.ensureCached();
    return monthAndDay(self.cached_year, self.cached_day_of_year).day;
}

pub fn dayOfYear(self: *Self) u16 {
    self.ensureCached();
    return self.cached_day_of_year;
}

pub fn hour(self: *const Self) u8 {
    return @intCast(@mod(@divFloor(self.timestamp, SECS_PER_HOUR), 24));
}

pub fn minute(self: *const Self) u8 {
    return @intCast(@mod(@divFloor(self.timestamp, SECS_PER_MIN), 60));
}

pub fn second(self: *const Self) u8 {
    return @intCast(@mod(self.timestamp, 60));
}

pub fn daysSinceEpoch(self: *const Self) i64 {
    return @divFloor(self.timestamp, SECS_PER_DAY);
}

fn ensureCached(self: *Self) void {
    if (self.cached) return;

    var remaining = self.daysSinceEpoch();

    // Handle dates before Unix epoch (1970)
    if (remaining < 0) {
        // Clamp to minimum valid date
        self.cached_year = constants.Time.EPOCH_YEAR;
        self.cached_day_of_year = 1;
        self.cached = true;
        return;
    }

    // Handle dates after reasonable maximum (year 9999)
    if (remaining > constants.Time.DAYS_PER_YEAR * constants.Time.MAX_YEARS_FROM_EPOCH) {
        self.cached_year = constants.Time.MAX_YEAR;
        self.cached_day_of_year = constants.Time.DAYS_PER_YEAR;
        self.cached = true;
        return;
    }

    var y: u16 = constants.Time.EPOCH_YEAR;
    while (true) {
        const days_in_year: i64 = if (isLeapYear(y)) constants.Time.DAYS_PER_LEAP_YEAR else constants.Time.DAYS_PER_YEAR;
        if (remaining < days_in_year) break;
        remaining -= days_in_year;
        y += 1;
        if (y > constants.Time.MAX_YEAR) {
            // Prevent overflow
            y = constants.Time.MAX_YEAR;
            break;
        }
    }

    self.cached_year = y;
    self.cached_day_of_year = @intCast(@max(1, @min(366, remaining + 1)));
    self.cached = true;
}

fn monthAndDay(y: u16, day_of_year: u16) struct { month: u8, day: u8 } {
    var remaining = day_of_year;
    const leap = isLeapYear(y);

    for (DAYS_IN_MONTH, 0..) |days, i| {
        var month_days = days;
        if (i == 1 and leap) month_days = 29;
        if (remaining <= month_days) return .{ .month = @intCast(i + 1), .day = @intCast(remaining) };
        remaining -= month_days;
    }
    return .{ .month = 12, .day = @intCast(remaining) };
}

fn isLeapYear(y: u16) bool {
    return (@mod(y, constants.LeapYear.DIVISOR_4) == 0 and @mod(y, constants.LeapYear.DIVISOR_100) != 0) or (@mod(y, constants.LeapYear.DIVISOR_400) == 0);
}

const testing = std.testing;

test "unix epoch" {
    var ts = init(0);
    try testing.expectEqual(@as(u16, constants.Time.EPOCH_YEAR), ts.year());
    try testing.expectEqual(@as(u8, 1), ts.month());
    try testing.expectEqual(@as(u8, 1), ts.dayOfMonth());
    try testing.expectEqual(@as(u8, 0), ts.hour());
    try testing.expectEqual(@as(u8, 0), ts.minute());
    try testing.expectEqual(@as(u8, 0), ts.second());
}

test "known date 2024-02-29 (leap year)" {
    var ts = init(1709209845);
    try testing.expectEqual(@as(u16, 2024), ts.year());
    try testing.expectEqual(@as(u8, 2), ts.month());
    try testing.expectEqual(@as(u8, 29), ts.dayOfMonth());
    try testing.expectEqual(@as(u8, 12), ts.hour());
    try testing.expectEqual(@as(u8, 30), ts.minute());
    try testing.expectEqual(@as(u8, 45), ts.second());
}

test "year 2000 (leap year, divisible by 100 and 400)" {
    var ts = init(951868800);
    try testing.expectEqual(@as(u16, 2000), ts.year());
    try testing.expectEqual(@as(u8, 3), ts.month());
    try testing.expectEqual(@as(u8, 1), ts.dayOfMonth());
}

test "year 2100 (not a leap year)" {
    var ts = init(4107542400);
    try testing.expectEqual(@as(u16, 2100), ts.year());
    try testing.expectEqual(@as(u8, 3), ts.month());
    try testing.expectEqual(@as(u8, 1), ts.dayOfMonth());
}

test "end of year" {
    var ts = init(1704067199);
    try testing.expectEqual(@as(u16, 2023), ts.year());
    try testing.expectEqual(@as(u8, 12), ts.month());
    try testing.expectEqual(@as(u8, 31), ts.dayOfMonth());
    try testing.expectEqual(@as(u8, 23), ts.hour());
    try testing.expectEqual(@as(u8, 59), ts.minute());
    try testing.expectEqual(@as(u8, 59), ts.second());
}

test "iso8601 format" {
    var ts = init(1704067199);
    var buf: [20]u8 = undefined;
    const result = ts.iso8601(&buf);
    try testing.expectEqualStrings("2023-12-31T23:59:59Z", result);
}

test "iso8601 format epoch" {
    var ts = init(0);
    var buf: [20]u8 = undefined;
    const result = ts.iso8601(&buf);
    try testing.expectEqualStrings("1970-01-01T00:00:00Z", result);
}

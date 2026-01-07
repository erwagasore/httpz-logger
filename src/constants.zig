//! Common constants used throughout the httpz-logger library.
//!
//! This module centralizes magic numbers and configuration defaults
//! to improve maintainability and readability.

const std = @import("std");

/// Time-related constants
pub const Time = struct {
    /// Unix epoch year
    pub const EPOCH_YEAR = 1970;

    /// Maximum supported year for timestamps
    pub const MAX_YEAR = 9999;

    /// Seconds per day
    pub const SECONDS_PER_DAY = 86400;

    /// Days per non-leap year
    pub const DAYS_PER_YEAR = 365;

    /// Days per leap year
    pub const DAYS_PER_LEAP_YEAR = 366;

    /// Maximum years from epoch we support
    pub const MAX_YEARS_FROM_EPOCH = 8000;
};

/// Buffer size constants
pub const Buffer = struct {
    /// Default buffer size for log entries
    pub const DEFAULT_SIZE = 2048;

    /// Maximum stack-allocated buffer size
    pub const STACK_THRESHOLD = 4096;

    /// Small buffer for temporary operations
    pub const SMALL = 256;

    /// Medium buffer for moderate operations
    pub const MEDIUM = 512;

    /// Large buffer for complex operations
    pub const LARGE = 1024;

    /// Extra large buffer for JSON/complex formatting
    pub const EXTRA_LARGE = 4096;

    /// Huge buffer for stress testing
    pub const HUGE = 8192;
};

/// Test-related constants
pub const Test = struct {
    /// Default number of iterations for property tests
    pub const FUZZ_ITERATIONS = 1000;

    /// Number of iterations for quick tests
    pub const QUICK_ITERATIONS = 100;

    /// Random offset range for timestamp tests
    pub const TIMESTAMP_OFFSET_RANGE = 1000;
};

/// HTTP status code ranges
pub const StatusCode = struct {
    /// Informational responses (100-199)
    pub const INFO_MIN = 100;
    pub const INFO_MAX = 199;

    /// Successful responses (200-299)
    pub const SUCCESS_MIN = 200;
    pub const SUCCESS_MAX = 299;

    /// Redirection messages (300-399)
    pub const REDIRECT_MIN = 300;
    pub const REDIRECT_MAX = 399;

    /// Client error responses (400-499)
    pub const CLIENT_ERROR_MIN = 400;
    pub const CLIENT_ERROR_MAX = 499;

    /// Server error responses (500-599)
    pub const SERVER_ERROR_MIN = 500;
    pub const SERVER_ERROR_MAX = 599;
};

/// Leap year calculation constants
pub const LeapYear = struct {
    /// Divisor for standard leap years
    pub const DIVISOR_4 = 4;

    /// Divisor for century non-leap years
    pub const DIVISOR_100 = 100;

    /// Divisor for century leap years
    pub const DIVISOR_400 = 400;
};

//! Error types for httpz-logger library.
//!
//! Provides standardized error types used across the codebase
//! for consistent error handling and reporting.

const std = @import("std");

/// Errors that can occur during log formatting
pub const FormatError = error{
    /// Buffer is too small for the formatted output
    BufferTooSmall,

    /// Invalid UTF-8 sequence in input data
    InvalidUtf8,

    /// General out of memory condition
    OutOfMemory,
};

/// Errors that can occur during log processing
pub const LogError = error{
    /// Failed to allocate memory for log buffer
    AllocationFailed,

    /// Log entry was truncated due to size limits
    LogTruncated,

    /// Failed to format timestamp
    TimestampError,
};

/// Convert standard library errors to our error types
pub fn convertError(err: anyerror) FormatError {
    return switch (err) {
        error.NoSpaceLeft => FormatError.BufferTooSmall,
        error.OutOfMemory => FormatError.OutOfMemory,
        error.InvalidUtf8 => FormatError.InvalidUtf8,
        else => FormatError.OutOfMemory,
    };
}

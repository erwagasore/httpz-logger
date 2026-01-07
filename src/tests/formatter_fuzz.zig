//! Fuzz tests for log formatters.

const std = @import("std");
const testing = std.testing;
const httpz = @import("httpz");
const constants = @import("../constants.zig");
const Timestamp = @import("../timestamp.zig");
const data_extractor = @import("../data_extractor.zig");
const logfmt = @import("../formatters/logfmt.zig");
const json = @import("../formatters/json.zig");
const test_utils = @import("test_utils.zig");

test "fuzz: logfmt formatter with random data" {
    var fuzzer = test_utils.Fuzzer.init(@intCast(std.time.timestamp() + 3));

    var i: usize = 0;
    while (i < constants.Test.FUZZ_ITERATIONS) : (i += 1) {
        var input_buf: [constants.Buffer.LARGE]u8 = undefined;

        // Create timestamp
        var ts = Timestamp.init(fuzzer.rng.random().int(i64));

        var data = data_extractor.LogData{
            .timestamp_buf = undefined,
            .address_buf = undefined,
            .address_len = if (fuzzer.rng.random().boolean()) fuzzer.rng.random().intRangeAtMost(usize, 0, 24) else 0,
            .method = .GET,
            .path = fuzzer.randomPrintableString(input_buf[0..100]),
            .query = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[100..200]) else null,
            .status = fuzzer.randomStatusCode(),
            .size = fuzzer.rng.random().int(usize),
            .duration_ms = fuzzer.rng.random().int(i64),
            .user_agent = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[250..350]) else null,
            .trace_id = if (fuzzer.rng.random().boolean()) fuzzer.randomHexString(input_buf[350..382]) else null,
            .span_id = if (fuzzer.rng.random().boolean()) fuzzer.randomHexString(input_buf[382..398]) else null,
            .request_id = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[398..450]) else null,
            .user_id = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[450..500]) else null,
        };

        // Format timestamp
        _ = ts.iso8601(&data.timestamp_buf);

        var output_buf: [constants.Buffer.EXTRA_LARGE]u8 = undefined;
        var stream = std.io.fixedBufferStream(&output_buf);

        // Should not crash
        _ = logfmt.formatWriter(data, fuzzer.randomLogLevel(), stream.writer()) catch |err| {
            // Some errors are acceptable
            try testing.expect(err == error.NoSpaceLeft or err == error.OutOfMemory);
        };

        const output = stream.getWritten();
        if (output.len > 0) {
            try testing.expect(std.mem.indexOf(u8, output, "=") != null);
        }
    }
}

test "fuzz: json formatter with random data" {
    var fuzzer = test_utils.Fuzzer.init(@intCast(std.time.timestamp() + 4));

    var i: usize = 0;
    while (i < constants.Test.FUZZ_ITERATIONS) : (i += 1) {
        var input_buf: [constants.Buffer.LARGE]u8 = undefined;

        var ts = Timestamp.init(fuzzer.rng.random().int(i64));

        var data = data_extractor.LogData{
            .timestamp_buf = undefined,
            .address_buf = undefined,
            .address_len = if (fuzzer.rng.random().boolean()) fuzzer.rng.random().intRangeAtMost(usize, 0, 24) else 0,
            .method = .POST,
            .path = fuzzer.randomPrintableString(input_buf[0..100]),
            .query = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[100..200]) else null,
            .status = fuzzer.randomStatusCode(),
            .size = fuzzer.rng.random().int(usize),
            .duration_ms = fuzzer.rng.random().int(i64),
            .user_agent = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[250..350]) else null,
            .trace_id = if (fuzzer.rng.random().boolean()) fuzzer.randomHexString(input_buf[350..382]) else null,
            .span_id = if (fuzzer.rng.random().boolean()) fuzzer.randomHexString(input_buf[382..398]) else null,
            .request_id = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[398..450]) else null,
            .user_id = if (fuzzer.rng.random().boolean()) fuzzer.randomPrintableString(input_buf[450..500]) else null,
        };

        _ = ts.iso8601(&data.timestamp_buf);

        var output_buf: [constants.Buffer.EXTRA_LARGE]u8 = undefined;

        // Should not crash
        var stream2 = std.io.fixedBufferStream(&output_buf);
        _ = json.formatWriter(data, fuzzer.randomLogLevel(), stream2.writer()) catch |err| {
            try testing.expect(err == error.NoSpaceLeft or err == error.OutOfMemory);
        };
    }
}

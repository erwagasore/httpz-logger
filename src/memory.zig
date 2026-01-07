//! Memory management utilities for httpz-logger.
//!
//! Provides safe memory allocation patterns and
//! pooling strategies for performance optimization.

const std = @import("std");
const constants = @import("constants.zig");

/// Thread-local buffer pool for temporary allocations
pub const BufferPool = struct {
    small_buffers: [4][constants.Buffer.SMALL]u8 = undefined,
    medium_buffers: [2][constants.Buffer.MEDIUM]u8 = undefined,
    large_buffer: [constants.Buffer.LARGE]u8 = undefined,
    small_index: usize = 0,
    medium_index: usize = 0,
    large_in_use: bool = false,

    /// Get a small buffer from the pool
    pub fn getSmall(self: *BufferPool) ?[]u8 {
        if (self.small_index >= self.small_buffers.len) {
            return null;
        }
        const buf = &self.small_buffers[self.small_index];
        self.small_index += 1;
        return buf;
    }

    /// Get a medium buffer from the pool
    pub fn getMedium(self: *BufferPool) ?[]u8 {
        if (self.medium_index >= self.medium_buffers.len) {
            return null;
        }
        const buf = &self.medium_buffers[self.medium_index];
        self.medium_index += 1;
        return buf;
    }

    /// Get the large buffer if available
    pub fn getLarge(self: *BufferPool) ?[]u8 {
        if (self.large_in_use) {
            return null;
        }
        self.large_in_use = true;
        return &self.large_buffer;
    }

    /// Reset the pool for reuse
    pub fn reset(self: *BufferPool) void {
        self.small_index = 0;
        self.medium_index = 0;
        self.large_in_use = false;
    }
};

/// Smart buffer that chooses stack or heap allocation based on size
pub fn SmartBuffer(comptime max_stack_size: usize) type {
    return struct {
        stack_buf: [max_stack_size]u8 = undefined,
        heap_buf: ?[]u8 = null,
        allocator: ?std.mem.Allocator = null,

        const Self = @This();

        /// Get a buffer of the requested size
        pub fn get(self: *Self, size: usize, allocator: std.mem.Allocator) ![]u8 {
            if (size <= max_stack_size) {
                return self.stack_buf[0..size];
            }

            self.allocator = allocator;
            self.heap_buf = try allocator.alloc(u8, size);
            return self.heap_buf.?;
        }

        /// Clean up heap allocation if any
        pub fn deinit(self: *Self) void {
            if (self.heap_buf) |buf| {
                if (self.allocator) |alloc| {
                    alloc.free(buf);
                }
            }
            self.heap_buf = null;
            self.allocator = null;
        }
    };
}

/// Memory leak detector for testing
pub const LeakDetector = struct {
    allocations: std.AutoHashMap(usize, usize),
    base_allocator: std.mem.Allocator,

    pub fn init(base: std.mem.Allocator) LeakDetector {
        return .{
            .allocations = std.AutoHashMap(usize, usize).init(base),
            .base_allocator = base,
        };
    }

    pub fn deinit(self: *LeakDetector) void {
        if (self.allocations.count() > 0) {
            std.debug.print("Memory leak detected: {} allocations not freed\n", .{self.allocations.count()});
        }
        self.allocations.deinit();
    }

    pub fn allocator(self: *LeakDetector) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self = @as(*LeakDetector, @ptrCast(@alignCast(ctx)));
        const ptr = self.base_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.allocations.put(@intFromPtr(ptr), len) catch {};
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self = @as(*LeakDetector, @ptrCast(@alignCast(ctx)));
        if (self.base_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
            self.allocations.put(@intFromPtr(buf.ptr), new_len) catch {};
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self = @as(*LeakDetector, @ptrCast(@alignCast(ctx)));
        _ = self.allocations.remove(@intFromPtr(buf.ptr));
        self.base_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

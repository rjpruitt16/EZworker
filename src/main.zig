const std = @import("std");
const executor = @import("executor.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🚀 EZworker HTTP Job Executor Starting...", .{});

    // Example job
    const headers = [_]executor.Header{
        .{ .name = "User-Agent", .value = "EZworker/1.0" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const job = executor.Job{
        .method = .GET,
        .url = "http://httpbin.org/get",
        .headers = &headers,
        .body = null,
        .timeout_ms = 30000,
    };

    // Execute with callback
    executor.executeJob(allocator, job, handleResult);

    std.log.info("✨ Job execution completed", .{});
}

fn handleResult(result: executor.JobResult) void {
    if (result.success) {
        std.log.info("✅ Job Success - Status: {?d}, Time: {d}ms", .{ result.status_code, result.execution_time_ms });
    } else {
        std.log.err("❌ Job Failed - Error: {?s}", .{result.error_message});
    }
}

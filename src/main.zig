const std = @import("std");
const jobq = @import("job_queue.zig");
const ratelimiter = @import("ratelimiter.zig");

fn simpleCallback(_: *anyopaque, result: jobq.JobResult) void {
    std.debug.print("Callback ⬜ success={} status={} time={}ms\n", .{ result.success, result.status_code orelse 0, result.execution_time_ms });
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var queue = jobq.JobQueue.init(allocator);
    defer queue.deinit();

    var limiter = ratelimiter.RateLimiter.init(allocator, 1); // 1 req/sec per domain
    defer limiter.deinit();

    const headers = &[_]jobq.Header{};
    const job = jobq.Job{
        .url = "https://httpbin.org/get",
        .method = jobq.HttpMethod.GET,
        .headers = headers,
        .body = null,
        .timeout_ms = 5000,
    };

    // Allocate a mutable copy of the job_id string
    const job_id = try allocator.dupe(u8, "test-job");

    // Now build your work item with the owned slice
    const work_item = jobq.WorkItem{
        .job_id = job_id,
        .job = job,
    };

    try queue.push(work_item);
    std.debug.print("Queue size after push: {}\n", .{queue.size()});

    if (queue.pop()) |rawItem| {
        var item = rawItem;
        std.debug.print("Popped job_id: {s}\n", .{item.job_id});

        // -- Rate limiting demo --
        const domain = try ratelimiter.extractDomain(allocator, item.job.url);
        defer allocator.free(domain);

        try limiter.waitForDomain(domain); // Will wait if called too soon
        try limiter.recordRequest(domain);

        jobq.executeJob(allocator, item.job, &simpleCallback, undefined);
        item.deinit(allocator);
    }

    queue.stop();
}

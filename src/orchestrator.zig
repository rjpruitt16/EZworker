const std = @import("std");
const poller = @import("poller.zig");
const executor = @import("executor.zig");
const reporter = @import("reporter.zig");
const queue = @import("queue.zig");
const ratelimiter = @import("ratelimiter.zig");
const sync_http = @import("sync_http.zig");

pub const OrchestratorConfig = struct {
    clockwork_url: []const u8 = "http://localhost:4000",
    poll_interval_seconds: u32 = 1,
    max_jitter_ms: u32 = 200,
    jobs_per_pull: u32 = 30,
    rate_limit_per_second: u32 = 2,
    executor_thread_count: u32 = 4,
};

pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    config: OrchestratorConfig,
    job_queue: queue.JobQueue,
    rate_limiter: ratelimiter.RateLimiter,
    job_poller: poller.JobPoller,
    job_reporter: *reporter.Reporter,
    http_client: *sync_http.HttpClient,
    should_stop: std.atomic.Value(bool),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: OrchestratorConfig) !Self {
        const poller_config = poller.PollerConfig{
            .clockwork_url = config.clockwork_url,
            .poll_interval_seconds = config.poll_interval_seconds,
            .max_jitter_ms = config.max_jitter_ms,
            .jobs_per_pull = config.jobs_per_pull,
        };

        const http_client = try allocator.create(sync_http.HttpClient);
        http_client.* = sync_http.HttpClient.init(allocator);

        const job_reporter = try allocator.create(reporter.Reporter);
        job_reporter.* = reporter.Reporter.init(allocator, config.clockwork_url, http_client);
        return Self{
            .allocator = allocator,
            .config = config,
            .job_queue = queue.JobQueue.init(allocator),
            .rate_limiter = ratelimiter.RateLimiter.init(allocator, config.rate_limit_per_second),
            .job_poller = poller.JobPoller.init(allocator, poller_config),
            .http_client = http_client,
            .job_reporter = job_reporter,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.job_queue.deinit();
        self.rate_limiter.deinit();
        self.job_poller.deinit();

        self.allocator.destroy(self.job_reporter);
        self.allocator.destroy(self.http_client);
    }

    pub fn run(self: *Self) !void {
        std.log.info("🚀 Starting orchestrator with {} executor threads", .{self.config.executor_thread_count});

        // Start executor threads
        const executor_threads = try self.allocator.alloc(std.Thread, self.config.executor_thread_count);
        defer self.allocator.free(executor_threads);

        for (executor_threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, executorThread, .{ self, i });
        }

        // Start poller thread
        const poller_thread = try std.Thread.spawn(.{}, pollerThread, .{self});

        // Wait for shutdown signal (in production, handle SIGTERM/SIGINT)
        // For now, just run indefinitely until manually stopped

        // Join threads on shutdown
        poller_thread.join();
        self.job_queue.stop(); // Signal executor threads to stop

        for (executor_threads) |thread| {
            thread.join();
        }

        std.log.info("✨ Orchestrator shutdown complete", .{});
    }

    pub fn stop(self: *Self) void {
        self.should_stop.store(true, .release);
        self.job_poller.stop();
    }

    fn pollerThread(self: *Self) void {
        std.log.info("📊 Poller thread started", .{});

        while (!self.should_stop.load(.acquire)) {
            // Pull jobs from Clockwork
            const jobs = self.job_poller.pullJobs() catch |err| {
                std.log.err("❌ Failed to pull jobs: {}", .{err});
                self.job_poller.sleepUntilNextPoll();
                continue;
            };
            defer self.allocator.free(jobs);

            // Convert JobData to executor.Job and add to queue
            for (jobs) |job_data| {
                self.enqueueJob(job_data) catch |err| {
                    std.log.err("❌ Failed to enqueue job: {}", .{err});
                };
            }

            if (jobs.len > 0) {
                std.log.info("📥 Queued {} jobs, queue size: {}", .{ jobs.len, self.job_queue.size() });
            }

            // Sleep until next poll
            self.job_poller.sleepUntilNextPoll();
        }

        std.log.info("📊 Poller thread stopped", .{});
    }

    fn executorThread(self: *Self, thread_id: usize) void {
        std.log.info("🔧 Executor thread {} started", .{thread_id});

        while (!self.should_stop.load(.acquire)) {
            if (self.job_queue.pop()) |work_item| {
                self.executeJob(work_item) catch |err| {
                    std.log.err("❌ Thread {} job execution failed: {}", .{ thread_id, err });
                };
            }
        }

        std.log.info("🔧 Executor thread {} stopped", .{thread_id});
    }

    fn enqueueJob(self: *Self, job_data: poller.JobData) !void {
        const job_headers = try self.allocator.alloc(executor.Header, 2);
        job_headers[0] = .{ .name = "User-Agent", .value = "EZworker/1.0" };
        job_headers[1] = .{ .name = "Accept", .value = "application/json" };

        const method = if (std.mem.eql(u8, job_data.method, "POST"))
            executor.HttpMethod.POST
        else if (std.mem.eql(u8, job_data.method, "PUT"))
            executor.HttpMethod.PUT
        else if (std.mem.eql(u8, job_data.method, "DELETE"))
            executor.HttpMethod.DELETE
        else if (std.mem.eql(u8, job_data.method, "PATCH"))
            executor.HttpMethod.PATCH
        else
            executor.HttpMethod.GET;

        // Deep copy everything that will be owned by the queue
        const copied_job_id = try self.allocator.dupe(u8, job_data.id);
        const copied_url = try self.allocator.dupe(u8, job_data.url);

        const copied_body = if (job_data.body) |b| try self.allocator.dupe(u8, b) else &[_]u8{};

        const job = executor.Job{
            .method = method,
            .url = copied_url,
            .headers = job_headers,
            .body = copied_body,
            .timeout_ms = job_data.timeout_ms,
        };

        const work_item = queue.WorkItem{
            .job_id = copied_job_id,
            .job = job,
        };
        try self.job_queue.push(work_item);
    }

    // In orchestrator.zig executeJob:
    fn executeJob(self: *Self, work_item: queue.WorkItem) !void {
        // Create an arena for this job execution
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit(); // This will free EVERYTHING at once
        const job_allocator = arena.allocator();

        // Copy work_item data since we can't modify const
        const job_copy = work_item.job;
        const job_id_copy = try self.allocator.dupe(u8, work_item.job_id);
        defer self.allocator.free(job_id_copy);

        // Extract domain for rate limiting (use arena allocator)
        const domain = try ratelimiter.extractDomain(job_allocator, job_copy.url);
        // No need to free domain - arena will handle it

        // Wait for rate limit
        try self.rate_limiter.waitForDomain(domain);

        std.log.info("🚀 Executing job: {} {s}", .{ job_copy.method, job_copy.url });

        // Make a copy of job_id for the callback (use arena)
        const callback_job_id = try job_allocator.dupe(u8, job_id_copy);

        // Create context for the callback
        const CallbackContext = struct {
            reporter: *reporter.Reporter,
            job_id: []const u8,
            rate_limiter: *ratelimiter.RateLimiter,
            domain: []const u8,
            allocator: std.mem.Allocator, // This is the main allocator, not arena
        };

        const callback_ctx = try self.allocator.create(CallbackContext);
        callback_ctx.* = CallbackContext{
            .reporter = self.job_reporter,
            .job_id = callback_job_id,
            .rate_limiter = &self.rate_limiter,
            .domain = domain,
            .allocator = self.allocator,
        };

        // Callback that doesn't need to worry about freeing the response body
        const reportToClockwork = struct {
            fn callback(ctx_ptr: *anyopaque, result: executor.JobResult) void {
                const ctx = @as(*CallbackContext, @ptrCast(@alignCast(ctx_ptr)));

                // Report the result - response_body is still valid here
                ctx.reporter.reportJobResult(ctx.job_id, result.success, result.status_code, result.response_body, result.execution_time_ms, result.error_message) catch |err| {
                    std.log.err("❌ Failed to report job result: {}", .{err});
                };

                // Record the request for rate limiting
                ctx.rate_limiter.recordRequest(ctx.domain) catch |err| {
                    std.log.err("❌ Failed to record request: {}", .{err});
                };

                // Only free the context itself (arena handles everything else)
                ctx.allocator.destroy(ctx);
            }
        }.callback;

        // Execute with arena allocator - all memory will be freed when this function returns
        executor.executeJob(job_allocator, job_copy, reportToClockwork, callback_ctx);

        // Arena automatically frees everything when we return
    }
};

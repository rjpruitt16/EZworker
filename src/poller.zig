const std = @import("std");

pub const PollerConfig = struct {
    clockwork_url: []const u8,
    poll_interval_seconds: u32 = 1,
    max_jitter_ms: u32 = 200,
    jobs_per_pull: u32 = 30,
};

// Job data structure that poller returns
pub const JobData = struct {
    id: []const u8,
    url: []const u8,
    method: []const u8,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const JobPoller = struct {
    config: PollerConfig,
    allocator: std.mem.Allocator,
    should_stop: std.atomic.Value(bool),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: PollerConfig) Self {
        return Self{
            .config = config,
            .allocator = allocator,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn stop(self: *Self) void {
        self.should_stop.store(true, .release);
    }

    pub fn pullJobs(self: *Self) ![]JobData {
        // Get worker_id and region from environment variables
        const worker_id = std.process.getEnvVarOwned(self.allocator, "FLY_MACHINE_ID") catch "ezworker-local";
        defer if (!std.mem.eql(u8, worker_id, "ezworker-local")) self.allocator.free(worker_id);

        const region = std.process.getEnvVarOwned(self.allocator, "FLY_REGION") catch "dev";
        defer if (!std.mem.eql(u8, region, "dev")) self.allocator.free(region);

        const api_url = try std.fmt.allocPrint(self.allocator, "{s}/worker/jobs?worker_id={s}&region={s}&limit={}", .{ self.config.clockwork_url, worker_id, region, self.config.jobs_per_pull });
        defer self.allocator.free(api_url);

        std.log.info("📡 Pulling jobs from: {s}", .{api_url});

        // Use synchronous HTTP client
        const sync_http = @import("sync_http.zig");
        const client = sync_http.HttpClient.init(self.allocator);

        const response = client.get(api_url) catch |err| {
            std.log.err("❌ HTTP request failed: {}", .{err});
            return &[_]JobData{};
        };
        defer response.deinit();

        // 204 No Content is not an error - it means queue is empty
        if (response.status_code == 204) {
            std.log.debug("📭 Queue is empty (HTTP 204)", .{});
            return &[_]JobData{};
        }

        if (response.status_code != 200) {
            std.log.err("❌ HTTP error: {d}", .{response.status_code});
            return &[_]JobData{};
        }

        // Parse jobs from JSON response
        const jobs_data = sync_http.parseJobsFromJson(self.allocator, response.body) catch |err| {
            std.log.err("❌ JSON parsing failed: {}", .{err});
            return &[_]JobData{};
        };

        // Convert sync_http.JobData to poller.JobData
        const jobs = try self.allocator.alloc(JobData, jobs_data.len);
        for (jobs_data, 0..) |job_data, i| {
            jobs[i] = JobData{
                .id = job_data.id,
                .url = job_data.url,
                .method = job_data.method,
                .headers = &[_]Header{},
                .body = job_data.body,
                .timeout_ms = @intCast(job_data.timeout_ms),
            };
        }
        self.allocator.free(jobs_data);

        if (jobs.len > 0) {
            std.log.info("✅ Pulled {} jobs from Clockwork", .{jobs.len});
        }
        return jobs;
    }
    pub fn sleepUntilNextPoll(self: *Self) void {
        // Calculate next clockwork second
        const now_ms = std.time.milliTimestamp();
        const now_seconds = @divTrunc(now_ms, 1000);
        const next_clockwork_second = (now_seconds + self.config.poll_interval_seconds) * 1000;

        // Add small jitter to prevent thundering herd
        const random = std.crypto.random;
        const jitter_ms = random.int(u32) % self.config.max_jitter_ms;
        const target_wake_time = next_clockwork_second + jitter_ms;

        const sleep_duration = if (target_wake_time > now_ms)
            @as(u64, @intCast(target_wake_time - now_ms))
        else
            100; // Minimum 100ms sleep

        std.log.info("💤 Sleeping {}ms until next poll", .{sleep_duration});
        std.time.sleep(sleep_duration * std.time.ns_per_ms);
    }
};

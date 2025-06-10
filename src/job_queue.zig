// File: src/job_queue.zig
const std = @import("std");
const print = std.debug.print;

// Result of executing an HTTP job
pub const JobResult = struct {
    success: bool,
    status_code: ?u16 = null,
    response_body: []const u8 = "",
    error_message: ?[]const u8 = null,
    execution_time_ms: u64 = 0,
};

// HTTP method types
pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,

    pub fn toString(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
        };
    }
};

// HTTP header structure
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

// Job to be executed
pub const Job = struct {
    url: []const u8,
    method: HttpMethod = .GET,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
};

// Callback function type for handling results
pub const ResultCallback = *const fn (context: *anyopaque, result: JobResult) void;

// Execute an HTTP job and call the callback with the result
pub fn executeJob(
    allocator: std.mem.Allocator,
    job: Job,
    callback: ResultCallback,
    context: *anyopaque,
) void {
    print("🚀 Executing job: {s} {s}\n", .{ job.method.toString(), job.url });

    const start_time = std.time.milliTimestamp();

    const result = makeHttpRequest(allocator, job, start_time) catch |err| {
        const end_time = std.time.milliTimestamp();
        const execution_time = @as(u64, @intCast(end_time - start_time));
        const error_result = JobResult{
            .success = false,
            .error_message = @errorName(err),
            .execution_time_ms = execution_time,
        };
        callback(context, error_result);
        return;
    };

    callback(context, result);
}

// Internal HTTP request implementation
fn makeHttpRequest(
    allocator: std.mem.Allocator,
    job: Job,
    start_time: i64,
) !JobResult {
    print("   → Making real HTTP request to: {s}\n", .{job.url});

    const uri = std.Uri.parse(job.url) catch {
        return error.InvalidUrl;
    };

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const method = switch (job.method) {
        .GET => std.http.Method.GET,
        .POST => std.http.Method.POST,
        .PUT => std.http.Method.PUT,
        .DELETE => std.http.Method.DELETE,
        .PATCH => std.http.Method.PATCH,
    };

    const server_header_buffer = try allocator.alloc(u8, 8192);
    defer allocator.free(server_header_buffer);

    var request = client.open(method, uri, .{
        .server_header_buffer = server_header_buffer,
    }) catch |err| {
        print("   ❌ Failed to create request: {}\n", .{err});
        return error.RequestFailed;
    };
    defer request.deinit();

    request.send() catch |err| {
        print("   ❌ Failed to send request: {}\n", .{err});
        return error.SendFailed;
    };
    request.wait() catch |err| {
        print("   ❌ Failed to receive response: {}\n", .{err});
        return error.ReceiveFailed;
    };

    const body = request.reader()
        .readAllAlloc(allocator, 1024 * 1024) catch |err| {
        print("   ❌ Failed to read response body: {}\n", .{err});
        return error.ReadFailed;
    };

    const end_time = std.time.milliTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));

    const status = request.response.status;
    const success = @intFromEnum(status) >= 200 and @intFromEnum(status) < 300;

    print("   ✅ Response: {} ({}ms)\n", .{ status, execution_time });

    return JobResult{
        .success = success,
        .status_code = @intFromEnum(status),
        .response_body = body,
        .execution_time_ms = execution_time,
    };
}

// Work item and queue definitions
pub const WorkItem = struct {
    job_id: []u8,
    job: Job,

    pub fn deinit(self: *WorkItem, allocator: std.mem.Allocator) void {
        allocator.free(self.job_id);
        allocator.free(self.job.url);
        if (self.job.body) |b| allocator.free(b);
    }
};

pub const JobQueue = struct {
    jobs: std.ArrayList(WorkItem),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    should_stop: bool,

    pub fn init(allocator: std.mem.Allocator) JobQueue {
        return JobQueue{
            .jobs = std.ArrayList(WorkItem).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .should_stop = false,
        };
    }

    pub fn deinit(self: *JobQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.jobs.capacity > 0) self.allocator.free(self.jobs.items);
        self.jobs.items = &[_]WorkItem{};
        self.jobs.capacity = 0;
    }

    pub fn push(self: *JobQueue, item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const copied_job_id = try self.allocator.dupe(u8, item.job_id);
        const copied_url = try self.allocator.dupe(u8, item.job.url);
        const copied_body = if (item.job.body) |b|
            try self.allocator.dupe(u8, b)
        else
            &[_]u8{};

        var job_copy = item.job;
        job_copy.url = copied_url;
        job_copy.body = copied_body;

        try self.jobs.append(WorkItem{
            .job_id = copied_job_id,
            .job = job_copy,
        });
        self.condition.signal();
    }

    pub fn pop(self: *JobQueue) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.jobs.items.len == 0 and !self.should_stop) {
            self.condition.wait(&self.mutex);
        }
        if (self.should_stop) return null;
        return self.jobs.orderedRemove(0);
    }

    pub fn size(self: *JobQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.jobs.items.len;
    }

    pub fn stop(self: *JobQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.should_stop = true;
        self.condition.broadcast();
    }
};

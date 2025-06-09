const std = @import("std");
const print = std.debug.print;

/// Result of executing an HTTP job
pub const JobResult = struct {
    success: bool,
    status_code: ?u16 = null,
    response_body: []const u8 = "",
    error_message: ?[]const u8 = null,
    execution_time_ms: u64 = 0,
};

/// HTTP method types
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

/// HTTP header structure
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Job to be executed
pub const Job = struct {
    url: []const u8,
    method: HttpMethod = .GET,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000, // 30 second default
};

/// Callback function type for handling results with context
pub const ResultCallback = *const fn (context: *anyopaque, result: JobResult) void;

/// Execute an HTTP job and call the callback with the result
pub fn executeJob(allocator: std.mem.Allocator, job: Job, callback: ResultCallback, context: *anyopaque) void {
    print("🚀 Executing job: {s} {s}\n", .{ job.method.toString(), job.url });

    const start_time = std.time.milliTimestamp();

    // For now, we'll use a simple HTTP implementation
    // TODO: Replace with robust HTTP client (like curl or custom implementation)
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

/// Make actual HTTP request (real implementation)
fn makeHttpRequest(allocator: std.mem.Allocator, job: Job, start_time: i64) !JobResult {
    print("   → Making real HTTP request to: {s}\n", .{job.url});

    // Parse URL
    const uri = std.Uri.parse(job.url) catch {
        return error.InvalidUrl;
    };

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Prepare request
    const method = switch (job.method) {
        .GET => std.http.Method.GET,
        .POST => std.http.Method.POST,
        .PUT => std.http.Method.PUT,
        .DELETE => std.http.Method.DELETE,
        .PATCH => std.http.Method.PATCH,
    };

    // Make the request
    const server_header_buffer = try allocator.alloc(u8, 8192);
    defer allocator.free(server_header_buffer);

    var request = client.open(method, uri, .{
        .server_header_buffer = server_header_buffer,
    }) catch |err| {
        print("   ❌ Failed to create request: {}\n", .{err});
        return error.RequestFailed;
    };
    defer request.deinit();

    // Add headers (skip for now - Zig 0.12 header API is complex)
    // TODO: Add custom headers once basic request works

    // Send request
    request.send() catch |err| {
        print("   ❌ Failed to send request: {}\n", .{err});
        return error.SendFailed;
    };

    // Wait for response
    request.wait() catch |err| {
        print("   ❌ Failed to receive response: {}\n", .{err});
        return error.ReceiveFailed;
    };

    // Read response body
    const body = request.reader().readAllAlloc(allocator, 1024 * 1024) catch |err| {
        print("   ❌ Failed to read response body: {}\n", .{err});
        return error.ReadFailed;
    };
    // WARNING must free body within callback
    // Note: body will be freed when allocator is freed

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

/// Example callback function for testing
pub fn exampleCallback(result: JobResult) void {
    if (result.success) {
        print("✅ Job succeeded: Status {?d}, Time: {}ms\n", .{ result.status_code, result.execution_time_ms });
        print("   Response: {s}\n", .{result.response_body});
    } else {
        print("❌ Job failed: {?s}, Time: {}ms\n", .{ result.error_message, result.execution_time_ms });
    }
}

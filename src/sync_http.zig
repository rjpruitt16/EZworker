const std = @import("std");

pub const HttpResponse = struct {
    status_code: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: HttpResponse) void {
        self.allocator.free(self.body);
    }
};

pub const HttpClient = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn get(self: Self, url: []const u8) !HttpResponse {
        return self.makeRequest(.GET, url, null);
    }

    pub fn post(self: Self, url: []const u8, payload: []const u8) !HttpResponse {
        return self.makeRequest(.POST, url, payload);
    }

    pub fn put(self: Self, url: []const u8, payload: []const u8) !HttpResponse {
        return self.makeRequest(.PUT, url, payload);
    }

    pub fn delete(self: Self, url: []const u8) !HttpResponse {
        return self.makeRequest(.DELETE, url, null);
    }

    pub fn patch(self: Self, url: []const u8, payload: []const u8) !HttpResponse {
        return self.makeRequest(.PATCH, url, payload);
    }

    fn makeRequest(self: Self, method: std.http.Method, url: []const u8, payload: ?[]const u8) !HttpResponse {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(url);

        const server_header_buffer = try self.allocator.alloc(u8, 16 * 1024);
        defer self.allocator.free(server_header_buffer);

        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();

        if (payload != null) {
            try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        }

        var request = try client.open(method, uri, .{
            .server_header_buffer = server_header_buffer,
            .extra_headers = headers.items,
        });
        defer request.deinit();

        if (payload) |p| {
            request.transfer_encoding = .{ .content_length = p.len };
        }

        try request.send();

        if (payload) |p| {
            try request.writeAll(p);
            try request.finish();
        }

        try request.wait();

        const body = try request.reader().readAllAlloc(self.allocator, 10 * 1024 * 1024);

        return HttpResponse{
            .status_code = @intFromEnum(request.response.status),
            .body = body,
            .allocator = self.allocator,
        };
    }
};

// Job data structure from Clockwork API
pub const JobData = struct {
    id: []const u8,
    url: []const u8,
    method: []const u8,
    body: ?[]const u8,
    timeout_ms: i64,
};

// Parse JSON response from Clockwork
pub fn parseJobsFromJson(allocator: std.mem.Allocator, json: []const u8) ![]JobData {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Check if we're on Fly.io (FLY_APP_NAME is set on Fly machines)
    const is_production = std.process.getEnvVarOwned(allocator, "FLY_APP_NAME") catch null;
    defer if (is_production) |p| allocator.free(p);

    // Clockwork returns: {"success": true, "job": {...}}
    if (root.object.get("success")) |success| {
        if (success.bool and root.object.get("job") != null) {
            const job_obj = root.object.get("job").?;

            var jobs = try allocator.alloc(JobData, 1);

            const target_url = job_obj.object.get("target_url").?.string;
            const url = if (is_production == null and std.mem.startsWith(u8, target_url, "https://")) blk: {
                // Local dev: downgrade HTTPS to HTTP
                const http_url = try std.fmt.allocPrint(allocator, "http://{s}", .{target_url[8..]});
                std.log.warn("⚠️  LOCAL DEV: Converting HTTPS to HTTP: {s} -> {s}", .{ target_url, http_url });
                break :blk http_url;
            } else blk: {
                break :blk try allocator.dupe(u8, target_url);
            };

            jobs[0] = JobData{
                .id = try allocator.dupe(u8, job_obj.object.get("id").?.string),
                .url = url,
                .method = try allocator.dupe(u8, job_obj.object.get("method").?.string),
                .body = if (job_obj.object.get("body")) |b|
                    if (b == .string) try allocator.dupe(u8, b.string) else null
                else
                    null,
                .timeout_ms = 30000, // Default since not in response
            };

            return jobs;
        }
    }

    // Return empty if no job or success=false
    return &[_]JobData{};
}

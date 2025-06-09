const std = @import("std");

pub const RateLimiter = struct {
    last_requests: std.HashMap(u64, i64, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    rate_limit_per_second: u32,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, rate_limit_per_second: u32) Self {
        return Self{
            .last_requests = std.HashMap(u64, i64, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .rate_limit_per_second = rate_limit_per_second,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.last_requests.deinit();
    }

    pub fn canMakeRequest(self: *Self, domain: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const domain_hash = std.hash_map.hashString(domain);

        if (self.last_requests.get(domain_hash)) |last_time| {
            const time_per_request = @as(i64, 1); // 1 second minimum between requests per domain
            return (now - last_time) >= time_per_request;
        }

        return true; // First request to this domain
    }

    pub fn recordRequest(self: *Self, domain: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const domain_hash = std.hash_map.hashString(domain);
        try self.last_requests.put(domain_hash, now);
    }

    pub fn waitForDomain(self: *Self, domain: []const u8) !void {
        while (!try self.canMakeRequest(domain)) {
            std.log.warn("⏱️  Rate limited for domain: {s}, waiting...", .{domain});
            std.time.sleep(500 * std.time.ns_per_ms);
        }
    }
};

// Helper function to extract domain from URL
pub fn extractDomain(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const uri = std.Uri.parse(url) catch {
        return error.InvalidUrl;
    };

    const host_component = uri.host orelse return error.NoHost;

    var host_str: []const u8 = undefined;
    switch (host_component) {
        .raw => |raw| host_str = raw,
        .percent_encoded => |encoded| host_str = encoded,
    }

    return try allocator.dupe(u8, host_str);
}

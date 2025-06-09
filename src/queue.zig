const std = @import("std");
const executor = @import("executor.zig");

pub const WorkItem = struct {
    job_id: []u8, // Now mutable for owned allocation
    job: executor.Job,

    pub fn deinit(self: *WorkItem, allocator: std.mem.Allocator) void {
        allocator.free(self.job_id);
        allocator.free(self.job.url);
        allocator.free(self.job.body);
        // Free any other dynamically allocated fields in job (like headers)
        // If headers or other fields need to be freed, do it here as well.
    }
};

pub const JobQueue = struct {
    jobs: std.ArrayList(WorkItem),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    should_stop: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .jobs = std.ArrayList(WorkItem).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .should_stop = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Only free the underlying buffer if we actually allocated one:
        if (self.jobs.capacity > 0) {
            self.allocator.free(self.jobs.items);
        }
        // Reset to the "empty slice" state so any future deinit is safe:
        self.jobs.items = &[_]WorkItem{};
        self.jobs.capacity = 0;
    }

    pub fn push(self: *Self, item: WorkItem) !void {
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

    pub fn pop(self: *Self) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.jobs.items.len == 0 and !self.should_stop) {
            self.condition.wait(&self.mutex);
        }

        if (self.should_stop) return null;

        if (self.jobs.items.len > 0) {
            return self.jobs.orderedRemove(0);
        }
        return null;
    }

    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.jobs.items.len;
    }

    pub fn stop(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.should_stop = true;
        self.condition.broadcast();
    }
};

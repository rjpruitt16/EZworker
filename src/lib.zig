// EZworker - HTTP job execution library
pub const executor = @import("executor.zig");
pub const queue = @import("queue.zig");
pub const ratelimiter = @import("ratelimiter.zig");

// Re-export commonly used types
pub const Job = executor.Job;
pub const JobResult = executor.JobResult;
pub const Header = executor.Header;
pub const HttpMethod = executor.HttpMethod;
pub const JobQueue = queue.JobQueue;
pub const WorkItem = queue.WorkItem;
pub const RateLimiter = ratelimiter.RateLimiter;

test {
    _ = @import("executor.zig");
    _ = @import("queue.zig");
    _ = @import("ratelimiter.zig");
}

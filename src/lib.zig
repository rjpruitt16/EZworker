// EZworker - HTTP job execution library
pub const jobQueue = @import("job_queue.zig");
pub const ratelimiter = @import("ratelimiter.zig");

// Re-export commonly used types
pub const Job = jobQueue.Job;
pub const JobResult = jobQueue.JobResult;
pub const Header = jobQueue.Header;
pub const HttpMethod = jobQueue.HttpMethod;
pub const JobQueue = jobQueue.JobQueue;
pub const WorkItem = jobQueue.WorkItem;
pub const RateLimiter = ratelimiter.RateLimiter;

test {
    _ = @import("job_queue.zig");
    _ = @import("ratelimiter.zig");
}

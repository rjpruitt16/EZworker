const std = @import("std");
const orchestrator = @import("orchestrator.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.log.info("🚀 EZworker HTTP Job Executor Starting...", .{});

    // Load configuration (could be from env vars or config file)
    const config = orchestrator.OrchestratorConfig{
        .clockwork_url = std.process.getEnvVarOwned(allocator, "CLOCKWORK_URL") catch "http://localhost:4000",
        .poll_interval_seconds = 1,
        .max_jitter_ms = 200,
        .jobs_per_pull = 30,
        .rate_limit_per_second = 2,
        .executor_thread_count = 4,
    };

    // Create and run the orchestrator
    var orch = try orchestrator.Orchestrator.init(allocator, config);
    defer orch.deinit();

    // Run the orchestrator (blocks until shutdown)
    try orch.run();

    std.log.info("✨ EZworker shutdown complete", .{});
}

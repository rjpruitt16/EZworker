# Zig ClockWork Executor

**A high-performance HTTP job executor for distributed request processing.**

## Overview

The Zig ClockWork Executor is the open-source execution engine that powers distributed HTTP job processing across networks of machines. It's designed to make HTTP requests politely and efficiently while respecting rate limits and avoiding server overload.

## Goals

🌍 **Distribute HTTP requests across global networks** - Spread API calls across multiple regions and machines to avoid rate limiting and improve reliability.

🚀 **High-performance execution** - Written in Zig for minimal memory usage and maximum speed.

🛡️ **Respectful request handling** - Built-in rate limiting and jitter to avoid overwhelming target servers.

🔧 **Simple integration** - Clean callback-based API that's easy to integrate into larger systems.

## Key Features

- **Callback-based execution** - Handle results asynchronously
- **Multiple HTTP methods** - GET, POST, PUT, DELETE, PATCH support
- **Custom headers and body** - Full control over request format
- **Error handling** - Graceful failure handling with detailed error reporting
- **Performance tracking** - Built-in execution time measurement
- **Memory efficient** - Minimal resource usage

## Usage

```zig
const std = @import("std");
const executor = @import("executor.zig");

fn handleResult(result: executor.JobResult) void {
    if (result.success) {
        std.debug.print("✅ Success: {d}ms\n", .{result.execution_time_ms});
    } else {
        std.debug.print("❌ Error: {?s}\n", .{result.error_message});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const job = executor.Job{
        .url = "https://api.example.com/webhook",
        .method = .POST,
        .body = "{ \"message\": \"Hello World\" }",
    };
    
    executor.executeJob(allocator, job, handleResult);
}
```

## Why Zig?

- **Performance** - Compiles to native code with no runtime overhead
- **Memory safety** - Prevents common bugs without garbage collection
- **Cross-platform** - Single binary deploys anywhere
- **Small footprint** - Perfect for distributed worker nodes

## Use Cases

- **Web scraping networks** - Distribute scraping across multiple IPs/regions
- **API monitoring** - Health checks from multiple geographic locations  
- **Webhook delivery** - Reliable webhook sending with retry logic
- **Load testing** - Gentle, distributed load testing
- **Data collection** - Large-scale data gathering with rate limit respect

## Integration

This executor is designed to be integrated into larger distributed job systems. It handles the core HTTP execution while delegating job management, scheduling, and coordination to external systems.

### ClockWork Integration

This executor was originally built as the execution engine for **ClockWork** - a distributed job scheduling and orchestration platform. ClockWork provides:

- **Global job coordination** across multiple regions
- **Intelligent retry logic** with geographic failover  
- **Rate limiting coordination** to prevent server overload
- **Real-time job monitoring** and analytics
- **Webhook delivery** with guaranteed delivery guarantees

While ClockWork is a commercial platform, this executor is open source so the community can benefit from high-performance HTTP execution and contribute improvements back to the ecosystem.

## Contributing

Contributions welcome! This project aims to be the standard for distributed HTTP execution.

## License

Apache 2.0 - See LICENSE file for details.

## About the Author

Built by **Rahmi Pruitt**, Ex-Amazon/Twitch developer specializing in distributed systems and infrastructure.

**Available for contracting opportunities** - Distributed systems, backend infrastructure, and system design consulting at $100/hour.

- 🌐 **Contra Profile**: [rahmi_pruitt_1km6xdt5](https://contra.com/rahmi_pruitt_1km6xdt5)
- 💼 **LinkedIn**: [Rahmi Pruitt](https://www.linkedin.com/in/rahmi-pruitt-a1bb4a127/)
- 📧 **Email**: Available via Contra or LinkedIn

---

*Built for developers who need to make HTTP requests at scale without getting blocked.*

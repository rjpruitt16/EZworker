app = "zig-dev-machine"
primary_region = "ord"

[build]
  image = "ubuntu:22.04"

[vm]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 256

[[mounts]]
  source = "dev_volume"
  destination = "/workspace"

[http_service]
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

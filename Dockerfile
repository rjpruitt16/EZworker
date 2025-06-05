# Lightweight Zig development container
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    curl \
    xz \
    bash \
    musl-dev \
    gcc

# Install Zig
RUN curl -L https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz | tar -xJ \
    && mv zig-linux-x86_64-0.12.0 /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig

# Set working directory
WORKDIR /workspace

# Verify Zig installation
RUN zig version

# Default command
CMD ["zig", "--help"]

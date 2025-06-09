# Lightweight Zig development container with debugging tools
FROM debian:bullseye-slim

# Install dependencies including valgrind and gdb
RUN apk add --no-cache \
    curl \
    xz \
    bash \
    musl-dev \
    gcc \
    valgrind \
    gdb \
    strace

# Install Zig
RUN curl -L https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz | tar -xJ \
    && mv zig-linux-x86_64-0.12.0 /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig

# Set working directory
WORKDIR /workspace

# Verify installations
RUN zig version && valgrind --version

# Default command
CMD ["bash"]

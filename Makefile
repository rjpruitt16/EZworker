# Simple Makefile for Docker-based Zig development

# Docker image to use (build locally)
ZIG_IMAGE = zig-dev
DOCKER_RUN = docker run --rm --network=host -v $(shell pwd):/workspace -w /workspace $(ZIG_IMAGE)

# Build the Docker image first
setup:
	@echo "🐳 Building Zig development image..."
	docker build -t $(ZIG_IMAGE) .

# Development commands
.PHONY: build run test clean version setup

build:
	@echo "🔨 Building in Docker..."
	$(DOCKER_RUN) zig build

run:
	@echo "🚀 Running in Docker..."
	$(DOCKER_RUN) zig build run

test:
	@echo "🧪 Testing in Docker..."
	$(DOCKER_RUN) zig test src/main.zig

version:
	@echo "📋 Zig version in Docker..."
	$(DOCKER_RUN) zig version

clean:
	@echo "🧹 Cleaning build artifacts..."
	$(DOCKER_RUN) rm -rf zig-out zig-cache

# Add local commands
run-local:
	@echo "🚀 Running locally..."
	zig build run

build-local:
	@echo "🔨 Building locally..."
	zig build

dev-local: build-local run-local

# Development workflow
dev: build run

# First time setup
init: setup version

# Help
help:
	@echo "Available commands:"
	@echo "  make init    - Build Docker image and test"
	@echo "  make build   - Build the project in Docker"
	@echo "  make run     - Run the project in Docker"
	@echo "  make dev     - Build and run"
	@echo "  make clean   - Clean build artifacts"

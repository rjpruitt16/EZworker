#!/bin/bash

# Build and run the debug container
echo "Building debug container..."
docker build -t ezworker-debug -f Dockerfile .

echo "Running container with source mounted..."
docker run -it --rm \
    -v $(pwd):/workspace \
    -p 8080:8080 \
    --name ezworker-debug \
    ezworker-debug bash -c "
        echo '=== Building EZworker in debug mode ==='
        zig build
        
        echo '=== Running with Valgrind ==='
        valgrind --leak-check=full \
                 --show-leak-kinds=all \
                 --track-origins=yes \
                 --verbose \
                 --log-file=valgrind.log \
                 ./zig-out/bin/ezworker
        
        echo '=== Valgrind log ==='
        cat valgrind.log
    "

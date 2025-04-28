#!/bin/sh
set -e

echo "Checking format..."
find src/ -name '*.zig' | xargs zig fmt --check
echo "Running unit tests..."
zig build test --summary all
echo "Compiling and installing..."
zig build --summary all

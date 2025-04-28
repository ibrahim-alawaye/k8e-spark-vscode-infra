#!/bin/bash

set -e

echo "=== Starting configuration for users ==="

# Make all scripts executable
chmod +x ./*.sh

# Run installation scripts in sequence
./setup-users.sh
./verify-users.sh

echo "=== Configuration complete! ==="

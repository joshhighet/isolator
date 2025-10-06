#!/bin/bash
set -e

echo "running bats tests..."
echo ""
bats --formatter tap scripts/isolator.bats

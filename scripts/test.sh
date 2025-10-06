#!/bin/bash
set -e
bats --timing --formatter pretty scripts/isolator.bats

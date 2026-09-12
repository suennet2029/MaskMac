#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp -t maskmac-transition-tests)
trap 'rm -f "$test_binary"' EXIT
swiftc Sources/MaskMac/Core/DisplayTransition.swift Tests/MaskMacTests/DisplayTransitionTests.swift -o "$test_binary"
"$test_binary"

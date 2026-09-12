#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp -t maskmac-transition-tests)
trap 'rm -f "$test_binary"' EXIT
swiftc Sources/MaskMac/Core/DisplayTransition.swift Tests/MaskMacTests/DisplayTransitionTests.swift -o "$test_binary"
"$test_binary"

test_binary2=$(mktemp -t maskmac-brightness-tests)
trap 'rm -f "$test_binary" "$test_binary2"' EXIT
swiftc -parse-as-library Tests/MaskMacTests/BrightnessAndLLMTests.swift -o "$test_binary2"
"$test_binary2"

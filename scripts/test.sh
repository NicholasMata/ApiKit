#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd -P)"
reports="$root/.build/reports"
mkdir -p "$reports"

case "${1:-coverage}" in
  coverage)
    swift test --force-resolved-versions --enable-code-coverage \
      --parallel --num-workers 4 --disable-swift-testing \
      --xunit-output "$reports/tests.xml"
    bin_path="$(swift build --show-bin-path)"
    profile="$bin_path/codecov/default.profdata"
    binary="$bin_path/ApiKitPackageTests.xctest/Contents/MacOS/ApiKitPackageTests"
    ignored='(/Tests/|/checkouts/|/derived/|/\.build/)'
    xcrun llvm-cov export "$binary" -instr-profile="$profile" \
      -ignore-filename-regex="$ignored" > "$reports/coverage.json"
    xcrun llvm-cov export "$binary" -instr-profile="$profile" \
      -ignore-filename-regex="$ignored" -format=lcov > "$reports/coverage.lcov"
    xcrun llvm-cov show "$binary" -instr-profile="$profile" \
      -ignore-filename-regex="$ignored" -format=html -output-dir="$reports/html"
    swift scripts/check-coverage.swift "$reports/coverage.json" "$root" \
      scripts/coverage-thresholds.json "$reports/summary.md"
    ;;
  thread)
    # Run XCTest directly: SwiftPM's parallel discovery helper cannot load TSan
    # on macOS versions that enforce the platform binary sanitizer policy.
    swift test --force-resolved-versions --sanitize=thread \
      --disable-swift-testing --scratch-path .build/tsan \
      2>&1 | tee "$reports/thread-sanitizer.log"
    ;;
  stress)
    filter='CancellationRaceTests|OAuthCancellationTests|HttpOperationTests|ApiUnitTests'
    swift test --force-resolved-versions --filter "$filter"
    for iteration in {1..10}; do
      echo "Concurrency regression run $iteration/10"
      swift test --skip-build --filter "$filter"
    done
    ;;
  release)
    swift test --force-resolved-versions -c release \
      --parallel --num-workers 4 --disable-swift-testing \
      --xunit-output "$reports/release.xml"
    ;;
  *)
    echo "Usage: bash scripts/test.sh [coverage|thread|stress|release]" >&2
    exit 2
    ;;
esac

# Testing

Run these commands from the repository root with Xcode selected as the active
developer directory. They use the checked-in `Package.resolved`; no test requires
public API services, Google credentials, or application keychain entries.
Package dependencies still need to be downloaded on the first build.

```sh
bash scripts/test.sh coverage
bash scripts/test.sh stress
bash scripts/test.sh thread
bash scripts/test.sh release
```

The complete suite covers URLSession request/response processing through local
URLProtocol fixtures, decoding, status-code boundaries, download writes and
failures, request construction and form encoding, operation dependencies,
cancellation races, shared OAuth refresh, and Google provider compatibility.
The Google SDK is replaced only through an internal test seam. On `1.1.0`, tests
preserve previous sign-in restoration during refresh. On `next`, tests verify
refresh of the current user and rejection of results from ended sessions.

## CI

The Tests workflow runs for pushes and pull requests targeting `1.1.0`, `main`,
or `next`, and can be started manually. Its jobs run:

- The complete suite with coverage on macOS 15 and macOS 26.
- Cancellation and concurrency tests once, then ten additional times.
- The complete suite under Thread Sanitizer, which fails on reported races.
- The complete suite with release optimizations enabled.
- All three modules' tests on an available iOS simulator.

The package test scheme does not run a formatter before building. Tests should
validate the checked-in code without rewriting source files.

Coverage and release jobs use SwiftPM's parallel XCTest runner, with bounded
worker counts, to produce JUnit results. Sanitizer and stress jobs run tests in
one process and exercise shared state across test cases. The sanitizer job saves
its diagnostic log; serial execution also avoids macOS restrictions on loading
sanitizers into SwiftPM's parallel test-discovery helper.

To run iOS tests locally, find a simulator with `xcrun simctl list devices available`
and substitute its UUID below. Use a fresh result-bundle path for each run:

```sh
xcodebuild test -scheme ApiKit-Package \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath .build/ios \
  -resultBundlePath .build/ios-tests.xcresult \
  -disableAutomaticPackageResolution \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

## Coverage reports

`coverage` writes reports into `.build/reports/`:

- `html/index.html`: browsable source coverage.
- `coverage.lcov`: LCOV data for coverage tools.
- `coverage.json`: LLVM coverage data.
- `summary.md`: module totals and critical-file checks.
- `tests.xml`: JUnit-compatible test results.

CI adds the coverage summary to each job and uploads downloadable reports for
14 days, including test results when available after a failure. No external
coverage service or token is required.

[`coverage-thresholds.json`](../scripts/coverage-thresholds.json) requires at least
90% line coverage for `HttpOperation`, `OAuthInterceptor`, and
`DefaultGoogleAuthProvider`, and 85% for `Api`. Falling below a threshold, missing
a required file, or missing a module's coverage data fails the check. The summary
shows all three modules' totals, including older code outside these gates;
the critical-file percentages are not overall library coverage.

Thresholds allow some variation in compiler instrumentation across toolchains.
They are minimums, not a guarantee of correctness. Race tests, sanitizer runs,
and iOS/release jobs provide separate checks that line coverage cannot.

OIDC persistence and real Google sign-in/restoration are not exercised against
live services. The declared oldest OS versions are not executed by this workflow;
the simulator job uses a runtime installed on its runner. Repository branch
protection must be configured separately if passing CI is required before merging.

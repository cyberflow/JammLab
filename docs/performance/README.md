# JammLab Performance Benchmarks

Performance benchmarks are intentionally isolated from the normal test workflow.
Do not add performance tests to `JammLabTests`.

## Normal Tests

Run correctness tests with the regular app scheme:

```sh
xcodebuild test \
  -project JammLab.xcodeproj \
  -scheme JammLab \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64
```

This command must not run `JammLabPerformanceTests`.

## Manual Benchmarks

Run performance benchmarks manually with the dedicated scheme:

```sh
SKIP_BUNDLED_SEPARATOR_HELPER=1 xcodebuild test \
  -project JammLab.xcodeproj \
  -scheme JammLabPerformance \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64
```

The benchmark suite writes the latest machine-readable and Markdown results to a
sandbox-writable temporary directory by default and prints the exact path:

- `latest.json`
- `latest.md`

Set `JAMMLAB_PERF_OUTPUT_DIR=/path/to/results` to request a different output
directory. The hosted macOS app sandbox may reject arbitrary repository paths; in
that case the benchmarks automatically fall back to the temporary directory.
Keep generated `latest.*` files out of the regular test workflow.

## Recording A Baseline

Before changing production performance code:

1. Run the manual benchmark command.
2. Open the printed results directory and copy the relevant values from `latest.md`.
3. Record machine, macOS, Xcode, branch, commit, and command in `baseline.md`.
4. Only then start optimization work.

After optimization, record the matching before/after comparison in
`optimization-report.md`.

Automated benchmarks are useful for repeatable wall-clock comparisons. CPU,
SwiftUI invalidations, audio start latency, and leak investigation require
Instruments and must be documented separately.

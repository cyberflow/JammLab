# Performance Baseline

This baseline was captured before production performance optimization work.
Do not claim performance improvements unless a later run uses the same benchmark
suite and compares against these values.

## Environment

- Date: 2026-06-13 08:40 EEST
- Branch: `perf/measurement-baseline`
- Baseline commit before measurement infrastructure changes: `ccedf51`
- Architecture: `arm64`
- macOS: 26.5.1 (25F80)
- Xcode: 26.5 (17F42)
- Hardware CPU/RAM details: unavailable in the current sandbox; record manually for
  future Instruments runs.

## Command

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

The hosted app sandbox rejected direct repository output and also rejected the
requested `/private/tmp/JammLabPerformanceResults` override in this environment.
The benchmark recorder fell back to:

`/Users/cyberflow/Library/Containers/com.cyberflow.JammLab/Data/tmp/JammLabPerformanceResults`

## Automated Results

| Benchmark | Iterations | Avg ms | Min ms | Max ms | Memory Delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| `large_marker_region_filtering_25000_notes` | 200 | 3.540 | 3.294 | 3.863 | 48.00 KB |
| `large_project_load_12000_notes` | 20 | 21.897 | 21.629 | 22.331 | 0 B |
| `large_project_save_12000_notes` | 20 | 20.194 | 19.739 | 20.884 | 80.00 KB |
| `peakform_generation_synthetic_20s` | 3 | 563.813 | 557.043 | 568.852 | 0 B |
| `tempo_grid_full_900s` | 2000 | 0.141 | 0.132 | 0.184 | 16.00 KB |
| `tempo_grid_zoomed_16s` | 2000 | 0.034 | 0.031 | 0.068 | 16.00 KB |
| `timeline_viewport_pan_zoom_10000_steps` | 100 | 1.686 | 1.610 | 1.784 | 0 B |
| `track_pitch_analyzer_synthetic_1s` | 2 | 7289.518 | 7284.615 | 7294.421 | 7.02 MB |
| `viewmodel_lifecycle_memory_smoke_100_cycles` | 5 | 35.817 | 35.461 | 36.257 | 0 B |
| `waveform_visible_range_aggregation_1920px` | 10 | 15.215 | 14.827 | 15.686 | 0 B |

## Initial Observations

- `track_pitch_analyzer_synthetic_1s` is the slowest automated benchmark by a
  large margin and allocates the most resident memory during the measured window.
- `peakform_generation_synthetic_20s` is the next highest wall-clock benchmark
  and should be checked with Instruments before production changes.
- Timeline math, tempo-grid generation, large marker/region filtering, and
  project encode/decode are now covered by deterministic synthetic workloads.

## Limitations

- CPU percentage, SwiftUI invalidation frequency, playback CPU, audio start
  latency, scrolling smoothness, and leak analysis are not reliably captured by
  this XCTest suite. Use `manual-profiling.md` with Instruments for those.
- The benchmark target is intentionally excluded from the normal `JammLab` test
  scheme and should be run only by a developer before and after performance work.
- Memory deltas are resident-memory snapshots around each scenario. They are
  useful as smoke signals, not as definitive leak proof.

# Performance Optimization Report

This report compares the baseline run in `baseline.md` with the first
post-optimization run after a focused pitch-analysis allocation cleanup.

## Change

- `TrackPitchAnalyzer` now passes `ArraySlice<Float>` windows into
  `PitchDetector` instead of copying each window into a new `Array`.
- `PitchDetector` now supports a reusable `PitchDetectionWorkspace` for YIN
  difference and cumulative-mean buffers during track analysis.
- Frequency limits and YIN threshold behavior were not changed.

## Before / After

| Benchmark | Baseline Avg ms | Post Avg ms | Change | Notes |
| --- | ---: | ---: | ---: | --- |
| `large_marker_region_filtering_25000_notes` | 3.540 | 3.629 | -2.5% | Noise, unrelated |
| `large_project_load_12000_notes` | 21.897 | 21.772 | +0.6% | Noise, unrelated |
| `large_project_save_12000_notes` | 20.194 | 20.747 | -2.7% | Noise, unrelated |
| `peakform_generation_synthetic_20s` | 563.813 | 559.500 | +0.8% | Noise, unrelated |
| `tempo_grid_full_900s` | 0.141 | 0.140 | +0.6% | Noise, unrelated |
| `tempo_grid_zoomed_16s` | 0.034 | 0.034 | -0.4% | Noise, unrelated |
| `timeline_viewport_pan_zoom_10000_steps` | 1.686 | 1.702 | -0.9% | Noise, unrelated |
| `track_pitch_analyzer_synthetic_1s` | 7289.518 | 6664.759 | +8.6% | Confirmed targeted improvement |
| `viewmodel_lifecycle_memory_smoke_100_cycles` | 35.817 | 36.353 | -1.5% | Noise, unrelated |
| `waveform_visible_range_aggregation_1920px` | 15.215 | 15.180 | +0.2% | Noise, unrelated |

Positive change means lower average wall-clock time.

## Memory

| Benchmark | Baseline Delta | Post Delta | Notes |
| --- | ---: | ---: | --- |
| `track_pitch_analyzer_synthetic_1s` | 7.02 MB | 7.08 MB | No confirmed resident-memory improvement |
| `tempo_grid_zoomed_16s` | 16.00 KB | 0 B | Small snapshot difference |
| Other scenarios | 0 B to 80.00 KB | 0 B to 80.00 KB | No meaningful change confirmed |

The pitch change reduces repeated short-lived allocations inside the measured
loop, but resident-memory snapshots did not show a confirmed decrease. Use
Allocations in Instruments to verify allocation count and lifetime if this path
needs deeper tuning.

## Bottlenecks

- `track_pitch_analyzer_synthetic_1s` remains the largest automated bottleneck
  after the cleanup. Further gains likely require algorithmic work or a bounded
  frequency search strategy, and must preserve low bass support.
- `peakform_generation_synthetic_20s` remains the second largest automated
  benchmark and should be profiled before changing decode or accumulator logic.

## Regressions And Trade-offs

- No correctness regressions were found in the regular XCTest suite.
- The pitch detector now exposes a reusable workspace type for batch analysis.
  This is a small API expansion inside the app module, not a user-facing change.
- Non-target benchmark changes are treated as measurement noise because they are
  small and unrelated to the modified code path.

## Validation

- Regular `JammLab` scheme: 163 tests, 0 failures.
- Manual `JammLabPerformance` scheme: 8 tests, 0 failures.
- Normal `JammLab` target graph did not include `JammLabPerformanceTests`.

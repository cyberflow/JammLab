# Manual Profiling Checklist

Use Instruments for metrics that are not reliable inside XCTest.

## Setup

1. Build `JammLab` in Debug or Release, matching the scenario being measured.
2. Use local audio/video files only.
3. Close unrelated CPU-heavy applications.
4. Record macOS version, Xcode version, machine model, branch, and commit.

## CPU: Idle And Playback

1. Open JammLab with no media.
2. Profile with Time Profiler for 60 seconds and record idle CPU.
3. Import a local audio file.
4. Start playback at 1x speed for 60 seconds.
5. Record average CPU and top call stacks.

## Timeline Scrolling And Zooming

1. Open a project with peakform data and many markers/regions.
2. Profile with Time Profiler.
3. Repeatedly scroll and zoom the timeline for 60 seconds.
4. Record average CPU, main-thread hot spots, and rendering-related call stacks.

## SwiftUI Invalidations

1. Use Instruments' SwiftUI template.
2. Open a project and start playback.
3. Scroll and zoom the timeline.
4. Record views with frequent body recomputation and whether the invalidations
   correlate with playback clock, timeline range, markers, regions, or peakform.

## Memory And Leaks

1. Use Allocations and Leaks.
2. Import a local audio file, play for 60 seconds, then stop.
3. Repeat open/close project operations at least 10 times.
4. Record persistent allocation growth and any retained task or ViewModel paths.

## Audio Start Latency

1. Add temporary signpost points only if needed around playback start request and
   first audible engine state transition.
2. Use Instruments' Points of Interest.
3. Measure latency across repeated playback starts.
4. Do not report latency improvements unless the same signposts are used before
   and after the change.

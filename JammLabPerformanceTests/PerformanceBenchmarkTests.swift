import AVFoundation
import Darwin
import XCTest
@testable import JammLab

final class PerformanceBenchmarkTests: XCTestCase {
    func testPeakformGenerationFromSyntheticAudio() throws {
        let directory = try BenchmarkFixtures.temporaryDirectory(named: "peakform-generation")
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("synthetic-20s.wav")
        try BenchmarkFixtures.writeSineWaveWAV(
            to: audioURL,
            duration: 20,
            frequencies: [110, 220, 440],
            amplitude: 0.45
        )

        let generator = PeakformGenerator()
        let result = try BenchmarkRunner.measure(
            name: "peakform_generation_synthetic_20s",
            iterations: 3
        ) {
            let peakform = try generator.buildPeakform(from: audioURL)
            return peakform.levels.reduce(0) { $0 + $1.peaks.count }
        }

        XCTAssertGreaterThan(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }

    func testWaveformVisibleRangeAggregation() throws {
        let peakform = BenchmarkFixtures.peakform(duration: 900, sampleRate: 44_100, samplesPerPeak: 128)
        let level = try XCTUnwrap(peakform.levels.first)
        let viewport = TimelineViewport(duration: peakform.duration, visibleRange: 120...720)
        let visibleRange = try XCTUnwrap(PeakformRenderer.visiblePeakRange(
            level: level,
            sampleRate: peakform.sampleRate,
            viewport: viewport
        ))
        let columnCount = 1_920
        let peakDuration = Double(level.samplesPerPeak) / peakform.sampleRate

        let result = BenchmarkRunner.measure(
            name: "waveform_visible_range_aggregation_1920px",
            iterations: 10
        ) {
            var checksum = 0
            for column in 0..<columnCount {
                let startTime = viewport.clampedRange.lowerBound
                    + (Double(column) / Double(columnCount)) * viewport.visibleDuration
                let endTime = viewport.clampedRange.lowerBound
                    + (Double(column + 1) / Double(columnCount)) * viewport.visibleDuration
                let startIndex = max(
                    visibleRange.lowerBound,
                    min(Int(floor(startTime / peakDuration)), visibleRange.upperBound - 1)
                )
                let endIndex = max(
                    startIndex,
                    min(Int(ceil(endTime / peakDuration)), visibleRange.upperBound - 1)
                )
                if let aggregate = PeakformRenderer.aggregate(peaks: level.peaks, in: startIndex..<(endIndex + 1)) {
                    checksum &+= Int((aggregate.max - aggregate.min) * 10_000)
                }
            }
            return checksum
        }

        XCTAssertNotEqual(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }

    func testTempoGridGenerationZoomedAndFullTrack() throws {
        let settings = BeatGridSettings(bpm: 132, firstBeatTime: 0.125)
        let zoomedViewport = TimelineViewport(duration: 900, visibleRange: 120...136)
        let fullViewport = TimelineViewport(duration: 900, visibleRange: 0...900)
        let calculator = TempoGridCalculator()

        let zoomed = BenchmarkRunner.measure(
            name: "tempo_grid_zoomed_16s",
            iterations: 2_000
        ) {
            calculator.grid(
                settings: settings,
                viewport: zoomedViewport,
                width: 1_920,
                minimumLabelSpacing: 72
            ).markers.count
        }

        let full = BenchmarkRunner.measure(
            name: "tempo_grid_full_900s",
            iterations: 2_000
        ) {
            calculator.grid(
                settings: settings,
                viewport: fullViewport,
                width: 1_920,
                minimumLabelSpacing: 72
            ).markers.count
        }

        XCTAssertGreaterThan(zoomed.checksum, 0)
        XCTAssertGreaterThan(full.checksum, 0)
        try BenchmarkRecorder.shared.record(zoomed)
        try BenchmarkRecorder.shared.record(full)
    }

    func testTimelineViewportPanZoomCalculations() throws {
        let result = BenchmarkRunner.measure(
            name: "timeline_viewport_pan_zoom_10000_steps",
            iterations: 100
        ) {
            var viewport = TimelineViewport(duration: 3_600, visibleRange: 600...660)
            var checksum = 0
            for step in 0..<10_000 {
                if step.isMultiple(of: 3) {
                    viewport = viewport.zoomed(
                        to: viewport.visibleDuration * 0.92,
                        anchoredAt: viewport.clampedRange.lowerBound + viewport.visibleDuration * 0.35
                    )
                } else {
                    viewport = viewport.panned(by: Double((step % 7) - 3) * 0.08)
                }
                checksum &+= Int(viewport.clampedRange.lowerBound * 100)
            }
            return checksum
        }

        XCTAssertNotEqual(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }

    func testLargeMarkerRegionPartitioning() throws {
        let notes = BenchmarkFixtures.notes(markerCount: 20_000, regionCount: 5_000, duration: 3_600)
        let viewport = TimelineViewport(duration: 3_600, visibleRange: 1_200...1_500)

        let result = BenchmarkRunner.measure(
            name: "large_marker_region_filtering_25000_notes",
            iterations: 200
        ) {
            let markers = notes.filter { $0.isMarker && viewport.contains($0.time) }
            let regions = notes.filter { note in
                note.isRegion && viewport.intersection(start: note.time, end: note.regionEndTime) != nil
            }
            return markers.count + regions.count
        }

        XCTAssertGreaterThan(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }

    func testLargeProjectEncodeDecode() throws {
        let directory = try BenchmarkFixtures.temporaryDirectory(named: "project-io")
        defer { try? FileManager.default.removeItem(at: directory) }

        let projectURL = directory.appendingPathComponent("LargeProject.jammlab")
        let project = BenchmarkFixtures.project(noteCount: 12_000, duration: 3_600)
        let service = ProjectDocumentService()

        let saveResult = try BenchmarkRunner.measure(
            name: "large_project_save_12000_notes",
            iterations: 20
        ) {
            try service.save(project, to: projectURL)
            return Int((try FileManager.default.attributesOfItem(atPath: projectURL.path)[.size] as? NSNumber)?.intValue ?? 0)
        }

        try service.save(project, to: projectURL)
        let loadResult = try BenchmarkRunner.measure(
            name: "large_project_load_12000_notes",
            iterations: 20
        ) {
            try service.load(from: projectURL).notes.count
        }

        XCTAssertGreaterThan(saveResult.checksum, 0)
        XCTAssertEqual(loadResult.checksum, project.notes.count * 20)
        try BenchmarkRecorder.shared.record(saveResult)
        try BenchmarkRecorder.shared.record(loadResult)
    }

    func testTrackPitchAnalyzerSyntheticAudio() async throws {
        let directory = try BenchmarkFixtures.temporaryDirectory(named: "pitch-analysis")
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("synthetic-pitch-1s.wav")
        try BenchmarkFixtures.writeSineWaveWAV(to: audioURL, duration: 1, frequencies: [220], amplitude: 0.5)
        let analyzer = TrackPitchAnalyzer(windowSize: 4_096, hopSize: 2_048)

        let result = try await BenchmarkRunner.measureAsync(
            name: "track_pitch_analyzer_synthetic_1s",
            iterations: 2
        ) {
            try await analyzer.analyze(url: audioURL).filter { $0.result != nil }.count
        }

        XCTAssertGreaterThan(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }

    @MainActor
    func testViewModelLifecycleMemorySmoke() throws {
        let result = BenchmarkRunner.measure(
            name: "viewmodel_lifecycle_memory_smoke_100_cycles",
            iterations: 5
        ) {
            var checksum = 0
            for _ in 0..<100 {
                autoreleasepool {
                    let engine = MockPlaybackEngine()
                    let viewModel = AudioPlayerViewModel(
                        analyzer: MockAnalyzer(),
                        peakformProvider: MockPeakformProvider(),
                        playbackEngine: engine,
                        videoFollower: MockVideoFollower(),
                        isSandboxed: { false }
                    )
                    viewModel.notes = BenchmarkFixtures.notes(markerCount: 200, regionCount: 50, duration: 300)
                    viewModel.duration = 300
                    checksum &+= viewModel.notes.count
                    viewModel.newProject()
                }
            }
            return checksum
        }

        XCTAssertGreaterThan(result.checksum, 0)
        try BenchmarkRecorder.shared.record(result)
    }
}

private enum BenchmarkFixtures {
    static func temporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JammLabPerformanceTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writeSineWaveWAV(
        to url: URL,
        duration: TimeInterval,
        sampleRate: Double = 44_100,
        frequencies: [Double],
        amplitude: Float
    ) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let sample = frequencies.reduce(0.0) { partial, frequency in
                partial + sin(2 * Double.pi * frequency * time)
            } / Double(max(frequencies.count, 1))
            channel[frame] = amplitude * Float(sample)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func peakform(duration: TimeInterval, sampleRate: Double, samplesPerPeak: Int) -> PeakformData {
        let peakCount = Int((duration * sampleRate) / Double(samplesPerPeak))
        let peaks = (0..<peakCount).map { index in
            let phase = Float(index % 512) / 512
            let maxValue = 0.15 + phase * 0.75
            return PeakPoint(min: -maxValue, max: maxValue, rms: maxValue * 0.62)
        }
        return PeakformData(
            duration: duration,
            sampleRate: sampleRate,
            levels: [PeakformLevel(samplesPerPeak: samplesPerPeak, peaks: peaks)]
        )
    }

    static func notes(markerCount: Int, regionCount: Int, duration: TimeInterval) -> [TimecodedNote] {
        let markers = (0..<markerCount).map { index in
            TimecodedNote(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                kind: .marker,
                time: duration * Double(index) / Double(max(markerCount, 1)),
                title: "Marker \(index)"
            )
        }
        let regions = (0..<regionCount).map { index in
            TimecodedNote(
                id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                kind: .region,
                time: duration * Double(index) / Double(max(regionCount, 1)),
                duration: 8 + Double(index % 16),
                title: "Region \(index)"
            )
        }
        return (markers + regions).sorted { $0.time < $1.time }
    }

    static func project(noteCount: Int, duration: TimeInterval) -> JammLabProject {
        JammLabProject(
            audioBookmarkData: Data("synthetic-audio-bookmark".utf8),
            artifactRootBookmarkData: Data("synthetic-artifact-bookmark".utf8),
            audioDisplayName: "Synthetic Benchmark.wav",
            audioDuration: duration,
            mediaKind: .audio,
            notes: notes(markerCount: noteCount * 3 / 4, regionCount: noteCount / 4, duration: duration),
            loopStart: 12,
            loopEnd: 28,
            isLoopEnabled: true,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: 128,
            beatGridSettings: BeatGridSettings(bpm: 128, firstBeatTime: 0.12),
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            isClickEnabled: false,
            clickVolume: AppSliderDefaults.clickVolume,
            isSnapEnabled: true,
            playbackMode: .original,
            stemState: nil,
            isVideoWindowOpen: nil
        )
    }
}

private struct BenchmarkResult: Codable {
    let name: String
    let iterations: Int
    let totalMilliseconds: Double
    let averageMilliseconds: Double
    let minMilliseconds: Double
    let maxMilliseconds: Double
    let residentMemoryBeforeBytes: UInt64
    let residentMemoryAfterBytes: UInt64
    let residentMemoryDeltaBytes: Int64
    let checksum: Int
}

private enum BenchmarkRunner {
    static func measure(
        name: String,
        iterations: Int,
        warmupIterations: Int = 1,
        _ body: () throws -> Int
    ) rethrows -> BenchmarkResult {
        for _ in 0..<warmupIterations {
            _ = try body()
        }

        let memoryBefore = MemorySampler.residentMemoryBytes()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        var checksum = 0

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= try body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }

        let memoryAfter = MemorySampler.residentMemoryBytes()
        let total = samples.reduce(0, +)
        return BenchmarkResult(
            name: name,
            iterations: iterations,
            totalMilliseconds: total,
            averageMilliseconds: total / Double(max(iterations, 1)),
            minMilliseconds: samples.min() ?? 0,
            maxMilliseconds: samples.max() ?? 0,
            residentMemoryBeforeBytes: memoryBefore,
            residentMemoryAfterBytes: memoryAfter,
            residentMemoryDeltaBytes: Int64(memoryAfter) - Int64(memoryBefore),
            checksum: checksum
        )
    }

    static func measureAsync(
        name: String,
        iterations: Int,
        warmupIterations: Int = 1,
        _ body: () async throws -> Int
    ) async rethrows -> BenchmarkResult {
        for _ in 0..<warmupIterations {
            _ = try await body()
        }

        let memoryBefore = MemorySampler.residentMemoryBytes()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        var checksum = 0

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= try await body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }

        let memoryAfter = MemorySampler.residentMemoryBytes()
        let total = samples.reduce(0, +)
        return BenchmarkResult(
            name: name,
            iterations: iterations,
            totalMilliseconds: total,
            averageMilliseconds: total / Double(max(iterations, 1)),
            minMilliseconds: samples.min() ?? 0,
            maxMilliseconds: samples.max() ?? 0,
            residentMemoryBeforeBytes: memoryBefore,
            residentMemoryAfterBytes: memoryAfter,
            residentMemoryDeltaBytes: Int64(memoryAfter) - Int64(memoryBefore),
            checksum: checksum
        )
    }
}

private final class BenchmarkRecorder {
    static let shared = BenchmarkRecorder()

    private let lock = NSLock()
    private var results: [BenchmarkResult] = []
    private var announcedOutputPath: String?

    func record(_ result: BenchmarkResult) throws {
        lock.lock()
        results.removeAll { $0.name == result.name }
        results.append(result)
        let snapshot = results.sorted { $0.name < $1.name }
        lock.unlock()

        let directory = try writableOutputDirectory()
        announceOutputDirectoryIfNeeded(directory)
        try writeJSON(snapshot, to: directory.appendingPathComponent("latest.json"))
        try writeMarkdown(snapshot, to: directory.appendingPathComponent("latest.md"))
    }

    private func outputDirectoryCandidates() -> [URL] {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JammLabPerformanceResults", isDirectory: true)

        if let path = ProcessInfo.processInfo.environment["JAMMLAB_PERF_OUTPUT_DIR"], !path.isEmpty {
            return [URL(fileURLWithPath: path, isDirectory: true), temporaryDirectory]
        }

        return [temporaryDirectory]
    }

    private func writableOutputDirectory() throws -> URL {
        var lastError: Error?

        for candidate in outputDirectoryCandidates() {
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                let probeURL = candidate.appendingPathComponent(".write-probe")
                try Data().write(to: probeURL, options: .atomic)
                try? FileManager.default.removeItem(at: probeURL)
                return candidate
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func announceOutputDirectoryIfNeeded(_ directory: URL) {
        lock.lock()
        defer { lock.unlock() }

        guard announcedOutputPath != directory.path else { return }
        announcedOutputPath = directory.path
        print("JammLab performance benchmark results: \(directory.path)")
    }

    private func writeJSON(_ results: [BenchmarkResult], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: url, options: .atomic)
    }

    private func writeMarkdown(_ results: [BenchmarkResult], to url: URL) throws {
        var lines = [
            "# Latest Performance Benchmark Results",
            "",
            "| Benchmark | Iterations | Avg ms | Min ms | Max ms | Memory Delta |",
            "| --- | ---: | ---: | ---: | ---: | ---: |"
        ]

        for result in results {
            lines.append(
                "| \(result.name) | \(result.iterations) | \(format(result.averageMilliseconds)) | \(format(result.minMilliseconds)) | \(format(result.maxMilliseconds)) | \(formatBytes(result.residentMemoryDeltaBytes)) |"
            )
        }

        lines.append("")
        lines.append("Generated by the manual `JammLabPerformance` scheme.")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func formatBytes(_ value: Int64) -> String {
        let sign = value < 0 ? "-" : ""
        let absolute = Double(abs(value))
        if absolute >= 1_048_576 {
            return "\(sign)\(String(format: "%.2f", absolute / 1_048_576)) MB"
        }
        if absolute >= 1_024 {
            return "\(sign)\(String(format: "%.2f", absolute / 1_024)) KB"
        }
        return "\(value) B"
    }
}

private enum MemorySampler {
    static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}

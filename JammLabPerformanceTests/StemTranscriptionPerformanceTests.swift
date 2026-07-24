import AVFoundation
import XCTest
@testable import JammLab

final class StemTranscriptionPerformanceTests: XCTestCase {
    func testRepresentativeDurationsAndSourceFormats() async throws {
        let service = StemTranscriptionService()
        let cases = [
            BenchmarkCase(label: "short-stereo-44k", duration: 10, sampleRate: 44_100, channels: 2),
            BenchmarkCase(label: "minute-mono-48k", duration: 60, sampleRate: 48_000, channels: 1),
            BenchmarkCase(label: "long-stereo-32k", duration: 120, sampleRate: 32_000, channels: 2)
        ]

        for (index, benchmark) in cases.enumerated() {
            let audioURL = try makeAudioFile(benchmark)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let operation = StemTranscriptionOperation()
            let progressRecorder = TranscriptionProgressRecorder()
            let result = try await service.transcribe(
                stemURL: audioURL,
                configuration: .neuralNoteDefaults,
                operation: operation,
                progress: { progressRecorder.record(phase: $0, progress: $1) }
            )

            XCTAssertFalse(result.notes.isEmpty, benchmark.label)
            XCTAssertEqual(
                result.timings.processedDurationSeconds,
                benchmark.duration,
                accuracy: 0.1,
                benchmark.label
            )
            XCTAssertEqual(
                progressRecorder.distinctPhases,
                [.preparingAudio, .loadingModel, .transcribing, .processingNotes],
                benchmark.label
            )
            XCTAssertTrue(
                progressRecorder.values.allSatisfy { (0...1).contains($0) },
                benchmark.label
            )
            if index == 0 {
                XCTAssertGreaterThan(result.timings.modelLoadSeconds, 0, benchmark.label)
            } else {
                XCTAssertEqual(result.timings.modelLoadSeconds, 0, benchmark.label)
            }
            print(
                "TRANSCRIPTION_BENCHMARK "
                    + "\(benchmark.label) "
                    + "duration=\(formatted(result.timings.processedDurationSeconds))s "
                    + "prepare=\(formatted(result.timings.audioPreparationSeconds))s "
                    + "model=\(formatted(result.timings.modelLoadSeconds))s "
                    + "inference=\(formatted(result.timings.inferenceSeconds))s "
                    + "post=\(formatted(result.timings.postProcessingSeconds))s "
                    + "total=\(formatted(result.timings.totalSeconds))s "
                    + "rtf=\(formatted(result.timings.processingTimeRatio))"
            )
        }
    }

    private func makeAudioFile(_ benchmark: BenchmarkCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-\(benchmark.label)-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: benchmark.sampleRate,
            channels: AVAudioChannelCount(benchmark.channels)
        ))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunkFrames: AVAudioFrameCount = 4_096
        let totalFrames = Int(benchmark.duration * benchmark.sampleRate)
        var writtenFrames = 0

        while writtenFrames < totalFrames {
            let frameCount = min(Int(chunkFrames), totalFrames - writtenFrames)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ))
            buffer.frameLength = AVAudioFrameCount(frameCount)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for frame in 0..<frameCount {
                let time = Double(writtenFrames + frame) / benchmark.sampleRate
                channels[0][frame] = Float(
                    0.35 * sin(2 * Double.pi * 220 * time)
                        + 0.25 * sin(2 * Double.pi * 329.6276 * time)
                )
                if benchmark.channels > 1 {
                    channels[1][frame] = Float(
                        0.35 * sin(2 * Double.pi * 220 * time)
                            + 0.25 * sin(2 * Double.pi * 440 * time)
                    )
                }
            }
            try file.write(from: buffer)
            writtenFrames += frameCount
        }
        return url
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private struct BenchmarkCase {
    var label: String
    var duration: Double
    var sampleRate: Double
    var channels: Int
}

private final class TranscriptionProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [StemTranscriptionPhase] = []
    private var progressValues: [Double] = []

    var distinctPhases: [StemTranscriptionPhase] {
        lock.withLock { phases }
    }

    var values: [Double] {
        lock.withLock { progressValues }
    }

    func record(phase: StemTranscriptionPhase, progress: Double) {
        lock.withLock {
            if phases.last != phase {
                phases.append(phase)
            }
            progressValues.append(progress)
        }
    }
}

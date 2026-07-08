import AVFoundation
import CoreAudio
import XCTest
@testable import JammLab

struct MockAudioBuffer {
    let samples: [Float]
    let sampleRate: Double
}

final class MockTunerInputEngine: TunerInputEngineControlling {
    var startDeviceIDs: [AudioDeviceID] = []
    var stopCallCount = 0
    var startErrors: [Error] = []
    var debugEvents: [TunerInputEngineDebugEvent] = []
    var audioBuffers: [MockAudioBuffer] = []
    private var audioBufferHandlers: [((AVAudioPCMBuffer, Double) -> Void)] = []
    private var debugHandlers: [((TunerInputEngineDebugEvent) -> Void)] = []

    func start(
        deviceID: AudioDeviceID,
        bufferSize: AVAudioFrameCount,
        onDebug: @escaping (TunerInputEngineDebugEvent) -> Void,
        onAudioBuffer: @escaping (AVAudioPCMBuffer, Double) -> Void
    ) throws {
        startDeviceIDs.append(deviceID)
        if !startErrors.isEmpty {
            throw startErrors.removeFirst()
        }
        debugHandlers.append(onDebug)
        audioBufferHandlers.append(onAudioBuffer)
        for event in debugEvents {
            onDebug(event)
        }
        for audioBuffer in audioBuffers {
            sendAudioBuffer(samples: audioBuffer.samples, sampleRate: audioBuffer.sampleRate)
        }
    }

    func stop() {
        stopCallCount += 1
    }

    func sendAudioBuffer(samples: [Float], sampleRate: Double = 44_100, toStartAt startIndex: Int? = nil) {
        sendAudioBuffer(Self.makeBuffer(samples: samples, sampleRate: sampleRate), sampleRate: sampleRate, toStartAt: startIndex)
    }

    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double = 44_100, toStartAt startIndex: Int? = nil) {
        let targetIndex: Int?
        if let startIndex {
            targetIndex = startIndex
        } else {
            targetIndex = audioBufferHandlers.indices.last
        }
        guard let index = targetIndex, audioBufferHandlers.indices.contains(index) else { return }
        if debugHandlers.indices.contains(index) {
            debugHandlers[index](.tap(frameLength: buffer.frameLength, sampleRate: sampleRate))
        }
        audioBufferHandlers[index](buffer, sampleRate)
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}

final class RecordingPitchDetector: PitchDetecting {
    private let lock = NSLock()
    private var recordedSampleRates: [Double] = []

    var sampleRates: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSampleRates
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        lock.lock()
        recordedSampleRates.append(sampleRate)
        lock.unlock()
        return nil
    }
}

final class BlockingPitchDetector: PitchDetecting {
    let firstDetectionStarted = XCTestExpectation(description: "First tuner pitch detection started")

    private let lock = NSLock()
    private let firstDetectionSemaphore = DispatchSemaphore(value: 0)
    private var detectionCount = 0
    private var markers: [Int] = []

    var detectedMarkers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return markers
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        let marker = Int(samples.first ?? 0)
        let index: Int

        lock.lock()
        detectionCount += 1
        index = detectionCount
        markers.append(marker)
        lock.unlock()

        if index == 1 {
            firstDetectionStarted.fulfill()
            _ = firstDetectionSemaphore.wait(timeout: .now() + 2)
        }

        return Self.result(for: marker)
    }

    func releaseFirstDetection() {
        firstDetectionSemaphore.signal()
    }

    private static func result(for marker: Int) -> PitchDetectionResult {
        switch marker {
        case 3:
            return PitchDetectionResult(
                frequencyHz: 523.25,
                midiNote: 72,
                noteName: "C",
                octave: 5,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        case 2:
            return PitchDetectionResult(
                frequencyHz: 493.88,
                midiNote: 71,
                noteName: "B",
                octave: 4,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        default:
            return PitchDetectionResult(
                frequencyHz: 440,
                midiNote: 69,
                noteName: "A",
                octave: 4,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        }
    }
}

final class QueuedPitchDetector: PitchDetecting {
    private let lock = NSLock()
    private var results: [PitchDetectionResult?]
    private var callCount = 0

    var detectCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    init(results: [PitchDetectionResult?]) {
        self.results = results
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        lock.lock()
        defer { lock.unlock() }

        callCount += 1
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
    }
}

extension XCTestCase {
    func tunerDrainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    func tunerSineWave(
        frequency: Double,
        duration: Double,
        sampleRate: Double = 44_100,
        amplitude: Float = 0.5
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }

    func tunerMarkerSamples(_ marker: Float) -> [Float] {
        Array(repeating: marker, count: 128)
    }

    @MainActor
    func waitForTunerMainActorCondition(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func makeTunerInt16Buffer(samples: [Int16], sampleRate: Double = 44_100) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(max(samples.count, 1))
        ))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.int16ChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
        }
        return buffer
    }
}

extension PitchDetectionResult {
    static func result(
        noteName: String,
        octave: Int,
        frequencyHz: Double,
        midiNote: Int
    ) -> PitchDetectionResult {
        PitchDetectionResult(
            frequencyHz: frequencyHz,
            midiNote: midiNote,
            noteName: noteName,
            octave: octave,
            centsOffset: 0,
            confidence: 1,
            rms: 1
        )
    }
}

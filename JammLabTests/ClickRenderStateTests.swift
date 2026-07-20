import AVFoundation
import XCTest
@testable import JammLab

final class ClickRenderStateTests: XCTestCase {
    private let sampleRate = 1_000.0

    func testClickDelayLineDelaysSamplesByConfiguredFrameCount() {
        var delayLine = ClickDelayLine()
        delayLine.setDelayFrames(3)

        let output = [1, 2, 3, 4, 5].map { delayLine.process(Float($0)) }

        XCTAssertEqual(output, [0, 0, 0, 1, 2])

        delayLine.setDelayFrames(0)
        XCTAssertEqual(delayLine.process(9), 9)
    }

    func testRenderOutputsSilenceWhenClickIsDisabled() {
        let state = makeClickState(settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour))
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 600)

        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testRenderUsesFirstBeatOffsetAndAccents() {
        let state = makeClickState(settings: BeatGridSettings(
            bpm: 120,
            firstBeatTime: 1,
            timeSignature: .fourFour
        ))
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 1_101)

        XCTAssertEqual(samples[0], 0.62, accuracy: 0.0001)
        XCTAssertEqual(samples[1_000], 0.95, accuracy: 0.0001)
    }

    func testRenderStartsAfterSeekPosition() {
        let state = makeClickState(settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour))
        state.setEnabled(true)
        state.play(startFrame: 1_250)

        let samples = renderSamples(from: state, frameCount: 801)

        XCTAssertEqual(nonZeroOnsetFrames(in: samples), [250, 750])
        XCTAssertEqual(samples[250], 0.62, accuracy: 0.0001)
        XCTAssertEqual(samples[750], 0.95, accuracy: 0.0001)
    }

    func testRenderSwitchesTempoMapAtMarker() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM - 3/4",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60, beatsPerBar: 3).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)
        let state = makeClickState(settings: baseSettings, durationSeconds: 6)
        state.setTempoMap(tempoMap)
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 5_101)

        XCTAssertEqual(normalizedInitialOnsetFrames(in: samples), [0, 500, 1_000, 1_500, 2_000, 3_000, 4_000, 5_000])
        XCTAssertEqual(samples[2_000], 0.95, accuracy: 0.0001)
        XCTAssertEqual(samples[3_000], 0.62, accuracy: 0.0001)
        XCTAssertEqual(samples[5_000], 0.95, accuracy: 0.0001)
    }

    func testRenderUsesEditableTimeSignatureForAccents() {
        let state = makeClickState(settings: BeatGridSettings(
            bpm: 120,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4)
        ))
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 1_601)

        XCTAssertEqual(normalizedInitialOnsetFrames(in: samples), [0, 500, 1_000, 1_500])
        XCTAssertEqual(samples[0], 0.95, accuracy: 0.0001)
        XCTAssertEqual(samples[500], 0.62, accuracy: 0.0001)
        XCTAssertEqual(samples[1_500], 0.95, accuracy: 0.0001)
    }

    func testRenderAccentsBarStartBeforePositiveFirstBeatOffset() {
        let state = makeClickState(settings: BeatGridSettings(
            bpm: 120,
            firstBeatTime: 2,
            timeSignature: .fourFour
        ))
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 2_101)

        XCTAssertEqual(normalizedInitialOnsetFrames(in: samples), [0, 500, 1_000, 1_500, 2_000])
        XCTAssertEqual(samples[0], 0.95, accuracy: 0.0001)
        XCTAssertEqual(samples[2_000], 0.95, accuracy: 0.0001)
    }

    func testRenderOutputsSilenceWithoutTempo() {
        let state = makeClickState(settings: BeatGridSettings())
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 1_000)

        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testRenderAdjustsBeatSpacingForPlaybackRate() {
        let state = makeClickState(settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour))
        state.setPlaybackRate(0.5)
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 1_101)
        let onsetFrames = normalizedInitialOnsetFrames(in: samples)

        XCTAssertEqual(onsetFrames.count, 2)
        XCTAssertEqual(onsetFrames.first, 0)
        XCTAssertEqual(Double(onsetFrames.last ?? -1), 1_000, accuracy: 1)
    }

    func testRenderRecalculatesBeatAfterLoopRestart() {
        let state = makeClickState(settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour), durationSeconds: 4)
        state.setEnabled(true)
        state.setLoop(enabled: true, startFrame: 500, endFrame: 1_500)
        state.play(startFrame: 500)

        let samples = renderSamples(from: state, frameCount: 1_101)

        XCTAssertEqual(normalizedInitialOnsetFrames(in: samples), [0, 500, 1_000])
    }

    func testRenderAppliesOutputDelay() {
        let state = makeClickState(settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour))
        state.setOutputDelay(seconds: 0.01)
        state.setEnabled(true)
        state.play(startFrame: 0)

        let samples = renderSamples(from: state, frameCount: 12)

        XCTAssertTrue(samples[0..<10].allSatisfy { $0 == 0 })
        XCTAssertEqual(samples[10], 0.95, accuracy: 0.0001)
    }

    private func makeClickState(
        settings: BeatGridSettings,
        durationSeconds: TimeInterval = 6
    ) -> ClickRenderState {
        let state = ClickRenderState()
        state.configure(
            durationFrames: AVAudioFramePosition(durationSeconds * sampleRate),
            sourceSampleRate: sampleRate,
            audioSampleRate: sampleRate
        )
        state.setSettings(settings)
        state.setVolume(1)
        return state
    }

    private func renderSamples(from state: ClickRenderState, frameCount: Int) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        state.render(frameCount: AVAudioFrameCount(frameCount), outputData: buffer.mutableAudioBufferList)

        let data = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: data, count: frameCount))
    }

    private func nonZeroOnsetFrames(in samples: [Float]) -> [Int] {
        onsetFrames(in: samples, threshold: 0.0001)
    }

    private func normalizedInitialOnsetFrames(in samples: [Float]) -> [Int] {
        onsetFrames(in: samples, threshold: 0.0001).map { $0 == 1 ? 0 : $0 }
    }

    private func onsetFrames(in samples: [Float], threshold: Float) -> [Int] {
        var frames: [Int] = []
        var previousFrame = -100

        for (frame, sample) in samples.enumerated() where abs(sample) > threshold {
            guard frame - previousFrame > 100 else { continue }
            frames.append(frame)
            previousFrame = frame
        }

        return frames
    }
}

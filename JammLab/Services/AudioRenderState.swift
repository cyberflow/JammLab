@preconcurrency import AVFoundation
import Foundation

final class AudioRenderAtomicInt64: @unchecked Sendable {
    private let storage: OpaquePointer

    init(_ value: Int64 = 0) {
        storage = JammLabAtomicInt64Create(value)
    }

    deinit {
        JammLabAtomicInt64Destroy(storage)
    }

    var value: Int64 {
        get { JammLabAtomicInt64Load(storage) }
        set { JammLabAtomicInt64Store(storage, newValue) }
    }

    @discardableResult
    func increment() -> Int64 {
        JammLabAtomicInt64Increment(storage)
    }

    @discardableResult
    func decrement() -> Int64 {
        JammLabAtomicInt64Decrement(storage)
    }
}

final class AudioRenderAtomicFloat: @unchecked Sendable {
    private let bits: AudioRenderAtomicInt64

    init(_ value: Float) {
        bits = AudioRenderAtomicInt64(Int64(value.bitPattern))
    }

    var value: Float {
        get { Float(bitPattern: UInt32(truncatingIfNeeded: bits.value)) }
        set { bits.value = Int64(newValue.bitPattern) }
    }
}

final class AudioRenderTrack: @unchecked Sendable {
    let id: MultiTrackAudioPlayer.TrackID
    let buffer: AVAudioPCMBuffer
    let frameLength: AVAudioFramePosition
    let channelCount: Int
    private let atomicVolume: AudioRenderAtomicFloat

    var volume: Float {
        get { atomicVolume.value }
        set { atomicVolume.value = newValue }
    }

    init(id: MultiTrackAudioPlayer.TrackID, buffer: AVAudioPCMBuffer, volume: Float) {
        self.id = id
        self.buffer = buffer
        self.frameLength = AVAudioFramePosition(buffer.frameLength)
        self.channelCount = Int(buffer.format.channelCount)
        atomicVolume = AudioRenderAtomicFloat(volume)
    }
}

final class AudioRenderGraphLease: @unchecked Sendable {
    let tracks: [AudioRenderTrack]
    private let activeCallbacks = AudioRenderAtomicInt64()

    init(tracks: [AudioRenderTrack]) {
        self.tracks = tracks
    }

    func beginRender() {
        activeCallbacks.increment()
    }

    func endRender() {
        activeCallbacks.decrement()
    }

    var isRenderInactive: Bool {
        activeCallbacks.value == 0
    }

    var activeRenderCount: Int64 {
        activeCallbacks.value
    }
}

final class AudioTransportRenderState: @unchecked Sendable {
    private var sourceFrame: Double = 0
    private var durationFrames: Double = 0
    private var loopStartFrame: Double = 0
    private var loopEndFrame: Double = 0
    private var isLoopEnabled = false
    private var loopArmed = false
    private var isPlaying = false
    private var didReachEnd = false
    private let publishedFrame = AudioRenderAtomicInt64()

    var currentFrame: AVAudioFramePosition {
        AVAudioFramePosition(max(0, publishedFrame.value))
    }

    func configure(durationFrames: AVAudioFramePosition) {
        self.durationFrames = max(0, Double(durationFrames))
        sourceFrame = min(sourceFrame, self.durationFrames)
        loopStartFrame = 0
        loopEndFrame = self.durationFrames
        loopArmed = false
        didReachEnd = false
        publishCurrentFrame()
    }

    func setLoop(enabled: Bool, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) {
        let start = max(0, min(Double(startFrame), durationFrames))
        let end = max(0, min(Double(endFrame), durationFrames))
        isLoopEnabled = enabled && end > start
        loopStartFrame = start
        loopEndFrame = end
        if !isLoopEnabled {
            loopArmed = false
        } else {
            loopArmed = sourceFrame < loopEndFrame
        }
    }

    func play() {
        if sourceFrame >= durationFrames {
            sourceFrame = 0
        }
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        isPlaying = true
        publishCurrentFrame()
    }

    func pause() {
        isPlaying = false
        publishCurrentFrame()
    }

    func stop() {
        sourceFrame = 0
        isPlaying = false
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        publishCurrentFrame()
    }

    func seek(to frame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(frame)))
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        publishCurrentFrame()
    }

    func nextSourceFrame() -> AVAudioFramePosition? {
        guard isPlaying, !didReachEnd else { return nil }

        if sourceFrame >= durationFrames {
            didReachEnd = true
            isPlaying = false
            publishCurrentFrame()
            return nil
        }

        if isLoopEnabled, loopArmed, sourceFrame >= loopEndFrame {
            sourceFrame = loopStartFrame
        }

        let frame = AVAudioFramePosition(max(0, min(durationFrames - 1, sourceFrame)))
        sourceFrame += 1

        if isLoopEnabled, loopArmed, sourceFrame >= loopEndFrame {
            sourceFrame = loopStartFrame
        } else if sourceFrame >= durationFrames {
            didReachEnd = true
            isPlaying = false
        }

        publishCurrentFrame()
        return frame
    }

    private func publishCurrentFrame() {
        let frame = AVAudioFramePosition(max(0, min(durationFrames, sourceFrame)).rounded())
        publishedFrame.value = Int64(frame)
    }
}

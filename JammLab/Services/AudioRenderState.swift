@preconcurrency import AVFoundation
import Foundation

final class AudioRenderTrack {
    let id: MultiTrackAudioPlayer.TrackID
    let buffer: AVAudioPCMBuffer
    let frameLength: AVAudioFramePosition
    let channelCount: Int
    var volume: Float

    init(id: MultiTrackAudioPlayer.TrackID, buffer: AVAudioPCMBuffer, volume: Float) {
        self.id = id
        self.buffer = buffer
        self.frameLength = AVAudioFramePosition(buffer.frameLength)
        self.channelCount = Int(buffer.format.channelCount)
        self.volume = volume
    }
}

final class AudioTransportRenderState {
    private(set) var sourceFrame: Double = 0
    private var durationFrames: Double = 0
    private var loopStartFrame: Double = 0
    private var loopEndFrame: Double = 0
    private var isLoopEnabled = false
    private var loopArmed = false
    private var isPlaying = false
    private var didReachEnd = false

    var currentFrame: AVAudioFramePosition {
        AVAudioFramePosition(max(0, min(durationFrames, sourceFrame)).rounded())
    }

    var reachedEnd: Bool {
        didReachEnd
    }

    func configure(durationFrames: AVAudioFramePosition) {
        self.durationFrames = max(0, Double(durationFrames))
        sourceFrame = min(sourceFrame, self.durationFrames)
        loopStartFrame = 0
        loopEndFrame = self.durationFrames
        loopArmed = false
        didReachEnd = false
    }

    func setLoop(enabled: Bool, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) {
        let start = max(0, min(Double(startFrame), durationFrames))
        let end = max(0, min(Double(endFrame), durationFrames))
        isLoopEnabled = enabled && end > start
        loopStartFrame = start
        loopEndFrame = end
        if !isLoopEnabled {
            loopArmed = false
        } else if sourceFrame < loopEndFrame {
            loopArmed = true
        } else {
            loopArmed = false
        }
    }

    func play() {
        if sourceFrame >= durationFrames {
            sourceFrame = 0
        }
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        sourceFrame = 0
        isPlaying = false
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
    }

    func seek(to frame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(frame)))
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
    }

    func nextSourceFrame() -> AVAudioFramePosition? {
        guard isPlaying, !didReachEnd else { return nil }

        if sourceFrame >= durationFrames {
            didReachEnd = true
            isPlaying = false
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

        return frame
    }
}

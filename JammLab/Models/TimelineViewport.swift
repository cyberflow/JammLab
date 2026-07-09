import CoreGraphics
import Foundation

struct TimelineViewport: Equatable {
    var duration: TimeInterval
    var visibleRange: ClosedRange<TimeInterval>

    init(duration: TimeInterval, visibleRange: ClosedRange<TimeInterval>) {
        self.duration = max(0, duration)
        self.visibleRange = visibleRange
    }

    init(duration: TimeInterval) {
        let duration = max(0, duration)
        self.init(duration: duration, visibleRange: 0...duration)
    }

    var clampedRange: ClosedRange<TimeInterval> {
        guard duration > 0 else { return 0...0 }

        let lower = max(0, min(visibleRange.lowerBound, duration))
        let upper = max(lower, min(visibleRange.upperBound, duration))
        return lower...upper
    }

    var visibleDuration: TimeInterval {
        let range = clampedRange
        return max(0, range.upperBound - range.lowerBound)
    }

    var minimumWindowLength: TimeInterval {
        Self.minimumWindowLength(for: duration)
    }

    static func minimumWindowLength(for duration: TimeInterval) -> TimeInterval {
        min(max(duration, 1), 4)
    }

    func contains(_ time: TimeInterval) -> Bool {
        let range = clampedRange
        return time >= range.lowerBound && time <= range.upperBound && duration > 0
    }

    func intersection(start: TimeInterval, end: TimeInterval) -> ClosedRange<TimeInterval>? {
        let range = clampedRange
        let lower = max(min(start, end), range.lowerBound)
        let upper = min(max(start, end), range.upperBound)

        guard upper > lower else { return nil }
        return lower...upper
    }

    func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        let range = clampedRange
        let length = range.upperBound - range.lowerBound

        guard length > 0, width > 0 else { return 0 }

        let clampedTime = max(range.lowerBound, min(time, range.upperBound))
        return CGFloat((clampedTime - range.lowerBound) / length) * width
    }

    func time(forX xPosition: CGFloat, width: CGFloat) -> TimeInterval {
        let range = clampedRange
        guard duration > 0, width > 0 else { return 0 }

        let progress = max(0, min(xPosition / width, 1))
        return range.lowerBound + TimeInterval(progress) * (range.upperBound - range.lowerBound)
    }

    func zoomed(to requestedLength: TimeInterval, centeredAt center: TimeInterval) -> TimelineViewport {
        guard duration > 0 else { return TimelineViewport(duration: 0) }

        let length = boundedWindowLength(requestedLength)
        let lower = max(0, min(center - length / 2, duration - length))
        return TimelineViewport(duration: duration, visibleRange: lower...(lower + length))
    }

    func zoomed(to requestedLength: TimeInterval, anchoredAt anchorTime: TimeInterval) -> TimelineViewport {
        guard duration > 0 else { return TimelineViewport(duration: 0) }

        let range = clampedRange
        let oldLength = max(range.upperBound - range.lowerBound, 0)
        guard oldLength > 0 else {
            return zoomed(to: requestedLength, centeredAt: duration / 2)
        }

        let clampedAnchor = max(range.lowerBound, min(anchorTime, range.upperBound))
        let anchorRatio = max(0, min((clampedAnchor - range.lowerBound) / oldLength, 1))
        let length = boundedWindowLength(requestedLength)
        let lower = max(0, min(clampedAnchor - anchorRatio * length, duration - length))
        return TimelineViewport(duration: duration, visibleRange: lower...(lower + length))
    }

    func panned(by delta: TimeInterval) -> TimelineViewport {
        guard duration > 0 else { return TimelineViewport(duration: 0) }

        let length = min(max(visibleDuration, minimumWindowLength), duration)
        let lower = max(0, min(clampedRange.lowerBound + delta, duration - length))
        return TimelineViewport(duration: duration, visibleRange: lower...(lower + length))
    }

    func shouldFollowPlaybackTime(_ time: TimeInterval) -> Bool {
        guard duration > 0, visibleDuration > 0, visibleDuration < duration else { return false }

        let range = clampedRange
        let followThreshold = range.lowerBound + visibleDuration * Self.playbackFollowRightEdgeRatio
        return time < range.lowerBound || time >= followThreshold - Self.playbackFollowComparisonTolerance
    }

    func positionedWithTimeNearLeadingEdge(_ time: TimeInterval) -> TimelineViewport {
        guard duration > 0 else { return TimelineViewport(duration: 0) }

        let length = min(visibleDuration, duration)
        guard length > 0 else { return TimelineViewport(duration: duration) }
        guard length < duration else { return TimelineViewport(duration: duration) }

        let clampedTime = max(0, min(time, duration))
        let leadingInset = length * Self.playbackFollowLeadingInsetRatio
        let lower = max(0, min(clampedTime - leadingInset, duration - length))
        return TimelineViewport(duration: duration, visibleRange: lower...(lower + length))
    }

    private func boundedWindowLength(_ requestedLength: TimeInterval) -> TimeInterval {
        max(minimumWindowLength, min(requestedLength, duration))
    }

    private static let playbackFollowLeadingInsetRatio: TimeInterval = 0.08
    private static let playbackFollowRightEdgeRatio: TimeInterval = 0.92
    private static let playbackFollowComparisonTolerance: TimeInterval = 0.000001
}

struct PlaybackDisplayState: Equatable {
    var sampledTime: TimeInterval
    var sampleDate: Date
    var playbackRate: Float
    var duration: TimeInterval
    var isPlaying: Bool
    var isLooping: Bool
    var loopRegion: LoopRegion

    static let idle = PlaybackDisplayState(
        sampledTime: 0,
        sampleDate: Date(timeIntervalSinceReferenceDate: 0),
        playbackRate: AppSliderDefaults.playbackRate,
        duration: 0,
        isPlaying: false,
        isLooping: false,
        loopRegion: .empty
    )

    func displayTime(at date: Date = Date()) -> TimeInterval {
        let safeDuration = max(0, duration)
        guard safeDuration > 0 else { return 0 }

        let clampedSample = max(0, min(sampledTime, safeDuration))
        guard isPlaying else { return clampedSample }

        let elapsed = max(0, date.timeIntervalSince(sampleDate)) * Double(ProjectStateNormalizer.normalizedPlaybackRate(playbackRate))
        let rawTime = clampedSample + elapsed

        if isLooping {
            let loop = loopRegion.clamped(to: safeDuration)
            let loopLength = loop.end - loop.start
            if loopLength > 0,
               clampedSample >= loop.start,
               clampedSample <= loop.end,
               rawTime > loop.end {
                let loopOffset = (rawTime - loop.start).truncatingRemainder(dividingBy: loopLength)
                return loop.start + max(0, loopOffset)
            }
        }

        return max(0, min(rawTime, safeDuration))
    }
}

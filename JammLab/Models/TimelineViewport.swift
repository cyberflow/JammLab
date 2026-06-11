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

    private func boundedWindowLength(_ requestedLength: TimeInterval) -> TimeInterval {
        max(minimumWindowLength, min(requestedLength, duration))
    }
}

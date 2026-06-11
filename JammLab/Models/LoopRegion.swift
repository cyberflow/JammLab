import Foundation

struct LoopRegion: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    static let empty = LoopRegion(start: 0, end: 0)
    static let minimumLength: TimeInterval = 0.5

    var duration: TimeInterval {
        max(0, end - start)
    }

    func clamped(to trackDuration: TimeInterval, minimumLength: TimeInterval = LoopRegion.minimumLength) -> LoopRegion {
        guard trackDuration > 0 else { return .empty }

        let minimumLength = Self.validMinimumLength(minimumLength, trackDuration: trackDuration)
        let lower = max(0, min(start, trackDuration))
        let upper = max(0, min(end, trackDuration))

        if upper - lower >= minimumLength {
            return LoopRegion(start: lower, end: upper)
        }

        let fixedEnd = min(trackDuration, lower + minimumLength)
        let fixedStart = max(0, fixedEnd - minimumLength)
        return LoopRegion(start: fixedStart, end: fixedEnd)
    }

    func movingStart(
        to newStart: TimeInterval,
        trackDuration: TimeInterval,
        minimumLength: TimeInterval = LoopRegion.minimumLength
    ) -> LoopRegion {
        let minimumLength = Self.validMinimumLength(minimumLength, trackDuration: trackDuration)
        let maximumStart = max(0, end - minimumLength)
        return LoopRegion(start: min(max(0, newStart), maximumStart), end: end)
            .clamped(to: trackDuration, minimumLength: minimumLength)
    }

    func movingEnd(
        to newEnd: TimeInterval,
        trackDuration: TimeInterval,
        minimumLength: TimeInterval = LoopRegion.minimumLength
    ) -> LoopRegion {
        let minimumLength = Self.validMinimumLength(minimumLength, trackDuration: trackDuration)
        let minimumEnd = min(trackDuration, start + minimumLength)
        return LoopRegion(start: start, end: max(min(newEnd, trackDuration), minimumEnd))
            .clamped(to: trackDuration, minimumLength: minimumLength)
    }

    func offset(
        by delta: TimeInterval,
        trackDuration: TimeInterval,
        minimumLength: TimeInterval = LoopRegion.minimumLength
    ) -> LoopRegion {
        guard trackDuration > 0 else { return .empty }

        let minimumLength = Self.validMinimumLength(minimumLength, trackDuration: trackDuration)
        let length = min(trackDuration, max(minimumLength, duration))
        let lower = max(0, min(start + delta, trackDuration - length))
        return LoopRegion(start: lower, end: lower + length)
            .clamped(to: trackDuration, minimumLength: minimumLength)
    }

    private static func validMinimumLength(_ minimumLength: TimeInterval, trackDuration: TimeInterval) -> TimeInterval {
        max(0, min(minimumLength, max(0, trackDuration)))
    }
}

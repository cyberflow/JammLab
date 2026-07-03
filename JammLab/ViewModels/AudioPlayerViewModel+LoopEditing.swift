import Foundation

extension AudioPlayerViewModel {
    func setLoopStartAtCurrentTime() {
        updateLoopStart(currentTime)
    }

    func setLoopEndAtCurrentTime() {
        updateLoopEnd(currentTime)
    }

    func updateLoopStart(_ start: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let maximumStart = max(0, loopRegion.end - minimumLength)
            let snappedStart = snappedTimelineTime(start)
            loopRegion.start = min(max(0, snappedStart), maximumStart)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopEnd(_ end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let minimumEnd = min(duration, loopRegion.start + minimumLength)
            let snappedEnd = snappedTimelineTime(end)
            loopRegion.end = max(min(snappedEnd, duration), minimumEnd)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopRegion(start: TimeInterval, end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let snappedStart = snappedTimelineTime(start)
            let snappedEnd = snappedTimelineTime(end)
            let lower = max(0, min(snappedStart, snappedEnd))
            let upper = min(duration, max(snappedStart, snappedEnd))
            loopRegion = LoopRegion(start: lower, end: upper).clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }
}

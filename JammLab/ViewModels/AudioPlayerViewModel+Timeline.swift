import Foundation

extension AudioPlayerViewModel {
    var tempoBPMText: String {
        guard let tempoBPM else { return "Pending" }
        return String(format: "%.1f", tempoBPM)
    }

    var firstBeatText: String {
        TimeFormatter.mmss(beatGridSettings.firstBeatTime)
    }

    var beatGridAlignmentText: String {
        beatGridSettings.isManuallyAligned ? "Manual" : "Auto"
    }

    var tempoMap: TempoMap {
        TempoMap(baseSettings: beatGridSettings, markers: notes, duration: duration)
    }

    func applyTempoMapToPlaybackEngine() {
        playbackEngine.setClickSettings(beatGridSettings)
        playbackEngine.setTempoMap(tempoMap)
    }

    func setTempoBPM(_ bpm: Double) {
        performUndoableEdit("Change Tempo") {
            tempoBPM = ProjectStateNormalizer.normalizedTempo(bpm)
            beatGridSettings.bpm = tempoBPM
            beatGridSettings.lastChangedAt = Date()
            shouldAcceptAnalyzedTempo = false
            applyTempoMapToPlaybackEngine()
        }
    }

    func setTimeSignature(beatsPerBar: Int, beatUnit: Int) {
        performUndoableEdit("Change Time Signature") {
            beatGridSettings.timeSignature = TimeSignature(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
            beatGridSettings.lastChangedAt = Date()
            shouldAcceptAnalyzedTempo = false
            applyTempoMapToPlaybackEngine()
        }
    }

    func setCurrentTimeAsBeatOne() {
        performUndoableEdit("Set Beat 1") {
            setFirstBeatTime(currentTime, source: .manual)
        }
    }

    func resetBeatGridAlignment() {
        performUndoableEdit("Reset Beat Grid") {
            setFirstBeatTime(beatGridSettings.automaticFirstBeatTime, source: .automatic)
        }
    }

    func nudgeBeatGrid(by delta: TimeInterval) {
        performUndoableEdit("Nudge Beat Grid") {
            setFirstBeatTime(beatGridSettings.firstBeatTime + delta, source: .manual)
        }
    }


    func toggleSnap() {
        performUndoableEdit("Toggle Snap") {
            isSnapEnabled.toggle()
        }
    }

    func zoomInTimeline() {
        let range = timelineViewport
            .zoomed(to: currentTimelineWindowLength * 0.5, centeredAt: preferredZoomCenter)
            .clampedRange
        setUserTimelineVisibleRange(range)
    }

    func zoomOutTimeline() {
        let range = timelineViewport
            .zoomed(to: currentTimelineWindowLength * 2, centeredAt: preferredZoomCenter)
            .clampedRange
        setUserTimelineVisibleRange(range)
    }

    func setTimelineVisibleRange(_ range: ClosedRange<TimeInterval>) {
        setUserTimelineVisibleRange(TimelineViewport(duration: duration, visibleRange: range).clampedRange)
    }

    func panTimelineLeft() {
        panTimeline(by: -currentTimelineWindowLength * 0.35)
    }

    func panTimelineRight() {
        panTimeline(by: currentTimelineWindowLength * 0.35)
    }

    func handleTimelineScroll(deltaX: Double, deltaY: Double, anchorTime: TimeInterval?) {
        guard duration > 0 else { return }

        if abs(deltaY) > 0.01 {
            let zoomFactor = min(1.18, max(0.84, exp(-deltaY * 0.012)))
            let range = timelineViewport
                .zoomed(to: currentTimelineWindowLength * zoomFactor, anchoredAt: anchorTime ?? preferredZoomCenter)
                .clampedRange
            setUserTimelineVisibleRange(range)
        }

        if abs(deltaX) > 0.01 {
            let visibleLength = min(currentTimelineWindowLength, duration)
            let panDelta = deltaX * visibleLength * 0.0025
            panTimeline(by: panDelta)
        }
    }

    func setFirstBeatTime(_ time: TimeInterval, source: BeatGridAlignmentSource) {
        guard duration > 0 else { return }

        beatGridSettings.firstBeatTime = max(0, min(time, duration))
        beatGridSettings.alignmentSource = source
        beatGridSettings.lastChangedAt = Date()
        applyTempoMapToPlaybackEngine()
    }

    func loopRegionContains(_ time: TimeInterval) -> Bool {
        time >= loopRegion.start && time <= loopRegion.end
    }


    func snappedTimelineTime(_ time: TimeInterval) -> TimeInterval {
        let clampedTime = max(0, min(time, duration))
        guard
            isSnapEnabled,
            let snappedTime = BeatGridCalculator().nearestBeatTime(
                to: clampedTime,
                tempoMap: tempoMap
            )
        else {
            return clampedTime
        }

        return snappedTime
    }

    var activeRangeMinimumLength: TimeInterval {
        guard
            isSnapEnabled,
            let beatDuration = beatGridSettings.beatDuration,
            beatDuration > 0
        else {
            return LoopRegion.minimumLength
        }

        return beatDuration
    }

    var currentTimelineWindowLength: TimeInterval {
        max(timelineViewport.visibleDuration, timelineViewport.minimumWindowLength)
    }

    var preferredZoomCenter: TimeInterval {
        if currentTime >= timelineVisibleRange.lowerBound, currentTime <= timelineVisibleRange.upperBound {
            return currentTime
        }

        return (timelineVisibleRange.lowerBound + timelineVisibleRange.upperBound) / 2
    }

    var minimumTimelineWindowLength: TimeInterval {
        timelineViewport.minimumWindowLength
    }

    func panTimeline(by delta: TimeInterval) {
        setUserTimelineVisibleRange(timelineViewport.panned(by: delta).clampedRange)
    }

    var timelineViewport: TimelineViewport {
        TimelineViewport(duration: duration, visibleRange: timelineVisibleRange)
    }

    func setUserTimelineVisibleRange(_ range: ClosedRange<TimeInterval>) {
        let normalizedRange = ProjectStateNormalizer.normalizedTimelineVisibleRange(range, duration: duration)
        timelineVisibleRange = normalizedRange
        userTimelineVisibleRange = normalizedRange
        refreshProjectModifiedState()
    }
}

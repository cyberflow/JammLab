import CoreGraphics
import Foundation

enum TempoGridMarkerKind: Equatable {
    case majorLabeled
    case minorBar
    case beat
}

struct TempoGridMarker: Identifiable, Equatable {
    var time: TimeInterval
    var xPosition: CGFloat
    var kind: TempoGridMarkerKind
    var barBeatLabel: String?
    var timeLabel: String?

    var id: String {
        "\(kind)-\(time)"
    }
}

struct TempoGridResult: Equatable {
    var markers: [TempoGridMarker]
    var barStep: Int
    var secondsPerBeat: TimeInterval
    var secondsPerBar: TimeInterval
}

struct TempoGridCalculator {
    static let barStepCandidates = [1, 2, 4, 8, 16, 32]
    static let beatLineMinimumSpacing: CGFloat = 24

    func grid(
        settings: BeatGridSettings,
        viewport: TimelineViewport,
        width: CGFloat,
        minimumLabelSpacing: CGFloat
    ) -> TempoGridResult {
        grid(
            tempoMap: TempoMap(baseSettings: settings, markers: [], duration: viewport.duration),
            viewport: viewport,
            width: width,
            minimumLabelSpacing: minimumLabelSpacing
        )
    }

    func grid(
        tempoMap: TempoMap,
        viewport: TimelineViewport,
        width: CGFloat,
        minimumLabelSpacing: CGFloat
    ) -> TempoGridResult {
        let activeSettings = tempoMap.settings(at: viewport.clampedRange.lowerBound)
        guard
            let secondsPerBeat = activeSettings.beatDuration,
            secondsPerBeat > 0,
            viewport.visibleDuration > 0,
            width > 0
        else {
            return TempoGridResult(markers: [], barStep: Self.barStepCandidates.last ?? 32, secondsPerBeat: 0, secondsPerBar: 0)
        }

        let beatsPerBar = max(1, activeSettings.timeSignature.beatsPerBar)
        let secondsPerBar = secondsPerBeat * Double(beatsPerBar)
        let markers = tempoMap.segments.enumerated().flatMap { index, segment in
            segmentMarkers(
                segment: segment,
                isLastSegment: index == tempoMap.segments.count - 1,
                viewport: viewport,
                width: width,
                minimumLabelSpacing: minimumLabelSpacing
            )
        }
        .sorted {
            if $0.time == $1.time {
                return priority($0.kind) < priority($1.kind)
            }

            return $0.time < $1.time
        }

        return TempoGridResult(
            markers: markers,
            barStep: Self.barStep(for: CGFloat(secondsPerBar) * width / CGFloat(max(viewport.visibleDuration, 0.0001)), minimumLabelSpacing: minimumLabelSpacing),
            secondsPerBeat: secondsPerBeat,
            secondsPerBar: secondsPerBar
        )
    }

    private func segmentMarkers(
        segment: TempoMapSegment,
        isLastSegment: Bool,
        viewport: TimelineViewport,
        width: CGFloat,
        minimumLabelSpacing: CGFloat
    ) -> [TempoGridMarker] {
        guard
            let secondsPerBeat = segment.settings.beatDuration,
            secondsPerBeat > 0,
            segment.endTime > segment.startTime
        else {
            return []
        }

        let beatsPerBar = max(1, segment.settings.timeSignature.beatsPerBar)
        let secondsPerBar = secondsPerBeat * Double(beatsPerBar)
        let pixelsPerSecond = width / CGFloat(viewport.visibleDuration)
        let pixelsPerBeat = pixelsPerSecond * CGFloat(secondsPerBeat)
        let pixelsPerBar = pixelsPerBeat * CGFloat(beatsPerBar)
        let barStep = Self.barStep(for: pixelsPerBar, minimumLabelSpacing: minimumLabelSpacing)
        let visibleRange = viewport.clampedRange
        let visibleStart = max(visibleRange.lowerBound, segment.startTime)
        let segmentEnd = isLastSegment ? segment.endTime : segment.endTime.nextDown
        let visibleEnd = min(visibleRange.upperBound, segmentEnd)
        guard visibleEnd >= visibleStart else { return [] }

        var markers = barMarkers(
            segment: segment,
            viewport: viewport,
            width: width,
            secondsPerBar: secondsPerBar,
            barStep: barStep,
            visibleStartTime: visibleStart,
            visibleEndTime: visibleEnd
        )

        if pixelsPerBeat > Self.beatLineMinimumSpacing {
            markers.append(contentsOf: beatMarkers(
                settings: segment.settings,
                viewport: viewport,
                width: width,
                visibleStartTime: visibleStart,
                visibleEndTime: visibleEnd
            ))
        }

        return markers
    }

    static func barStep(for pixelsPerBar: CGFloat, minimumLabelSpacing: CGFloat) -> Int {
        for candidate in barStepCandidates where CGFloat(candidate) * pixelsPerBar >= minimumLabelSpacing {
            return candidate
        }

        return barStepCandidates.last ?? 32
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let centiseconds = max(0, Int((time * 100).rounded()))
        let minutes = centiseconds / 6_000
        let seconds = (centiseconds / 100) % 60
        let fraction = centiseconds % 100
        return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
    }

    private func barMarkers(
        segment: TempoMapSegment,
        viewport: TimelineViewport,
        width: CGFloat,
        secondsPerBar: TimeInterval,
        barStep: Int,
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval
    ) -> [TempoGridMarker] {
        guard secondsPerBar > 0 else { return [] }

        let firstBeatTime = segment.settings.firstBeatTime
        let firstVisibleBarOrdinal = Int(floor((visibleStartTime - firstBeatTime) / secondsPerBar)) - 1
        let lastVisibleBarOrdinal = Int(ceil((visibleEndTime - firstBeatTime) / secondsPerBar)) + 1

        return (firstVisibleBarOrdinal...lastVisibleBarOrdinal).compactMap { barOrdinal in
            let time = firstBeatTime + Double(barOrdinal) * secondsPerBar
            guard time >= visibleStartTime, time <= visibleEndTime else { return nil }

            let shouldLabel = barOrdinal % barStep == 0
            let musicalBarNumber = TempoMap.displayedBarNumber(for: barOrdinal, firstBarNumber: segment.firstBarNumber)
            return TempoGridMarker(
                time: time,
                xPosition: viewport.xPosition(for: time, width: width),
                kind: shouldLabel ? .majorLabeled : .minorBar,
                barBeatLabel: shouldLabel ? "\(musicalBarNumber).1" : nil,
                timeLabel: shouldLabel ? Self.formatTime(time) : nil
            )
        }
    }

    private func beatMarkers(
        settings: BeatGridSettings,
        viewport: TimelineViewport,
        width: CGFloat,
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval
    ) -> [TempoGridMarker] {
        let beatsPerBar = max(1, settings.timeSignature.beatsPerBar)

        return BeatGridCalculator()
            .markers(settings: settings, visibleStartTime: visibleStartTime, visibleEndTime: visibleEndTime)
            .filter { $0.beatIndex % beatsPerBar != 0 }
            .map { marker in
                TempoGridMarker(
                    time: marker.time,
                    xPosition: viewport.xPosition(for: marker.time, width: width),
                    kind: .beat,
                    barBeatLabel: nil,
                    timeLabel: nil
                )
            }
    }

    private func priority(_ kind: TempoGridMarkerKind) -> Int {
        switch kind {
        case .majorLabeled:
            return 0
        case .minorBar:
            return 1
        case .beat:
            return 2
        }
    }
}

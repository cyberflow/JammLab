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
        guard
            let secondsPerBeat = settings.beatDuration,
            secondsPerBeat > 0,
            viewport.visibleDuration > 0,
            width > 0
        else {
            return TempoGridResult(markers: [], barStep: Self.barStepCandidates.last ?? 32, secondsPerBeat: 0, secondsPerBar: 0)
        }

        let beatsPerBar = max(1, settings.timeSignature.beatsPerBar)
        let secondsPerBar = secondsPerBeat * Double(beatsPerBar)
        let pixelsPerSecond = width / CGFloat(viewport.visibleDuration)
        let pixelsPerBeat = pixelsPerSecond * CGFloat(secondsPerBeat)
        let pixelsPerBar = pixelsPerBeat * CGFloat(beatsPerBar)
        let barStep = Self.barStep(for: pixelsPerBar, minimumLabelSpacing: minimumLabelSpacing)
        let visibleRange = viewport.clampedRange

        var markers = barMarkers(
            settings: settings,
            viewport: viewport,
            width: width,
            secondsPerBar: secondsPerBar,
            barStep: barStep
        )

        if pixelsPerBeat > Self.beatLineMinimumSpacing {
            markers.append(contentsOf: beatMarkers(
                settings: settings,
                viewport: viewport,
                width: width,
                visibleStartTime: visibleRange.lowerBound,
                visibleEndTime: visibleRange.upperBound
            ))
        }

        markers.sort {
            if $0.time == $1.time {
                return priority($0.kind) < priority($1.kind)
            }

            return $0.time < $1.time
        }

        return TempoGridResult(
            markers: markers,
            barStep: barStep,
            secondsPerBeat: secondsPerBeat,
            secondsPerBar: secondsPerBar
        )
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
        settings: BeatGridSettings,
        viewport: TimelineViewport,
        width: CGFloat,
        secondsPerBar: TimeInterval,
        barStep: Int
    ) -> [TempoGridMarker] {
        guard secondsPerBar > 0 else { return [] }

        let range = viewport.clampedRange
        let firstBeatTime = settings.firstBeatTime
        let firstVisibleBarOrdinal = Int(floor((range.lowerBound - firstBeatTime) / secondsPerBar)) - 1
        let lastVisibleBarOrdinal = Int(ceil((range.upperBound - firstBeatTime) / secondsPerBar)) + 1

        return (firstVisibleBarOrdinal...lastVisibleBarOrdinal).compactMap { barOrdinal in
            let time = firstBeatTime + Double(barOrdinal) * secondsPerBar
            guard time >= range.lowerBound, time <= range.upperBound else { return nil }

            let shouldLabel = barOrdinal % barStep == 0
            let musicalBarNumber = barNumber(for: barOrdinal)
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

    private func barNumber(for barOrdinal: Int) -> Int {
        barOrdinal >= 0 ? barOrdinal + 1 : barOrdinal
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

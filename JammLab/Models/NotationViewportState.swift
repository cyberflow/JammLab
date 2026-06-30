import Foundation

struct NotationViewportState: Equatable {
    enum Availability: Equatable {
        case ready
        case pending
    }

    var availability: Availability
    var clef: Clef
    var keySignature: KeySignature
    var timeSignature: TimeSignature
    var firstVisibleMeasureNumber: Int
    var visibleMeasureCount: Int
    var visibleMeasures: [ScoreMeasure]
    var anchorTime: TimeInterval
    var activeMeasureNumber: Int?

    var isReady: Bool {
        availability == .ready
    }

    static func pending(
        visibleMeasureCount: Int,
        keySignature: KeySignature = .cMajor
    ) -> NotationViewportState {
        NotationViewportState(
            availability: .pending,
            clef: .treble,
            keySignature: keySignature,
            timeSignature: .fourFour,
            firstVisibleMeasureNumber: 1,
            visibleMeasureCount: visibleMeasureCount,
            visibleMeasures: [],
            anchorTime: 0,
            activeMeasureNumber: nil
        )
    }
}

struct NotationScoreState: Equatable {
    var availability: NotationViewportState.Availability
    var keySignature: KeySignature
    var measures: [ScoreMeasure]
    var anchorTime: TimeInterval
    var activeMeasureNumber: Int?

    var isReady: Bool {
        availability == .ready
    }

    static func pending(keySignature: KeySignature = .cMajor) -> NotationScoreState {
        NotationScoreState(
            availability: .pending,
            keySignature: keySignature,
            measures: [],
            anchorTime: 0,
            activeMeasureNumber: nil
        )
    }

    func systems(measuresPerSystem: Int) -> [NotationSystemState] {
        guard isReady, !measures.isEmpty else { return [] }

        let safeMeasuresPerSystem = max(1, measuresPerSystem)
        return stride(from: 0, to: measures.count, by: safeMeasuresPerSystem).map { startIndex in
            let endIndex = min(startIndex + safeMeasuresPerSystem, measures.count)
            let systemMeasures = Array(measures[startIndex..<endIndex])

            return NotationSystemState(
                index: startIndex / safeMeasuresPerSystem,
                viewportState: NotationViewportState(
                    availability: availability,
                    clef: systemMeasures.first?.attributes.clef ?? .treble,
                    keySignature: systemMeasures.first?.attributes.keySignature ?? keySignature,
                    timeSignature: systemMeasures.first?.attributes.timeSignature ?? .fourFour,
                    firstVisibleMeasureNumber: systemMeasures.first?.number ?? 1,
                    visibleMeasureCount: systemMeasures.count,
                    visibleMeasures: systemMeasures,
                    anchorTime: anchorTime,
                    activeMeasureNumber: activeMeasureNumber
                )
            )
        }
    }
}

struct NotationSystemState: Equatable, Identifiable {
    var index: Int
    var viewportState: NotationViewportState

    var id: String {
        guard let firstMeasure = viewportState.visibleMeasures.first else {
            return "system-\(index)-empty"
        }

        return "system-\(index)-\(firstMeasure.id)"
    }
}

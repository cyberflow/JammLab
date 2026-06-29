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

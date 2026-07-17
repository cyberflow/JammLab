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
    var tieConnections: [NotationTieConnection] = []

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
    var tieConnections: [NotationTieConnection] = []

    var isReady: Bool {
        availability == .ready
    }

    static func pending(keySignature: KeySignature = .cMajor) -> NotationScoreState {
        NotationScoreState(
            availability: .pending,
            keySignature: keySignature,
            measures: [],
            anchorTime: 0,
            activeMeasureNumber: nil,
            tieConnections: []
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
                    activeMeasureNumber: activeMeasureNumber,
                    tieConnections: NotationTieResolver.connections(
                        tieConnections,
                        visibleIn: systemMeasures
                    )
                )
            )
        }
    }
}

struct NotationScoreContent: Equatable {
    var availability: NotationViewportState.Availability
    var keySignature: KeySignature
    var measures: [ScoreMeasure]

    var isReady: Bool {
        availability == .ready
    }

    static func pending(keySignature: KeySignature = .cMajor) -> NotationScoreContent {
        NotationScoreContent(
            availability: .pending,
            keySignature: keySignature,
            measures: []
        )
    }

    func measureIndex(containing time: TimeInterval) -> Int? {
        guard !measures.isEmpty else { return nil }

        var lower = 0
        var upper = measures.count - 1
        while lower <= upper {
            let middle = (lower + upper) / 2
            let measure = measures[middle]
            if time < measure.startTime {
                upper = middle - 1
            } else if time >= measure.endTime, middle < measures.count - 1 {
                lower = middle + 1
            } else {
                return middle
            }
        }

        if let first = measures.first, time < first.startTime {
            return measures.startIndex
        }

        return measures.indices.last
    }
}

final class NotationProjectionCache {
    private var cachedEntries: [Scope: Entry] = [:]
    private(set) var cacheMissCount = 0

    var cachedScopeCount: Int {
        cachedEntries.count
    }

    func content(
        tempoMap: TempoMap,
        duration: TimeInterval,
        keyName: String?,
        clef: Clef = .treble,
        partID: NotationPartID = .main,
        includesHarmonies: Bool = true,
        notationItems: [NotationMeasureItem],
        harmonySymbols: [HarmonySymbol],
        notes: [TimecodedNote]
    ) -> NotationScoreContent {
        let scopedNotationItems = notationItems.filter { $0.partID == partID }
        let scopedHarmonySymbols = includesHarmonies ? harmonySymbols : []
        let regionNotes = notes.filter(\.isRegion)
        let inputs = Inputs(
            tempoMap: tempoMap,
            duration: duration,
            keyName: keyName,
            clef: clef,
            notationItems: scopedNotationItems,
            harmonySymbols: scopedHarmonySymbols,
            regionNotes: regionNotes
        )
        let scope = Scope(partID: partID, includesHarmonies: includesHarmonies)

        if let entry = cachedEntries[scope], entry.inputs == inputs {
            return entry.content
        }

        cacheMissCount += 1
        let content = NotationViewportFactory().scoreContent(
            tempoMap: tempoMap,
            duration: duration,
            keyName: keyName,
            clef: clef,
            partID: partID,
            includesHarmonies: includesHarmonies,
            notationItems: scopedNotationItems,
            harmonySymbols: scopedHarmonySymbols,
            notes: regionNotes
        )
        cachedEntries[scope] = Entry(inputs: inputs, content: content)
        return content
    }

    func invalidate() {
        cachedEntries.removeAll()
        cacheMissCount = 0
    }

    private struct Scope: Hashable {
        var partID: NotationPartID
        var includesHarmonies: Bool
    }

    private struct Entry {
        var inputs: Inputs
        var content: NotationScoreContent
    }

    private struct Inputs: Equatable {
        var tempoMap: TempoMap
        var duration: TimeInterval
        var keyName: String?
        var clef: Clef
        var notationItems: [NotationMeasureItem]
        var harmonySymbols: [HarmonySymbol]
        var regionNotes: [TimecodedNote]
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

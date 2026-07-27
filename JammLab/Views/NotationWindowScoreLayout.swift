import CoreGraphics
import Foundation

struct NotationWindowPartRenderState: Equatable {
    var part: NotationPartDescriptor
    var scoreState: NotationScoreState
}

struct NotationWindowStaffRenderState: Equatable, Identifiable {
    var part: NotationPartDescriptor
    var system: NotationSystemState
    var showsRegionLabels: Bool

    var id: NotationPartID {
        part.id
    }
}

struct NotationWindowScoreSystem: Equatable, Identifiable {
    var id: String
    var staves: [NotationWindowStaffRenderState]
    var measureLayout: NotationSystemMeasureLayout

    var connectorHeight: CGFloat {
        let rowCount = CGFloat(staves.count)
        let totalHeight = rowCount * AppTheme.NotationWindow.systemHeight
            + CGFloat(max(0, staves.count - 1)) * AppTheme.NotationWindow.staffSpacing
        return max(
            0,
            totalHeight
                - AppTheme.NotationWindow.systemConnectorTopInset
                - AppTheme.NotationWindow.systemConnectorBottomInset
        )
    }

    func contains(anchorTime: TimeInterval) -> Bool {
        guard let measures = staves.first?.system.viewportState.visibleMeasures,
              let firstMeasure = measures.first,
              let lastMeasure = measures.last
        else { return false }

        return anchorTime >= firstMeasure.startTime - NotationMeasureTiming.timelineTolerance
            && anchorTime <= lastMeasure.endTime + NotationMeasureTiming.timelineTolerance
    }
}

struct NotationWindowLayoutSignature: Equatable {
    var partIDs: [NotationPartID]
    var systemIDs: [String]
}

struct NotationWindowScoreLayout: Equatable {
    var systems: [NotationWindowScoreSystem]
    var anchorTime: TimeInterval
    var measuresPerSystem: Int
    var usesPartGutter: Bool
    var signature: NotationWindowLayoutSignature

    var activeSystemID: String? {
        systems.first(where: { $0.contains(anchorTime: anchorTime) })?.id
    }

    static func make(
        partStates: [NotationWindowPartRenderState],
        contentWidth: CGFloat
    ) -> NotationWindowScoreLayout {
        let readyPartStates = partStates.filter { $0.scoreState.isReady && !$0.scoreState.measures.isEmpty }
        let usesPartGutter = readyPartStates.count > 1
        let reservedWidth = usesPartGutter
            ? AppTheme.NotationWindow.partLabelWidth + AppTheme.NotationWindow.partGutterSpacing
            : 0
        let staffWidth = max(1, contentWidth - reservedWidth)
        let systemLayouts = fittedSystemLayouts(
            width: staffWidth,
            partStates: readyPartStates
        )
        return make(
            readyPartStates: readyPartStates,
            systemLayouts: systemLayouts,
            usesPartGutter: usesPartGutter
        )
    }

    fileprivate static func make(
        readyPartStates: [NotationWindowPartRenderState],
        systemLayouts: [FittedSystemLayout],
        usesPartGutter: Bool
    ) -> NotationWindowScoreLayout {
        let partIDs = readyPartStates.map(\.part.id)
        let systems = systemLayouts.enumerated().compactMap {
            systemIndex,
            systemLayout -> NotationWindowScoreSystem? in
            let staves = readyPartStates.enumerated().compactMap {
                partIndex,
                partState -> NotationWindowStaffRenderState? in
                guard let system = partState.scoreState.system(
                    index: systemIndex,
                    measureRange: systemLayout.measureRange
                ) else {
                    assertionFailure("Notation part is missing score system \(systemIndex)")
                    return nil
                }
                return NotationWindowStaffRenderState(
                    part: partState.part,
                    system: system,
                    showsRegionLabels: partIndex == 0
                )
            }

            guard let referenceSystem = staves.first?.system, !staves.isEmpty else { return nil }
            return NotationWindowScoreSystem(
                id: systemID(for: referenceSystem),
                staves: staves,
                measureLayout: systemLayout.layout
            )
        }

        return NotationWindowScoreLayout(
            systems: systems,
            anchorTime: readyPartStates.first?.scoreState.anchorTime ?? 0,
            measuresPerSystem: systemLayouts.map(\.measureRange.count).max() ?? 1,
            usesPartGutter: usesPartGutter,
            signature: NotationWindowLayoutSignature(
                partIDs: partIDs,
                systemIDs: systems.map(\.id)
            )
        )
    }

    fileprivate static func fittedSystemLayouts(
        width: CGFloat,
        partStates: [NotationWindowPartRenderState]
    ) -> [FittedSystemLayout] {
        guard let referenceMeasures = partStates.first?.scoreState.measures,
              !referenceMeasures.isEmpty,
              partStates.allSatisfy({
                  $0.scoreState.measures.map(NotationMeasureIdentity.init)
                    == referenceMeasures.map(NotationMeasureIdentity.init)
              })
        else { return [] }

        let candidatesByStart = referenceMeasures.indices.map { startIndex in
            let maximumCount = min(
                AppTheme.NotationWindow.maximumMeasuresPerSystem,
                referenceMeasures.endIndex - startIndex
            )
            return (1...maximumCount).compactMap { count -> FittedSystemLayout? in
                let range = startIndex..<(startIndex + count)
                let rows = partStates.map { Array($0.scoreState.measures[range]) }
                guard let layout = NotationSystemMeasureLayout.make(measureRows: rows) else {
                    return nil
                }
                return FittedSystemLayout(
                    measureRange: range,
                    layout: layout
                )
            }
        }
        let totalMeasureCount = referenceMeasures.count
        if totalMeasureCount > 1,
           let balanced = bestSystemLayout(
               candidatesByStart: candidatesByStart,
               totalMeasureCount: totalMeasureCount,
               width: width,
               allowsSingleMeasureSystems: false
           ) {
            return balanced
        }
        return bestSystemLayout(
            candidatesByStart: candidatesByStart,
            totalMeasureCount: totalMeasureCount,
            width: width,
            allowsSingleMeasureSystems: true
        ) ?? []
    }

    private static func bestSystemLayout(
        candidatesByStart: [[FittedSystemLayout]],
        totalMeasureCount: Int,
        width: CGFloat,
        allowsSingleMeasureSystems: Bool
    ) -> [FittedSystemLayout]? {
        guard totalMeasureCount > 0 else { return [] }

        var costByStart = Array<LayoutCost?>(repeating: nil, count: totalMeasureCount + 1)
        var decisionByStart = Array<FittedSystemLayout?>(
            repeating: nil,
            count: totalMeasureCount
        )
        costByStart[totalMeasureCount] = LayoutCost(
            systemCount: 0,
            singleMeasureSystemCount: 0,
            stretchPenalty: 0
        )
        let safeWidth = max(1, width)

        for startIndex in stride(from: totalMeasureCount - 1, through: 0, by: -1) {
            guard candidatesByStart.indices.contains(startIndex) else { continue }
            var bestCost: LayoutCost?
            var bestCandidate: FittedSystemLayout?

            for candidate in candidatesByStart[startIndex] {
                let measureCount = candidate.measureRange.count
                guard measureCount > 0,
                      candidate.measureRange.upperBound <= totalMeasureCount,
                      let tailCost = costByStart[candidate.measureRange.upperBound]
                else {
                    continue
                }
                if measureCount == 1 {
                    guard allowsSingleMeasureSystems else { continue }
                } else {
                    guard candidate.layout.minimumRequiredWidth
                        <= width + NotationVisibleMeasureFitter.widthTolerance
                    else {
                        continue
                    }
                }

                let normalizedSlack = max(
                    0,
                    (safeWidth - candidate.layout.minimumRequiredWidth) / safeWidth
                )
                let candidateCost = LayoutCost(
                    systemCount: tailCost.systemCount + 1,
                    singleMeasureSystemCount: tailCost.singleMeasureSystemCount
                        + (measureCount == 1 ? 1 : 0),
                    stretchPenalty: tailCost.stretchPenalty
                        + Double(normalizedSlack * normalizedSlack)
                )
                if bestCost == nil
                    || candidateCost.isPreferred(
                        over: bestCost!,
                        firstMeasureCount: measureCount,
                        otherFirstMeasureCount: bestCandidate?.measureRange.count ?? 0,
                        considersSingleMeasureSystems: allowsSingleMeasureSystems
                    ) {
                    bestCost = candidateCost
                    bestCandidate = candidate
                }
            }
            costByStart[startIndex] = bestCost
            decisionByStart[startIndex] = bestCandidate
        }

        guard costByStart[0] != nil else { return nil }
        var layouts: [FittedSystemLayout] = []
        var startIndex = 0
        while startIndex < totalMeasureCount,
              decisionByStart.indices.contains(startIndex),
              let decision = decisionByStart[startIndex] {
            layouts.append(decision)
            startIndex = decision.measureRange.upperBound
        }
        return startIndex == totalMeasureCount ? layouts : nil
    }

    private static func systemID(for system: NotationSystemState) -> String {
        guard let first = system.viewportState.visibleMeasures.first,
              let last = system.viewportState.visibleMeasures.last
        else {
            return "score-system-\(system.index)-empty"
        }

        return "score-system-\(first.number)-\(first.startTime)-\(last.number)-\(last.endTime)"
    }

    fileprivate struct FittedSystemLayout {
        var measureRange: Range<Int>
        var layout: NotationSystemMeasureLayout
    }

    private struct LayoutCost {
        var systemCount: Int
        var singleMeasureSystemCount: Int
        var stretchPenalty: Double

        func isPreferred(
            over other: LayoutCost,
            firstMeasureCount: Int,
            otherFirstMeasureCount: Int,
            considersSingleMeasureSystems: Bool
        ) -> Bool {
            if considersSingleMeasureSystems,
               singleMeasureSystemCount != other.singleMeasureSystemCount {
                return singleMeasureSystemCount < other.singleMeasureSystemCount
            }
            if systemCount != other.systemCount {
                return systemCount < other.systemCount
            }
            if abs(stretchPenalty - other.stretchPenalty) > 0.000_001 {
                return stretchPenalty < other.stretchPenalty
            }
            return firstMeasureCount > otherFirstMeasureCount
        }
    }
}

final class NotationWindowScoreLayoutCache {
    private var entry: Entry?
    private(set) var cacheMissCount = 0

    func layout(
        partStates: [NotationWindowPartRenderState],
        contentWidth: CGFloat
    ) -> NotationWindowScoreLayout {
        let readyPartStates = partStates.filter {
            $0.scoreState.isReady && !$0.scoreState.measures.isEmpty
        }
        let usesPartGutter = readyPartStates.count > 1
        let reservedWidth = usesPartGutter
            ? AppTheme.NotationWindow.partLabelWidth + AppTheme.NotationWindow.partGutterSpacing
            : 0
        let staffWidth = max(1, contentWidth - reservedWidth)
        let inputs = Inputs(
            partIDs: readyPartStates.map(\.part.id),
            measureRows: readyPartStates.map(\.scoreState.measures),
            staffWidth: staffWidth
        )
        let systemLayouts: [NotationWindowScoreLayout.FittedSystemLayout]

        if let entry, entry.inputs == inputs {
            systemLayouts = entry.systemLayouts
        } else {
            cacheMissCount += 1
            systemLayouts = NotationWindowScoreLayout.fittedSystemLayouts(
                width: staffWidth,
                partStates: readyPartStates
            )
            entry = Entry(inputs: inputs, systemLayouts: systemLayouts)
        }

        return NotationWindowScoreLayout.make(
            readyPartStates: readyPartStates,
            systemLayouts: systemLayouts,
            usesPartGutter: usesPartGutter
        )
    }

    func invalidate() {
        entry = nil
        cacheMissCount = 0
    }

    private struct Inputs: Equatable {
        var partIDs: [NotationPartID]
        var measureRows: [[ScoreMeasure]]
        var staffWidth: CGFloat
    }

    private struct Entry {
        var inputs: Inputs
        var systemLayouts: [NotationWindowScoreLayout.FittedSystemLayout]
    }
}

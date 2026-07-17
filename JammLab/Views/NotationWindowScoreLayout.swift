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
        let partIDs = readyPartStates.map(\.part.id)
        let usesPartGutter = readyPartStates.count > 1
        let reservedWidth = usesPartGutter
            ? AppTheme.NotationWindow.partLabelWidth + AppTheme.NotationWindow.partGutterSpacing
            : 0
        let staffWidth = max(1, contentWidth - reservedWidth)
        let measuresPerSystem = fittedMeasuresPerSystem(
            width: staffWidth,
            partStates: readyPartStates
        )
        let systemsByPart = readyPartStates.map { partState in
            (partState, partState.scoreState.systems(measuresPerSystem: measuresPerSystem))
        }
        let referenceSystems = systemsByPart.first?.1 ?? []
        let systems = referenceSystems.compactMap { referenceSystem -> NotationWindowScoreSystem? in
            let staves = systemsByPart.enumerated().compactMap { partIndex, entry -> NotationWindowStaffRenderState? in
                guard entry.1.indices.contains(referenceSystem.index) else {
                    assertionFailure("Notation part is missing score system \(referenceSystem.index)")
                    return nil
                }

                let candidate = entry.1[referenceSystem.index]
                guard hasMatchingMeasureRange(referenceSystem, candidate) else {
                    assertionFailure("Notation parts have mismatched score system ranges")
                    return nil
                }

                return NotationWindowStaffRenderState(
                    part: entry.0.part,
                    system: candidate,
                    showsRegionLabels: partIndex == 0
                )
            }

            guard !staves.isEmpty else { return nil }
            return NotationWindowScoreSystem(
                id: systemID(for: referenceSystem),
                staves: staves
            )
        }

        return NotationWindowScoreLayout(
            systems: systems,
            anchorTime: readyPartStates.first?.scoreState.anchorTime ?? 0,
            measuresPerSystem: measuresPerSystem,
            usesPartGutter: usesPartGutter,
            signature: NotationWindowLayoutSignature(
                partIDs: partIDs,
                systemIDs: systems.map(\.id)
            )
        )
    }

    private static func fittedMeasuresPerSystem(
        width: CGFloat,
        partStates: [NotationWindowPartRenderState]
    ) -> Int {
        guard !partStates.isEmpty else { return 1 }

        for count in stride(
            from: AppTheme.NotationWindow.maximumMeasuresPerSystem,
            through: 1,
            by: -1
        ) {
            let requiredWidth = partStates
                .flatMap { $0.scoreState.systems(measuresPerSystem: count) }
                .map { NotationVisibleMeasureFitter.minimumRequiredWidth(for: $0.viewportState) }
                .max() ?? 0
            if requiredWidth <= width + NotationVisibleMeasureFitter.widthTolerance {
                return count
            }
        }

        return 1
    }

    private static func hasMatchingMeasureRange(
        _ lhs: NotationSystemState,
        _ rhs: NotationSystemState
    ) -> Bool {
        let lhsMeasures = lhs.viewportState.visibleMeasures
        let rhsMeasures = rhs.viewportState.visibleMeasures
        guard lhsMeasures.count == rhsMeasures.count else { return false }

        return zip(lhsMeasures, rhsMeasures).allSatisfy { lhsMeasure, rhsMeasure in
            lhsMeasure.number == rhsMeasure.number
                && abs(lhsMeasure.startTime - rhsMeasure.startTime) < NotationMeasureTiming.timelineTolerance
                && abs(lhsMeasure.endTime - rhsMeasure.endTime) < NotationMeasureTiming.timelineTolerance
        }
    }

    private static func systemID(for system: NotationSystemState) -> String {
        guard let first = system.viewportState.visibleMeasures.first,
              let last = system.viewportState.visibleMeasures.last
        else {
            return "score-system-\(system.index)-empty"
        }

        return "score-system-\(first.number)-\(first.startTime)-\(last.number)-\(last.endTime)"
    }
}

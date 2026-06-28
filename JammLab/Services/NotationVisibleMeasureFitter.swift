import CoreGraphics

struct NotationVisibleMeasureFitter {
    static let widthTolerance: CGFloat = 0.5

    static func fittedMeasureCount(
        availableWidth: CGFloat,
        maximumMeasureCount: Int,
        stateForMeasureCount: (Int) -> NotationViewportState
    ) -> Int {
        let safeMaximumMeasureCount = max(1, maximumMeasureCount)
        let safeAvailableWidth = max(0, availableWidth)

        for measureCount in stride(from: safeMaximumMeasureCount, through: 1, by: -1) {
            let state = stateForMeasureCount(measureCount)
            let requiredWidth = minimumRequiredWidth(for: state)
            if requiredWidth <= safeAvailableWidth + widthTolerance {
                return measureCount
            }
        }

        return 1
    }

    static func minimumRequiredWidth(for state: NotationViewportState) -> CGFloat {
        let measureCount = max(
            1,
            state.visibleMeasures.isEmpty ? state.visibleMeasureCount : state.visibleMeasures.count
        )
        let reserveWidths = attributeReserveWidths(for: state, measureCount: measureCount)
        return NotationMeasureLayout.minimumCanvasWidth(
            measureCount: measureCount,
            attributeReserveWidths: reserveWidths
        )
    }

    static func attributeReserveWidths(
        for state: NotationViewportState,
        measureCount: Int
    ) -> [CGFloat] {
        (0..<max(1, measureCount)).map { index in
            guard state.visibleMeasures.indices.contains(index) else { return 0 }

            let previousAttributes = index > 0 ? state.visibleMeasures[index - 1].attributes : nil
            let display = NotationAttributeDisplay.display(
                for: state.visibleMeasures[index].attributes,
                previousAttributes: previousAttributes
            )
            return NotationMeasureLayout.attributeReserveWidth(
                for: state.visibleMeasures[index].attributes,
                display: display
            )
        }
    }
}

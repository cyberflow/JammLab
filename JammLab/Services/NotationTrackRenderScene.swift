import CoreGraphics
import Foundation

struct NotationTrackRenderScene: Equatable {
    struct Input: Equatable {
        var visibleMeasures: [ScoreMeasure]
        var measureLayout: NotationSystemMeasureLayout?
        var renderedMeasureCount: Int
        var width: CGFloat
        var attributeDisplays: [NotationAttributeDisplay]
        var attributeReserveWidths: [CGFloat]
    }

    var input: Input
    var geometries: [NotationMeasureCanvasGeometry]
    var barlines: [NotationBarlineGeometry]
    var barlineHitTargets: [NotationBarlineHitTarget]
    var notationItems: [NotationItemLayoutItem]
    var harmonies: [HarmonyLayoutItem]
    var regionLabels: [RegionLabelLayoutItem]

    static func make(input: Input) -> NotationTrackRenderScene {
        let geometries: [NotationMeasureCanvasGeometry]
        if let measureLayout = input.measureLayout,
           measureLayout.matches(input.visibleMeasures) {
            geometries = measureLayout.geometries(totalWidth: input.width)
        } else {
            geometries = NotationMeasureLayout.canvasGeometries(
                measureCount: max(1, input.renderedMeasureCount),
                totalWidth: input.width,
                attributeReserveWidths: input.attributeReserveWidths
            )
        }

        return NotationTrackRenderScene(
            input: input,
            geometries: geometries,
            barlines: NotationMeasureLayout.barlineGeometries(for: geometries),
            barlineHitTargets: NotationMeasureLayout.barlineHitTargets(
                for: geometries,
                measures: input.visibleMeasures
            ),
            notationItems: NotationTrackLayoutItems.notationItems(
                visibleMeasures: input.visibleMeasures,
                geometries: geometries
            ),
            harmonies: NotationTrackLayoutItems.harmonies(
                visibleMeasures: input.visibleMeasures,
                geometries: geometries
            ),
            regionLabels: NotationTrackLayoutItems.regionLabels(
                visibleMeasures: input.visibleMeasures,
                geometries: geometries
            )
        )
    }
}

final class NotationTrackRenderSceneCache {
    private var cachedScene: NotationTrackRenderScene?
    private(set) var buildCount = 0

    func scene(input: NotationTrackRenderScene.Input) -> NotationTrackRenderScene {
        if let cachedScene, cachedScene.input == input {
            return cachedScene
        }

        let scene = NotationTrackRenderScene.make(input: input)
        cachedScene = scene
        buildCount += 1
        return scene
    }

    func scene(matching geometries: [NotationMeasureCanvasGeometry]) -> NotationTrackRenderScene? {
        guard cachedScene?.geometries == geometries else { return nil }
        return cachedScene
    }
}

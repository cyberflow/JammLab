import XCTest
@testable import JammLab

final class TimelineViewportLogicTests: XCTestCase {
    func testTimelineViewportMapsAndBoundsVisibleRange() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...60)

        XCTAssertEqual(viewport.clampedRange.lowerBound, 20)
        XCTAssertEqual(viewport.clampedRange.upperBound, 60)
        XCTAssertEqual(viewport.xPosition(for: 40, width: 200), 100, accuracy: 0.0001)
        XCTAssertEqual(viewport.time(forX: 50, width: 200), 30, accuracy: 0.0001)
        XCTAssertEqual(viewport.intersection(start: 10, end: 30)?.lowerBound, 20)
        XCTAssertEqual(viewport.intersection(start: 10, end: 30)?.upperBound, 30)
    }

    func testTimelineViewportZoomAndPanStayInBounds() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...60)

        let zoomed = viewport.zoomed(to: 20, anchoredAt: 30)
        XCTAssertEqual(zoomed.visibleDuration, 20, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(zoomed.clampedRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(zoomed.clampedRange.upperBound, 100)

        let pannedToStart = viewport.panned(by: -1000)
        XCTAssertEqual(pannedToStart.clampedRange.lowerBound, 0, accuracy: 0.0001)

        let pannedToEnd = viewport.panned(by: 1000)
        XCTAssertEqual(pannedToEnd.clampedRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportPositionsTimeNearLeadingEdgePreservingZoom() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...40)

        let followed = viewport.positionedWithTimeNearLeadingEdge(30)

        XCTAssertEqual(followed.visibleDuration, 20, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.lowerBound, 28.4, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.upperBound, 48.4, accuracy: 0.0001)
        XCTAssertEqual(followed.xPosition(for: 30, width: 100), 8, accuracy: 0.0001)
    }

    func testTimelineViewportFollowPositionClampsAtTrackEdges() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 20...40)

        let start = viewport.positionedWithTimeNearLeadingEdge(1)
        let end = viewport.positionedWithTimeNearLeadingEdge(98)

        XCTAssertEqual(start.clampedRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(start.clampedRange.upperBound, 20, accuracy: 0.0001)
        XCTAssertEqual(end.clampedRange.lowerBound, 80, accuracy: 0.0001)
        XCTAssertEqual(end.clampedRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportFollowIsNoOpForFullRange() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 0...100)

        let followed = viewport.positionedWithTimeNearLeadingEdge(90)

        XCTAssertEqual(followed.clampedRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(followed.clampedRange.upperBound, 100, accuracy: 0.0001)
        XCTAssertFalse(viewport.shouldFollowPlaybackTime(90))
    }

    func testTimelineViewportShouldFollowNearRightEdgeOnlyWhenZoomed() {
        let viewport = TimelineViewport(duration: 100, visibleRange: 0...20)

        XCTAssertFalse(viewport.shouldFollowPlaybackTime(18.39))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(18.4))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(21))
        XCTAssertTrue(viewport.shouldFollowPlaybackTime(-1))
    }

    func testTimelineViewportScrollerMetricsMapsVisibleRangeToThumb() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 25...75,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        XCTAssertEqual(metrics.thumbWidth, 100, accuracy: 0.0001)
        XCTAssertEqual(metrics.thumbX, 50, accuracy: 0.0001)
    }

    func testTimelineViewportScrollerDragPreservesVisibleDuration() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 20...60,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        let range = metrics.range(draggedBy: 50)

        XCTAssertEqual(range.upperBound - range.lowerBound, 40, accuracy: 0.0001)
        XCTAssertGreaterThan(range.lowerBound, 20)
    }

    func testTimelineViewportScrollerDragClampsAtTrackEdges() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 100,
            visibleRange: 20...60,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        let startRange = metrics.range(draggedBy: -1_000)
        let endRange = metrics.range(draggedBy: 1_000)

        XCTAssertEqual(startRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(startRange.upperBound, 40, accuracy: 0.0001)
        XCTAssertEqual(endRange.lowerBound, 60, accuracy: 0.0001)
        XCTAssertEqual(endRange.upperBound, 100, accuracy: 0.0001)
    }

    func testTimelineViewportScrollerHandlesZeroDuration() {
        let metrics = TimelineViewportScrollerMetrics(
            duration: 0,
            visibleRange: 0...0,
            trackWidth: 200,
            minimumThumbWidth: 24
        )

        XCTAssertEqual(metrics.thumbWidth, 200, accuracy: 0.0001)
        XCTAssertEqual(metrics.thumbX, 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.range(draggedBy: 50).lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.range(draggedBy: 50).upperBound, 0, accuracy: 0.0001)
    }
}

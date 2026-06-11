import SwiftUI

struct TimelineViewportScrollerMetrics: Equatable {
    var duration: TimeInterval
    var visibleRange: ClosedRange<TimeInterval>
    var trackWidth: CGFloat
    var minimumThumbWidth: CGFloat

    var clampedVisibleRange: ClosedRange<TimeInterval> {
        TimelineViewport(duration: duration, visibleRange: visibleRange).clampedRange
    }

    var visibleDuration: TimeInterval {
        max(0, clampedVisibleRange.upperBound - clampedVisibleRange.lowerBound)
    }

    var thumbWidth: CGFloat {
        guard duration > 0, trackWidth > 0 else { return trackWidth }

        let proportionalWidth = CGFloat(visibleDuration / duration) * trackWidth
        return min(trackWidth, max(minimumThumbWidth, proportionalWidth))
    }

    var thumbX: CGFloat {
        guard duration > 0, trackWidth > 0 else { return 0 }

        let travelWidth = max(0, trackWidth - thumbWidth)
        let maximumLowerBound = max(0, duration - visibleDuration)
        guard travelWidth > 0, maximumLowerBound > 0 else { return 0 }

        return CGFloat(clampedVisibleRange.lowerBound / maximumLowerBound) * travelWidth
    }

    func range(draggedBy translationX: CGFloat) -> ClosedRange<TimeInterval> {
        guard duration > 0, trackWidth > 0 else { return 0...0 }

        let length = min(max(visibleDuration, TimelineViewport.minimumWindowLength(for: duration)), duration)
        let maximumLowerBound = max(0, duration - length)
        let travelWidth = max(0, trackWidth - thumbWidth)
        guard travelWidth > 0, maximumLowerBound > 0 else { return 0...duration }

        let startX = thumbX
        let newX = max(0, min(startX + translationX, travelWidth))
        let lower = TimeInterval(newX / travelWidth) * maximumLowerBound
        return lower...(lower + length)
    }
}

struct TimelineViewportControlBar: View {
    let duration: TimeInterval
    let visibleRange: ClosedRange<TimeInterval>
    let onVisibleRangeChanged: (ClosedRange<TimeInterval>) -> Void
    let onPanLeft: () -> Void
    let onPanRight: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Color.clear
                .frame(width: AppTheme.Timeline.trackControlWidth)

            TimelineViewportScroller(
                duration: duration,
                visibleRange: visibleRange,
                onVisibleRangeChanged: onVisibleRangeChanged
            )
            .frame(height: AppTheme.Timeline.viewportControlBarHeight)

            HStack(spacing: AppTheme.Spacing.xs) {
                viewportButton(systemName: "chevron.left", helpText: ControlHelpText.timelinePanLeft, action: onPanLeft)
                viewportButton(systemName: "chevron.right", helpText: ControlHelpText.timelinePanRight, action: onPanRight)
                viewportButton(systemName: "plus", helpText: ControlHelpText.timelineZoomIn, action: onZoomIn)
                viewportButton(systemName: "minus", helpText: ControlHelpText.timelineZoomOut, action: onZoomOut)
            }
        }
        .frame(height: AppTheme.Timeline.viewportControlBarHeight)
        .disabled(duration <= 0)
        .opacity(duration > 0 ? 1 : 0.45)
    }

    private func viewportButton(
        systemName: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appColors.secondaryText)
                .frame(
                    width: AppTheme.Timeline.viewportControlButtonSize,
                    height: AppTheme.Timeline.viewportControlButtonSize
                )
                .background(appColors.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Timeline.viewportControlButtonRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Timeline.viewportControlButtonRadius, style: .continuous)
                        .stroke(appColors.border, lineWidth: AppTheme.Stroke.thin)
                }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

private struct TimelineViewportScroller: View {
    let duration: TimeInterval
    let visibleRange: ClosedRange<TimeInterval>
    let onVisibleRangeChanged: (ClosedRange<TimeInterval>) -> Void
    @Environment(\.appColors) private var appColors
    @State private var isDragging = false
    @State private var dragStartRange: ClosedRange<TimeInterval>?

    var body: some View {
        GeometryReader { proxy in
            let metrics = TimelineViewportScrollerMetrics(
                duration: duration,
                visibleRange: dragStartRange ?? visibleRange,
                trackWidth: proxy.size.width,
                minimumThumbWidth: AppTheme.Timeline.viewportScrollerThumbMinWidth
            )

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Timeline.viewportScrollerRadius, style: .continuous)
                    .fill(appColors.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Timeline.viewportScrollerRadius, style: .continuous)
                            .stroke(appColors.border, lineWidth: AppTheme.Stroke.thin)
                    }

                RoundedRectangle(cornerRadius: AppTheme.Timeline.viewportScrollerRadius, style: .continuous)
                    .fill(isDragging ? appColors.controlActive : appColors.controlHover)
                    .frame(width: metrics.thumbWidth)
                    .offset(x: metrics.thumbX)
                    .gesture(
                        DragGesture(minimumDistance: AppTheme.Timeline.viewportScrollerDragThreshold)
                            .onChanged { value in
                                if dragStartRange == nil {
                                    dragStartRange = visibleRange
                                }

                                let startMetrics = TimelineViewportScrollerMetrics(
                                    duration: duration,
                                    visibleRange: dragStartRange ?? visibleRange,
                                    trackWidth: proxy.size.width,
                                    minimumThumbWidth: AppTheme.Timeline.viewportScrollerThumbMinWidth
                                )
                                isDragging = true
                                onVisibleRangeChanged(startMetrics.range(draggedBy: value.translation.width))
                            }
                            .onEnded { value in
                                let startMetrics = TimelineViewportScrollerMetrics(
                                    duration: duration,
                                    visibleRange: dragStartRange ?? visibleRange,
                                    trackWidth: proxy.size.width,
                                    minimumThumbWidth: AppTheme.Timeline.viewportScrollerThumbMinWidth
                                )
                                onVisibleRangeChanged(startMetrics.range(draggedBy: value.translation.width))
                                dragStartRange = nil
                                isDragging = false
                            }
                    )
            }
            .frame(height: AppTheme.Timeline.viewportScrollerHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .help(ControlHelpText.timelineViewport)
        .accessibilityLabel("Timeline viewport")
    }
}

#Preview {
    TimelineViewportControlBar(
        duration: 180,
        visibleRange: 30...90,
        onVisibleRangeChanged: { _ in },
        onPanLeft: {},
        onPanRight: {},
        onZoomIn: {},
        onZoomOut: {}
    )
    .padding()
    .frame(width: 760)
    .environment(\.appColors, .default)
}

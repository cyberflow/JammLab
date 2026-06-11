import SwiftUI

struct TempoGridRulerView: View {
    let settings: BeatGridSettings
    let viewport: TimelineViewport

    private let calculator = TempoGridCalculator()
    @Environment(\.appColors) private var appColors

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let result = calculator.grid(
                settings: settings,
                viewport: viewport,
                width: size.width,
                minimumLabelSpacing: AppTheme.Timeline.rulerMinimumLabelSpacing
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    drawMarkers(result.markers, in: &context, size: canvasSize)
                }

                ForEach(result.markers.filter { $0.kind == .majorLabeled }) { marker in
                    markerLabel(marker, width: size.width)
                }
            }
        }
    }

    private func drawMarkers(
        _ markers: [TempoGridMarker],
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        for marker in markers {
            let line = lineStyle(for: marker.kind)
            let lineHeight = marker.kind == .majorLabeled ? size.height : size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: marker.xPosition, y: size.height - lineHeight))
            path.addLine(to: CGPoint(x: marker.xPosition, y: size.height))
            context.stroke(path, with: .color(line.color), lineWidth: line.width)
        }
    }

    private func markerLabel(_ marker: TempoGridMarker, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxxs) {
            if let barBeatLabel = marker.barBeatLabel {
                Text(barBeatLabel)
                    .font(AppTheme.Typography.timelineLabel.weight(.medium))
                    .foregroundStyle(appColors.secondaryText)
            }

            if let timeLabel = marker.timeLabel {
                Text(timeLabel)
                    .font(AppTheme.Typography.timelineLabel)
                    .foregroundStyle(appColors.secondaryText.opacity(AppTheme.Timeline.rulerTimeLabelOpacity))
            }
        }
        .lineLimit(1)
        .frame(width: AppTheme.Timeline.rulerLabelWidth, alignment: .leading)
        .offset(x: labelXPosition(for: marker, width: width), y: AppTheme.Spacing.xs)
        .allowsHitTesting(false)
    }

    private func labelXPosition(for marker: TempoGridMarker, width: CGFloat) -> CGFloat {
        let preferredX = marker.xPosition + AppTheme.Spacing.xs
        let maxX = max(0, width - AppTheme.Timeline.rulerLabelWidth)
        return min(max(preferredX, 0), maxX)
    }

    private func lineStyle(for kind: TempoGridMarkerKind) -> (color: Color, width: CGFloat) {
        switch kind {
        case .majorLabeled:
            return (
                appColors.timeTrackAccentBeatLine.opacity(AppTheme.Timeline.rulerMajorLineOpacity),
                AppTheme.Stroke.medium
            )
        case .minorBar:
            return (
                appColors.secondaryText.opacity(AppTheme.Timeline.rulerMinorBarLineOpacity),
                AppTheme.Stroke.thin
            )
        case .beat:
            return (
                appColors.timeTrackBeatLine.opacity(AppTheme.Timeline.rulerBeatLineOpacity),
                AppTheme.Stroke.thin
            )
        }
    }
}

#Preview {
    TempoGridRulerView(
        settings: BeatGridSettings(bpm: 120),
        viewport: TimelineViewport(duration: 60, visibleRange: 0...20)
    )
    .frame(height: 38)
    .padding()
}

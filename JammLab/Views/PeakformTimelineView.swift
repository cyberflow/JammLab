import SwiftUI

struct PeakformTimelineView: View {
    let peakformData: PeakformData?
    let duration: TimeInterval
    let currentTime: TimeInterval
    let playbackMarkerTime: TimeInterval
    let loopStart: TimeInterval
    let loopEnd: TimeInterval
    let notes: [TimecodedNote]
    let selectedRegionID: TimecodedNote.ID?
    let sections: [TimelineSection]
    let tempoMap: TempoMap
    let visibleStartTime: TimeInterval
    let visibleEndTime: TimeInterval
    let isLoading: Bool
    let showsImportPlaceholder: Bool
    var waveformColor: Color? = nil
    @Environment(\.appColors) private var appColors

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawSections(in: &context, size: size)
                drawPreRollArea(in: &context, size: size)
                PeakformRenderer.draw(
                    peakformData: peakformData,
                    viewport: viewport,
                    in: &context,
                    size: size,
                    colors: appColors,
                    waveformColor: resolvedWaveformColor
                )
                drawRegionEdgeLines(in: &context, size: size)
                drawBeatGrid(in: &context, size: size)
                drawLoopRegion(in: &context, size: size)
                drawPlaybackOverlays(in: &context, size: size)
            }

            if isLoading {
                HStack(spacing: AppTheme.Spacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Building peakform")
                        .font(AppTheme.Typography.tileTitle)
                        .foregroundStyle(appColors.secondaryText)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
            }

            if shouldShowEmptyImportPlaceholder {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .medium))
                    Text("Import media")
                        .font(AppTheme.Typography.tileValue)
                    Text("Drop audio or video on the waveform")
                        .font(.caption)
                }
                .foregroundStyle(appColors.secondaryText)
                .allowsHitTesting(false)
            }
        }
    }

    private var shouldShowEmptyImportPlaceholder: Bool {
        showsImportPlaceholder && peakformData == nil && !isLoading
    }

    private var resolvedWaveformColor: Color {
        waveformColor ?? appColors.waveformColor
    }

    private func drawSections(in context: inout GraphicsContext, size: CGSize) {
        for section in sections {
            guard let rect = rect(for: section.start, end: section.end, size: size) else { continue }
            context.fill(Path(rect), with: .color(section.color.opacity(AppTheme.Timeline.sectionOpacity)))
        }
    }

    private func drawPreRollArea(in context: inout GraphicsContext, size: CGSize) {
        let firstBeatTime = tempoMap.segments.first?.settings.firstBeatTime ?? 0
        guard firstBeatTime > viewport.clampedRange.lowerBound else { return }

        if let rect = rect(
            for: viewport.clampedRange.lowerBound,
            end: min(firstBeatTime, viewport.clampedRange.upperBound),
            size: size
        ) {
            context.fill(Path(rect), with: .color(appColors.secondaryText.opacity(AppTheme.Timeline.preRollOpacity)))
        }
    }

    private func drawLoopRegion(in context: inout GraphicsContext, size: CGSize) {
        if let rect = rect(for: loopStart, end: loopEnd, size: size) {
            context.fill(Path(rect), with: .color(AppTheme.Timeline.loopIndicatorColor.opacity(AppTheme.Timeline.waveformLoopRegionOpacity)))
        }
    }

    private func drawRegionEdgeLines(in context: inout GraphicsContext, size: CGSize) {
        let visibleRegions = notes
            .filter(\.isRegion)
            .sorted { $0.time < $1.time }

        for region in visibleRegions {
            let isSelected = selectedRegionID == region.id
            drawVerticalLine(
                time: region.time,
                color: region.resolvedSwiftUIColor.opacity(isSelected ? AppTheme.Timeline.selectedRegionEdgeOpacity : AppTheme.Timeline.unselectedRegionEdgeOpacity),
                lineWidth: isSelected ? AppTheme.Stroke.medium : AppTheme.Stroke.thin,
                in: &context,
                size: size
            )
            drawVerticalLine(
                time: region.regionEndTime,
                color: region.resolvedSwiftUIColor.opacity(isSelected ? AppTheme.Timeline.selectedRegionEdgeOpacity : AppTheme.Timeline.unselectedRegionEdgeOpacity),
                lineWidth: isSelected ? AppTheme.Stroke.medium : AppTheme.Stroke.thin,
                in: &context,
                size: size
            )
        }
    }

    private func drawBeatGrid(in context: inout GraphicsContext, size: CGSize) {
        let result = TempoGridCalculator().grid(
            tempoMap: tempoMap,
            viewport: viewport,
            width: size.width,
            minimumLabelSpacing: AppTheme.Timeline.rulerMinimumLabelSpacing
        )

        for marker in result.markers {
            let line = beatGridLineStyle(for: marker.kind)
            var path = Path()
            path.move(to: CGPoint(x: marker.xPosition, y: 0))
            path.addLine(to: CGPoint(x: marker.xPosition, y: size.height))

            context.stroke(
                path,
                with: .color(line.color),
                lineWidth: line.width
            )
        }
    }

    private func beatGridLineStyle(for kind: TempoGridMarkerKind) -> (color: Color, width: CGFloat) {
        switch kind {
        case .majorLabeled:
            return (
                appColors.waveformAccentBeatLine.opacity(AppTheme.Timeline.rulerMajorLineOpacity),
                AppTheme.Stroke.medium
            )
        case .minorBar:
            return (
                appColors.secondaryText.opacity(AppTheme.Timeline.rulerMinorBarLineOpacity),
                AppTheme.Stroke.thin
            )
        case .beat:
            return (
                appColors.waveformBeatLine.opacity(AppTheme.Timeline.rulerBeatLineOpacity),
                AppTheme.Stroke.thin
            )
        }
    }

    private func drawPlaybackOverlays(in context: inout GraphicsContext, size: CGSize) {
        drawVerticalLine(time: loopStart, color: AppTheme.Timeline.loopIndicatorColor, lineWidth: AppTheme.Stroke.thick, in: &context, size: size)
        drawVerticalLine(time: loopEnd, color: AppTheme.Timeline.loopIndicatorColor, lineWidth: AppTheme.Stroke.thick, in: &context, size: size)
        if abs(playbackMarkerTime - currentTime) > 0.0001 {
            drawVerticalLine(time: playbackMarkerTime, color: appColors.accent, lineWidth: AppTheme.Stroke.medium, in: &context, size: size)
        }
        drawVerticalLine(time: currentTime, color: AppTheme.Colors.playhead, lineWidth: AppTheme.Stroke.thick, in: &context, size: size)
    }

    private func drawVerticalLine(
        time: TimeInterval,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard viewport.contains(time) else { return }

        let x = viewport.xPosition(for: time, width: size.width)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func rect(for start: TimeInterval, end: TimeInterval, size: CGSize) -> CGRect? {
        guard let range = viewport.intersection(start: start, end: end) else { return nil }

        let startX = viewport.xPosition(for: range.lowerBound, width: size.width)
        let endX = viewport.xPosition(for: range.upperBound, width: size.width)
        return CGRect(x: startX, y: 0, width: max(endX - startX, AppTheme.Timeline.minRectWidth), height: size.height)
    }

    private var viewport: TimelineViewport {
        TimelineViewport(duration: duration, visibleRange: visibleStartTime...visibleEndTime)
    }
}

enum PeakformRenderer {
    static func draw(
        peakformData: PeakformData?,
        viewport: TimelineViewport,
        in context: inout GraphicsContext,
        size: CGSize,
        colors: AppThemeColors,
        waveformColor: Color? = nil
    ) {
        let resolvedWaveformColor = waveformColor ?? colors.waveformColor

        guard
            let peakformData,
            peakformData.sampleRate > 0,
            let level = peakformData.preferredLevel(for: viewport, width: size.width),
            !level.peaks.isEmpty,
            level.samplesPerPeak > 0,
            viewport.visibleDuration > 0,
            size.width > 0,
            size.height > 0
        else {
            drawEmpty(in: &context, size: size, colors: colors, waveformColor: resolvedWaveformColor)
            return
        }

        guard let visiblePeakRange = visiblePeakRange(
            level: level,
            sampleRate: peakformData.sampleRate,
            viewport: viewport
        ) else {
            drawEmpty(in: &context, size: size, colors: colors, waveformColor: resolvedWaveformColor)
            return
        }

        let peakDuration = Double(level.samplesPerPeak) / peakformData.sampleRate
        guard peakDuration > 0 else { return }

        let columnCount = max(1, Int(size.width.rounded(.up)))
        let centerY = size.height / 2
        let amplitudeScale = size.height * AppTheme.Timeline.waveformAmplitudeScale
        let columnWidth = size.width / CGFloat(columnCount)
        let range = viewport.clampedRange

        if visiblePeakRange.count <= columnCount {
            drawDirect(
                level: level,
                visiblePeakRange: visiblePeakRange,
                peakDuration: peakDuration,
                viewport: viewport,
                in: &context,
                centerY: centerY,
                amplitudeScale: amplitudeScale,
                size: size,
                waveformColor: resolvedWaveformColor
            )
            return
        }

        for column in 0..<columnCount {
            let startTime = range.lowerBound + (Double(column) / Double(columnCount)) * viewport.visibleDuration
            let endTime = range.lowerBound + (Double(column + 1) / Double(columnCount)) * viewport.visibleDuration
            let startIndex = max(visiblePeakRange.lowerBound, min(Int(floor(startTime / peakDuration)), visiblePeakRange.upperBound - 1))
            let endIndex = max(startIndex, min(Int(ceil(endTime / peakDuration)), visiblePeakRange.upperBound - 1))
            guard let aggregate = aggregate(peaks: level.peaks, in: startIndex..<(endIndex + 1)) else { continue }

            let clampedMin = max(-1, min(1, aggregate.min))
            let clampedMax = max(-1, min(1, aggregate.max))
            let clampedRMS = max(0, min(1, aggregate.rms))
            let x = CGFloat(column) * columnWidth + columnWidth / 2
            let topY = centerY - CGFloat(clampedMax) * amplitudeScale
            let bottomY = centerY - CGFloat(clampedMin) * amplitudeScale

            var rmsPath = Path()
            rmsPath.move(to: CGPoint(x: x, y: centerY - CGFloat(clampedRMS) * amplitudeScale))
            rmsPath.addLine(to: CGPoint(x: x, y: centerY + CGFloat(clampedRMS) * amplitudeScale))
            context.stroke(rmsPath, with: .color(resolvedWaveformColor.opacity(AppTheme.Timeline.peakRMSOpacity)), lineWidth: max(AppTheme.Stroke.thin, columnWidth))

            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(path, with: .color(resolvedWaveformColor.opacity(AppTheme.Timeline.peakOpacity)), lineWidth: max(AppTheme.Stroke.thin, columnWidth))
        }
    }

    static func visiblePeakRange(
        level: PeakformLevel,
        sampleRate: Double,
        viewport: TimelineViewport
    ) -> Range<Int>? {
        guard
            !level.peaks.isEmpty,
            level.samplesPerPeak > 0,
            sampleRate > 0,
            viewport.visibleDuration > 0
        else {
            return nil
        }

        let peakDuration = Double(level.samplesPerPeak) / sampleRate
        guard peakDuration > 0 else { return nil }

        let range = viewport.clampedRange
        let lower = max(0, min(Int(floor(range.lowerBound / peakDuration)), level.peaks.count - 1))
        let upper = max(lower + 1, min(Int(ceil(range.upperBound / peakDuration)), level.peaks.count))
        return lower..<upper
    }

    static func aggregate(peaks: [PeakPoint], in range: Range<Int>) -> PeakPoint? {
        guard
            !peaks.isEmpty,
            !range.isEmpty,
            range.lowerBound >= 0,
            range.upperBound <= peaks.count
        else {
            return nil
        }

        var minValue = Float32.greatestFiniteMagnitude
        var maxValue = -Float32.greatestFiniteMagnitude
        var rmsValue: Float32 = 0

        for index in range {
            let peak = peaks[index]
            minValue = min(minValue, peak.min)
            maxValue = max(maxValue, peak.max)
            rmsValue = max(rmsValue, peak.rms)
        }

        return PeakPoint(min: minValue, max: maxValue, rms: rmsValue)
    }

    private static func drawDirect(
        level: PeakformLevel,
        visiblePeakRange: Range<Int>,
        peakDuration: TimeInterval,
        viewport: TimelineViewport,
        in context: inout GraphicsContext,
        centerY: CGFloat,
        amplitudeScale: CGFloat,
        size: CGSize,
        waveformColor: Color
    ) {
        for index in visiblePeakRange {
            let peak = level.peaks[index]
            let startTime = Double(index) * peakDuration
            let endTime = startTime + peakDuration
            guard let visibleRange = viewport.intersection(start: startTime, end: endTime) else { continue }

            let startX = viewport.xPosition(for: visibleRange.lowerBound, width: size.width)
            let endX = viewport.xPosition(for: visibleRange.upperBound, width: size.width)
            let x = (startX + endX) / 2
            let lineWidth = max(AppTheme.Stroke.thin, endX - startX)
            let clampedMin = max(-1, min(1, peak.min))
            let clampedMax = max(-1, min(1, peak.max))
            let clampedRMS = max(0, min(1, peak.rms))
            let topY = centerY - CGFloat(clampedMax) * amplitudeScale
            let bottomY = centerY - CGFloat(clampedMin) * amplitudeScale

            var rmsPath = Path()
            rmsPath.move(to: CGPoint(x: x, y: centerY - CGFloat(clampedRMS) * amplitudeScale))
            rmsPath.addLine(to: CGPoint(x: x, y: centerY + CGFloat(clampedRMS) * amplitudeScale))
            context.stroke(rmsPath, with: .color(waveformColor.opacity(AppTheme.Timeline.peakRMSOpacity)), lineWidth: lineWidth)

            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(path, with: .color(waveformColor.opacity(AppTheme.Timeline.peakOpacity)), lineWidth: lineWidth)
        }
    }

    static func drawEmpty(
        in context: inout GraphicsContext,
        size: CGSize,
        colors: AppThemeColors,
        waveformColor: Color? = nil
    ) {
        let centerY = size.height / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: centerY))
        path.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(path, with: .color((waveformColor ?? colors.waveformColor).opacity(AppTheme.Timeline.emptyPeakOpacity)), lineWidth: AppTheme.Stroke.thin)
    }
}

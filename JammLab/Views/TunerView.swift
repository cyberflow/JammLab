import SwiftUI

struct TunerView: View {
    @StateObject private var inputService: TunerInputService
    @Environment(\.appColors) private var appColors

    init(settingsStore: AppSettingsStore) {
        _inputService = StateObject(wrappedValue: TunerInputService(appSettingsStore: settingsStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionGap) {
            header
            noteDisplay
            centsMeter
            detailGrid
        }
        .padding(AppTheme.Spacing.windowPadding)
        .frame(width: AppTheme.Window.tunerWidth, alignment: .topLeading)
        .frame(minHeight: AppTheme.Window.tunerMinHeight, alignment: .topLeading)
        .background(appColors.appBackground)
        .task {
            await inputService.start()
        }
        .onDisappear {
            inputService.stop()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Tuner")
                .font(.title2.weight(.semibold))
                .foregroundStyle(appColors.primaryText)

            Text(inputService.inputDeviceName)
                .font(.caption)
                .foregroundStyle(appColors.secondaryText)
                .lineLimit(1)
        }
    }

    private var noteDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Text(inputService.currentResult?.noteName ?? "--")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(noteColor)
                .lineLimit(1)
                .frame(width: AppTheme.Tuner.noteNameWidth, alignment: .leading)
                .accessibilityLabel("Detected note")
                .accessibilityValue(inputService.currentResult?.displayNote ?? "No stable pitch")

            Text(octaveText)
                .font(.title.weight(.semibold))
                .foregroundStyle(appColors.secondaryText)
                .frame(width: AppTheme.Tuner.octaveWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var centsMeter: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                Capsule()
                    .fill(appColors.controlBackground)
                    .frame(height: AppTheme.Tuner.meterHeight)

                Rectangle()
                    .fill(appColors.border)
                    .frame(width: AppTheme.Stroke.thin, height: AppTheme.Tuner.meterCenterHeight)

                GeometryReader { proxy in
                    let x = indicatorX(width: proxy.size.width)
                    Rectangle()
                        .fill(noteColor)
                        .frame(width: AppTheme.Stroke.thick, height: AppTheme.Tuner.meterIndicatorHeight)
                        .position(x: x, y: proxy.size.height / 2)
                }
                .frame(height: AppTheme.Tuner.meterIndicatorHeight)
            }
            .frame(height: AppTheme.Tuner.meterIndicatorHeight)
            .accessibilityLabel("Tuning cents offset")
            .accessibilityValue(centsText)

            HStack {
                Text("-50")
                Spacer()
                Text(centsText)
                    .font(AppTheme.Typography.captionMonospaced.weight(.semibold))
                    .foregroundStyle(noteColor)
                Spacer()
                Text("+50")
            }
            .font(.caption)
            .foregroundStyle(appColors.secondaryText)
        }
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            detailRow(title: "Frequency", value: frequencyText)

            if let errorMessage = inputService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appColors.secondaryText)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.captionMonospaced)
                .foregroundStyle(appColors.primaryText)
        }
    }

    private var noteColor: Color {
        guard let cents = inputService.currentResult?.centsOffset else {
            return appColors.secondaryText
        }

        let absoluteCents = abs(cents)
        if absoluteCents <= 5 {
            return appColors.accent
        } else if absoluteCents <= 15 {
            return appColors.statusButtonAttentionFill
        } else {
            return appColors.statusButtonCriticalFill
        }
    }

    private var octaveText: String {
        guard let octave = inputService.currentResult?.octave else { return "" }
        return "\(octave)"
    }

    private var centsText: String {
        guard let cents = inputService.currentResult?.centsOffset else { return "-- cents" }
        return "\(cents >= 0 ? "+" : "")\(Int(cents.rounded())) cents"
    }

    private var frequencyText: String {
        guard let frequency = inputService.currentResult?.frequencyHz else { return "-- Hz" }
        return String(format: "%.1f Hz", frequency)
    }

    private func indicatorX(width: CGFloat) -> CGFloat {
        let cents = inputService.currentResult?.centsOffset ?? 0
        let clamped = min(50, max(-50, cents))
        return width * CGFloat((clamped + 50) / 100)
    }
}

#Preview {
    TunerView(settingsStore: AppSettingsStore())
        .environment(\.appColors, AppThemeColors.default)
}

import AVFoundation
import SwiftUI

struct TunerView: View {
    private static let showsInputDebug = false

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
            if Self.showsInputDebug {
                inputDebugSection
            }
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
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
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
            }

            Spacer(minLength: 0)

            inputSignalMeter
        }
    }

    private var inputSignalMeter: some View {
        GeometryReader { proxy in
            let level = max(0, min(1, inputService.inputSignalLevel))
            let fillHeight = level > 0
                ? max(AppTheme.Tuner.inputSignalMeterMinimumActiveHeight, proxy.size.height * level)
                : 0
            let shape = RoundedRectangle(cornerRadius: AppTheme.Tuner.inputSignalMeterCornerRadius)

            ZStack(alignment: .bottom) {
                shape
                    .fill(appColors.controlBackground.opacity(0.85))

                Rectangle()
                    .fill(appColors.accent)
                    .frame(height: fillHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(appColors.secondaryText.opacity(0.35), lineWidth: AppTheme.Stroke.thin)
            }
        }
        .frame(
            width: AppTheme.Tuner.inputSignalMeterWidth,
            height: AppTheme.Tuner.inputSignalMeterHeight
        )
        .help("Input signal level")
        .accessibilityLabel("Input signal")
        .accessibilityValue(inputSignalAccessibilityValue)
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

            if let inputDiagnosticMessage = inputService.inputDiagnosticMessage {
                Text(inputDiagnosticMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = inputService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var inputDebugSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Input Debug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appColors.secondaryText)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                debugRow("Permission", permissionDebugText)
                debugRow("Saved UID", inputService.inputDebugSnapshot.savedInputDeviceUID ?? "System Default")
                debugRow("Resolved", resolvedDeviceDebugText)
                debugRow("Switch", deviceSwitchDebugText)
                debugRow("Format", engineFormatDebugText)
                debugRow("Tap", tapDebugText)
                debugRow("Convert", conversionDebugText)
                debugRow("Signal", signalDebugText)
                debugRow("Pitch", pitchDebugText)
                debugRow("Error", inputService.inputDebugSnapshot.lastErrorMessage ?? "--")
            }
        }
        .font(AppTheme.Typography.captionMonospaced)
        .foregroundStyle(appColors.secondaryText)
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityLabel("Input debug")
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

    private func debugRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var inputSignalAccessibilityValue: String {
        "\(Int((inputService.inputSignalLevel * 100).rounded()))%"
    }

    private var permissionDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        let status = snapshot.permissionStatus.map(permissionStatusText) ?? "--"
        guard let granted = snapshot.permissionRequestGranted else { return status }
        return "\(status), request \(granted ? "granted" : "denied")"
    }

    private var resolvedDeviceDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        guard let name = snapshot.resolvedDeviceName else { return "--" }
        let idText = snapshot.resolvedDeviceID.map { "#\($0)" } ?? "#--"
        if snapshot.didFallbackToDefaultDevice {
            return "\(name) \(idText), fallback"
        }
        return "\(name) \(idText)"
    }

    private var deviceSwitchDebugText: String {
        guard let status = inputService.inputDebugSnapshot.deviceSwitchStatus else { return "--" }
        if status == noErr {
            return "ok"
        }
        return "\(status) \(AudioOSStatusFormatter.name(for: status))"
    }

    private var engineFormatDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        guard let sampleRate = snapshot.engineSampleRate,
              let channelCount = snapshot.engineChannelCount,
              let commonFormat = snapshot.engineCommonFormat,
              let isInterleaved = snapshot.engineIsInterleaved else {
            return "--"
        }

        let interleavedText = isInterleaved ? "interleaved" : "non-interleaved"
        return "\(String(format: "%.0f", sampleRate)) Hz, \(channelCount) ch, \(commonFormatText(commonFormat)), \(interleavedText)"
    }

    private var tapDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        let frameText = snapshot.lastFrameLength.map { "\($0) frames" } ?? "-- frames"
        let sampleRateText = snapshot.bufferSampleRate.map { "\(String(format: "%.0f", $0)) Hz" } ?? "-- Hz"
        return "\(snapshot.tapCallbackCount) callbacks, \(frameText), \(sampleRateText)"
    }

    private var conversionDebugText: String {
        switch inputService.inputDebugSnapshot.conversionStatus {
        case .notStarted:
            return "--"
        case .converted:
            return "converted"
        case .empty:
            return "empty"
        case .unsupported:
            return "unsupported"
        }
    }

    private var signalDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        let rmsText = snapshot.lastRMS.map { String(format: "rms %.5f", $0) } ?? "rms --"
        let levelText = "level \(Int((snapshot.signalLevel * 100).rounded()))%"
        return "\(rmsText), \(levelText)"
    }

    private var pitchDebugText: String {
        let snapshot = inputService.inputDebugSnapshot
        guard let detected = snapshot.lastPitchDetected else { return "--" }
        guard detected else { return "nil" }
        let note = "\(snapshot.lastPitchNoteName ?? "?")\(snapshot.lastPitchOctave.map(String.init) ?? "")"
        let frequency = snapshot.lastPitchFrequencyHz.map { String(format: "%.1f Hz", $0) } ?? "-- Hz"
        return "\(note), \(frequency)"
    }

    private func permissionStatusText(_ status: AudioInputPermissionStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not determined"
        case .denied:
            return "denied"
        }
    }

    private func commonFormatText(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32:
            return "float32"
        case .pcmFormatFloat64:
            return "float64"
        case .pcmFormatInt16:
            return "int16"
        case .pcmFormatInt32:
            return "int32"
        case .otherFormat:
            return "other"
        @unknown default:
            return "unknown"
        }
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

import SwiftUI

struct TransportBarView: View {
    let playbackState: PlaybackState
    let canPlay: Bool
    let isLooping: Bool
    let statusText: String
    let currentTime: TimeInterval
    let playbackRate: Float
    let pitchShiftSemitones: Float
    let onGoToStart: () -> Void
    let onGoToEnd: () -> Void
    let onPlayStop: () -> Void
    let onPause: () -> Void
    let onLoopChanged: (Bool) -> Void
    let onPlaybackRateChanged: (Float) -> Void
    let onPitchShiftChanged: (Float) -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        AppPanel {
            ZStack {
                HStack(spacing: AppTheme.Spacing.xl) {
                    TransportControlsView(
                        playbackState: playbackState,
                        isLooping: isLooping,
                        onGoToStart: onGoToStart,
                        onGoToEnd: onGoToEnd,
                        onPlayStop: onPlayStop,
                        onPause: onPause,
                        onLoopChanged: onLoopChanged
                    )

                    Text(TimeFormatter.mmss(currentTime))
                        .font(AppTheme.Typography.bodyMonospaced)
                        .foregroundStyle(appColors.secondaryText)
                        .frame(width: AppTheme.ControlSize.transportTimeWidth, alignment: .leading)

                    Spacer(minLength: 0)

                    HStack(spacing: AppTheme.Spacing.xxl) {
                        jammSlider(
                            accessibilityLabel: "Pitch",
                            helpText: ControlHelpText.pitch,
                            systemImage: "music.quarternote.3",
                            value: Binding(
                                get: { Double(pitchShiftSemitones) },
                                set: { onPitchShiftChanged(Float($0)) }
                            ),
                            minValue: -12,
                            maxValue: 12,
                            defaultValue: Double(AppSliderDefaults.pitchShiftSemitones),
                            step: 1,
                            sensitivity: 0.08,
                            precision: 0,
                            displayFormatter: pitchDisplayText
                        )

                        jammSlider(
                            accessibilityLabel: "Speed",
                            helpText: ControlHelpText.speed,
                            systemImage: "metronome",
                            value: Binding(
                                get: { Double(playbackRate) },
                                set: { onPlaybackRateChanged(Float($0)) }
                            ),
                            minValue: 0.25,
                            maxValue: 1,
                            defaultValue: Double(AppSliderDefaults.playbackRate),
                            step: 0.01,
                            precision: 0,
                            displayFormatter: speedDisplayText
                        )
                    }
                }

                Text("[\(statusText)]")
                    .font(AppTheme.Typography.bodyMonospaced)
                    .foregroundStyle(appColors.secondaryText)
            }
        }
        .frame(minHeight: AppTheme.ControlSize.transportBarMinHeight)
        .disabled(!canPlay)
    }

    private func jammSlider(
        accessibilityLabel: String,
        helpText: String,
        systemImage: String,
        value: Binding<Double>,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        step: Double,
        sensitivity: Double = AppTheme.JammValueSlider.defaultSensitivity,
        precision: Int,
        displayFormatter: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(appColors.secondaryText)
                .frame(width: AppTheme.ControlSize.jammValueSliderHeight)
                .help(helpText)
                .accessibilityHidden(true)

            JammValueSlider(
                value: value,
                minValue: minValue,
                maxValue: maxValue,
                defaultValue: defaultValue,
                step: step,
                sensitivity: sensitivity,
                precision: precision,
                fillColor: transportSliderFillColor,
                displayFormatter: displayFormatter,
                accessibilityLabel: accessibilityLabel
            )
            .frame(
                width: AppTheme.ControlSize.jammValueSliderWidth,
                height: AppTheme.ControlSize.jammValueSliderHeight
            )
        }
        .help(helpText)
    }

    private var transportSliderFillColor: Color {
        Color(red: 60 / 255, green: 106 / 255, blue: 182 / 255)
    }

    private func speedDisplayText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func pitchDisplayText(_ value: Double) -> String {
        let semitones = Int(value.rounded())
        if semitones > 0 {
            return "+\(semitones)"
        }
        return "\(semitones)"
    }
}

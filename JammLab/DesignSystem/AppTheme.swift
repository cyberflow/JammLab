import AppKit
import SwiftUI

struct AppThemeColors: Equatable {
    static let `default` = AppThemeColors(palette: .defaultValue)

    let palette: AppColorPalette

    func color(for role: AppColorRole) -> Color {
        Self.color(hex: palette.hex(for: role))
    }

    func nsColor(for role: AppColorRole) -> NSColor {
        Self.nsColor(hex: palette.hex(for: role))
    }

    var appBackground: Color { color(for: .appBackground) }
    var panelBackground: Color { color(for: .panelBackground) }
    var elevatedSurface: Color { color(for: .elevatedSurface) }
    var controlBackground: Color { color(for: .controlBackground) }
    var controlHover: Color { color(for: .controlHover) }
    var controlActive: Color { color(for: .controlActive) }
    var loopButtonActive: Color { color(for: .loopButtonActive) }
    var border: Color { color(for: .border) }
    var primaryText: Color { color(for: .primaryText) }
    var secondaryText: Color { color(for: .secondaryText) }
    var tertiaryText: Color { color(for: .tertiaryText) }
    var disabledText: Color { color(for: .disabledText) }
    var accent: Color { color(for: .accent) }
    var accentHover: Color { color(for: .accentHover) }
    var accentPressed: Color { color(for: .accentPressed) }
    var statusButtonFill: Color { color(for: .statusButtonFill) }
    var statusButtonCriticalFill: Color { color(for: .statusButtonCriticalFill) }
    var statusButtonAttentionFill: Color { color(for: .statusButtonAttentionFill) }
    var valueSliderFill: Color { color(for: .valueSliderFill) }
    var waveformBackground: Color { color(for: .waveformBackground) }
    var waveformColor: Color { color(for: .waveformColor) }
    var waveformDisabledBackground: Color { color(for: .waveformDisabledBackground) }
    var waveformDisabledColor: Color { color(for: .waveformDisabledColor) }
    var timeTrackAccentBeatLine: Color { color(for: .timeTrackAccentBeatLine) }
    var timeTrackBeatLine: Color { color(for: .timeTrackBeatLine) }
    var waveformAccentBeatLine: Color { color(for: .waveformAccentBeatLine) }
    var waveformBeatLine: Color { color(for: .waveformBeatLine) }

    private static func color(hex: String) -> Color {
        let nsColor = nsColor(hex: hex)
        return Color(nsColor: nsColor)
    }

    private static func nsColor(hex: String) -> NSColor {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard
            raw.count == 6,
            let value = Int(raw, radix: 16)
        else {
            return .clear
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

private struct AppThemeColorsKey: EnvironmentKey {
    static let defaultValue = AppThemeColors.default
}

extension EnvironmentValues {
    var appColors: AppThemeColors {
        get { self[AppThemeColorsKey.self] }
        set { self[AppThemeColorsKey.self] = newValue }
    }
}

enum AppTheme {
    enum Window {
        static let minWidth: CGFloat = 860
        static var minHeight: CGFloat { Workspace.minimumHeight }
        static let helpWidth: CGFloat = 520
        static let helpMinHeight: CGFloat = 300
        static let helpHeight: CGFloat = 420
    }

    enum Colors {
        static var windowBackground: Color { AppThemeColors.default.appBackground }
        static var panelBackground: Color { AppThemeColors.default.panelBackground }
        static var controlBackground: Color { AppThemeColors.default.controlBackground }
        static var border: Color { AppThemeColors.default.border }
        static var primaryText: Color { AppThemeColors.default.primaryText }
        static var secondaryText: Color { AppThemeColors.default.secondaryText }
        static var disabledText: Color { AppThemeColors.default.disabledText }
        static var accent: Color { AppThemeColors.default.accent }
        static let error = Color.orange
        static let playhead = Color.red
    }

    enum Spacing {
        static let none: CGFloat = 0
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 14
        static let panelPadding: CGFloat = 16
        static let sectionGap: CGFloat = 18
        static let headerVertical: CGFloat = 20
        static let windowPadding: CGFloat = 24
        static let pagePadding: CGFloat = 28
    }

    enum Radius {
        static let marker: CGFloat = 2
        static let small: CGFloat = 4
        static let medium: CGFloat = 6
        static let panel: CGFloat = 8
    }

    enum Typography {
        static let sectionTitle = Font.headline
        static let tileTitle = Font.caption
        static let tileValue = Font.headline
        static let badge = Font.caption.weight(.medium)
        static let bodyMonospaced = Font.system(.body, design: .monospaced)
        static let captionMonospaced = Font.system(.caption, design: .monospaced)
        static let noteTitle = Font.subheadline.weight(.medium)
        static let timelineLabel = Font.caption2
    }

    enum IconSize {
        static let markerLineWidth: CGFloat = 2
        static let markerCapWidth: CGFloat = 10
        static let markerCapHeight: CGFloat = 8
    }

    enum ControlSize {
        static let toolbarHeight: CGFloat = 48
        static let toolbarTempoFieldWidth: CGFloat = 62
        static let toolbarTimeSignatureNumberFieldWidth: CGFloat = 28
        static let toolbarKeyFieldWidth: CGFloat = 88
        static let transportTimeWidth: CGFloat = 56
        static let transportSliderWidth: CGFloat = 130
        static let clickVolumeWidth: CGFloat = 110
        static let clickVolumeTextWidth: CGFloat = 38
        static let notesSidebarWidth: CGFloat = 260
        static let inspectorSidebarWidth: CGFloat = 280
        static let notesEmptyMinHeight: CGFloat = 118
        static let dividerHeight: CGFloat = 24
        static let hotkeyKeyWidth: CGFloat = 70
        static let controlHeight: CGFloat = 28
        static let buttonHeight: CGFloat = 28
        static let transportBarMinHeight: CGFloat = 70
        static let abletonNumberFieldHeight: CGFloat = 24
        static let jammValueSliderWidth: CGFloat = 70
        static let jammValueSliderHeight: CGFloat = 20
        static let letterToggleButtonWidth: CGFloat = 24
        static let letterToggleButtonHeight: CGFloat = 22
    }

    enum AbletonNumberField {
        static let horizontalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 4
        static let dragThreshold: CGFloat = 3
        static let defaultSensitivity: Double = 0.25
    }

    enum JammValueSlider {
        static let cornerRadius: CGFloat = 2
        static let dragThreshold: CGFloat = 3
        static let defaultSensitivity: Double = 1
        static let borderWidth: CGFloat = 1
        static let horizontalPadding: CGFloat = 4
    }

    enum Settings {
        static let windowWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 390
        static let sidebarWidth: CGFloat = 154
        static let rowHeight: CGFloat = 30
        static let detailPadding: CGFloat = 20
        static let detailContentWidth: CGFloat = 392
        static let selectedRowBackground = Color.primary.opacity(0.10)
        static let sidebarBackground = Color.primary.opacity(0.035)
        static let dividerColor = Color.primary.opacity(0.12)
    }

    enum TransportControls {
        static let groupPadding: CGFloat = 4
        static let groupSpacing: CGFloat = 5
        static let roundButtonSize: CGFloat = 30
        static let stopButtonSize: CGFloat = 28
        static let skipButtonWidth: CGFloat = 28
        static let skipButtonHeight: CGFloat = 28
        static let skipButtonRadius: CGFloat = 7
        static let segmentedSpacing: CGFloat = 1
        static let stopButtonRadius: CGFloat = 5
        static let iconSize: CGFloat = 12
        static let groupRadius: CGFloat = 9
        static let groupBorderWidth: CGFloat = 1
        static let buttonBorderWidth: CGFloat = 1
        static let pressedOffset: CGFloat = 1
        static let shadowRadius: CGFloat = 2
        static let shadowY: CGFloat = 1
    }

    enum Workspace {
        static let dividerHeight: CGFloat = 1
        static var bodyMinimumHeight: CGFloat {
            Timeline.minimumContentHeight
                + Spacing.md
                + ControlSize.transportBarMinHeight
        }
        static var minimumHeight: CGFloat {
            ControlSize.toolbarHeight
                + dividerHeight
                + Spacing.pagePadding * 2
                + bodyMinimumHeight
        }
    }

    enum Stroke {
        static let thin: CGFloat = 1
        static let medium: CGFloat = 1.5
        static let thick: CGFloat = 2
    }

    enum Timeline {
        static let trackControlWidth: CGFloat = 160
        static let regionTrackHeight: CGFloat = 24
        static let markerTrackHeight: CGFloat = 24
        static let tempoTrackHeight: CGFloat = 38
        static let waveformTrackHeight: CGFloat = 110
        static let stemTrackHeight: CGFloat = 48
        static let trackSpacing: CGFloat = 6
        static var upperTrackStackHeight: CGFloat {
            regionTrackHeight + markerTrackHeight + tempoTrackHeight + waveformTrackHeight
        }
        static var stemTracksHeight: CGFloat {
            CGFloat(StemType.allCases.count) * stemTrackHeight
                + CGFloat(max(0, StemType.allCases.count - 1)) * AppTheme.Spacing.md
        }
        static var tracksMinimumHeight: CGFloat {
            upperTrackStackHeight + trackSpacing + stemTracksHeight
        }
        static let viewportFooterGap: CGFloat = AppTheme.Spacing.md
        static var trackControlsMinimumHeight: CGFloat {
            tracksMinimumHeight
        }
        static var timelineBlockMinimumHeight: CGFloat {
            tracksMinimumHeight + viewportFooterGap + viewportControlBarHeight
        }
        static var minimumContentHeight: CGFloat {
            timelineBlockMinimumHeight
        }
        static let loopBracketHeight: CGFloat = 3
        static let loopBracketEdgeHeight: CGFloat = 10
        static let loopHandleHitWidth: CGFloat = 12
        static let loopHandleTriangleWidth: CGFloat = 6
        static let loopHandleTriangleHeight: CGFloat = 5
        static let regionEdgeHitWidth: CGFloat = 8
        static let markerHitWidth: CGFloat = 16
        static let regionMinPixelWidth: CGFloat = 10
        static let regionLabelMinWidth: CGFloat = 54
        static let minOverlayWidth: CGFloat = 2
        static let minRectWidth: CGFloat = 1
        static let waveformAmplitudeScale: CGFloat = 0.46
        static let weakBeatHeightMultiplier: CGFloat = 0.5
        static let rulerMinimumLabelSpacing: CGFloat = 86
        static let rulerLabelWidth: CGFloat = 72
        static let viewportControlBarHeight: CGFloat = 24
        static let viewportScrollerHeight: CGFloat = 14
        static let viewportScrollerThumbMinWidth: CGFloat = 24
        static let viewportScrollerRadius: CGFloat = 7
        static let viewportScrollerDragThreshold: CGFloat = 3
        static let viewportControlButtonSize: CGFloat = 20
        static let viewportControlButtonRadius: CGFloat = 10

        static let loopIndicatorColor = Color.gray
        static let regionTrackBackground = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
        static let markerTrackBackground = Color(red: 60 / 255, green: 60 / 255, blue: 60 / 255)
        static let selectedRegionStroke = Color.white.opacity(0.9)
        static let unselectedRegionStroke = Color.black.opacity(0.32)
        static let regionLabelText = Color.black.opacity(0.82)
        static let markerCapStroke = Color.black.opacity(0.35)
        static let waveformMarkerLineOpacity = 0.62
        static let tempoTrackOpacity = 0.72
        static let loopBracketOpacity = 0.75
        static let waveformLoopRegionOpacity = 0.12
        static let selectedRegionFillOpacity = 0.55
        static let unselectedRegionFillOpacity = 0.28
        static let selectedRegionEdgeOpacity = 0.72
        static let unselectedRegionEdgeOpacity = 0.34
        static let selectedNoteBackgroundOpacity = 0.16
        static let selectedNoteStrokeOpacity = 0.7
        static let beatBarOpacity = 0.9
        static let weakBeatOpacity = 0.55
        static let rulerMajorLineOpacity = 0.62
        static let rulerMinorBarLineOpacity = 0.28
        static let rulerBeatLineOpacity = 0.14
        static let rulerTimeLabelOpacity = 0.72
        static let waveformBarOpacity = 0.38
        static let waveformBeatOpacity = 0.2
        static let peakRMSOpacity = 0.18
        static let peakOpacity = 1.0
        static let emptyPeakOpacity = 0.25
        static let preRollOpacity = 0.08
        static let sectionOpacity = 0.14
    }

    enum Animation {
        static let fast = 0.16
        static let standard = 0.22
    }
}

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
    var notationTrackBackground: Color { color(for: .notationTrackBackground) }
    var notationSymbolsAndLines: Color { color(for: .notationSymbolsAndLines) }
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

extension NSColor {
    convenience init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        let digits = String(normalized.dropFirst())
        guard normalized.count == 7, let value = Int(digits, radix: 16) else { return nil }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String? {
        hexString(using: .sRGB)
    }

    func hexString(using colorSpace: NSColorSpace, fallsBackToOriginalColor: Bool = false) -> String? {
        guard let rgbColor = usingColorSpace(colorSpace) ?? (fallsBackToOriginalColor ? self : nil) else {
            return nil
        }

        let red = Int((rgbColor.redComponent * 255).rounded())
        let green = Int((rgbColor.greenComponent * 255).rounded())
        let blue = Int((rgbColor.blueComponent * 255).rounded())

        return String(format: "#%02X%02X%02X", red, green, blue)
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
        static let notationWidth: CGFloat = 900
        static let notationMinWidth: CGFloat = 620
        static let notationHeight: CGFloat = 720
        static let notationMinHeight: CGFloat = 420
        static let tunerWidth: CGFloat = 360
        static let tunerMinHeight: CGFloat = 460
    }

    enum Colors {
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
        static let toolbarKeyTonicFieldWidth: CGFloat = 64
        static let toolbarKeyModeFieldWidth: CGFloat = 72
        static let transportPositionReadoutWidth: CGFloat = 150
        static let clickVolumeWidth: CGFloat = 110
        static let inspectorSidebarWidth: CGFloat = 280
        static let notesEmptyMinHeight: CGFloat = 118
        static let dividerHeight: CGFloat = 24
        static let hotkeyKeyWidth: CGFloat = 70
        static let controlHeight: CGFloat = 28
        static let notationDurationButtonWidth: CGFloat = 27
        static let notationDurationButtonSpacing: CGFloat = AppTheme.Spacing.xxxs
        static let notationModeButtonWidth: CGFloat = 32
        static let notationDurationControlHeight: CGFloat = controlHeight
        static let notationDurationGlyphSize: CGFloat = 20
        static let notationAugmentationDotNoteOffsetX: CGFloat = -3
        static let notationAugmentationDotGlyphOffsetX: CGFloat = 7
        static let notationAugmentationDotGlyphOffsetY: CGFloat = 5
        static let notationTieNoteOffsetX: CGFloat = 6
        static let notationTieArcOffsetY: CGFloat = 5
        static let notationTieArcHeight: CGFloat = 3
        static let notationTieEndpointThickness: CGFloat = 0.6
        static let notationTieMidpointThickness: CGFloat = 1.4
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
        static let dividerColor = Color.primary.opacity(0.12)
    }

    enum Tuner {
        static let noteNameWidth: CGFloat = 150
        static let octaveWidth: CGFloat = 36
        static let inputSignalMeterWidth: CGFloat = 14
        static let inputSignalMeterHeight: CGFloat = 80
        static let inputSignalMeterMinimumActiveHeight: CGFloat = 3
        static let inputSignalMeterCornerRadius: CGFloat = 4
        static let meterHeight: CGFloat = 12
        static let meterCenterHeight: CGFloat = 34
        static let meterIndicatorHeight: CGFloat = 46
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
        static let notationTrackHeight: CGFloat = 124
        static let notationTrackCollapsedHeight: CGFloat = 36
        static let midiRulerHeight: CGFloat = 18
        static let midiPitchLabelWidth: CGFloat = 40
        static let midiPitchRowHeight: CGFloat = 12
        static let midiNoteInset: CGFloat = 1
        static let midiLabelFontSize: CGFloat = 9
        static let midiMinimumNoteHitWidth: CGFloat = 6
        static let midiMinimumNoteHitHeight: CGFloat = 10
        static let midiResizeHandleHitWidth: CGFloat = 8
        static let midiAutoPageEdgeThreshold: CGFloat = 24
        static let midiMinimumDragDistance: CGFloat = 3
        static let midiAutoPageDelay: TimeInterval = 0.35
        static let midiBlackKeyRowOpacity = 0.12
        static let midiDisabledPitchRowOpacity = 0.34
        static let midiRowSeparatorOpacity = 0.35
        static let midiBarLineOpacity = 0.7
        static let midiBeatLineOpacity = 0.24
        static let midiSubdivisionLineOpacity = 0.1
        static let midiNoteOpacity = 0.82
        static let midiHoverNoteOpacity = 0.5
        static let midiEditedSourceOpacity = 0.28
        static let midiEditPreviewOpacity = 0.68
        static let notationMaximumVisibleMeasureCount = 8
        static let notationMeasureMinWidth: CGFloat = 148
        static let notationStaffLineSpacing: CGFloat = 8
        static let notationStaffHorizontalInset: CGFloat = 10
        static let notationAttributeStaffTopInset: CGFloat = AppTheme.Spacing.xxl
        static let notationClefFontSize: CGFloat = 33
        static let notationClefWidth: CGFloat = 38
        static let notationTimeSignatureWidth: CGFloat = 26
        static let notationAccidentalWidth: CGFloat = 11
        static let notationMinimumMeasureContentWidth: CGFloat = 28
        static let notationMeasureNumberLabelWidth: CGFloat = 34
        static let notationSlashWidth: CGFloat = 7
        static let notationSlashMinimumBeatSpacing: CGFloat = 16
        static let notationItemAnchorInset: CGFloat = AppTheme.Spacing.lg
        static let notationChordSecondOffset: CGFloat = 4
        static let notationPolyphonicLaneSpacing: CGFloat = 9
        static let notationNoteHitWidth: CGFloat = 8
        static let notationNoteHitHeight: CGFloat = 4
        static let notationTieNoteheadInset: CGFloat = 5
        static let notationTieVerticalOffset: CGFloat = 5
        static let notationTieArcHeight: CGFloat = 5
        static let notationTieEndpointThickness: CGFloat = 0.7
        static let notationTieMidpointThickness: CGFloat = 1.7
        static let notationHarmonyAnchorLeadingOffset: CGFloat = AppTheme.Spacing.md
        static let notationHarmonySymbolWidth: CGFloat = 84
        static let notationHarmonyEditorMinWidth: CGFloat = 38
        static let notationHarmonyEditorMaxWidth: CGFloat = 104
        static let notationRegionLabelMaxWidth: CGFloat = 88
        static let notationRegionLabelHeight: CGFloat = 16
        static let notationRegionLabelFontSize: CGFloat = 10
        static let notationRegionLabelCornerRadius: CGFloat = 1.5
        static let notationRegionLabelGap: CGFloat = AppTheme.Spacing.xs
        static let notationBarlineHitWidth: CGFloat = 8
        static let stemTrackHeight: CGFloat = 48
        static let defaultVisibleStemRows = 4
        static let trackSpacing: CGFloat = 6
        static var zoomableUpperTrackStackHeight: CGFloat {
            regionTrackHeight + markerTrackHeight + tempoTrackHeight + waveformTrackHeight
        }
        static func notationTrackCurrentHeight(isCollapsed: Bool) -> CGFloat {
            isCollapsed ? notationTrackCollapsedHeight : notationTrackHeight
        }
        static func upperTrackStackHeight(isNotationTrackCollapsed: Bool) -> CGFloat {
            zoomableUpperTrackStackHeight + notationTrackCurrentHeight(isCollapsed: isNotationTrackCollapsed)
        }
        static var upperTrackStackHeight: CGFloat {
            upperTrackStackHeight(isNotationTrackCollapsed: false)
        }
        static func stemRowHeight(isNotationExpanded: Bool) -> CGFloat {
            stemTrackHeight
                + (isNotationExpanded ? trackSpacing + notationTrackHeight : 0)
        }
        static func stemTracksHeight(
            rowCount: Int,
            expandedStemNotationCount: Int = 0
        ) -> CGFloat {
            let visibleRows = max(defaultVisibleStemRows, rowCount)
            let expandedRows = min(max(0, expandedStemNotationCount), max(0, rowCount))
            return CGFloat(visibleRows) * stemTrackHeight
                + CGFloat(max(0, visibleRows - 1)) * AppTheme.Spacing.md
                + CGFloat(expandedRows) * (trackSpacing + notationTrackHeight)
        }
        static var stemTracksHeight: CGFloat {
            stemTracksHeight(rowCount: defaultVisibleStemRows)
        }
        static func tracksMinimumHeight(
            stemRowCount: Int,
            isNotationTrackCollapsed: Bool = false,
            expandedStemNotationCount: Int = 0
        ) -> CGFloat {
            upperTrackStackHeight(isNotationTrackCollapsed: isNotationTrackCollapsed)
                + trackSpacing
                + stemTracksHeight(
                    rowCount: stemRowCount,
                    expandedStemNotationCount: expandedStemNotationCount
                )
        }
        static var tracksMinimumHeight: CGFloat {
            tracksMinimumHeight(stemRowCount: defaultVisibleStemRows)
        }
        static let viewportFooterGap: CGFloat = AppTheme.Spacing.md
        static var trackControlsMinimumHeight: CGFloat {
            tracksMinimumHeight
        }
        static func timelineBlockMinimumHeight(
            stemRowCount: Int,
            isNotationTrackCollapsed: Bool = false,
            expandedStemNotationCount: Int = 0
        ) -> CGFloat {
            tracksMinimumHeight(
                stemRowCount: stemRowCount,
                isNotationTrackCollapsed: isNotationTrackCollapsed,
                expandedStemNotationCount: expandedStemNotationCount
            ) + viewportFooterGap + viewportControlBarHeight
        }
        static var timelineBlockMinimumHeight: CGFloat {
            timelineBlockMinimumHeight(stemRowCount: defaultVisibleStemRows)
        }
        static func minimumContentHeight(
            stemRowCount: Int,
            isNotationTrackCollapsed: Bool = false,
            expandedStemNotationCount: Int = 0
        ) -> CGFloat {
            timelineBlockMinimumHeight(
                stemRowCount: stemRowCount,
                isNotationTrackCollapsed: isNotationTrackCollapsed,
                expandedStemNotationCount: expandedStemNotationCount
            )
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
        static let rulerMinimumLabelSpacing: CGFloat = 86
        static let rulerLabelWidth: CGFloat = 72
        static let playbackMarkerHandleWidth: CGFloat = 11
        static let playbackMarkerHandleHeight: CGFloat = 8
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
        static let rulerMajorLineOpacity = 0.62
        static let rulerMinorBarLineOpacity = 0.28
        static let rulerBeatLineOpacity = 0.14
        static let rulerTimeLabelOpacity = 0.72
        static let peakRMSOpacity = 0.18
        static let peakOpacity = 1.0
        static let emptyPeakOpacity = 0.25
        static let preRollOpacity = 0.08
    }

    enum Animation {
        static let fast = 0.16
        static let standard = 0.22
    }

    enum NotationWindow {
        static let maximumMeasuresPerSystem = 4
        static let systemHeight: CGFloat = 124
        static let staffSpacing: CGFloat = AppTheme.Spacing.none
        static let systemSpacing: CGFloat = AppTheme.Spacing.xxl
        static let pagePadding: CGFloat = 28
        static let partLabelWidth: CGFloat = 104
        static let partGutterSpacing: CGFloat = AppTheme.Spacing.xl
        static let systemConnectorWidth: CGFloat = AppTheme.Spacing.sm
        static let systemConnectorTopInset: CGFloat = max(
            AppTheme.Spacing.xxl,
            (systemHeight - AppTheme.Timeline.notationStaffLineSpacing * 4) / 2 + AppTheme.Spacing.xs
        )
        static let systemConnectorBottomInset: CGFloat = systemHeight
            - systemConnectorTopInset
            - AppTheme.Timeline.notationStaffLineSpacing * 4
    }
}

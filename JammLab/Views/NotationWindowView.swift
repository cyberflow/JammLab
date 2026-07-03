import AppKit
import SwiftUI

struct NotationWindowView: View {
    @ObservedObject var viewModel: AudioPlayerViewModel

    @Environment(\.appColors) private var appColors
    @State private var didSetInitialFocus = false
    @State private var isUserNavigating = false
    @State private var lastAutoScrolledSystemID: NotationSystemState.ID?
    @State private var resumeAutoScrollTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(
                1,
                proxy.size.width - AppTheme.NotationWindow.pagePadding * 2
            )
            let scoreState = notationScoreState
            let systems = fittedSystems(
                width: contentWidth,
                scoreState: scoreState
            )

            VStack(spacing: AppTheme.Spacing.none) {
                header

                Divider()

                scoreBody(scoreState: scoreState, systems: systems)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(appColors.appBackground)
            .background(
                NotationWindowInitialFocusLandingView(
                    didSetInitialFocus: $didSetInitialFocus
                )
            )
            .background(
                AppHotkeyMonitorView(
                    allowedHotkeys: allowedHotkeys,
                    onHotkeyShouldConsume: handleHotkey
                )
            )
        }
        .frame(
            minWidth: AppTheme.Window.notationMinWidth,
            minHeight: AppTheme.Window.notationMinHeight
        )
        .onDisappear {
            resumeAutoScrollTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            NotationResolutionControl(
                denominator: Binding(
                    get: { viewModel.harmonyInputResolutionDenominator },
                    set: { viewModel.setHarmonyInputResolutionDenominator($0) }
                ),
                isEnabled: viewModel.canShowNotationWindow
            )

            Spacer(minLength: AppTheme.Spacing.md)

            AppControlButton(
                title: "Export MusicXML",
                systemImage: "square.and.arrow.up"
            ) {
                Task {
                    await viewModel.exportNotationAsMusicXML()
                }
            }
            .disabled(!viewModel.canExportNotation)
            .help(ControlHelpText.exportNotationMusicXML)
            .accessibilityLabel(ControlHelpText.exportNotationMusicXML)
        }
        .padding(.horizontal, AppTheme.Spacing.panelPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    @ViewBuilder
    private func scoreBody(
        scoreState: NotationScoreState,
        systems: [NotationSystemState]
    ) -> some View {
        if scoreState.isReady, !systems.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.NotationWindow.systemSpacing) {
                        ForEach(systems) { system in
                            NotationTrackView(
                                state: system.viewportState,
                                selectedHarmonySymbolID: viewModel.selectedHarmonySymbolID,
                                selectedMeasures: viewModel.selectedNotationMeasures,
                                selectedBeat: viewModel.selectedNotationBeat,
                                pendingEditorRequest: viewModel.pendingHarmonyEditorRequest,
                                inputResolution: HarmonyInputResolution(
                                    denominator: viewModel.harmonyInputResolutionDenominator
                                ),
                                actions: notationActions,
                                cornerRadius: AppTheme.Spacing.none
                            )
                            .frame(height: AppTheme.NotationWindow.systemHeight)
                            .id(system.id)
                        }
                    }
                    .padding(AppTheme.NotationWindow.pagePadding)
                }
                .background(appColors.elevatedSurface)
                .simultaneousGesture(userNavigationGesture)
                .onAppear {
                    scrollToActiveSystem(
                        in: systems,
                        anchorTime: scoreState.anchorTime,
                        reader: proxy,
                        animated: false
                    )
                }
                .onChange(of: scoreState.anchorTime) { _, _ in
                    scrollToActiveSystem(
                        in: systems,
                        anchorTime: scoreState.anchorTime,
                        reader: proxy,
                        animated: true
                    )
                }
            }
        } else {
            VStack {
                Spacer()
                Text("No notation available")
                    .font(AppTheme.Typography.noteTitle)
                    .foregroundStyle(appColors.secondaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.elevatedSurface)
        }
    }

    private var notationScoreState: NotationScoreState {
        NotationViewportFactory().scoreState(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing,
            keyName: viewModel.effectiveKeyName,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
    }

    private var notationActions: NotationTrackActions {
        NotationTrackActions(
            selectHarmony: { viewModel.selectHarmonySymbol(id: $0) },
            selectMeasure: { viewModel.selectNotationMeasure($0, extendingSelection: $1) },
            selectBeat: { viewModel.selectNotationBeat($0) },
            saveHarmony: { viewModel.saveHarmonySymbol($0) },
            deleteHarmony: { viewModel.deleteHarmonySymbol(id: $0) },
            adjacentHarmonyPlacement: { viewModel.adjacentHarmonyPlacement(from: $0, direction: $1) }
        )
    }

    private var allowedHotkeys: Set<AppHotkey> {
        var hotkeys: Set<AppHotkey> = [.playPause]
        if viewModel.canCopySelectedNotationMeasure {
            hotkeys.insert(.copyMeasure)
        }
        if viewModel.canPasteNotationMeasureClipboard {
            hotkeys.insert(.pasteMeasure)
        }
        if viewModel.hasSelectedNotationMeasures {
            hotkeys.insert(.clearNotationMeasureSelection)
        }
        if viewModel.canEditSelectedNotationBeat {
            hotkeys.insert(.editHarmonyAtSelectedBeat)
        }
        return hotkeys
    }

    @discardableResult
    private func handleHotkey(_ hotkey: AppHotkey) -> Bool {
        switch hotkey {
        case .playPause:
            viewModel.togglePlayStop()
            return true
        case .copyMeasure:
            return viewModel.copySelectedNotationMeasure()
        case .pasteMeasure:
            return viewModel.pasteNotationMeasureClipboard()
        case .clearNotationMeasureSelection:
            viewModel.clearNotationMeasureSelection()
            return true
        case .editHarmonyAtSelectedBeat:
            return viewModel.requestEditSelectedNotationBeat()
        default:
            return false
        }
    }

    private var userNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                suspendAutoScroll()
            }
    }

    private func fittedSystems(
        width: CGFloat,
        scoreState: NotationScoreState
    ) -> [NotationSystemState] {
        let measuresPerSystem = fittedMeasuresPerSystem(
            width: width,
            scoreState: scoreState
        )
        return scoreState.systems(measuresPerSystem: measuresPerSystem)
    }

    private func fittedMeasuresPerSystem(
        width: CGFloat,
        scoreState: NotationScoreState
    ) -> Int {
        guard scoreState.isReady else { return 1 }

        let maximum = AppTheme.NotationWindow.maximumMeasuresPerSystem
        for count in stride(from: maximum, through: 1, by: -1) {
            let systems = scoreState.systems(measuresPerSystem: count)
            let requiredWidth = systems
                .map { NotationVisibleMeasureFitter.minimumRequiredWidth(for: $0.viewportState) }
                .max() ?? 0
            if requiredWidth <= width + NotationVisibleMeasureFitter.widthTolerance {
                return count
            }
        }

        return 1
    }

    private func scrollToActiveSystem(
        in systems: [NotationSystemState],
        anchorTime: TimeInterval,
        reader: ScrollViewProxy,
        animated: Bool
    ) {
        guard !isUserNavigating,
              viewModel.pendingHarmonyEditorRequest == nil
        else { return }

        guard let activeSystem = systems.first(where: { system in
            system.viewportState.visibleMeasures.contains { measure in
                anchorTime >= measure.startTime
                    && (
                        anchorTime < measure.endTime
                            || abs(anchorTime - measure.endTime) < 0.000_001
                    )
            }
        }) else { return }
        guard activeSystem.id != lastAutoScrolledSystemID else { return }

        let action = {
            lastAutoScrolledSystemID = activeSystem.id
            reader.scrollTo(activeSystem.id, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: AppTheme.Animation.standard)) {
                action()
            }
        } else {
            action()
        }
    }

    private func suspendAutoScroll() {
        isUserNavigating = true
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isUserNavigating = false
            }
        }
    }
}

private struct NotationResolutionControl: View {
    @Binding var denominator: Int
    let isEnabled: Bool
    @Environment(\.appColors) private var appColors

    private var options: [NotationResolutionOption] {
        HarmonyInputResolution.allowedDenominators
            .reversed()
            .compactMap(NotationResolutionOption.init)
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(options) { option in
                resolutionButton(for: option)
            }
        }
        .frame(height: AppTheme.ControlSize.notationResolutionControlHeight)
    }

    private func resolutionButton(for option: NotationResolutionOption) -> some View {
        let isSelected = HarmonyInputResolution.normalizedDenominator(denominator) == option.denominator
        let helpText = "Set \(ControlHelpText.harmonyInputResolution.lowercased()) to \(option.resolutionName)"

        return Button {
            denominator = option.denominator
        } label: {
            NotationResolutionIcon(
                kind: option.iconKind,
                color: iconColor(isSelected: isSelected)
            )
                .frame(
                    width: AppTheme.ControlSize.notationResolutionButtonWidth,
                    height: AppTheme.ControlSize.notationResolutionControlHeight
                )
                .background(backgroundColor(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(borderColor(isSelected: isSelected), lineWidth: AppTheme.Stroke.thin)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .accessibilityLabel("Harmony input resolution: \(option.resolutionName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func iconColor(isSelected: Bool) -> Color {
        guard isEnabled else { return appColors.disabledText }
        return isSelected ? appColors.accent : appColors.secondaryText
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        isEnabled && isSelected ? appColors.controlActive : Color.clear
    }

    private func borderColor(isSelected: Bool) -> Color {
        isEnabled && isSelected ? appColors.accent : Color.clear
    }
}

private struct NotationResolutionOption: Identifiable {
    let denominator: Int
    let iconKind: NotationResolutionIcon.Kind
    let resolutionName: String

    var id: Int { denominator }

    init?(denominator: Int) {
        self.denominator = denominator

        switch denominator {
        case 8:
            iconKind = .eighth
            resolutionName = "eighth notes"
        case 4:
            iconKind = .quarter
            resolutionName = "quarter notes"
        case 2:
            iconKind = .half
            resolutionName = "half notes"
        case 1:
            iconKind = .whole
            resolutionName = "whole notes"
        default:
            return nil
        }
    }
}

private struct NotationResolutionIcon: View {
    enum Kind {
        case eighth
        case quarter
        case half
        case whole
    }

    let kind: Kind
    let color: Color

    var body: some View {
        Canvas { context, size in
            let strokeStyle = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)

            switch kind {
            case .eighth:
                drawNote(
                    in: &context,
                    size: size,
                    color: color,
                    filledHead: true,
                    hasStem: true,
                    hasFlag: true,
                    strokeStyle: strokeStyle
                )
            case .quarter:
                drawNote(
                    in: &context,
                    size: size,
                    color: color,
                    filledHead: true,
                    hasStem: true,
                    hasFlag: false,
                    strokeStyle: strokeStyle
                )
            case .half:
                drawNote(
                    in: &context,
                    size: size,
                    color: color,
                    filledHead: false,
                    hasStem: true,
                    hasFlag: false,
                    strokeStyle: strokeStyle
                )
            case .whole:
                drawWholeNote(in: &context, size: size, color: color, strokeStyle: strokeStyle)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawNote(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        filledHead: Bool,
        hasStem: Bool,
        hasFlag: Bool,
        strokeStyle: StrokeStyle
    ) {
        let headRect = CGRect(
            x: size.width * 0.24,
            y: size.height * 0.56,
            width: size.width * 0.27,
            height: size.height * 0.22
        )
        let head = Path(ellipseIn: headRect)
        if filledHead {
            context.fill(head, with: .color(color))
        } else {
            context.stroke(head, with: .color(color), style: strokeStyle)
        }

        guard hasStem else { return }

        var stem = Path()
        stem.move(to: CGPoint(x: headRect.maxX, y: headRect.midY))
        stem.addLine(to: CGPoint(x: headRect.maxX, y: size.height * 0.18))
        context.stroke(stem, with: .color(color), style: strokeStyle)

        guard hasFlag else { return }

        var flag = Path()
        flag.move(to: CGPoint(x: headRect.maxX, y: size.height * 0.18))
        flag.addCurve(
            to: CGPoint(x: size.width * 0.66, y: size.height * 0.42),
            control1: CGPoint(x: size.width * 0.64, y: size.height * 0.23),
            control2: CGPoint(x: size.width * 0.71, y: size.height * 0.34)
        )
        context.stroke(flag, with: .color(color), style: strokeStyle)
    }

    private func drawWholeNote(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        strokeStyle: StrokeStyle
    ) {
        let headRect = CGRect(
            x: size.width * 0.35,
            y: size.height * 0.58,
            width: size.width * 0.28,
            height: size.height * 0.17
        )
        context.stroke(Path(ellipseIn: headRect), with: .color(color), style: strokeStyle)
    }
}

#Preview {
    NotationWindowView(viewModel: AudioPlayerViewModel())
        .environment(\.appColors, AppThemeColors.default)
}

private struct NotationWindowInitialFocusLandingView: NSViewRepresentable {
    @Binding var didSetInitialFocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(didSetInitialFocus: $didSetInitialFocus)
    }

    func makeNSView(context: Context) -> NotationWindowInitialFocusLandingNSView {
        let view = NotationWindowInitialFocusLandingNSView(frame: .zero)
        configure(view, context: context)
        return view
    }

    func updateNSView(
        _ nsView: NotationWindowInitialFocusLandingNSView,
        context: Context
    ) {
        configure(nsView, context: context)
    }

    private func configure(
        _ view: NotationWindowInitialFocusLandingNSView,
        context: Context
    ) {
        view.onFocusLandingRequested = { [weak coordinator = context.coordinator] window, landingView in
            coordinator?.requestInitialFocus(in: window, landingView: landingView)
        }
    }

    final class Coordinator {
        private let didSetInitialFocus: Binding<Bool>
        private var isSchedulingFocus = false

        init(didSetInitialFocus: Binding<Bool>) {
            self.didSetInitialFocus = didSetInitialFocus
        }

        func requestInitialFocus(
            in window: NSWindow,
            landingView: NotationWindowInitialFocusLandingNSView
        ) {
            guard !didSetInitialFocus.wrappedValue, !isSchedulingFocus else { return }
            isSchedulingFocus = true

            let delays: [TimeInterval] = [0, 0.08]
            for (index, delay) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window, weak landingView] in
                    guard let self else { return }
                    guard let window, let landingView else {
                        self.isSchedulingFocus = false
                        return
                    }
                    let isFinalAttempt = index == delays.count - 1
                    self.trySetInitialFocus(
                        in: window,
                        landingView: landingView,
                        isFinalAttempt: isFinalAttempt
                    )
                }
            }
        }

        private func trySetInitialFocus(
            in window: NSWindow,
            landingView: NotationWindowInitialFocusLandingNSView,
            isFinalAttempt: Bool
        ) {
            guard !didSetInitialFocus.wrappedValue else {
                isSchedulingFocus = false
                return
            }
            guard shouldOverrideFirstResponder(
                window.firstResponder,
                window: window,
                landingView: landingView
            ) else {
                if isFinalAttempt {
                    isSchedulingFocus = false
                }
                return
            }

            let didLandFocus = window.makeFirstResponder(landingView)
                && window.firstResponder === landingView
            if didLandFocus, isFinalAttempt {
                didSetInitialFocus.wrappedValue = true
            }
            if isFinalAttempt {
                isSchedulingFocus = false
            }
        }

        private func shouldOverrideFirstResponder(
            _ firstResponder: NSResponder?,
            window: NSWindow,
            landingView: NotationWindowInitialFocusLandingNSView
        ) -> Bool {
            guard let firstResponder else { return true }
            if firstResponder === window { return true }
            if firstResponder === landingView { return true }
            return AppHotkeyEventFilter.isAbletonNumberFieldResponder(firstResponder)
        }
    }
}

private final class NotationWindowInitialFocusLandingNSView: NSView {
    var onFocusLandingRequested: ((NSWindow, NotationWindowInitialFocusLandingNSView) -> Void)?

    private var didBecomeKeyObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    deinit {
        removeWindowObserver()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObserver()
        guard let window else { return }

        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow
            else { return }
            self.onFocusLandingRequested?(window, self)
        }

        onFocusLandingRequested?(window, self)
    }

    private func removeWindowObserver() {
        guard let didBecomeKeyObserver else { return }
        NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        self.didBecomeKeyObserver = nil
    }
}

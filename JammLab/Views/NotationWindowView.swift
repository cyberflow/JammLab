import AppKit
import SwiftUI

struct NotationWindowView: View {
    @ObservedObject var viewModel: AudioPlayerViewModel

    @Environment(\.appColors) private var appColors
    @State private var didSetInitialFocus = false
    @State private var isUserNavigating = false
    @State private var lastAutoScrolledSystemID: NotationSystemState.ID?
    @State private var resumeAutoScrollTask: Task<Void, Never>?
    @State private var notationProjectionCache = NotationProjectionCache()

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
            NotationDurationControl(
                denominator: Binding(
                    get: { viewModel.notationDurationDenominator },
                    set: { viewModel.setNotationDurationDenominator($0) }
                ),
                isEnabled: viewModel.canChangeNotationDuration
            )

            AppControlButton(
                title: "Note Entry",
                systemImage: "music.note",
                isActive: viewModel.isNotationNoteEntryModeEnabled
            ) {
                viewModel.toggleNotationNoteEntryMode()
            }
            .disabled(viewModel.duration <= 0)
            .help("Add notes to Notation (N)")
            .accessibilityLabel("Notation Note Entry")
            .accessibilityValue(viewModel.isNotationNoteEntryModeEnabled ? "Enabled" : "Disabled")

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
                                playbackDisplayState: viewModel.playbackDisplayState,
                                selectedHarmonySymbolID: viewModel.selectedHarmonySymbolID,
                                selectedMeasures: viewModel.selectedNotationMeasures,
                                selectedItem: viewModel.selectedNotationItem,
                                selectedDuration: NotationDuration(denominator: viewModel.notationDurationDenominator),
                                isNoteEntryModeEnabled: viewModel.isNotationNoteEntryModeEnabled,
                                pendingEditorRequest: viewModel.pendingHarmonyEditorRequest,
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
        let content = notationProjectionCache.content(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            keyName: viewModel.effectiveKeyName,
            notationItems: viewModel.notationItems,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
        return NotationViewportFactory().scoreState(
            content: content,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing
        )
    }

    private var notationActions: NotationTrackActions {
        NotationTrackActions(
            selectHarmony: { viewModel.selectHarmonySymbol(id: $0) },
            selectMeasure: { viewModel.selectNotationMeasure($0, extendingSelection: $1) },
            selectItem: { viewModel.selectNotationItem($0, shouldAudition: $1) },
            insertNotationNote: { viewModel.insertNotationNote($0) },
            changeSelectedNotePitch: { viewModel.changeSelectedNotationNotePitch(to: $0, shouldAudition: $1) },
            auditionNotePitch: { viewModel.auditionNotationNotePitch($0) },
            deleteSelectedNotationNote: { viewModel.deleteSelectedNotationNote() },
            locatePlaybackMarkerExactly: { viewModel.locatePlaybackMarkerExactly(to: $0) },
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
        if viewModel.hasSelectedNotationMeasures || viewModel.isNotationNoteEntryModeEnabled {
            hotkeys.insert(.clearNotationMeasureSelection)
        }
        if viewModel.canEditSelectedNotationItem {
            hotkeys.insert(.editHarmonyAtSelectedNotationItem)
        }
        if viewModel.canChangeNotationDuration {
            hotkeys.formUnion(AppHotkey.notationDurationHotkeys)
        }
        if viewModel.duration > 0 {
            hotkeys.insert(.toggleNotationNoteEntryMode)
        }
        if viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1) {
            hotkeys.insert(.moveSelectedNotationNotePitchUp)
        }
        if viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1) {
            hotkeys.insert(.moveSelectedNotationNotePitchDown)
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
            if viewModel.isNotationNoteEntryModeEnabled {
                viewModel.clearNotationNoteEntryMode()
            } else {
                viewModel.clearNotationMeasureSelection()
            }
            return true
        case .editHarmonyAtSelectedNotationItem:
            return viewModel.requestEditSelectedNotationItem()
        case .toggleNotationNoteEntryMode:
            viewModel.toggleNotationNoteEntryMode()
            return true
        case .moveSelectedNotationNotePitchUp:
            return viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: -1)
        case .moveSelectedNotationNotePitchDown:
            return viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: 1)
        case .setNotationDurationEighth,
                .setNotationDurationQuarter,
                .setNotationDurationHalf,
                .setNotationDurationWhole:
            guard let denominator = hotkey.notationDurationDenominator else { return false }
            viewModel.setNotationDurationDenominator(denominator)
            return true
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

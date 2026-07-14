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
            let scoreLayout = notationScoreLayout(contentWidth: contentWidth)

            VStack(spacing: AppTheme.Spacing.none) {
                header

                Divider()

                scoreBody(layout: scoreLayout)
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
            NotationEntryModeButton(
                mode: .note,
                isActive: viewModel.isNotationNoteEntryModeEnabled
            ) {
                viewModel.toggleNotationNoteEntryMode()
            }
            .disabled(viewModel.duration <= 0)
            .help("Add notes to Notation (N)")
            .accessibilityLabel("Notation Note Entry")
            .accessibilityValue(viewModel.isNotationNoteEntryModeEnabled ? "Enabled" : "Disabled")

            NotationDurationControl(
                denominator: Binding(
                    get: { viewModel.notationDurationDenominator },
                    set: { viewModel.setNotationDurationDenominator($0) }
                ),
                isEnabled: viewModel.canChangeNotationDuration
            )

            NotationEntryModeButton(
                mode: .rest,
                isActive: viewModel.isNotationRestEntryModeEnabled
            ) {
                viewModel.toggleNotationRestEntryMode()
            }
            .disabled(viewModel.duration <= 0)
            .help("Add rests to Notation")
            .accessibilityLabel("Notation Rest Entry")
            .accessibilityValue(viewModel.isNotationRestEntryModeEnabled ? "Enabled" : "Disabled")

            partVisibilityMenu

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
        layout: NotationWindowScoreLayout
    ) -> some View {
        if !layout.systems.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.NotationWindow.systemSpacing) {
                        ForEach(layout.systems) { system in
                            notationSystem(system, usesPartGutter: layout.usesPartGutter)
                                .id(system.id)
                        }
                    }
                    .padding(AppTheme.NotationWindow.pagePadding)
                }
                .background(appColors.elevatedSurface)
                .simultaneousGesture(userNavigationGesture)
                .onAppear {
                    scrollToActiveSystem(
                        in: layout,
                        reader: proxy,
                        animated: false
                    )
                }
                .onChange(of: layout.anchorTime) { _, _ in
                    scrollToActiveSystem(
                        in: layout,
                        reader: proxy,
                        animated: true
                    )
                }
                .onChange(of: layout.signature) { _, _ in
                    lastAutoScrolledSystemID = nil
                    scrollToActiveSystem(
                        in: layout,
                        reader: proxy,
                        animated: false
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

    private func notationSystem(
        _ system: NotationWindowScoreSystem,
        usesPartGutter: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: AppTheme.NotationWindow.staffSpacing) {
                ForEach(system.staves) { staff in
                    HStack(spacing: AppTheme.Spacing.none) {
                        if usesPartGutter {
                            Text(staff.part.abbreviation)
                                .font(AppTheme.Typography.noteTitle)
                                .foregroundStyle(appColors.secondaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.trailing)
                                .frame(
                                    width: AppTheme.NotationWindow.partLabelWidth,
                                    alignment: .trailing
                                )

                            Color.clear
                                .frame(width: AppTheme.NotationWindow.partGutterSpacing)
                        }

                        NotationTrackView(
                            state: staff.system.viewportState,
                            partID: staff.part.id,
                            playbackDisplayState: viewModel.playbackDisplayState,
                            selectedHarmonySymbolID: staff.part.id.isMain ? viewModel.selectedHarmonySymbolID : nil,
                            selectedMeasures: viewModel.selectedNotationMeasures,
                            selectedItem: viewModel.selectedNotationItem,
                            selectedDuration: NotationDuration(denominator: viewModel.notationDurationDenominator),
                            entryMode: viewModel.notationEntryMode,
                            pendingEditorRequest: staff.part.id.isMain ? viewModel.pendingHarmonyEditorRequest : nil,
                            showsRegionLabels: staff.showsRegionLabels,
                            actions: notationActions,
                            cornerRadius: AppTheme.Spacing.none
                        )
                    }
                    .frame(height: AppTheme.NotationWindow.systemHeight)
                }
            }

            if usesPartGutter, system.staves.count > 1 {
                NotationWindowSystemConnector(color: appColors.notationSymbolsAndLines)
                    .frame(
                        width: AppTheme.NotationWindow.systemConnectorWidth,
                        height: system.connectorHeight
                    )
                    .offset(
                        x: AppTheme.NotationWindow.partLabelWidth,
                        y: AppTheme.NotationWindow.systemConnectorTopInset
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partVisibilityMenu: some View {
        Menu {
            ForEach(viewModel.availableNotationParts) { part in
                Button {
                    viewModel.toggleNotationWindowPartVisibility(part.id)
                } label: {
                    if viewModel.normalizedVisibleNotationPartIDs().contains(part.id) {
                        Label(part.title, systemImage: "checkmark")
                    } else {
                        Text(part.title)
                    }
                }
            }
        } label: {
            Label("Parts", systemImage: "rectangle.stack")
        }
        .disabled(viewModel.availableNotationParts.count <= 1)
        .help("Choose visible Notation parts")
        .accessibilityLabel("Visible Notation Parts")
    }

    private func notationScoreLayout(contentWidth: CGFloat) -> NotationWindowScoreLayout {
        let partStates = viewModel.visibleNotationParts.map { part in
            let scoreState = notationScoreState(partID: part.id)
            return NotationWindowPartRenderState(
                part: part,
                scoreState: scoreState
            )
        }
        return NotationWindowScoreLayout.make(
            partStates: partStates,
            contentWidth: contentWidth
        )
    }

    private func notationScoreState(partID: NotationPartID) -> NotationScoreState {
        let content = notationProjectionCache.content(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            keyName: viewModel.effectiveKeyName,
            clef: viewModel.notationClef(for: partID),
            partID: partID,
            includesHarmonies: partID.isMain,
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
            selectMeasure: { viewModel.selectNotationMeasure($0, extendingSelection: $1, partID: $2) },
            selectItem: { viewModel.selectNotationItem($0, shouldAudition: $1) },
            insertNotationNote: { viewModel.insertNotationNote($0) },
            insertNotationRest: { viewModel.insertNotationRest($0) },
            changeSelectedNotePitch: { viewModel.changeSelectedNotationNotePitch(to: $0, shouldAudition: $1) },
            changeClef: { viewModel.setNotationClef($1, for: $0) },
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
        if viewModel.hasSelectedNotationMeasures || viewModel.isNotationEntryModeEnabled {
            hotkeys.insert(.clearNotationMeasureSelection)
        }
        if viewModel.canEditHarmonyAtSelectedNotationItem {
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
            if viewModel.isNotationEntryModeEnabled {
                viewModel.clearNotationEntryMode()
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

    private func scrollToActiveSystem(
        in layout: NotationWindowScoreLayout,
        reader: ScrollViewProxy,
        animated: Bool
    ) {
        guard !isUserNavigating,
              viewModel.pendingHarmonyEditorRequest == nil
        else { return }

        guard let targetID = layout.activeSystemID else { return }
        guard targetID != lastAutoScrolledSystemID else { return }

        let action = {
            lastAutoScrolledSystemID = targetID
            reader.scrollTo(targetID, anchor: .center)
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

private struct NotationWindowSystemConnector: View {
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let x = proxy.size.width - AppTheme.Stroke.thin / 2
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: x, y: 0))
                path.move(to: CGPoint(x: 0, y: proxy.size.height))
                path.addLine(to: CGPoint(x: x, y: proxy.size.height))
            }
            .stroke(color, lineWidth: AppTheme.Stroke.thin)
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

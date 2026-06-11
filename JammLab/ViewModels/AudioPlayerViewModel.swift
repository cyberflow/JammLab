import AVFoundation
import Combine
import Foundation

enum PlaybackState: Equatable {
    case idle
    case playing
    case paused
    case stopped

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        }
    }
}

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var importedFile: ImportedAudioFile?
    @Published private(set) var analysisResult: AnalysisResult?
    @Published private(set) var peakformData: PeakformData?
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = AppSliderDefaults.playbackRate
    @Published private(set) var pitchShiftSemitones: Float = AppSliderDefaults.pitchShiftSemitones
    @Published private(set) var tempoBPM: Double? = AppDefaults.defaultTempoBPM
    @Published private(set) var beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
    @Published private(set) var notes: [TimecodedNote] = []
    @Published private(set) var selectedRegionID: TimecodedNote.ID?
    @Published private(set) var activeLoopRegionID: TimecodedNote.ID?
    @Published private(set) var loopRegion: LoopRegion = .empty
    @Published private(set) var timelineVisibleRange: ClosedRange<TimeInterval> = 0...0
    @Published private(set) var currentProjectURL: URL?
    @Published private(set) var isImporting = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isBuildingWaveform = false
    @Published private(set) var playbackMode: PlaybackMode = .original
    @Published private(set) var stemFiles: [StemFile] = []
    @Published private(set) var stemPeakforms: [StemType: PeakformData] = [:]
    @Published private(set) var isBuildingStemPeakforms = false
    @Published private(set) var stemMixState = StemMixState()
    @Published private(set) var stemSeparationState = StemSeparationViewState()
    @Published var isLooping = false
    @Published var isClickEnabled = false
    @Published private(set) var isSnapEnabled = false
    @Published private(set) var mainTrackVolume: Float = AppSliderDefaults.mainTrackVolume
    @Published private(set) var clickVolume: Float = AudioPlayerViewModel.restoredClickVolume()
    @Published private(set) var undoStateRevision = 0
    @Published private(set) var isProjectModified = false
    @Published var errorMessage: String?
    weak var undoManager: UndoManager? {
        didSet {
            refreshUndoAvailability()
        }
    }

    private let importer: AudioFileImporter
    private let analyzer: AudioAnalyzing
    private let peakformProvider: PeakformProvider
    private let playbackEngine: AudioPlaybackControlling
    private let videoFollower: VideoFollowerControlling
    private let appSettingsStore: AppSettingsStore
    private let stemSeparationService: StemSeparationService
    private let projectService: ProjectDocumentService
    private let projectArtifactStore: ProjectArtifactStore
    private let recentProjectsStore: RecentProjectsStore
    private let isSandboxed: () -> Bool
    private var clockTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var stemSeparationTask: Task<Void, Never>?
    private var stemPeakformTask: Task<Void, Never>?
    private var stemCacheMetadata: StemCacheMetadata?
    private var shouldAcceptAnalyzedTempo = true
    private var securityScopedURL: URL?
    private var hasSecurityScopedAccess = false
    private var projectSecurityScopedURL: URL?
    private var hasProjectSecurityScopedAccess = false
    private var settingsCancellables: Set<AnyCancellable> = []
    private var isRestoringUndoState = false
    private var lastSavedProjectState: ProjectPersistedEditableState?

    private static func restoredClickVolume() -> Float {
        let key = "metronome.volume"

        guard UserDefaults.standard.object(forKey: key) != nil else {
            return AppSliderDefaults.clickVolume
        }

        return min(1, max(0, UserDefaults.standard.float(forKey: key)))
    }

    nonisolated private static func defaultSandboxDetection() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    var canPlay: Bool {
        activePlaybackEngine.isLoaded
    }

    var canShowVideoWindow: Bool {
        importedFile?.mediaKind == .video
    }

    var windowTitle: String {
        guard let importedFile else { return "JammLab" }

        let modifiedSuffix = isProjectModified ? " [modified]" : ""
        return "\(importedFile.displayName)\(modifiedSuffix) - JammLab"
    }

    var transportStatusText: String {
        if isBuildingWaveform {
            return "Building peakform"
        }

        if isAnalyzing {
            return "Analyzing"
        }

        return playbackState.title
    }

    var playbackRateText: String {
        "\(Int((playbackRate * 100).rounded()))%"
    }

    var pitchShiftText: String {
        let roundedSemitones = Int(pitchShiftSemitones.rounded())

        if roundedSemitones > 0 {
            return "+\(roundedSemitones) st"
        }

        return "\(roundedSemitones) st"
    }

    var clickVolumeText: String {
        "\(Int((clickVolume * 100).rounded()))%"
    }

    var tempoBPMText: String {
        guard let tempoBPM else { return "Pending" }
        return String(format: "%.1f", tempoBPM)
    }

    var firstBeatText: String {
        TimeFormatter.mmss(beatGridSettings.firstBeatTime)
    }

    var beatGridAlignmentText: String {
        beatGridSettings.isManuallyAligned ? "Manual" : "Auto"
    }

    var regionNotes: [TimecodedNote] {
        notes.filter(\.isRegion)
    }

    var canUseStemsPlayback: Bool {
        !stemFiles.isEmpty
    }

    var canUndo: Bool {
        undoManager?.canUndo ?? false
    }

    var canRedo: Bool {
        undoManager?.canRedo ?? false
    }

    var editableState: ProjectEditableState {
        ProjectEditableState(
            notes: notes,
            selectedRegionID: selectedRegionID,
            activeLoopRegionID: activeLoopRegionID,
            loopRegion: loopRegion,
            isLooping: isLooping,
            tempoBPM: tempoBPM,
            beatGridSettings: beatGridSettings,
            playbackRate: playbackRate,
            pitchShiftSemitones: pitchShiftSemitones,
            mainTrackVolume: mainTrackVolume,
            stemMixState: stemMixState,
            playbackMode: playbackMode,
            isClickEnabled: isClickEnabled,
            clickVolume: clickVolume,
            isSnapEnabled: isSnapEnabled
        )
    }

    var persistedEditableState: ProjectPersistedEditableState? {
        guard importedFile != nil else { return nil }

        let clampedLoop = loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength)

        return ProjectPersistedEditableState(
            notes: ProjectStateNormalizer.normalizedNotes(notes, duration: duration),
            loopRegion: clampedLoop,
            isLooping: isLooping,
            tempoBPM: ProjectStateNormalizer.normalizedTempo(tempoBPM),
            beatGridSettings: beatGridSettings.clamped(to: duration),
            playbackRate: ProjectStateNormalizer.normalizedPlaybackRate(playbackRate),
            pitchShiftSemitones: ProjectStateNormalizer.normalizedPitchShift(pitchShiftSemitones),
            mainTrackVolume: clampedVolume(mainTrackVolume),
            stemMixState: stemMixState,
            playbackMode: playbackMode,
            isClickEnabled: isClickEnabled,
            clickVolume: clampedVolume(clickVolume),
            isSnapEnabled: isSnapEnabled
        )
    }

    init(
        importer: AudioFileImporter = AudioFileImporter(),
        analyzer: AudioAnalyzing = AudioAnalyzer(),
        peakformProvider: PeakformProvider = CachedPeakformProvider(),
        playbackEngine: AudioPlaybackControlling? = nil,
        videoFollower: VideoFollowerControlling? = nil,
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        stemSeparationService: StemSeparationService? = nil,
        projectService: ProjectDocumentService = ProjectDocumentService(),
        projectArtifactStore: ProjectArtifactStore = ProjectArtifactStore(),
        recentProjectsStore: RecentProjectsStore? = nil,
        isSandboxed: @escaping () -> Bool = AudioPlayerViewModel.defaultSandboxDetection
    ) {
        self.importer = importer
        self.analyzer = analyzer
        self.peakformProvider = peakformProvider
        self.playbackEngine = playbackEngine ?? MultiTrackAudioPlayer()
        self.videoFollower = videoFollower ?? VideoFollowerController()
        self.appSettingsStore = appSettingsStore
        self.stemSeparationService = stemSeparationService ?? StemSeparationService(appSettingsStore: appSettingsStore)
        self.projectService = projectService
        self.projectArtifactStore = projectArtifactStore
        self.recentProjectsStore = recentProjectsStore ?? .shared
        self.isSandboxed = isSandboxed
        self.playbackEngine.setClickVolume(clickVolume)
        self.playbackEngine.setMainVolume(mainTrackVolume)
        self.playbackEngine.setClickSettings(beatGridSettings)
        self.playbackEngine.setClickSoundSettings(appSettingsStore.clickSoundSettings)
        applyAudioOutputDeviceSetting(appSettingsStore.audioDeviceSettings.outputDeviceUID)

        appSettingsStore.$clickSoundSettings
            .dropFirst()
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.playbackEngine.setClickSoundSettings(settings)
                }
            }
            .store(in: &settingsCancellables)

        appSettingsStore.$audioDeviceSettings
            .dropFirst()
            .map(\.outputDeviceUID)
            .removeDuplicates()
            .sink { [weak self] outputDeviceUID in
                Task { @MainActor in
                    self?.applyAudioOutputDeviceSetting(outputDeviceUID)
                }
            }
            .store(in: &settingsCancellables)
    }

    deinit {
        clockTask?.cancel()
        analysisTask?.cancel()
        waveformTask?.cancel()
        stemSeparationTask?.cancel()
        stemPeakformTask?.cancel()
        stemSeparationService.cancel()

        if hasSecurityScopedAccess {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }

        if hasProjectSecurityScopedAccess {
            projectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    func importAudio() async {
        errorMessage = nil
        isImporting = true

        do {
            guard let file = try await importer.importFile() else {
                isImporting = false
                return
            }

            try loadImportedAudio(file)
        } catch {
            isImporting = false
            errorMessage = error.localizedDescription
        }
    }

    func importAudio(from url: URL) async {
        errorMessage = nil
        isImporting = true

        do {
            let file = try await importer.importFile(from: url)
            try loadImportedAudio(file)
        } catch {
            isImporting = false
            errorMessage = error.localizedDescription
        }
    }

    func openProject() async {
        guard let url = projectService.chooseProjectToOpen() else { return }
        await openProject(at: url)
    }

    func openRecentProject(_ entry: RecentProjectEntry) async {
        do {
            let url = try entry.resolvedURL()
            guard recentProjectsStore.canOpenProject(at: url) else {
                recentProjectsStore.remove(entry)
                errorMessage = "Could not open recent project: The file doesn’t exist."
                return
            }
            await openProject(at: url)
        } catch {
            errorMessage = "Could not open recent project: \(error.localizedDescription)"
            recentProjectsStore.remove(entry)
        }
    }

    @discardableResult
    func saveProject() async -> Bool {
        if let currentProjectURL {
            return await saveProject(to: currentProjectURL)
        } else {
            return await saveProjectAs()
        }
    }

    @discardableResult
    func saveProjectAs() async -> Bool {
        let defaultName = defaultProjectFilename()
        guard let destination = projectService.chooseProjectSaveDestination(defaultName: defaultName) else { return false }
        guard beginProjectSecurityScopedAccess(for: destination.securityScopedAccessURL) || !isSandboxed() else {
            let error: ProjectDocumentError = destination.createSubdirectory
                ? .projectArtifactAccessDenied
                : .projectArtifactAccessDeniedUseProjectFolder
            errorMessage = "Project save failed: \(error.localizedDescription)"
            return false
        }
        return await saveProject(to: destination.projectURL)
    }

    @discardableResult
    func saveProjectForClose() async -> Bool {
        guard importedFile != nil else { return false }
        return await saveProject()
    }

    func newProject() {
        playbackEngine.unload()
        videoFollower.unload()
        cancelBackgroundWork()
        clearUndoHistory()

        importedFile = nil
        analysisResult = nil
        peakformData = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        playbackRate = AppSliderDefaults.playbackRate
        pitchShiftSemitones = AppSliderDefaults.pitchShiftSemitones
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        shouldAcceptAnalyzedTempo = true
        notes = []
        selectedRegionID = nil
        activeLoopRegionID = nil
        loopRegion = .empty
        timelineVisibleRange = 0...0
        currentProjectURL = nil
        isImporting = false
        isAnalyzing = false
        isBuildingWaveform = false
        resetStemState()
        isLooping = false
        isClickEnabled = false
        isSnapEnabled = false
        mainTrackVolume = AppSliderDefaults.mainTrackVolume
        clickVolume = AppSliderDefaults.clickVolume
        errorMessage = nil
        playbackEngine.setClickSettings(beatGridSettings)
        playbackEngine.setClickVolume(clickVolume)
        playbackEngine.setClickEnabled(false)
        endSecurityScopedAccess()
        endProjectSecurityScopedAccess()
        markProjectClean()
    }

    func restoreEditableState(_ state: ProjectEditableState) {
        let wasRestoringUndoState = isRestoringUndoState
        isRestoringUndoState = true
        defer {
            isRestoringUndoState = wasRestoringUndoState
            refreshUndoAvailability()
        }

        let preservedTime = currentTime

        playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(state.playbackRate)
        pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(state.pitchShiftSemitones)
        mainTrackVolume = clampedVolume(state.mainTrackVolume)
        clickVolume = clampedVolume(state.clickVolume)
        isSnapEnabled = state.isSnapEnabled
        isLooping = state.isLooping
        tempoBPM = ProjectStateNormalizer.normalizedTempo(state.tempoBPM)
        beatGridSettings = state.beatGridSettings.clamped(to: duration)
        beatGridSettings.bpm = tempoBPM
        shouldAcceptAnalyzedTempo = false
        notes = ProjectStateNormalizer.normalizedNotes(state.notes, duration: duration)
        selectedRegionID = availableRegionID(state.selectedRegionID)
        activeLoopRegionID = availableRegionID(state.activeLoopRegionID)
        loopRegion = state.loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength)
        stemMixState = state.stemMixState
        stemMixState.setAvailability(from: stemFiles)
        isClickEnabled = state.isClickEnabled && canPlay && beatGridSettings.bpm != nil

        restorePlaybackMode(state.playbackMode, preservedTime: preservedTime)
        playbackEngine.applyMix(stemMixState)
        applyLoopConfiguration()
        applyPlaybackConfiguration()

        if canPlay {
            activePlaybackEngine.seek(to: preservedTime)
        }
        currentTime = preservedTime
        refreshProjectModifiedState()
    }

    func undoLastEdit() {
        undoManager?.undo()
        refreshUndoAvailability()
    }

    func redoLastEdit() {
        undoManager?.redo()
        refreshUndoAvailability()
    }

    func showVideoWindow() {
        guard canShowVideoWindow else { return }
        videoFollower.showWindow(
            at: currentTime,
            isPlaying: playbackState == .playing,
            rate: playbackRate
        )
    }

    func play() {
        guard canPlay else { return }

        do {
            try activePlaybackEngine.play()
            videoFollower.play(rate: playbackRate)
            playbackState = .playing
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard canPlay else { return }
        activePlaybackEngine.pause()
        videoFollower.pause()
        currentTime = activePlaybackEngine.currentTime
        playbackState = .paused
    }

    func stop() {
        guard canPlay else { return }
        activePlaybackEngine.stop()
        videoFollower.stop()
        currentTime = 0
        playbackState = .stopped
    }

    func togglePlayPause() {
        guard canPlay else { return }

        if playbackState == .playing {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        guard canPlay else { return }
        let targetTime = snappedTimelineTime(time)
        activePlaybackEngine.seek(to: targetTime)
        videoFollower.seek(to: targetTime)
        currentTime = targetTime
    }

    func seekToStart() {
        seekExactly(to: 0)
    }

    func seekToEnd() {
        guard canPlay else { return }

        if playbackState == .playing {
            activePlaybackEngine.pause()
            playbackState = .paused
        }

        seekExactly(to: duration)
    }

    func setLooping(_ isEnabled: Bool) {
        performUndoableEdit("Toggle Loop") {
            isLooping = isEnabled
            applyLoopConfiguration()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        performUndoableEdit("Change Speed") {
            playbackRate = min(1, max(0.25, rate))
            playbackEngine.setPlaybackRate(playbackRate)
            videoFollower.setPlaybackRate(playbackRate)
        }
    }

    func resetPlaybackRateToDefault() {
        setPlaybackRate(AppSliderDefaults.playbackRate)
    }

    func setPitchShift(semitones: Float) {
        performUndoableEdit("Change Pitch") {
            pitchShiftSemitones = min(12, max(-12, semitones))
            playbackEngine.setPitchShift(semitones: pitchShiftSemitones)
        }
    }

    func resetPitchShiftToDefault() {
        setPitchShift(semitones: AppSliderDefaults.pitchShiftSemitones)
    }

    func setTempoBPM(_ bpm: Double) {
        performUndoableEdit("Change Tempo") {
            tempoBPM = ProjectStateNormalizer.normalizedTempo(bpm)
            beatGridSettings.bpm = tempoBPM
            beatGridSettings.lastChangedAt = Date()
            shouldAcceptAnalyzedTempo = false
            playbackEngine.setClickSettings(beatGridSettings)
        }
    }

    func setTimeSignature(beatsPerBar: Int, beatUnit: Int) {
        performUndoableEdit("Change Time Signature") {
            beatGridSettings.timeSignature = TimeSignature(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
            beatGridSettings.lastChangedAt = Date()
            shouldAcceptAnalyzedTempo = false
            playbackEngine.setClickSettings(beatGridSettings)
        }
    }

    func setCurrentTimeAsBeatOne() {
        performUndoableEdit("Set Beat 1") {
            setFirstBeatTime(currentTime, source: .manual)
        }
    }

    func resetBeatGridAlignment() {
        performUndoableEdit("Reset Beat Grid") {
            setFirstBeatTime(beatGridSettings.automaticFirstBeatTime, source: .automatic)
        }
    }

    func nudgeBeatGrid(by delta: TimeInterval) {
        performUndoableEdit("Nudge Beat Grid") {
            setFirstBeatTime(beatGridSettings.firstBeatTime + delta, source: .manual)
        }
    }

    func toggleClick() {
        setClickEnabled(!isClickEnabled)
    }

    func setClickEnabled(_ isEnabled: Bool) {
        performUndoableEdit("Toggle Click") {
            isClickEnabled = isEnabled && canPlay && beatGridSettings.bpm != nil
            playbackEngine.setClickSettings(beatGridSettings)
            playbackEngine.setClickEnabled(isClickEnabled)
        }
    }

    func setClickVolume(_ volume: Float) {
        performUndoableEdit("Change Click Volume") {
            applyClickVolume(volume, shouldPersist: false)
        }
    }

    func resetClickVolumeToDefault() {
        performUndoableEdit("Reset Click Volume") {
            applyClickVolume(AppSliderDefaults.clickVolume, shouldPersist: false)
        }
    }

    private func applyClickVolume(_ volume: Float, shouldPersist: Bool) {
        clickVolume = min(1, max(0, volume))
        playbackEngine.setClickVolume(clickVolume)
        guard shouldPersist else { return }
        UserDefaults.standard.set(clickVolume, forKey: "metronome.volume")
    }

    func setMainTrackVolume(_ volume: Float) {
        performUndoableEdit("Change Main Volume") {
            mainTrackVolume = min(1, max(0, volume))
            playbackEngine.setMainVolume(mainTrackVolume)
        }
    }

    func resetMainTrackVolumeToDefault() {
        setMainTrackVolume(AppSliderDefaults.mainTrackVolume)
    }

    func toggleLooping() {
        setLooping(!isLooping)
    }

    func toggleSnap() {
        performUndoableEdit("Toggle Snap") {
            isSnapEnabled.toggle()
        }
    }

    func separateStems() {
        guard let importedFile else {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(StemSeparationError.missingAudioFile.localizedDescription),
                progress: nil,
                status: StemSeparationError.missingAudioFile.localizedDescription
            )
            return
        }

        guard stemSeparationTask == nil else { return }

        clearStemPeakforms()

        stemSeparationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let metadata = try await stemSeparationService.separate(
                    audioURL: importedFile.url,
                    originalDuration: importedFile.duration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.stemSeparationState = StemSeparationViewState(
                            phase: progress.phase,
                            progress: progress.progress,
                            status: progress.status
                        )
                    }
                }

                guard !Task.isCancelled else { throw StemSeparationError.cancelled }
                let persistedMetadata = try persistStemArtifactsIfNeeded(metadata)
                registerStemMetadata(persistedMetadata)
                refreshProjectModifiedState()
                stemSeparationTask = nil
            } catch {
                let message = error.localizedDescription
                let diagnostics = (error as? StemSeparationError)?.diagnostics
                stemSeparationState = StemSeparationViewState(
                    phase: error is CancellationError ? .cancelled : .failed(message),
                    progress: nil,
                    status: message,
                    diagnostics: diagnostics
                )
                if !(error is CancellationError) {
                    errorMessage = message
                }
                stemSeparationTask = nil
            }
        }
    }

    func cancelStemSeparation() {
        stemSeparationTask?.cancel()
        stemSeparationTask = nil
        clearStemPeakforms()
        stemSeparationService.cancel()
        stemSeparationState = StemSeparationViewState(
            phase: .cancelled,
            progress: nil,
            status: "Stem separation cancelled"
        )
    }

    func retryStemSeparation() {
        separateStems()
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        let targetMode: PlaybackMode = mode == .stems && !canUseStemsPlayback ? .original : mode

        performUndoableEdit("Change Playback Mode") {
            guard targetMode != playbackMode else { return }

            let wasPlaying = playbackState == .playing
            let preservedTime = currentTime
            activePlaybackEngine.pause()

            do {
                playbackMode = targetMode
                if targetMode == .stems {
                    try loadStemPlaybackEngine()
                } else if let importedFile {
                    try configurePlayer(with: importedFile)
                    playbackEngine.seek(to: preservedTime)
                }
            } catch {
                let switchError = error
                playbackMode = .original
                do {
                    if let importedFile {
                        try configurePlayer(with: importedFile)
                        playbackEngine.seek(to: preservedTime)
                    }
                } catch let restoreError {
                    errorMessage = "Playback mode switch failed: \(restoreError.localizedDescription)"
                    return
                }
                errorMessage = "Playback mode switch failed: \(switchError.localizedDescription)"
                return
            }

            activePlaybackEngine.seek(to: preservedTime)
            currentTime = preservedTime

            if wasPlaying {
                play()
            }
        }
    }

    func togglePlaybackMode() {
        guard canUseStemsPlayback else {
            setPlaybackMode(.original)
            return
        }

        setPlaybackMode(playbackMode == .stems ? .original : .stems)
    }

    func setStemVolume(_ type: StemType, volume: Float) {
        performUndoableEdit("Change Stem Volume") {
            stemMixState.update(type) { item in
                item.volume = volume
            }
            playbackEngine.applyMix(stemMixState)
        }
    }

    func resetStemVolumeToDefault(_ type: StemType) {
        setStemVolume(type, volume: AppSliderDefaults.stemTrackVolume)
    }

    func toggleStemMute(_ type: StemType) {
        performUndoableEdit("Toggle Stem Mute") {
            stemMixState.update(type) { item in
                item.isMuted.toggle()
            }
            playbackEngine.applyMix(stemMixState)
        }
    }

    func toggleStemSolo(_ type: StemType) {
        performUndoableEdit("Toggle Stem Solo") {
            stemMixState.update(type) { item in
                item.isSoloed.toggle()
            }
            playbackEngine.applyMix(stemMixState)
        }
    }

    func setLoopStartAtCurrentTime() {
        updateLoopStart(currentTime)
    }

    func setLoopEndAtCurrentTime() {
        updateLoopEnd(currentTime)
    }

    func addNoteAtCurrentTime() {
        addNote(at: currentTime)
    }

    func addNote(at time: TimeInterval) {
        performUndoableEdit("Add Marker") {
            guard duration > 0 else { return }

            let clampedTime = snappedTimelineTime(time)
            let note = TimecodedNote(
                time: clampedTime,
                title: "Marker \(notes.count + 1)"
            )
            notes.append(note)
            notes.sort { $0.time < $1.time }
        }
    }

    func saveCurrentLoopRegionAsRegion() {
        performUndoableEdit("Add Region") {
            guard duration > 0, loopRegion.end > loopRegion.start else { return }

            let regionCount = notes.filter(\.isRegion).count
            let note = TimecodedNote(
                kind: .region,
                time: loopRegion.start,
                duration: loopRegion.duration,
                title: "Region \(regionCount + 1)"
            )
            notes.append(note)
            selectedRegionID = note.id
            activeLoopRegionID = nil
            notes.sort { $0.time < $1.time }
        }
    }

    func seek(to note: TimecodedNote) {
        if note.isRegion {
            activateRegionAsLoop(id: note.id, shouldSeek: true)
            return
        }

        seek(to: note.time)
    }

    func selectRegion(id: TimecodedNote.ID?, shouldSeek: Bool = false) {
        guard let id else {
            selectedRegionID = nil
            return
        }

        guard let note = notes.first(where: { $0.id == id && $0.isRegion }) else { return }

        selectedRegionID = id

        if shouldSeek {
            seek(to: note.time)
        }
    }

    func activateRegionAsLoop(id: TimecodedNote.ID, shouldSeek: Bool = false) {
        var seekTime: TimeInterval?
        performUndoableEdit("Activate Region Loop") {
            guard let note = notes.first(where: { $0.id == id && $0.isRegion }) else { return }

            selectedRegionID = id
            activeLoopRegionID = id
            loopRegion = LoopRegion(start: note.time, end: note.regionEndTime).clamped(to: duration)
            applyLoopConfiguration()
            seekTime = note.time
        }

        if shouldSeek, let seekTime {
            seek(to: seekTime)
        }
    }

    func focusRegion(id: TimecodedNote.ID) {
        guard notes.contains(where: { $0.id == id && $0.isRegion }) else { return }
        selectedRegionID = id
    }

    func updateRegionRange(id: TimecodedNote.ID, start: TimeInterval, end: TimeInterval) {
        performUndoableEdit("Edit Region") {
            guard let index = notes.firstIndex(where: { $0.id == id && $0.isRegion }) else { return }

            let snappedStart = snappedTimelineTime(start)
            let snappedEnd = snappedTimelineTime(end)
            let updatedRange = LoopRegion(start: snappedStart, end: snappedEnd)
                .clamped(to: duration, minimumLength: activeRangeMinimumLength)
            notes[index].kind = .region
            notes[index].time = updatedRange.start
            notes[index].duration = updatedRange.duration
            notes.sort { $0.time < $1.time }

            // Region editing is intentionally independent from the current loop range.
            // Double-click a region on the region track when it should become the active loop again.
            if activeLoopRegionID == id {
                activeLoopRegionID = nil
                applyLoopConfiguration()
            }
        }
    }

    func updateNoteTitle(id: TimecodedNote.ID, title: String) {
        performUndoableEdit("Rename Marker") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = notes[index].isRegion ? "Region" : "Marker"
            notes[index].title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
        }
    }

    func updateNoteColor(id: TimecodedNote.ID, color: MarkerColor) {
        performUndoableEdit("Change Marker Color") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].color = color
            notes[index].customColorHex = nil
        }
    }

    func updateNoteCustomColor(id: TimecodedNote.ID, hex: String) {
        performUndoableEdit("Change Marker Color") {
            guard
                let index = notes.firstIndex(where: { $0.id == id }),
                let normalizedHex = TimecodedNote.normalizedColorHex(hex)
            else { return }

            notes[index].customColorHex = normalizedHex
        }
    }

    func updateMarkerTime(id: TimecodedNote.ID, time: TimeInterval) {
        performUndoableEdit("Move Marker") {
            guard let index = notes.firstIndex(where: { $0.id == id && $0.isMarker }) else { return }

            notes[index].time = snappedTimelineTime(time)
            notes.sort { $0.time < $1.time }
        }
    }

    func deleteNote(id: TimecodedNote.ID) {
        performUndoableEdit("Delete Marker") {
            notes.removeAll { $0.id == id }

            if selectedRegionID == id {
                selectedRegionID = nil
            }

            if activeLoopRegionID == id {
                activeLoopRegionID = nil
                applyLoopConfiguration()
            }
        }
    }

    func updateLoopStart(_ start: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let maximumStart = max(0, loopRegion.end - minimumLength)
            let snappedStart = snappedTimelineTime(start)
            loopRegion.start = min(max(0, snappedStart), maximumStart)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopEnd(_ end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let minimumEnd = min(duration, loopRegion.start + minimumLength)
            let snappedEnd = snappedTimelineTime(end)
            loopRegion.end = max(min(snappedEnd, duration), minimumEnd)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopRegion(start: TimeInterval, end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let snappedStart = snappedTimelineTime(start)
            let snappedEnd = snappedTimelineTime(end)
            let lower = max(0, min(snappedStart, snappedEnd))
            let upper = min(duration, max(snappedStart, snappedEnd))
            loopRegion = LoopRegion(start: lower, end: upper).clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func zoomInTimeline() {
        timelineVisibleRange = timelineViewport
            .zoomed(to: currentTimelineWindowLength * 0.5, centeredAt: preferredZoomCenter)
            .clampedRange
    }

    func zoomOutTimeline() {
        timelineVisibleRange = timelineViewport
            .zoomed(to: currentTimelineWindowLength * 2, centeredAt: preferredZoomCenter)
            .clampedRange
    }

    func setTimelineVisibleRange(_ range: ClosedRange<TimeInterval>) {
        timelineVisibleRange = TimelineViewport(duration: duration, visibleRange: range).clampedRange
    }

    func panTimelineLeft() {
        panTimeline(by: -currentTimelineWindowLength * 0.35)
    }

    func panTimelineRight() {
        panTimeline(by: currentTimelineWindowLength * 0.35)
    }

    func handleTimelineScroll(deltaX: Double, deltaY: Double, anchorTime: TimeInterval?) {
        guard duration > 0 else { return }

        if abs(deltaY) > 0.01 {
            let zoomFactor = min(1.18, max(0.84, exp(-deltaY * 0.012)))
            timelineVisibleRange = timelineViewport
                .zoomed(to: currentTimelineWindowLength * zoomFactor, anchoredAt: anchorTime ?? preferredZoomCenter)
                .clampedRange
        }

        if abs(deltaX) > 0.01 {
            let visibleLength = min(currentTimelineWindowLength, duration)
            let panDelta = deltaX * visibleLength * 0.0025
            panTimeline(by: panDelta)
        }
    }

    func startPlaybackClock() {
        guard clockTask == nil else { return }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPlaybackPosition()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    func stopPlaybackClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func performUndoableEdit(_ actionName: String, edit: () -> Void) {
        let previousState = editableState
        edit()

        if editableState != previousState {
            registerUndoState(previousState, actionName: actionName)
        }
        refreshProjectModifiedState()
    }

    private func registerUndoState(_ state: ProjectEditableState, actionName: String) {
        guard !isRestoringUndoState, let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { target in
            let redoState = target.editableState
            target.restoreEditableState(state)
            target.registerUndoState(redoState, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        refreshUndoAvailability()
    }

    private func clearUndoHistory() {
        undoManager?.removeAllActions(withTarget: self)
        refreshUndoAvailability()
    }

    private func refreshUndoAvailability() {
        undoStateRevision += 1
    }

    private func markProjectClean() {
        lastSavedProjectState = persistedEditableState
        refreshProjectModifiedState()
    }

    private func refreshProjectModifiedState() {
        isProjectModified = persistedEditableState != lastSavedProjectState
    }

    private func availableRegionID(_ id: TimecodedNote.ID?) -> TimecodedNote.ID? {
        guard let id, notes.contains(where: { $0.id == id && $0.isRegion }) else { return nil }
        return id
    }

    private func clampedVolume(_ volume: Float) -> Float {
        guard volume.isFinite else { return AppSliderDefaults.mainTrackVolume }
        return min(1, max(0, volume))
    }

    private func restorePlaybackMode(_ mode: PlaybackMode, preservedTime: TimeInterval) {
        let targetMode: PlaybackMode = mode == .stems && canUseStemsPlayback ? .stems : .original
        guard targetMode != playbackMode else { return }

        let wasPlaying = playbackState == .playing
        activePlaybackEngine.pause()

        do {
            playbackMode = targetMode
            if targetMode == .stems {
                try loadStemPlaybackEngine()
            } else if let importedFile {
                try configurePlayer(with: importedFile)
            }

            if canPlay {
                activePlaybackEngine.seek(to: preservedTime)
            }
            currentTime = preservedTime

            if wasPlaying {
                play()
            }
        } catch {
            playbackMode = .original
            errorMessage = "Playback mode restore failed: \(error.localizedDescription)"
        }
    }

    private func configurePlayer(with file: ImportedAudioFile) throws {
        try playbackEngine.load(url: file.url)
        applyPlaybackConfiguration()
    }

    private func applyPlaybackConfiguration() {
        playbackEngine.setPlaybackRate(playbackRate)
        videoFollower.setPlaybackRate(playbackRate)
        playbackEngine.setPitchShift(semitones: pitchShiftSemitones)
        playbackEngine.setMainVolume(mainTrackVolume)
        playbackEngine.setClickVolume(clickVolume)
        playbackEngine.setClickSettings(beatGridSettings)
        playbackEngine.setClickSoundSettings(appSettingsStore.clickSoundSettings)
        playbackEngine.setClickEnabled(isClickEnabled && beatGridSettings.bpm != nil)
        applyAudioOutputDeviceSetting(appSettingsStore.audioDeviceSettings.outputDeviceUID)
        applyLoopConfiguration()
    }

    private func applyAudioOutputDeviceSetting(_ outputDeviceUID: String?) {
        do {
            try playbackEngine.setAudioOutputDevice(uid: outputDeviceUID)
        } catch {
            errorMessage = "Audio output device failed: \(error.localizedDescription)"
        }
    }

    private func registerStemMetadata(_ metadata: StemCacheMetadata) {
        stemCacheMetadata = metadata
        stemFiles = metadata.stems
        stemMixState.setAvailability(from: metadata.stems)
        buildStemPeakforms(for: metadata.stems)
        stemSeparationState = StemSeparationViewState(
            phase: .completed,
            progress: 1,
            status: "Stems ready"
        )

        if playbackMode == .stems {
            do {
                try loadStemPlaybackEngine()
            } catch {
                playbackMode = .original
                errorMessage = "Stem playback failed: \(error.localizedDescription)"
            }
        }
    }

    private func restoreCachedStems(
        for audioURL: URL,
        preferredMixState: StemMixState? = nil,
        preferredPlaybackMode: PlaybackMode = .original
    ) -> Bool {
        do {
            guard let metadata = try stemSeparationService.cachedResult(for: audioURL) else {
                return false
            }

            if let preferredMixState {
                stemMixState = preferredMixState
            }

            if preferredPlaybackMode == .stems {
                playbackMode = .stems
            }
            registerStemMetadata(metadata)

            return true
        } catch {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(error.localizedDescription),
                progress: nil,
                status: "Stems unavailable: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func loadStemPlaybackEngine() throws {
        guard !stemFiles.isEmpty else { return }

        try playbackEngine.load(stems: stemFiles, mixState: stemMixState)
        applyPlaybackConfiguration()
        playbackEngine.seek(to: currentTime)
    }

    private func restoreStemState(_ projectStemState: StemProjectState?, audioURL: URL, projectURL: URL?) {
        resetStemState(mixState: projectStemState?.mixState ?? StemMixState())

        if let projectURL, projectStemState != nil {
            do {
                let currentFingerprint = try? stemSeparationService.sourceFingerprint(for: audioURL)
                if let metadata = try projectArtifactStore.readStemMetadata(
                    projectURL: projectURL,
                    expectedFingerprint: currentFingerprint,
                    fallbackFingerprint: projectStemState?.sourceFingerprint
                ) {
                    if projectStemState?.playbackMode == .stems {
                        playbackMode = .stems
                    }
                    registerStemMetadata(metadata)
                    return
                }
            } catch {
                stemSeparationState = StemSeparationViewState(
                    phase: .failed(error.localizedDescription),
                    progress: nil,
                    status: "Stems unavailable: \(error.localizedDescription)"
                )
            }
        }

        guard
            let projectStemState,
            let cacheKey = projectStemState.cacheKey,
            let fingerprint = projectStemState.sourceFingerprint
        else {
            if !restoreCachedStems(
                for: audioURL,
                preferredMixState: projectStemState?.mixState,
                preferredPlaybackMode: projectStemState?.playbackMode ?? .original
            ) {
                stemSeparationState = StemSeparationViewState()
            }
            return
        }

        do {
            let currentFingerprint = try stemSeparationService.sourceFingerprint(for: audioURL)
            guard currentFingerprint == fingerprint else {
                if !restoreCachedStems(
                    for: audioURL,
                    preferredMixState: projectStemState.mixState,
                    preferredPlaybackMode: projectStemState.playbackMode
                ) {
                    stemSeparationState = StemSeparationViewState(
                        phase: .failed("Source audio changed"),
                        progress: nil,
                        status: "Stems unavailable: source audio changed"
                    )
                }
                return
            }

            guard let metadata = try stemSeparationService.cachedResult(cacheKey: cacheKey, expectedFingerprint: fingerprint) else {
                if !restoreCachedStems(
                    for: audioURL,
                    preferredMixState: projectStemState.mixState,
                    preferredPlaybackMode: projectStemState.playbackMode
                ) {
                    stemSeparationState = StemSeparationViewState(
                        phase: .failed("Stem cache missing"),
                        progress: nil,
                        status: "Stems unavailable: cache missing"
                    )
                }
                return
            }

            stemFiles = metadata.stems
            stemCacheMetadata = metadata
            stemMixState.setAvailability(from: metadata.stems)
            buildStemPeakforms(for: metadata.stems)
            if projectStemState.playbackMode == .stems {
                playbackMode = .stems
            }
            stemSeparationState = StemSeparationViewState(
                phase: .completed,
                progress: 1,
                status: "Stems ready"
            )
            if playbackMode == .stems {
                try loadStemPlaybackEngine()
            }
        } catch {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(error.localizedDescription),
                progress: nil,
                status: "Stems unavailable: \(error.localizedDescription)"
            )
        }
    }

    private func makeStemProjectState() -> StemProjectState? {
        guard !stemFiles.isEmpty, let stemCacheMetadata else {
            return StemProjectState(playbackMode: .original, mixState: stemMixState)
        }

        return StemProjectState(
            cacheKey: stemCacheMetadata.cacheKey,
            sourceFingerprint: stemCacheMetadata.sourceFingerprint,
            backendIdentifier: stemCacheMetadata.backendIdentifier,
            modelName: stemCacheMetadata.modelName,
            settingsVersion: stemCacheMetadata.settingsVersion,
            playbackMode: playbackMode,
            mixState: stemMixState
        )
    }

    func loadImportedAudio(_ file: ImportedAudioFile) throws {
        playbackEngine.stop()
        videoFollower.stop()
        cancelBackgroundWork()

        beginSecurityScopedAccess(for: file.sourceMediaURL)
        do {
            try configurePlayer(with: file)
        } catch {
            endSecurityScopedAccess()
            throw error
        }

        importedFile = file
        videoFollower.load(videoURL: file.videoURL)
        currentProjectURL = nil
        duration = file.duration
        currentTime = 0
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM).clamped(to: file.duration)
        shouldAcceptAnalyzedTempo = true
        notes = []
        selectedRegionID = nil
        activeLoopRegionID = nil
        loopRegion = LoopRegion(start: 0, end: file.duration).clamped(to: file.duration)
        timelineVisibleRange = 0...file.duration
        playbackState = .stopped
        resetStemState()
        isImporting = false
        clearUndoHistory()

        _ = restoreCachedStems(for: file.url)
        markProjectClean()

        buildPeakform(file: file)
        analyze(file: file)
    }

    private func openProject(at url: URL) async {
        errorMessage = nil
        isImporting = true
        var didAdoptProject = false

        do {
            beginProjectSecurityScopedAccess(for: url)
            let project = try projectService.load(from: url)
            if let artifactRootURL = try? project.resolvedArtifactRootURL() {
                beginProjectSecurityScopedAccess(for: artifactRootURL)
            }
            let projectDuration = ProjectStateNormalizer.normalizedDuration(project.audioDuration)
            guard projectDuration > 0 else {
                throw ProjectDocumentError.invalidProjectData("audio duration is missing or zero.")
            }

            let mediaKind = project.mediaKind ?? .audio
            let localVideoAudioURL = projectArtifactStore.existingVideoAudioURL(for: url)
            let mediaURL: URL?
            let mediaWarning: String?
            do {
                let resolvedMediaURL = try project.resolvedMediaURL()
                beginSecurityScopedAccess(for: resolvedMediaURL)
                mediaURL = resolvedMediaURL
                mediaWarning = nil
            } catch {
                guard mediaKind == .video, localVideoAudioURL != nil else {
                    throw error
                }
                mediaURL = nil
                mediaWarning = "Video source is unavailable; opened saved project audio only."
            }

            playbackEngine.stop()
            videoFollower.stop()
            playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(project.playbackRate)
            pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(project.pitchShiftSemitones)
            mainTrackVolume = clampedVolume(project.mainTrackVolume ?? AppSliderDefaults.mainTrackVolume)
            clickVolume = clampedVolume(project.clickVolume ?? AppSliderDefaults.clickVolume)
            isSnapEnabled = project.isSnapEnabled ?? false
            let storedProjectTempo = ProjectStateNormalizer.normalizedTempo(project.beatGridSettings?.bpm ?? project.tempoBPM)
            let shouldAnalyzeTempo = storedProjectTempo == nil
            beatGridSettings = ProjectStateNormalizer.normalizedBeatGridSettings(
                projectSettings: project.beatGridSettings,
                legacyTempoBPM: project.tempoBPM,
                duration: projectDuration
            )
            if beatGridSettings.bpm == nil {
                beatGridSettings.bpm = AppDefaults.defaultTempoBPM
            }
            tempoBPM = beatGridSettings.bpm
            beatGridSettings.bpm = tempoBPM
            shouldAcceptAnalyzedTempo = shouldAnalyzeTempo
            isClickEnabled = (project.isClickEnabled ?? false) && beatGridSettings.bpm != nil
            let restoredPlaybackMode = project.playbackMode ?? project.stemState?.playbackMode ?? .original
            let file: ImportedAudioFile
            switch mediaKind {
            case .audio:
                guard let mediaURL else {
                    throw ProjectDocumentError.invalidProjectData("audio file is missing.")
                }
                file = ImportedAudioFile(
                    url: mediaURL,
                    displayName: project.audioDisplayName,
                    duration: projectDuration
                )
            case .video:
                if let localVideoAudioURL,
                   let localDuration = try? AudioFileImporter.decodedDuration(for: localVideoAudioURL) {
                    file = ImportedAudioFile(
                        url: localVideoAudioURL,
                        sourceMediaURL: mediaURL ?? localVideoAudioURL,
                        displayName: project.audioDisplayName,
                        duration: localDuration,
                        mediaKind: mediaURL == nil ? .audio : .video
                    )
                } else {
                    guard let mediaURL else {
                        throw ProjectDocumentError.invalidProjectData("video source is missing.")
                    }
                    let importedVideo = try await importer.importFile(from: mediaURL)
                    file = ImportedAudioFile(
                        url: importedVideo.url,
                        sourceMediaURL: mediaURL,
                        displayName: project.audioDisplayName,
                        duration: importedVideo.duration,
                        mediaKind: .video
                    )
                }
            }
            let resolvedProjectDuration = ProjectStateNormalizer.normalizedDuration(file.duration)
            guard resolvedProjectDuration > 0 else {
                throw ProjectDocumentError.invalidProjectData("audio duration is missing or zero.")
            }
            beatGridSettings = beatGridSettings.clamped(to: resolvedProjectDuration)
            beatGridSettings.bpm = tempoBPM
            try configurePlayer(with: file)

            importedFile = file
            videoFollower.load(videoURL: file.videoURL)
            currentProjectURL = url
            didAdoptProject = true
            duration = resolvedProjectDuration
            currentTime = 0
            notes = ProjectStateNormalizer.normalizedNotes(project.notes, duration: resolvedProjectDuration)
            selectedRegionID = nil
            activeLoopRegionID = nil
            loopRegion = ProjectStateNormalizer.normalizedLoopRegion(
                start: project.loopStart,
                end: project.loopEnd,
                duration: resolvedProjectDuration
            )
            isLooping = project.isLoopEnabled ?? false
            applyLoopConfiguration()
            timelineVisibleRange = 0...resolvedProjectDuration
            playbackState = .stopped
            restoreStemState(project.stemState, audioURL: file.url, projectURL: url)
            restorePlaybackMode(restoredPlaybackMode, preservedTime: currentTime)
            isImporting = false
            clearUndoHistory()
            markProjectClean()
            if let mediaWarning {
                errorMessage = mediaWarning
            }

            addRecentProject(url: url)
            buildPeakform(file: file)
            analyze(file: file, includesTempo: shouldAcceptAnalyzedTempo)
        } catch {
            isImporting = false
            if !didAdoptProject {
                endSecurityScopedAccess()
                endProjectSecurityScopedAccess()
            }
            errorMessage = "Project open failed: \(error.localizedDescription)"
        }
    }

    private func cancelBackgroundWork() {
        analysisTask?.cancel()
        analysisTask = nil
        waveformTask?.cancel()
        waveformTask = nil
        stemSeparationTask?.cancel()
        stemSeparationTask = nil
        stemPeakformTask?.cancel()
        stemPeakformTask = nil
        stemSeparationService.cancel()
    }

    private func resetStemState(mixState: StemMixState = StemMixState()) {
        playbackMode = .original
        stemFiles = []
        clearStemPeakforms()
        stemMixState = mixState
        stemSeparationState = StemSeparationViewState()
        stemCacheMetadata = nil
    }

    private func saveProject(to url: URL) async -> Bool {
        errorMessage = nil

        do {
            guard ensureProjectArtifactAccess(for: url) else {
                throw ProjectDocumentError.projectArtifactAccessDenied
            }
            let persistenceResult = try await prepareProjectArtifacts(to: url)
            let previousImportedFile = importedFile

            if let persistedFile = persistenceResult.importedFile {
                importedFile = persistedFile
            }

            do {
                let project = try makeProject(projectURL: url)
                try projectService.save(project, to: url)
            } catch {
                importedFile = previousImportedFile
                throw error
            }

            currentProjectURL = url
            await applyProjectArtifactPersistence(persistenceResult)
            addRecentProject(url: url)
            markProjectClean()
            return true
        } catch {
            errorMessage = "Project save failed: \(error.localizedDescription)"
            return false
        }
    }

    private struct ProjectArtifactPersistenceResult {
        var importedFile: ImportedAudioFile?
        var temporaryVideoAudioURLToRemove: URL?
        var peakformURLsToRemove: [URL] = []
        var stemMetadata: StemCacheMetadata?
        var stemCacheKeyToRemove: String?
    }

    private func prepareProjectArtifacts(to projectURL: URL) async throws -> ProjectArtifactPersistenceResult {
        guard var file = importedFile else {
            throw ProjectDocumentError.missingAudioFile
        }

        var result = ProjectArtifactPersistenceResult()
        try projectArtifactStore.ensureArtifactRoot(for: projectURL)
        try projectArtifactStore.ensureArtifactDirectories(for: projectURL)
        let previousAudioURL = file.url
        file = try projectArtifactStore.persistVideoAudioIfNeeded(file, projectURL: projectURL)
        if file.url != previousAudioURL {
            result.importedFile = file
            result.temporaryVideoAudioURLToRemove = previousAudioURL
        }

        if let peakformData {
            try projectArtifactStore.writeMainPeakform(peakformData, projectURL: projectURL)
            result.peakformURLsToRemove.append(previousAudioURL)
        }

        if !stemPeakforms.isEmpty {
            try projectArtifactStore.writeStemPeakforms(stemPeakforms, projectURL: projectURL)
            result.peakformURLsToRemove.append(contentsOf: stemFiles.map(\.url))
        }

        if let metadata = stemCacheMetadata {
            let localMetadata = try projectArtifactStore.writeStemMetadata(metadata, projectURL: projectURL)
            result.stemMetadata = localMetadata
            result.stemCacheKeyToRemove = localMetadata.cacheKey
        }

        return result
    }

    private func applyProjectArtifactPersistence(_ result: ProjectArtifactPersistenceResult) async {
        if let oldURL = result.temporaryVideoAudioURLToRemove,
           let persistedURL = result.importedFile?.url {
            removeTemporaryVideoAudioIfNeeded(oldURL, persistedURL: persistedURL)
        }

        for url in result.peakformURLsToRemove {
            await peakformProvider.removeCachedPeakform(for: url)
        }

        if let metadata = result.stemMetadata {
            stemCacheMetadata = metadata
            stemFiles = metadata.stems
            stemMixState.setAvailability(from: metadata.stems)
        }

        if let cacheKey = result.stemCacheKeyToRemove {
            stemSeparationService.removeCachedResult(cacheKey: cacheKey)
        }
    }

    private func makeProject(projectURL: URL) throws -> JammLabProject {
        guard let importedFile else {
            throw ProjectDocumentError.missingAudioFile
        }
        let artifactRootURL = projectArtifactStore.artifactRoot(for: projectURL)

        return JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: importedFile.sourceMediaURL),
            artifactRootBookmarkData: try? projectService.bookmarkData(for: artifactRootURL),
            audioDisplayName: importedFile.displayName,
            audioDuration: duration,
            mediaKind: importedFile.mediaKind,
            notes: ProjectStateNormalizer.normalizedNotes(notes, duration: duration),
            loopStart: loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength).start,
            loopEnd: loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength).end,
            isLoopEnabled: isLooping,
            playbackRate: playbackRate,
            pitchShiftSemitones: pitchShiftSemitones,
            tempoBPM: tempoBPM,
            beatGridSettings: beatGridSettings.clamped(to: duration),
            mainTrackVolume: mainTrackVolume,
            isClickEnabled: isClickEnabled,
            clickVolume: clickVolume,
            isSnapEnabled: isSnapEnabled,
            playbackMode: playbackMode,
            stemState: makeStemProjectState()
        )
    }

    private func defaultProjectFilename() -> String {
        let baseName = (importedFile?.displayName as NSString?)?.deletingPathExtension ?? "JammLab Project"

        return "\(baseName).\(ProjectDocumentService.fileExtension)"
    }

    private func addRecentProject(url: URL) {
        guard let bookmarkData = try? projectService.bookmarkData(for: url) else { return }
        recentProjectsStore.addProject(url: url, bookmarkData: bookmarkData)
    }

    private func beginSecurityScopedAccess(for url: URL) {
        endSecurityScopedAccess()
        hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        securityScopedURL = hasSecurityScopedAccess ? url : nil
    }

    private func endSecurityScopedAccess() {
        if hasSecurityScopedAccess {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }

        securityScopedURL = nil
        hasSecurityScopedAccess = false
    }

    @discardableResult
    private func beginProjectSecurityScopedAccess(for url: URL) -> Bool {
        endProjectSecurityScopedAccess()
        hasProjectSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        projectSecurityScopedURL = hasProjectSecurityScopedAccess ? url : nil
        return hasProjectSecurityScopedAccess
    }

    private func endProjectSecurityScopedAccess() {
        if hasProjectSecurityScopedAccess {
            projectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }

        projectSecurityScopedURL = nil
        hasProjectSecurityScopedAccess = false
    }

    private func ensureProjectArtifactAccess(for projectURL: URL) -> Bool {
        guard isSandboxed() else { return true }

        let artifactRootURL = projectArtifactStore.artifactRoot(for: projectURL).standardizedFileURL
        if hasProjectSecurityScopedAccess,
           projectSecurityScopedURL?.standardizedFileURL == artifactRootURL {
            return true
        }

        return beginProjectSecurityScopedAccess(for: artifactRootURL)
    }

    private func analyze(file: ImportedAudioFile, includesTempo: Bool = true) {
        analysisTask?.cancel()
        isAnalyzing = true
        analysisResult = nil

        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await analyzer.analyze(url: file.url, includesTempo: includesTempo)
                guard !Task.isCancelled else { return }
                analysisResult = result
                if includesTempo, shouldAcceptAnalyzedTempo, let analyzedBPM = result.bpm {
                    tempoBPM = Double(analyzedBPM)
                    beatGridSettings.bpm = tempoBPM
                    beatGridSettings.automaticFirstBeatTime = 0
                    beatGridSettings.firstBeatTime = 0
                    beatGridSettings.alignmentSource = .automatic
                    beatGridSettings.lastChangedAt = Date()
                    playbackEngine.setClickSettings(beatGridSettings)
                    playbackEngine.setClickEnabled(isClickEnabled && beatGridSettings.bpm != nil)
                    if !isProjectModified {
                        markProjectClean()
                    } else {
                        refreshProjectModifiedState()
                    }
                }
                isAnalyzing = false
            } catch {
                guard !Task.isCancelled else { return }
                isAnalyzing = false
                errorMessage = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    private func persistStemArtifactsIfNeeded(_ metadata: StemCacheMetadata) throws -> StemCacheMetadata {
        guard let currentProjectURL else { return metadata }
        let localMetadata = try projectArtifactStore.writeStemMetadata(metadata, projectURL: currentProjectURL)
        stemSeparationService.removeCachedResult(cacheKey: metadata.cacheKey)
        return localMetadata
    }

    private func removeTemporaryVideoAudioIfNeeded(_ oldURL: URL, persistedURL: URL) {
        guard oldURL != persistedURL,
              oldURL.path.contains("/MediaCache/")
        else {
            return
        }

        try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
    }

    private func buildPeakform(file: ImportedAudioFile) {
        waveformTask?.cancel()
        isBuildingWaveform = true
        peakformData = nil

        if let currentProjectURL,
           let projectPeakform = try? projectArtifactStore.readMainPeakform(projectURL: currentProjectURL) {
            peakformData = projectPeakform
            isBuildingWaveform = false
            return
        }

        waveformTask = Task { [weak self] in
            guard let self else { return }

            do {
                let peakform = try await peakformProvider.peakform(for: file.url)
                guard !Task.isCancelled else { return }
                peakformData = peakform
                isBuildingWaveform = false
                if let currentProjectURL {
                    try? projectArtifactStore.writeMainPeakform(peakform, projectURL: currentProjectURL)
                    await peakformProvider.removeCachedPeakform(for: file.url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                isBuildingWaveform = false
                errorMessage = "Peakform failed: \(error.localizedDescription)"
            }
        }
    }

    private func clearStemPeakforms() {
        stemPeakformTask?.cancel()
        stemPeakformTask = nil
        stemPeakforms = [:]
        isBuildingStemPeakforms = false
    }

    private func buildStemPeakforms(for stems: [StemFile]) {
        stemPeakformTask?.cancel()
        stemPeakforms = [:]

        guard !stems.isEmpty else {
            isBuildingStemPeakforms = false
            return
        }

        isBuildingStemPeakforms = true

        stemPeakformTask = Task { [weak self] in
            guard let self else { return }

            var nextPeakforms: [StemType: PeakformData] = [:]
            var lastError: Error?

            for stem in stems {
                do {
                    let peakform: PeakformData
                    if let currentProjectURL,
                       let projectPeakform = try? projectArtifactStore.readStemPeakform(
                        type: stem.type,
                        projectURL: currentProjectURL
                       ) {
                        peakform = projectPeakform
                    } else {
                        peakform = try await peakformProvider.peakform(for: stem.url)
                        if let currentProjectURL {
                            try? projectArtifactStore.writeStemPeakforms([stem.type: peakform], projectURL: currentProjectURL)
                            await peakformProvider.removeCachedPeakform(for: stem.url)
                        }
                    }
                    guard !Task.isCancelled else { return }
                    nextPeakforms[stem.type] = peakform
                    stemPeakforms = nextPeakforms
                } catch {
                    guard !Task.isCancelled else { return }
                    lastError = error
                }
            }

            isBuildingStemPeakforms = false
            stemPeakformTask = nil

            if nextPeakforms.isEmpty, let lastError {
                errorMessage = "Stem peakform failed: \(lastError.localizedDescription)"
            }
        }
    }

    private func refreshPlaybackPosition() {
        guard canPlay else { return }

        currentTime = activePlaybackEngine.currentTime
        videoFollower.sync(to: currentTime, isPlaying: playbackState == .playing, rate: playbackRate)

        if playbackState == .playing, (!activePlaybackEngine.isPlaying || currentTime >= duration), currentTime >= duration - 0.02 {
            playbackState = .stopped
            currentTime = 0
            activePlaybackEngine.stop()
            videoFollower.stop()
        }
    }

    private func setFirstBeatTime(_ time: TimeInterval, source: BeatGridAlignmentSource) {
        guard duration > 0 else { return }

        beatGridSettings.firstBeatTime = max(0, min(time, duration))
        beatGridSettings.alignmentSource = source
        beatGridSettings.lastChangedAt = Date()
        playbackEngine.setClickSettings(beatGridSettings)
    }

    private func loopRegionContains(_ time: TimeInterval) -> Bool {
        time >= loopRegion.start && time <= loopRegion.end
    }

    private func applyLoopConfiguration() {
        playbackEngine.setLoop(enabled: isLooping, region: loopRegion)
    }

    private func seekExactly(to time: TimeInterval) {
        guard canPlay else { return }

        let targetTime = max(0, min(time, duration))
        activePlaybackEngine.seek(to: targetTime)
        videoFollower.seek(to: targetTime)
        currentTime = targetTime
    }

    private func snappedTimelineTime(_ time: TimeInterval) -> TimeInterval {
        let clampedTime = max(0, min(time, duration))
        guard
            isSnapEnabled,
            let snappedTime = BeatGridCalculator().nearestBeatTime(
                to: clampedTime,
                settings: beatGridSettings,
                duration: duration
            )
        else {
            return clampedTime
        }

        return snappedTime
    }

    private var activeRangeMinimumLength: TimeInterval {
        guard
            isSnapEnabled,
            let beatDuration = beatGridSettings.beatDuration,
            beatDuration > 0
        else {
            return LoopRegion.minimumLength
        }

        return beatDuration
    }

    private var currentTimelineWindowLength: TimeInterval {
        max(timelineViewport.visibleDuration, timelineViewport.minimumWindowLength)
    }

    private var preferredZoomCenter: TimeInterval {
        if currentTime >= timelineVisibleRange.lowerBound, currentTime <= timelineVisibleRange.upperBound {
            return currentTime
        }

        return (timelineVisibleRange.lowerBound + timelineVisibleRange.upperBound) / 2
    }

    private var minimumTimelineWindowLength: TimeInterval {
        timelineViewport.minimumWindowLength
    }

    private func panTimeline(by delta: TimeInterval) {
        timelineVisibleRange = timelineViewport.panned(by: delta).clampedRange
    }

    private var timelineViewport: TimelineViewport {
        TimelineViewport(duration: duration, visibleRange: timelineVisibleRange)
    }

    private var activePlaybackEngine: AudioPlaybackControlling {
        return playbackEngine
    }
}

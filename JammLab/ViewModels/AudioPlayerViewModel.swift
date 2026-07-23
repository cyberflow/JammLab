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

enum NotationEntryMode: Equatable {
    case note
    case rest
}

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published var importedFile: ImportedAudioFile?
    @Published var analysisResult: AnalysisResult?
    @Published var peakformData: PeakformData?
    @Published var playbackState: PlaybackState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var playbackMarkerTime: TimeInterval = 0
    @Published var playbackDisplayState: PlaybackDisplayState = .idle
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = AppSliderDefaults.playbackRate
    @Published var pitchShiftSemitones: Float = AppSliderDefaults.pitchShiftSemitones
    @Published var tempoBPM: Double? = AppDefaults.defaultTempoBPM
    @Published var beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
    @Published var notes: [TimecodedNote] = []
    @Published var harmonySymbols: [HarmonySymbol] = []
    @Published var projectKeySelection: ProjectKeySelection?
    @Published var selectedRegionID: TimecodedNote.ID?
    @Published var selectedHarmonySymbolID: HarmonySymbol.ID?
    @Published var selectedNotationMeasures: [NotationMeasureSelection] = []
    @Published var selectedNotationItem: NotationItemSelection?
    @Published var notationMeasureClipboard: NotationMeasureClipboard?
    @Published var notationDurationDenominator = NotationDuration.defaultDenominator
    @Published var notationEntryDurationIsDotted = false
    @Published var notationItems: [NotationMeasureItem] = []
    @Published var stemTranscriptionTracks: [StemTranscriptionTrack] = []
    @Published var notationPartClefs: [NotationPartID: Clef] = [:]
    @Published var selectedDrumInstrumentMIDINoteNumber = DrumInstrumentMap.defaultMIDINoteNumber
    @Published var notationEntryMode: NotationEntryMode?
    @Published var pendingNotationAccidental: NotationAccidental?
    @Published var pendingHarmonyEditorRequest: HarmonyEditorRequest?
    @Published var activeLoopRegionID: TimecodedNote.ID?
    @Published var loopRegion: LoopRegion = .empty
    @Published var timelineVisibleRange: ClosedRange<TimeInterval> = 0...0
    @Published var currentProjectURL: URL?
    @Published var isImporting = false
    @Published var isAnalyzing = false
    @Published var isBuildingWaveform = false
    @Published var playbackMode: PlaybackMode = .original
    @Published var stemFiles: [StemFile] = []
    @Published var stemPeakforms: [StemType: PeakformData] = [:]
    @Published var isBuildingStemPeakforms = false
    @Published var stemMixState = StemMixState()
    @Published var stemSeparationState = StemSeparationViewState()
    @Published var stemTranscriptionStates: [StemType: StemTranscriptionViewState] = [:]
    @Published var isLooping = false
    @Published var isClickEnabled = false
    @Published var isSnapEnabled = false
    @Published var isVideoWindowOpen = false
    @Published var isNotationTrackCollapsed = true
    @Published var stemNotationTrackCollapsed: [StemType: Bool] = [:]
    @Published var stemNoteDisplayModes: [StemType: StemNoteDisplayMode] = [:]
    @Published var visibleNotationPartIDs: Set<NotationPartID> = [.main]
    @Published var mainTrackVolume: Float = AppSliderDefaults.mainTrackVolume
    @Published var clickVolume: Float = AppSliderDefaults.clickVolume
    @Published var undoStateRevision = 0
    @Published var isProjectModified = false
    @Published var errorMessage: String?
    var preparedNotationNoteEditSession: NotationNoteEditPlanner.PreparedSession?
    weak var undoManager: UndoManager? {
        didSet {
            refreshUndoAvailability()
        }
    }

    // Module-scoped so same-module ViewModel extensions can own behavior without changing public API.
    let importer: AudioFileImporter
    let analyzer: AudioAnalyzing
    let peakformProvider: PeakformProvider
    let playbackEngine: AudioPlaybackControlling
    let videoFollower: VideoFollowerControlling
    let appSettingsStore: AppSettingsStore
    let stemSeparationService: StemSeparationService
    let stemTranscriptionService: StemTranscriptionService
    let projectService: ProjectDocumentService
    let projectArtifactStore: ProjectArtifactStore
    let projectPersistenceCoordinator: ProjectPersistenceCoordinator
    let notationExportService: NotationExportService
    let notationExportDocumentService: NotationExportDocumentService
    let notationNoteAuditioner: NotationNoteAuditioning
    let recentProjectsStore: RecentProjectsStore
    let isSandboxed: () -> Bool
    var clockTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var waveformTask: Task<Void, Never>?
    var notationMeasureSelectionAnchor: NotationMeasureSelection?
    var stemSeparationTask: Task<Void, Never>?
    var stemSeparationRunID: UUID?
    var stemPeakformTask: Task<Void, Never>?
    var stemTranscriptionTasks: [StemType: Task<Void, Never>] = [:]
    var stemTranscriptionOperations: [StemType: StemTranscriptionOperation] = [:]
    var stemTranscriptionRunIDs: [StemType: UUID] = [:]
    var stemCacheMetadata: StemCacheMetadata?
    var shouldAcceptAnalyzedTempo = true
    var securityScopedURL: URL?
    var hasSecurityScopedAccess = false
    var projectSecurityScopedURL: URL?
    var hasProjectSecurityScopedAccess = false
    var settingsCancellables: Set<AnyCancellable> = []
    var isRestoringUndoState = false
    var isRestoringVideoWindowState = false
    var userTimelineVisibleRange: ClosedRange<TimeInterval> = 0...0
    var lastSavedProjectState: ProjectPersistedEditableState?

    nonisolated private static func defaultSandboxDetection() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    var canPlay: Bool {
        activePlaybackEngine.isLoaded
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

    var canUndo: Bool {
        undoManager?.canUndo ?? false
    }

    var canRedo: Bool {
        undoManager?.canRedo ?? false
    }

    var effectiveKeyName: String? {
        projectKeySelection?.canonicalKeyName ?? analysisResult?.keyName
    }

    init(
        importer: AudioFileImporter = AudioFileImporter(),
        analyzer: AudioAnalyzing = AudioAnalyzer(),
        peakformProvider: PeakformProvider = CachedPeakformProvider(),
        playbackEngine: AudioPlaybackControlling? = nil,
        videoFollower: VideoFollowerControlling? = nil,
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        stemSeparationService: StemSeparationService? = nil,
        stemTranscriptionService: StemTranscriptionService = StemTranscriptionService(),
        projectService: ProjectDocumentService = ProjectDocumentService(),
        projectArtifactStore: ProjectArtifactStore = ProjectArtifactStore(),
        projectPersistenceCoordinator: ProjectPersistenceCoordinator? = nil,
        notationExportService: NotationExportService = NotationExportService(),
        notationExportDocumentService: NotationExportDocumentService = NotationExportDocumentService(),
        notationNoteAuditioner: NotationNoteAuditioning? = nil,
        recentProjectsStore: RecentProjectsStore? = nil,
        isSandboxed: @escaping () -> Bool = AudioPlayerViewModel.defaultSandboxDetection
    ) {
        let resolvedStemSeparationService = stemSeparationService ?? StemSeparationService(appSettingsStore: appSettingsStore)
        self.importer = importer
        self.analyzer = analyzer
        self.peakformProvider = peakformProvider
        self.playbackEngine = playbackEngine ?? MultiTrackAudioPlayer()
        self.videoFollower = videoFollower ?? VideoFollowerController()
        self.appSettingsStore = appSettingsStore
        self.stemSeparationService = resolvedStemSeparationService
        self.stemTranscriptionService = stemTranscriptionService
        self.projectService = projectService
        self.projectArtifactStore = projectArtifactStore
        self.projectPersistenceCoordinator = projectPersistenceCoordinator ?? ProjectPersistenceCoordinator(
            projectArtifactStore: projectArtifactStore,
            projectDocumentService: projectService,
            importer: importer,
            peakformProvider: peakformProvider,
            stemSeparationService: resolvedStemSeparationService
        )
        self.notationExportService = notationExportService
        self.notationExportDocumentService = notationExportDocumentService
        self.notationNoteAuditioner = notationNoteAuditioner ?? SamplerNotationNoteAuditioner()
        self.recentProjectsStore = recentProjectsStore ?? .shared
        self.isSandboxed = isSandboxed
        self.clickVolume = appSettingsStore.restoredClickVolume()
        self.playbackEngine.setClickVolume(clickVolume)
        self.playbackEngine.setMainVolume(mainTrackVolume)
        self.playbackEngine.setClickSettings(beatGridSettings)
        self.playbackEngine.setTempoMap(TempoMap(baseSettings: beatGridSettings, markers: [], duration: 0))
        self.playbackEngine.setClickSoundSettings(appSettingsStore.clickSoundSettings)
        applyAudioOutputDeviceSetting(appSettingsStore.audioDeviceSettings.outputDeviceUID)
        self.videoFollower.onWindowOpenChanged = { [weak self] isOpen in
            self?.handleVideoWindowOpenChanged(isOpen)
        }

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
}

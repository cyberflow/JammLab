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
    @Published var importedFile: ImportedAudioFile?
    @Published var analysisResult: AnalysisResult?
    @Published var peakformData: PeakformData?
    @Published var playbackState: PlaybackState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = AppSliderDefaults.playbackRate
    @Published var pitchShiftSemitones: Float = AppSliderDefaults.pitchShiftSemitones
    @Published var tempoBPM: Double? = AppDefaults.defaultTempoBPM
    @Published var beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
    @Published var notes: [TimecodedNote] = []
    @Published var selectedRegionID: TimecodedNote.ID?
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
    @Published var isLooping = false
    @Published var isClickEnabled = false
    @Published var isSnapEnabled = false
    @Published var mainTrackVolume: Float = AppSliderDefaults.mainTrackVolume
    @Published var clickVolume: Float = AudioPlayerViewModel.restoredClickVolume()
    @Published var undoStateRevision = 0
    @Published var isProjectModified = false
    @Published var errorMessage: String?
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
    let projectService: ProjectDocumentService
    let projectArtifactStore: ProjectArtifactStore
    let recentProjectsStore: RecentProjectsStore
    let isSandboxed: () -> Bool
    var clockTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var waveformTask: Task<Void, Never>?
    var stemSeparationTask: Task<Void, Never>?
    var stemPeakformTask: Task<Void, Never>?
    var stemCacheMetadata: StemCacheMetadata?
    var shouldAcceptAnalyzedTempo = true
    var securityScopedURL: URL?
    var hasSecurityScopedAccess = false
    var projectSecurityScopedURL: URL?
    var hasProjectSecurityScopedAccess = false
    var settingsCancellables: Set<AnyCancellable> = []
    var isRestoringUndoState = false
    var lastSavedProjectState: ProjectPersistedEditableState?

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
}

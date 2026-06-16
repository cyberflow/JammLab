import XCTest
@testable import JammLab

extension XCTestCase {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("JammLabTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func temporaryFile(name: String, contents: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try temporaryFile(in: directory, name: name, contents: contents)
    }

    func temporaryFile(in directory: URL, name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }

    func temporaryUserDefaults() throws -> UserDefaults {
        let suiteName = "JammLabTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func executableHelperFile(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("JammLabStemHelper")
        try Data("helper".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func writeHeartbeat(to url: URL, updatedAt: Date) throws {
        try writeHeartbeat(to: url, helperVersion: StemJobFiles.helperVersion, updatedAt: updatedAt)
    }

    func writeHeartbeat(to url: URL, helperVersion: Int, updatedAt: Date) throws {
        let heartbeat = StemHelperHeartbeat(
            helperVersion: helperVersion,
            updatedAt: updatedAt,
            activeJobID: nil
        )
        try JSONEncoder().encode(heartbeat).write(to: url, options: .atomic)
    }
}

final class MockStemHelperLauncher: StemHelperProcessLaunching {
    private let process: MockStemHelperProcess
    var launchCount = 0
    var onLaunch: (URL) throws -> Void = { _ in }

    init(process: MockStemHelperProcess = MockStemHelperProcess()) {
        self.process = process
    }

    func launchStemHelper(at executableURL: URL) throws -> StemHelperLaunchedProcess {
        launchCount += 1
        try onLaunch(executableURL)
        return process
    }
}

final class MockStemHelperProcess: StemHelperLaunchedProcess {
    var isRunning = true
    var didTerminate = false

    func terminate() {
        didTerminate = true
        isRunning = false
    }
}

struct MockAnalyzer: AudioAnalyzing {
    var result = AnalysisResult(bpm: nil, keyName: nil, keyConfidence: 0)

    func analyze(url: URL, includesTempo: Bool) async throws -> AnalysisResult {
        result
    }
}

struct MockPeakformProvider: PeakformProvider {
    var samplesPerPeakLevels = PeakformData.defaultSamplesPerPeakLevels
    var peakform = PeakformData(
        duration: 0.5,
        sampleRate: 44_100,
        levels: [
            PeakformLevel(
                samplesPerPeak: 512,
                peaks: [PeakPoint(min: -0.5, max: 0.5, rms: 0.25)]
            )
        ]
    )

    func peakform(for url: URL) async throws -> PeakformData {
        peakform
    }
}

@MainActor
final class MockPlaybackEngine: AudioPlaybackControlling {
    var isLoaded = false
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var unloadCount = 0
    var clickEnabled = false
    var playbackRate: Float = AppSliderDefaults.playbackRate
    var pitchShiftSemitones: Float = AppSliderDefaults.pitchShiftSemitones
    var mainVolume: Float = AppSliderDefaults.mainTrackVolume
    var clickVolume: Float = AppSliderDefaults.clickVolume
    var clickSettings = BeatGridSettings()
    var tempoMap: TempoMap?
    var clickSoundSettings = JammLab.ClickSoundSettings.defaultValue
    var audioOutputDeviceUID: String?
    var audioOutputDeviceUIDs: [String?] = []
    var mixState = StemMixState()
    var seekCount = 0
    var loopEnabled = false
    var loopRegion = LoopRegion.empty

    func load(url: URL) throws {
        isLoaded = true
    }

    func play() throws {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        isPlaying = false
        currentTime = 0
    }

    func unload() {
        unloadCount += 1
        isLoaded = false
        isPlaying = false
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        seekCount += 1
        currentTime = time
    }

    func setLoop(enabled: Bool, region: LoopRegion) {
        loopEnabled = enabled
        loopRegion = region
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }

    func setPitchShift(semitones: Float) {
        pitchShiftSemitones = semitones
    }

    func setMainVolume(_ volume: Float) {
        mainVolume = volume
    }

    func load(stems: [StemFile], mixState: StemMixState) throws {
        isLoaded = true
        self.mixState = mixState
    }

    func applyMix(_ mixState: StemMixState) {
        self.mixState = mixState
    }

    func setClickEnabled(_ isEnabled: Bool) {
        clickEnabled = isEnabled
    }

    func setClickVolume(_ volume: Float) {
        clickVolume = volume
    }

    func setClickSettings(_ settings: BeatGridSettings) {
        clickSettings = settings
    }

    func setTempoMap(_ tempoMap: TempoMap) {
        self.tempoMap = tempoMap
    }

    func setClickSoundSettings(_ settings: JammLab.ClickSoundSettings) {
        clickSoundSettings = settings
    }

    func setAudioOutputDevice(uid: String?) throws {
        audioOutputDeviceUID = uid
        audioOutputDeviceUIDs.append(uid)
    }

    func resetClickSchedule() {}
}

@MainActor
final class MockVideoFollower: VideoFollowerControlling {
    var loadedVideoURL: URL?
    var didUnload = false
    var closeWindowCount = 0
    var isWindowOpen = false
    var onWindowOpenChanged: ((Bool) -> Void)?
    var playRate: Float?
    var didPause = false
    var didStop = false
    var seekTimes: [TimeInterval] = []
    var playbackRate: Float?
    var syncEvents: [(time: TimeInterval, isPlaying: Bool, rate: Float)] = []
    var showWindowEvents: [(time: TimeInterval, isPlaying: Bool, rate: Float)] = []
    var toggleWindowEvents: [(time: TimeInterval, isPlaying: Bool, rate: Float)] = []

    func load(videoURL: URL?) {
        loadedVideoURL = videoURL
    }

    func unload() {
        didUnload = true
        loadedVideoURL = nil
        closeWindow()
    }

    func closeWindow() {
        closeWindowCount += 1
        setWindowOpen(false)
    }

    func showWindow(at time: TimeInterval, isPlaying: Bool, rate: Float) {
        showWindowEvents.append((time, isPlaying, rate))
        setWindowOpen(true)
    }

    func toggleWindow(at time: TimeInterval, isPlaying: Bool, rate: Float) {
        toggleWindowEvents.append((time, isPlaying, rate))
        setWindowOpen(!isWindowOpen)
    }

    func play(rate: Float) {
        playRate = rate
    }

    func pause() {
        didPause = true
    }

    func stop() {
        didStop = true
    }

    func seek(to time: TimeInterval) {
        seekTimes.append(time)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }

    func sync(to audioTime: TimeInterval, isPlaying: Bool, rate: Float) {
        syncEvents.append((audioTime, isPlaying, rate))
    }

    private func setWindowOpen(_ isOpen: Bool) {
        guard isWindowOpen != isOpen else { return }

        isWindowOpen = isOpen
        onWindowOpenChanged?(isOpen)
    }
}

extension Data {
    mutating func appendTestUInt16(_ value: UInt16) {
        appendTestInteger(value.littleEndian)
    }

    mutating func appendTestUInt32(_ value: UInt32) {
        appendTestInteger(value.littleEndian)
    }

    mutating func appendTestInteger<T: FixedWidthInteger>(_ value: T) {
        var value = value
        Swift.withUnsafeBytes(of: &value) { buffer in
            append(contentsOf: buffer)
        }
    }
}

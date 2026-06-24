import AudioToolbox
import AVFoundation
import Combine
import Foundation

enum AudioInputPermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
}

protocol AudioInputPermissionProviding {
    var authorizationStatus: AudioInputPermissionStatus { get }
    func requestAccess() async -> Bool
}

struct SystemAudioInputPermissionProvider: AudioInputPermissionProviding {
    var authorizationStatus: AudioInputPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }
}

enum AudioOSStatusFormatter {
    static func name(for status: OSStatus) -> String {
        switch status {
        case kAudioUnitErr_InvalidProperty:
            return "kAudioUnitErr_InvalidProperty"
        case kAudioUnitErr_InvalidParameter:
            return "kAudioUnitErr_InvalidParameter"
        case kAudioUnitErr_InvalidElement:
            return "kAudioUnitErr_InvalidElement"
        case kAudioUnitErr_NoConnection:
            return "kAudioUnitErr_NoConnection"
        case kAudioUnitErr_FailedInitialization:
            return "kAudioUnitErr_FailedInitialization"
        case kAudioUnitErr_TooManyFramesToProcess:
            return "kAudioUnitErr_TooManyFramesToProcess"
        case kAudioUnitErr_FormatNotSupported:
            return "kAudioUnitErr_FormatNotSupported"
        case kAudioUnitErr_Uninitialized:
            return "kAudioUnitErr_Uninitialized"
        case kAudioUnitErr_InvalidScope:
            return "kAudioUnitErr_InvalidScope"
        case kAudioUnitErr_PropertyNotWritable:
            return "kAudioUnitErr_PropertyNotWritable"
        case kAudioUnitErr_CannotDoInCurrentContext:
            return "kAudioUnitErr_CannotDoInCurrentContext"
        case kAudioUnitErr_InvalidPropertyValue:
            return "kAudioUnitErr_InvalidPropertyValue"
        case kAudioUnitErr_PropertyNotInUse:
            return "kAudioUnitErr_PropertyNotInUse"
        case kAudioUnitErr_Initialized:
            return "kAudioUnitErr_Initialized"
        case kAudioUnitErr_InvalidOfflineRender:
            return "kAudioUnitErr_InvalidOfflineRender"
        case kAudioUnitErr_Unauthorized:
            return "kAudioUnitErr_Unauthorized"
        default:
            return "OSStatus \(status)"
        }
    }
}

enum TunerInputSignalLevel {
    private static let floorDB = -60.0
    private static let ceilingDB = -12.0

    static func normalized(rms: Double) -> Double {
        guard rms > 0, rms.isFinite else { return 0 }

        let decibels = 20 * log10(rms)
        guard decibels > floorDB else { return 0 }
        guard decibels < ceilingDB else { return 1 }

        return (decibels - floorDB) / (ceilingDB - floorDB)
    }
}

enum TunerInputConversionStatus: Equatable {
    case notStarted
    case converted
    case empty
    case unsupported
}

enum TunerInputEngineDebugEvent: Equatable {
    case deviceSwitch(status: OSStatus)
    case format(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        commonFormat: AVAudioCommonFormat,
        isInterleaved: Bool
    )
    case tap(frameLength: AVAudioFrameCount, sampleRate: Double)
}

struct TunerInputDebugSnapshot: Equatable {
    var permissionStatus: AudioInputPermissionStatus?
    var permissionRequestGranted: Bool?
    var savedInputDeviceUID: String?
    var resolvedDeviceName: String?
    var resolvedDeviceID: AudioDeviceID?
    var didFallbackToDefaultDevice = false
    var fallbackMessage: String?
    var deviceSwitchStatus: OSStatus?
    var engineSampleRate: Double?
    var engineChannelCount: AVAudioChannelCount?
    var engineCommonFormat: AVAudioCommonFormat?
    var engineIsInterleaved: Bool?
    var bufferSampleRate: Double?
    var tapCallbackCount = 0
    var lastFrameLength: AVAudioFrameCount?
    var conversionStatus: TunerInputConversionStatus = .notStarted
    var lastRMS: Double?
    var signalLevel = 0.0
    var lastPitchDetected: Bool?
    var lastPitchNoteName: String?
    var lastPitchOctave: Int?
    var lastPitchFrequencyHz: Double?
    var lastErrorMessage: String?
}

protocol PitchDetecting {
    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult?
}

extension PitchDetector: PitchDetecting {}

protocol TunerInputEngineControlling: AnyObject {
    func start(
        deviceID: AudioDeviceID,
        bufferSize: AVAudioFrameCount,
        onDebug: @escaping (TunerInputEngineDebugEvent) -> Void,
        onAudioBuffer: @escaping (AVAudioPCMBuffer, Double) -> Void
    ) throws
    func stop()
}

final class SystemTunerInputEngine: TunerInputEngineControlling {
    private var engine: AVAudioEngine?

    func start(
        deviceID: AudioDeviceID,
        bufferSize: AVAudioFrameCount,
        onDebug: @escaping (TunerInputEngineDebugEvent) -> Void,
        onAudioBuffer: @escaping (AVAudioPCMBuffer, Double) -> Void
    ) throws {
        stop()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try applyInputDevice(deviceID, to: inputNode, onDebug: onDebug)

        let format = inputNode.outputFormat(forBus: 0)
        onDebug(.format(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            commonFormat: format.commonFormat,
            isInterleaved: format.isInterleaved
        ))
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TunerInputServiceError.inputFormatUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            let actualSampleRate = buffer.format.sampleRate > 0 ? buffer.format.sampleRate : format.sampleRate
            onDebug(.tap(frameLength: buffer.frameLength, sampleRate: actualSampleRate))
            onAudioBuffer(buffer, actualSampleRate)
        }

        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func applyInputDevice(
        _ deviceID: AudioDeviceID,
        to inputNode: AVAudioInputNode,
        onDebug: @escaping (TunerInputEngineDebugEvent) -> Void
    ) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw TunerInputServiceError.inputFormatUnavailable
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        onDebug(.deviceSwitch(status: status))
        guard status == noErr else {
            throw TunerInputServiceError.inputDeviceSwitchFailed(status)
        }
    }
}

enum TunerInputServiceError: LocalizedError {
    case microphonePermissionDenied
    case inputFormatUnavailable
    case inputDeviceSwitchFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is disabled. Allow JammLab to use audio input in System Settings to use the tuner."
        case .inputFormatUnavailable:
            return "The selected audio input did not provide a usable audio stream."
        case let .inputDeviceSwitchFailed(status):
            return "Audio input device switch failed with status \(status) (\(AudioOSStatusFormatter.name(for: status)))."
        }
    }
}

final class TunerInputService: ObservableObject {
    @Published private(set) var currentResult: PitchDetectionResult?
    @Published private(set) var inputDeviceName = "System Default"
    @Published private(set) var errorMessage: String?
    @Published private(set) var inputDiagnosticMessage: String?
    @Published private(set) var inputSignalLevel = 0.0
    @Published private(set) var inputDebugSnapshot = TunerInputDebugSnapshot()

    // Low bass notes need enough cycles in each analysis window to avoid dropping A0/B0.
    private static let inputBufferSize: AVAudioFrameCount = 16_384
    private static let signalLevelPublishInterval: TimeInterval = 1.0 / 30.0
    private static let publishesPerBufferDebug = false
    private static let defaultNoteHoldDuration: TimeInterval = 1.0

    private let appSettingsStore: AppSettingsStore
    private let audioDeviceResolver: TunerInputDeviceResolver
    private let inputPermissionProvider: AudioInputPermissionProviding
    private let inputEngine: TunerInputEngineControlling
    private let detector: any PitchDetecting
    private let noteHoldDuration: TimeInterval
    private let analysisQueue = DispatchQueue(label: "com.cyberflow.JammLab.tuner.pitch", qos: .userInitiated)
    private let analysisLock = NSLock()
    private var settingsCancellable: AnyCancellable?
    private var analysisInFlight = false
    private var pendingAnalysis: TunerAnalysisWork?
    private var activeAnalysisSessionID = 0
    private var lastDetectedAt: Date?
    private var noteHoldClearTask: Task<Void, Never>?
    private var isRunning = false
    private var isStarting = false
    private var lastPublishedAt: Date = .distantPast
    private var lastSignalLevelPublishedAt: Date = .distantPast
    private var inputSessionID = 0

    init(
        appSettingsStore: AppSettingsStore,
        audioDeviceProvider: AudioDeviceProviding = AudioDeviceService(),
        inputPermissionProvider: AudioInputPermissionProviding = SystemAudioInputPermissionProvider(),
        inputEngine: TunerInputEngineControlling = SystemTunerInputEngine(),
        detector: any PitchDetecting = PitchDetector.tunerDefault,
        noteHoldDuration: TimeInterval = TunerInputService.defaultNoteHoldDuration
    ) {
        self.appSettingsStore = appSettingsStore
        self.audioDeviceResolver = TunerInputDeviceResolver(audioDeviceProvider: audioDeviceProvider)
        self.inputPermissionProvider = inputPermissionProvider
        self.inputEngine = inputEngine
        self.detector = detector
        self.noteHoldDuration = noteHoldDuration
        observeInputDeviceChanges()
    }

    deinit {
        noteHoldClearTask?.cancel()
        stopEngine()
    }

    @MainActor
    func start() async {
        guard !isRunning, !isStarting else { return }

        inputSessionID += 1
        let sessionID = inputSessionID
        resetAnalysisState(for: sessionID)
        isStarting = true
        errorMessage = nil
        inputDiagnosticMessage = nil
        inputSignalLevel = 0
        lastPublishedAt = .distantPast
        lastSignalLevelPublishedAt = .distantPast
        inputDebugSnapshot = TunerInputDebugSnapshot(
            permissionStatus: inputPermissionProvider.authorizationStatus,
            savedInputDeviceUID: appSettingsStore.audioDeviceSettings.inputDeviceUID
        )

        let isInputAllowed = await requestInputPermissionIfNeeded()
        inputDebugSnapshot.permissionStatus = inputPermissionProvider.authorizationStatus
        inputDebugSnapshot.permissionRequestGranted = isInputAllowed
        guard isInputSessionActive(sessionID) else { return }
        guard isInputAllowed else {
            publishError(TunerInputServiceError.microphonePermissionDenied)
            return
        }

        do {
            try configureAndStartEngine(sessionID: sessionID)
        } catch {
            publishError(error)
        }
    }

    @MainActor
    func stop() {
        invalidateInputSession()
        stopEngine()
        isRunning = false
        isStarting = false
        clearHeldPitch()
        inputDiagnosticMessage = nil
        inputDebugSnapshot.conversionStatus = .notStarted
        inputDebugSnapshot.lastPitchDetected = nil
    }

    private func observeInputDeviceChanges() {
        settingsCancellable = appSettingsStore.$audioDeviceSettings
            .map(\.inputDeviceUID)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning || self.isStarting else { return }
                Task { @MainActor in
                    self.invalidateInputSession()
                    self.stopEngine()
                    self.isRunning = false
                    self.isStarting = false
                    await self.start()
                }
            }
    }

    @MainActor
    private func configureAndStartEngine(sessionID: Int) throws {
        stopEngine()

        let selectedDevice = try resolveInputDeviceForStart()
        inputDeviceName = selectedDevice.name
        inputDebugSnapshot.resolvedDeviceName = selectedDevice.name
        inputDebugSnapshot.resolvedDeviceID = selectedDevice.id

        let detector = detector
        try inputEngine.start(
            deviceID: selectedDevice.id,
            bufferSize: Self.inputBufferSize,
            onDebug: { [weak self] event in
                self?.publishEngineDebug(event, sessionID: sessionID)
            },
            onAudioBuffer: { [weak self] buffer, sampleRate in
                guard let samples = AudioSampleConverter.monoFloatSamples(from: buffer) else {
                    self?.publishAudioDebug(
                        conversionStatus: .unsupported,
                        rms: nil,
                        signalLevel: nil,
                        sessionID: sessionID
                    )
                    return
                }
                guard !samples.isEmpty else {
                    self?.publishAudioDebug(
                        conversionStatus: .empty,
                        rms: nil,
                        signalLevel: nil,
                        sessionID: sessionID
                    )
                    return
                }

                let rms = PitchDetector.rms(samples)
                let signalLevel = TunerInputSignalLevel.normalized(rms: rms)
                self?.publishAudioDebug(
                    conversionStatus: .converted,
                    rms: rms,
                    signalLevel: signalLevel,
                    sessionID: sessionID
                )
                self?.publishInputSignalLevel(signalLevel, sessionID: sessionID)
                self?.scheduleAnalysis(samples: samples, sampleRate: sampleRate, detector: detector, sessionID: sessionID)
            }
        )

        isRunning = true
        isStarting = false
        errorMessage = nil
    }

    @MainActor
    private func resolveInputDeviceForStart() throws -> TunerInputDeviceSelection {
        let selectedUID = appSettingsStore.audioDeviceSettings.inputDeviceUID
        do {
            return try audioDeviceResolver.resolveInputDevice(selectedUID: selectedUID)
        } catch AudioDeviceServiceError.deviceNotFound(_) where selectedUID != nil {
            let fallback = try audioDeviceResolver.resolveInputDevice(selectedUID: nil)
            inputDiagnosticMessage = "Selected tuner input is unavailable. Using System Default."
            inputDebugSnapshot.didFallbackToDefaultDevice = true
            inputDebugSnapshot.fallbackMessage = inputDiagnosticMessage
            return fallback
        } catch {
            throw error
        }
    }

    private func scheduleAnalysis(
        samples: [Float],
        sampleRate: Double,
        detector: any PitchDetecting,
        sessionID: Int
    ) {
        guard sampleRate > 0 else { return }

        let work = TunerAnalysisWork(samples: samples, sampleRate: sampleRate, sessionID: sessionID)
        if enqueueAnalysis(work) {
            startAnalysis(work, detector: detector)
        }
    }

    private func enqueueAnalysis(_ work: TunerAnalysisWork) -> Bool {
        analysisLock.lock()
        defer { analysisLock.unlock() }

        guard work.sessionID == activeAnalysisSessionID else { return false }

        if analysisInFlight {
            pendingAnalysis = work
            return false
        }

        analysisInFlight = true
        return true
    }

    private func startAnalysis(_ work: TunerAnalysisWork, detector: any PitchDetecting) {
        analysisQueue.async { [weak self] in
            let result = detector.detect(samples: work.samples, sampleRate: work.sampleRate)
            DispatchQueue.main.async {
                self?.publish(result: result, sessionID: work.sessionID)
            }
            self?.completeAnalysis(work, detector: detector)
        }
    }

    private func completeAnalysis(_ work: TunerAnalysisWork, detector: any PitchDetecting) {
        let nextWork: TunerAnalysisWork?

        analysisLock.lock()
        if work.sessionID == activeAnalysisSessionID {
            nextWork = pendingAnalysis
            pendingAnalysis = nil
            analysisInFlight = nextWork != nil
        } else {
            nextWork = nil
        }
        analysisLock.unlock()

        if let nextWork {
            startAnalysis(nextWork, detector: detector)
        }
    }

    @MainActor
    private func publish(result: PitchDetectionResult?, sessionID: Int) {
        guard isInputSessionActive(sessionID) else { return }

        if let result {
            publishDetectedResult(result)
            return
        }

        publishMissingResult(sessionID: sessionID)
    }

    @MainActor
    private func publishDetectedResult(_ result: PitchDetectionResult) {
        let now = Date()
        noteHoldClearTask?.cancel()
        noteHoldClearTask = nil
        lastDetectedAt = now

        guard now.timeIntervalSince(lastPublishedAt) >= 1.0 / 30.0 || currentResult != result else { return }
        lastPublishedAt = now

        currentResult = result
        errorMessage = nil
        if Self.publishesPerBufferDebug {
            inputDebugSnapshot.lastPitchDetected = true
            inputDebugSnapshot.lastPitchNoteName = result.noteName
            inputDebugSnapshot.lastPitchOctave = result.octave
            inputDebugSnapshot.lastPitchFrequencyHz = result.frequencyHz
        }
    }

    @MainActor
    private func publishMissingResult(sessionID: Int) {
        guard let lastDetectedAt else {
            if currentResult != nil {
                publishClearedPitch()
            }
            return
        }
        guard currentResult != nil else {
            publishClearedPitch()
            return
        }

        let elapsed = Date().timeIntervalSince(lastDetectedAt)
        if elapsed >= noteHoldDuration {
            publishClearedPitch()
            return
        }

        scheduleHeldPitchClear(sessionID: sessionID, after: noteHoldDuration - elapsed)
    }

    @MainActor
    private func scheduleHeldPitchClear(sessionID: Int, after delay: TimeInterval) {
        guard noteHoldClearTask == nil else { return }

        noteHoldClearTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.isInputSessionActive(sessionID) else { return }
                self.publishClearedPitch()
            }
        }
    }

    @MainActor
    private func publishClearedPitch() {
        noteHoldClearTask?.cancel()
        noteHoldClearTask = nil
        lastDetectedAt = nil
        lastPublishedAt = Date()
        currentResult = nil
        if Self.publishesPerBufferDebug {
            inputDebugSnapshot.lastPitchDetected = false
            inputDebugSnapshot.lastPitchNoteName = nil
            inputDebugSnapshot.lastPitchOctave = nil
            inputDebugSnapshot.lastPitchFrequencyHz = nil
        }
    }

    @MainActor
    private func clearHeldPitch() {
        noteHoldClearTask?.cancel()
        noteHoldClearTask = nil
        lastDetectedAt = nil
        currentResult = nil
    }

    @MainActor
    private func publishError(_ error: Error) {
        invalidateInputSession()
        stopEngine()
        isRunning = false
        isStarting = false
        clearHeldPitch()
        inputDiagnosticMessage = nil
        errorMessage = error.localizedDescription
        inputDebugSnapshot.lastErrorMessage = error.localizedDescription
        if let serviceError = error as? TunerInputServiceError,
           case let .inputDeviceSwitchFailed(status) = serviceError {
            inputDebugSnapshot.deviceSwitchStatus = status
        }
    }

    private func requestInputPermissionIfNeeded() async -> Bool {
        switch inputPermissionProvider.authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await inputPermissionProvider.requestAccess()
        case .denied:
            return false
        }
    }

    private func stopEngine() {
        inputEngine.stop()
    }

    private func resetAnalysisState(for sessionID: Int) {
        analysisLock.lock()
        activeAnalysisSessionID = sessionID
        analysisInFlight = false
        pendingAnalysis = nil
        analysisLock.unlock()
    }

    private func publishInputSignalLevel(_ level: Double, sessionID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isInputSessionActive(sessionID) else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastSignalLevelPublishedAt) >= Self.signalLevelPublishInterval else {
                return
            }

            self.lastSignalLevelPublishedAt = now
            self.inputSignalLevel = max(0, min(1, level))
        }
    }

    private func publishEngineDebug(_ event: TunerInputEngineDebugEvent, sessionID: Int) {
        if case .tap = event, !Self.publishesPerBufferDebug {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isInputSessionActive(sessionID) else { return }

            switch event {
            case let .deviceSwitch(status):
                self.inputDebugSnapshot.deviceSwitchStatus = status
            case let .format(sampleRate, channelCount, commonFormat, isInterleaved):
                self.inputDebugSnapshot.engineSampleRate = sampleRate
                self.inputDebugSnapshot.engineChannelCount = channelCount
                self.inputDebugSnapshot.engineCommonFormat = commonFormat
                self.inputDebugSnapshot.engineIsInterleaved = isInterleaved
            case let .tap(frameLength, sampleRate):
                self.inputDebugSnapshot.tapCallbackCount += 1
                self.inputDebugSnapshot.lastFrameLength = frameLength
                self.inputDebugSnapshot.bufferSampleRate = sampleRate
            }
        }
    }

    private func publishAudioDebug(
        conversionStatus: TunerInputConversionStatus,
        rms: Double?,
        signalLevel: Double?,
        sessionID: Int
    ) {
        guard Self.publishesPerBufferDebug else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isInputSessionActive(sessionID) else { return }

            self.inputDebugSnapshot.conversionStatus = conversionStatus
            self.inputDebugSnapshot.lastRMS = rms
            if let signalLevel {
                self.inputDebugSnapshot.signalLevel = max(0, min(1, signalLevel))
            }
        }
    }

    @MainActor
    private func invalidateInputSession() {
        inputSessionID += 1
        resetAnalysisState(for: inputSessionID)
        clearHeldPitch()
        lastSignalLevelPublishedAt = .distantPast
        inputSignalLevel = 0
        inputDebugSnapshot.signalLevel = 0
    }

    @MainActor
    private func isInputSessionActive(_ sessionID: Int) -> Bool {
        sessionID == inputSessionID && (isRunning || isStarting)
    }
}

private struct TunerAnalysisWork {
    let samples: [Float]
    let sampleRate: Double
    let sessionID: Int
}

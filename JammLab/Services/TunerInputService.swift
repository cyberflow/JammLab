import AudioToolbox
import AVFoundation
import Combine
import Foundation

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
            return "Audio input device switch failed with status \(status)."
        }
    }
}

final class TunerInputService: ObservableObject {
    @Published private(set) var currentResult: PitchDetectionResult?
    @Published private(set) var inputDeviceName = "System Default"
    @Published private(set) var errorMessage: String?

    // Low bass notes need enough cycles in each analysis window to avoid dropping A0/B0.
    private static let inputBufferSize: AVAudioFrameCount = 16_384

    private let appSettingsStore: AppSettingsStore
    private let audioDeviceService: AudioDeviceService
    private let detector: PitchDetector
    private let analysisQueue = DispatchQueue(label: "com.cyberflow.JammLab.tuner.pitch", qos: .userInitiated)
    private let analysisLock = NSLock()
    private var settingsCancellable: AnyCancellable?
    private var engine: AVAudioEngine?
    private var analysisPending = false
    private var isRunning = false
    private var isStarting = false
    private var lastPublishedAt: Date = .distantPast

    init(
        appSettingsStore: AppSettingsStore,
        audioDeviceService: AudioDeviceService = AudioDeviceService(),
        detector: PitchDetector = PitchDetector()
    ) {
        self.appSettingsStore = appSettingsStore
        self.audioDeviceService = audioDeviceService
        self.detector = detector
        observeInputDeviceChanges()
    }

    deinit {
        stopEngine()
    }

    @MainActor
    func start() async {
        guard !isRunning, !isStarting else { return }

        isStarting = true
        errorMessage = nil

        guard await requestInputPermissionIfNeeded() else {
            publishError(TunerInputServiceError.microphonePermissionDenied)
            return
        }

        do {
            try configureAndStartEngine()
        } catch {
            publishError(error)
        }
    }

    @MainActor
    func stop() {
        stopEngine()
        isRunning = false
        isStarting = false
        currentResult = nil
    }

    private func observeInputDeviceChanges() {
        settingsCancellable = appSettingsStore.$audioDeviceSettings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning || self.isStarting else { return }
                Task { @MainActor in
                    self.stopEngine()
                    self.isRunning = false
                    self.isStarting = false
                    await self.start()
                }
            }
    }

    @MainActor
    private func configureAndStartEngine() throws {
        stopEngine()

        let selectedDevice = try resolvedInputDevice()
        inputDeviceName = selectedDevice.name

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try applyInputDevice(selectedDevice.id, to: inputNode)

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TunerInputServiceError.inputFormatUnavailable
        }

        let detector = detector
        inputNode.installTap(onBus: 0, bufferSize: Self.inputBufferSize, format: format) { [weak self] buffer, _ in
            guard let samples = AudioSampleConverter.monoFloatSamples(from: buffer), !samples.isEmpty else {
                return
            }
            self?.scheduleAnalysis(samples: samples, sampleRate: format.sampleRate, detector: detector)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        isRunning = true
        isStarting = false
        errorMessage = nil
    }

    private func scheduleAnalysis(samples: [Float], sampleRate: Double, detector: PitchDetector) {
        guard beginAnalysis() else { return }

        analysisQueue.async { [weak self] in
            let result = detector.detect(samples: samples, sampleRate: sampleRate)
            DispatchQueue.main.async {
                self?.publish(result: result)
                self?.finishAnalysis()
            }
        }
    }

    @MainActor
    private func publish(result: PitchDetectionResult?) {
        let now = Date()
        guard now.timeIntervalSince(lastPublishedAt) >= 1.0 / 30.0 else { return }
        lastPublishedAt = now

        currentResult = result
        errorMessage = nil
    }

    private func beginAnalysis() -> Bool {
        analysisLock.lock()
        defer { analysisLock.unlock() }

        guard !analysisPending else { return false }
        analysisPending = true
        return true
    }

    private func finishAnalysis() {
        analysisLock.lock()
        analysisPending = false
        analysisLock.unlock()
    }

    @MainActor
    private func publishError(_ error: Error) {
        stopEngine()
        isRunning = false
        isStarting = false
        currentResult = nil
        errorMessage = error.localizedDescription
    }

    @MainActor
    private func resolvedInputDevice() throws -> (id: AudioDeviceID, name: String) {
        let devices = (try? audioDeviceService.inputDevices()) ?? []
        if let uid = appSettingsStore.audioDeviceSettings.inputDeviceUID {
            let deviceID = try audioDeviceService.deviceID(forUID: uid, kind: .input)
            let name = devices.first(where: { $0.uid == uid })?.name ?? uid
            return (deviceID, name)
        }

        let defaultID = try audioDeviceService.defaultDeviceID(kind: .input)
        let defaultName = devices.first(where: \.isDefault)?.name ?? "System Default"
        return (defaultID, defaultName)
    }

    private func applyInputDevice(_ deviceID: AudioDeviceID, to inputNode: AVAudioInputNode) throws {
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
        guard status == noErr else {
            throw TunerInputServiceError.inputDeviceSwitchFailed(status)
        }
    }

    private func requestInputPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}

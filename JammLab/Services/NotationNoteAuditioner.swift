@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

@MainActor
protocol NotationNoteAuditioning: AnyObject {
    func audition(pitch: NotationPitch) throws
}

@MainActor
final class NoopNotationNoteAuditioner: NotationNoteAuditioning {
    func audition(pitch: NotationPitch) throws {}
}

enum NotationNoteAuditionerError: LocalizedError {
    case soundBankUnavailable
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .soundBankUnavailable:
            return "The system General MIDI sound bank is unavailable."
        case .initializationFailed:
            return "Notation note preview could not be initialized."
        }
    }
}

private enum NotationNoteAuditionDefaults {
    static let previewVelocity: UInt8 = 88
    static let previewDurationNanoseconds: UInt64 = 450_000_000
    static let midiChannel: UInt8 = 0
}

@MainActor
final class SamplerNotationNoteAuditioner: NotationNoteAuditioning {
    private var engine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var isPrepared = false
    private var didFailPreparation = false
    private var currentPreviewNote: UInt8?
    private var noteOffTask: Task<Void, Never>?

    deinit {
        noteOffTask?.cancel()
        if let currentPreviewNote, let sampler {
            sampler.stopNote(currentPreviewNote, onChannel: NotationNoteAuditionDefaults.midiChannel)
        }
        engine?.stop()
    }

    func audition(pitch: NotationPitch) throws {
        guard !didFailPreparation else {
            throw NotationNoteAuditionerError.initializationFailed
        }

        do {
            try prepareIfNeeded()
            try startEngineIfNeeded()
        } catch {
            didFailPreparation = true
            stopEngine()
            throw error
        }

        guard let sampler else {
            didFailPreparation = true
            throw NotationNoteAuditionerError.initializationFailed
        }

        let midiNote = UInt8(pitch.midiNoteNumber)
        stopCurrentPreviewNote()
        sampler.startNote(
            midiNote,
            withVelocity: NotationNoteAuditionDefaults.previewVelocity,
            onChannel: NotationNoteAuditionDefaults.midiChannel
        )
        currentPreviewNote = midiNote
        noteOffTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: NotationNoteAuditionDefaults.previewDurationNanoseconds)
            } catch {
                return
            }
            await MainActor.run {
                self?.stopPreviewNote(midiNote)
            }
        }
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }
        guard let soundBankURL = Self.defaultSoundBankURL() else {
            throw NotationNoteAuditionerError.soundBankUnavailable
        }

        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        try sampler.loadSoundBankInstrument(
            at: soundBankURL,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )

        self.engine = engine
        self.sampler = sampler
        isPrepared = true
    }

    private func startEngineIfNeeded() throws {
        guard let engine, !engine.isRunning else { return }
        try engine.start()
    }

    private func stopCurrentPreviewNote() {
        noteOffTask?.cancel()
        noteOffTask = nil
        if let currentPreviewNote, let sampler {
            sampler.stopNote(currentPreviewNote, onChannel: NotationNoteAuditionDefaults.midiChannel)
        }
        currentPreviewNote = nil
    }

    private func stopPreviewNote(_ note: UInt8) {
        guard currentPreviewNote == note else { return }
        sampler?.stopNote(note, onChannel: NotationNoteAuditionDefaults.midiChannel)
        currentPreviewNote = nil
        noteOffTask = nil
    }

    private func stopEngine() {
        noteOffTask?.cancel()
        noteOffTask = nil
        currentPreviewNote = nil
        sampler = nil
        engine?.stop()
        engine = nil
        isPrepared = false
    }

    private static func defaultSoundBankURL() -> URL? {
        let url = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

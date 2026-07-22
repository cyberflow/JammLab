@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

@MainActor
protocol NotationNoteAuditioning: AnyObject {
    func audition(pitch: NotationPitch, route: NotationNoteAuditionRoute) throws
}

enum NotationNoteAuditionRoute: Equatable {
    case melodic
    case drums

    static func route(for clef: Clef) -> NotationNoteAuditionRoute {
        clef == .drums ? .drums : .melodic
    }
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
    static let melodicMIDIChannel: UInt8 = 0
    static let percussionMIDIChannel: UInt8 = 9
}

@MainActor
final class SamplerNotationNoteAuditioner: NotationNoteAuditioning {
    private var engine: AVAudioEngine?
    private var melodicSampler: AVAudioUnitSampler?
    private var drumSampler: AVAudioUnitSampler?
    private var isPrepared = false
    private var didFailPreparation = false
    private var currentPreviewNote: UInt8?
    private var currentPreviewRoute: NotationNoteAuditionRoute?
    private var noteOffTask: Task<Void, Never>?

    deinit {
        noteOffTask?.cancel()
        if let currentPreviewNote, let currentPreviewRoute {
            switch currentPreviewRoute {
            case .melodic:
                melodicSampler?.stopNote(
                    currentPreviewNote,
                    onChannel: NotationNoteAuditionDefaults.melodicMIDIChannel
                )
            case .drums:
                drumSampler?.stopNote(
                    currentPreviewNote,
                    onChannel: NotationNoteAuditionDefaults.percussionMIDIChannel
                )
            }
        }
        engine?.stop()
    }

    func audition(pitch: NotationPitch, route: NotationNoteAuditionRoute) throws {
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

        guard let sampler = sampler(for: route) else {
            didFailPreparation = true
            throw NotationNoteAuditionerError.initializationFailed
        }

        let midiNote = UInt8(pitch.midiNoteNumber)
        stopCurrentPreviewNote()
        sampler.startNote(
            midiNote,
            withVelocity: NotationNoteAuditionDefaults.previewVelocity,
            onChannel: midiChannel(for: route)
        )
        currentPreviewNote = midiNote
        currentPreviewRoute = route
        noteOffTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: NotationNoteAuditionDefaults.previewDurationNanoseconds)
            } catch {
                return
            }
            await MainActor.run {
                self?.stopPreviewNote(midiNote, route: route)
            }
        }
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }
        guard let soundBankURL = Self.defaultSoundBankURL() else {
            throw NotationNoteAuditionerError.soundBankUnavailable
        }

        let engine = AVAudioEngine()
        let melodicSampler = AVAudioUnitSampler()
        let drumSampler = AVAudioUnitSampler()
        engine.attach(melodicSampler)
        engine.attach(drumSampler)
        engine.connect(melodicSampler, to: engine.mainMixerNode, format: nil)
        engine.connect(drumSampler, to: engine.mainMixerNode, format: nil)
        try melodicSampler.loadSoundBankInstrument(
            at: soundBankURL,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        try drumSampler.loadSoundBankInstrument(
            at: soundBankURL,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )

        self.engine = engine
        self.melodicSampler = melodicSampler
        self.drumSampler = drumSampler
        isPrepared = true
    }

    private func startEngineIfNeeded() throws {
        guard let engine, !engine.isRunning else { return }
        try engine.start()
    }

    private func stopCurrentPreviewNote() {
        noteOffTask?.cancel()
        noteOffTask = nil
        if let currentPreviewNote, let currentPreviewRoute {
            sampler(for: currentPreviewRoute)?.stopNote(
                currentPreviewNote,
                onChannel: midiChannel(for: currentPreviewRoute)
            )
        }
        currentPreviewNote = nil
        currentPreviewRoute = nil
    }

    private func stopPreviewNote(_ note: UInt8, route: NotationNoteAuditionRoute) {
        guard currentPreviewNote == note, currentPreviewRoute == route else { return }
        sampler(for: route)?.stopNote(note, onChannel: midiChannel(for: route))
        currentPreviewNote = nil
        currentPreviewRoute = nil
        noteOffTask = nil
    }

    private func sampler(for route: NotationNoteAuditionRoute) -> AVAudioUnitSampler? {
        switch route {
        case .melodic: return melodicSampler
        case .drums: return drumSampler
        }
    }

    private func midiChannel(for route: NotationNoteAuditionRoute) -> UInt8 {
        switch route {
        case .melodic: return NotationNoteAuditionDefaults.melodicMIDIChannel
        case .drums: return NotationNoteAuditionDefaults.percussionMIDIChannel
        }
    }

    private func stopEngine() {
        noteOffTask?.cancel()
        noteOffTask = nil
        currentPreviewNote = nil
        melodicSampler = nil
        drumSampler = nil
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

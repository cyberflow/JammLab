import CoreAudio
import Foundation

enum AudioDeviceKind: String, Codable, CaseIterable, Identifiable {
    case input
    case output

    var id: String { rawValue }
}

struct AudioDeviceInfo: Codable, Equatable, Identifiable {
    var id: String { uid }

    let uid: String
    let name: String
    let kind: AudioDeviceKind
    let isDefault: Bool
}

protocol AudioDeviceProviding {
    func inputDevices() throws -> [AudioDeviceInfo]
    func outputDevices() throws -> [AudioDeviceInfo]
    func deviceID(forUID uid: String, kind: AudioDeviceKind) throws -> AudioDeviceID
    func defaultDeviceID(kind: AudioDeviceKind) throws -> AudioDeviceID
}

enum AudioDeviceServiceError: LocalizedError {
    case deviceListUnavailable
    case deviceNotFound(String)
    case defaultDeviceUnavailable(AudioDeviceKind)
    case deviceSwitchFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceListUnavailable:
            return "Audio devices could not be read from CoreAudio."
        case let .deviceNotFound(uid):
            return "Audio device was not found: \(uid)."
        case let .defaultDeviceUnavailable(kind):
            return "System default \(kind.rawValue) audio device is not available."
        case let .deviceSwitchFailed(status):
            return "Audio output device switch failed with status \(status)."
        }
    }
}

final class AudioDeviceService: AudioDeviceProviding {
    func inputDevices() throws -> [AudioDeviceInfo] {
        try devices(kind: .input)
    }

    func outputDevices() throws -> [AudioDeviceInfo] {
        try devices(kind: .output)
    }

    func deviceID(forUID uid: String, kind: AudioDeviceKind) throws -> AudioDeviceID {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else {
            throw AudioDeviceServiceError.deviceNotFound(uid)
        }

        for deviceID in try allDeviceIDs() where deviceHasStreams(deviceID, kind: kind) {
            if stringProperty(.deviceUID, for: deviceID) == normalizedUID {
                return deviceID
            }
        }

        throw AudioDeviceServiceError.deviceNotFound(uid)
    }

    func defaultDeviceID(kind: AudioDeviceKind) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kind.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw AudioDeviceServiceError.defaultDeviceUnavailable(kind)
        }

        return deviceID
    }

    private func devices(kind: AudioDeviceKind) throws -> [AudioDeviceInfo] {
        let defaultID = try? defaultDeviceID(kind: kind)
        return try allDeviceIDs()
            .filter { deviceHasStreams($0, kind: kind) }
            .compactMap { deviceID in
                guard let uid = stringProperty(.deviceUID, for: deviceID), !uid.isEmpty else { return nil }
                let name = stringProperty(.deviceName, for: deviceID) ?? uid
                return AudioDeviceInfo(
                    uid: uid,
                    name: name,
                    kind: kind,
                    isDefault: deviceID == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw AudioDeviceServiceError.deviceListUnavailable
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard status == noErr else {
            throw AudioDeviceServiceError.deviceListUnavailable
        }

        return deviceIDs
    }

    private func deviceHasStreams(_ deviceID: AudioDeviceID, kind: AudioDeviceKind) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kind.streamScope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return false }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPointer)
        guard status == noErr else { return false }

        let bufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func stringProperty(_ property: AudioDeviceStringProperty, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: property.selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}

struct TunerInputDeviceSelection: Equatable {
    let id: AudioDeviceID
    let name: String
}

struct TunerInputDeviceResolver {
    let audioDeviceProvider: AudioDeviceProviding

    func resolveInputDevice(selectedUID: String?) throws -> TunerInputDeviceSelection {
        let devices = (try? audioDeviceProvider.inputDevices()) ?? []

        if let uid = selectedUID {
            let deviceID = try audioDeviceProvider.deviceID(forUID: uid, kind: .input)
            let name = devices.first(where: { $0.uid == uid })?.name ?? uid
            return TunerInputDeviceSelection(id: deviceID, name: name)
        }

        let defaultID = try audioDeviceProvider.defaultDeviceID(kind: .input)
        let defaultName = devices.first(where: \.isDefault)?.name ?? "System Default"
        return TunerInputDeviceSelection(id: defaultID, name: defaultName)
    }
}

private enum AudioDeviceStringProperty {
    case deviceUID
    case deviceName

    var selector: AudioObjectPropertySelector {
        switch self {
        case .deviceUID:
            return kAudioDevicePropertyDeviceUID
        case .deviceName:
            return kAudioObjectPropertyName
        }
    }
}

private extension AudioDeviceKind {
    var streamScope: AudioObjectPropertyScope {
        switch self {
        case .input:
            return kAudioDevicePropertyScopeInput
        case .output:
            return kAudioDevicePropertyScopeOutput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input:
            return kAudioHardwarePropertyDefaultInputDevice
        case .output:
            return kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

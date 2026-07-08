import CoreAudio
@testable import JammLab

final class MockAudioDeviceProvider: AudioDeviceProviding {
    var inputDevicesResult: [AudioDeviceInfo] = []
    var outputDevicesResult: [AudioDeviceInfo] = []
    var deviceIDs: [String: AudioDeviceID] = [:]
    var defaultInputDeviceID = AudioDeviceID(1)
    var defaultOutputDeviceID = AudioDeviceID(2)
    var inputDevicesCallCount = 0
    var outputDevicesCallCount = 0
    var defaultDeviceCallKinds: [AudioDeviceKind] = []

    func inputDevices() throws -> [AudioDeviceInfo] {
        inputDevicesCallCount += 1
        return inputDevicesResult
    }

    func outputDevices() throws -> [AudioDeviceInfo] {
        outputDevicesCallCount += 1
        return outputDevicesResult
    }

    func deviceID(forUID uid: String, kind: AudioDeviceKind) throws -> AudioDeviceID {
        guard let deviceID = deviceIDs[uid] else {
            throw AudioDeviceServiceError.deviceNotFound(uid)
        }
        return deviceID
    }

    func defaultDeviceID(kind: AudioDeviceKind) throws -> AudioDeviceID {
        defaultDeviceCallKinds.append(kind)
        switch kind {
        case .input:
            return defaultInputDeviceID
        case .output:
            return defaultOutputDeviceID
        }
    }
}

final class MockAudioInputPermissionProvider: AudioInputPermissionProviding {
    var authorizationStatus: AudioInputPermissionStatus
    var requestAccessCount = 0
    var requestResult: Bool

    init(status: AudioInputPermissionStatus, requestResult: Bool = false) {
        self.authorizationStatus = status
        self.requestResult = requestResult
    }

    func requestAccess() async -> Bool {
        requestAccessCount += 1
        authorizationStatus = requestResult ? .authorized : .denied
        return requestResult
    }
}

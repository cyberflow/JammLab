import Foundation

enum TimeFormatter {
    static func mmssTenths(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00.0" }

        let totalTenths = Int((time * 10).rounded())
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    static func mmssMilliseconds(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00.000" }

        let totalMilliseconds = Int((time * 1_000).rounded())
        let minutes = totalMilliseconds / 60_000
        let seconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }
}

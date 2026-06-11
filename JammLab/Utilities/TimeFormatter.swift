import Foundation

enum TimeFormatter {
    static func mmss(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }

        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func mmssTenths(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00.0" }

        let totalTenths = Int((time * 10).rounded())
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

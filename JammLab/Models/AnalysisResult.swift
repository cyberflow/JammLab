import Foundation

struct AnalysisResult: Equatable {
    let bpm: Int?
    let keyName: String?
    let keyConfidence: Double

    var bpmText: String {
        guard let bpm else { return "Unknown" }
        return "\(bpm)"
    }

    var confidenceText: String {
        "\(Int((keyConfidence * 100).rounded()))%"
    }
}

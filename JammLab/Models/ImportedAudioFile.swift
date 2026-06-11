import Foundation

enum ImportedMediaKind: String, Codable, Equatable {
    case audio
    case video
}

struct ImportedAudioFile: Equatable {
    /// Audio URL consumed by waveform, analysis, playback, and stem separation.
    let url: URL
    /// Original user-selected media URL. For audio imports this is the same as `url`.
    let sourceMediaURL: URL
    let displayName: String
    let duration: TimeInterval
    let mediaKind: ImportedMediaKind

    init(
        url: URL,
        sourceMediaURL: URL? = nil,
        displayName: String,
        duration: TimeInterval,
        mediaKind: ImportedMediaKind = .audio
    ) {
        self.url = url
        self.sourceMediaURL = sourceMediaURL ?? url
        self.displayName = displayName
        self.duration = duration
        self.mediaKind = mediaKind
    }

    var videoURL: URL? {
        mediaKind == .video ? sourceMediaURL : nil
    }
}

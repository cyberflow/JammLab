import CoreText
import CoreGraphics
import Foundation

enum NotationSMuFLSymbol: Equatable {
    case restWhole
    case restHalf
    case restQuarter
    case rest8th

    init?(duration: NotationDuration) {
        switch duration.denominator {
        case 1:
            self = .restWhole
        case 2:
            self = .restHalf
        case 4:
            self = .restQuarter
        case 8:
            self = .rest8th
        default:
            return nil
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .restWhole:
            return 0xE4E3
        case .restHalf:
            return 0xE4E4
        case .restQuarter:
            return 0xE4E5
        case .rest8th:
            return 0xE4E6
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

enum NotationDurationControlSymbol: Equatable {
    case whole
    case half
    case quarter
    case eighth

    init?(duration: NotationDuration) {
        switch duration.denominator {
        case 1:
            self = .whole
        case 2:
            self = .half
        case 4:
            self = .quarter
        case 8:
            self = .eighth
        default:
            return nil
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .whole:
            return 0xECA2
        case .half:
            return 0xECA3
        case .quarter:
            return 0xECA5
        case .eighth:
            return 0xECA7
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

enum NotationMusicFontRegistry {
    static let fallbackFontName = "Leland"

    static var fontName: String {
        registeredFontName ?? fallbackFontName
    }

    private static let registeredFontName: String? = {
        guard let url = lelandFontURL else { return nil }
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return descriptors?.compactMap { descriptor in
            CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        }.first
    }()

    private static var lelandFontURL: URL? {
        Bundle.main.url(forResource: "Leland", withExtension: "otf")
            ?? Bundle.main.url(forResource: "Leland", withExtension: "otf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "Leland", withExtension: "otf", subdirectory: "Resources/Fonts")
    }

    static func glyphPath(for symbol: NotationSMuFLSymbol, fontSize: CGFloat) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationDurationControlSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    private static func glyphPath(forCodepoint codepoint: UInt32, fontSize: CGFloat) -> NotationSMuFLGlyphPath? {
        guard let character = UniChar(exactly: codepoint) else { return nil }

        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var characters = [character]
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else {
            return nil
        }

        var glyph = glyphs[0]
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let bounds = CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, nil, 1)
        guard !bounds.isEmpty else { return nil }

        return NotationSMuFLGlyphPath(path: path, bounds: bounds)
    }
}

struct NotationSMuFLGlyphPath {
    var path: CGPath
    var bounds: CGRect
}

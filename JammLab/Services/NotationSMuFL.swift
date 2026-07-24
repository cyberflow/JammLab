import CoreText
import CoreGraphics
import Foundation

enum NotationSMuFLSymbol: Equatable {
    case restWhole
    case restHalf
    case restQuarter
    case rest8th
    case rest16th
    case rest32nd

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
        case 16:
            self = .rest16th
        case 32:
            self = .rest32nd
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
        case .rest16th:
            return 0xE4E7
        case .rest32nd:
            return 0xE4E8
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

enum NotationAugmentationDotSymbol: Equatable {
    case augmentationDot

    var codepoint: UInt32 { 0xE1E7 }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

extension NotationAccidental {
    var codepoint: UInt32 {
        switch self {
        case .flat: return 0xE260
        case .natural: return 0xE261
        case .sharp: return 0xE262
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

enum NotationAugmentationDotLayout {
    static func noteDotStaffPosition(for noteStaffPosition: Int) -> Int {
        noteStaffPosition.isMultiple(of: 2) ? noteStaffPosition - 1 : noteStaffPosition
    }

    static func noteTarget(
        noteX: CGFloat,
        noteStaffPosition: Int,
        staffTop: CGFloat
    ) -> CGPoint {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        return CGPoint(
            x: noteX + spacing,
            y: NotationNotePlacementResolver.yPosition(
                forStaffPosition: noteDotStaffPosition(for: noteStaffPosition),
                staffTop: staffTop
            )
        )
    }

    static func restTarget(restX: CGFloat, staffTop: CGFloat) -> CGPoint {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        return CGPoint(
            x: restX + spacing,
            y: NotationNotePlacementResolver.yPosition(
                forStaffPosition: 3,
                staffTop: staffTop
            )
        )
    }
}

enum NotationDurationControlSymbol: Equatable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth

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
        case 16:
            self = .sixteenth
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
        case .sixteenth:
            return 0xECA9
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }
}

enum NotationStemDirection: Hashable {
    case up
    case down

    static func direction(forStaffPosition staffPosition: Int) -> NotationStemDirection {
        staffPosition < 4 ? .down : .up
    }
}

enum NotationTiePlacement: Equatable {
    case above
    case below
}

enum NotationTiePath {
    static func path(
        start: CGPoint,
        end: CGPoint,
        placement: NotationTiePlacement,
        arcHeight: CGFloat,
        endpointThickness: CGFloat,
        midpointThickness: CGFloat
    ) -> CGPath {
        let direction: CGFloat = placement == .below ? 1 : -1
        let controlY = (start.y + end.y) / 2 + direction * arcHeight
        let upperControlY = controlY - midpointThickness / 2
        let lowerControlY = controlY + midpointThickness / 2
        let startUpper = CGPoint(x: start.x, y: start.y - endpointThickness / 2)
        let endUpper = CGPoint(x: end.x, y: end.y - endpointThickness / 2)
        let startLower = CGPoint(x: start.x, y: start.y + endpointThickness / 2)
        let endLower = CGPoint(x: end.x, y: end.y + endpointThickness / 2)
        let horizontalDistance = end.x - start.x

        let path = CGMutablePath()
        path.move(to: startUpper)
        path.addCurve(
            to: endUpper,
            control1: CGPoint(x: start.x + horizontalDistance * 0.33, y: upperControlY),
            control2: CGPoint(x: start.x + horizontalDistance * 0.67, y: upperControlY)
        )
        path.addLine(to: endLower)
        path.addCurve(
            to: startLower,
            control1: CGPoint(x: start.x + horizontalDistance * 0.67, y: lowerControlY),
            control2: CGPoint(x: start.x + horizontalDistance * 0.33, y: lowerControlY)
        )
        path.closeSubpath()
        return path
    }
}

enum NotationStaffNoteSymbol: Equatable {
    case whole
    case half(NotationStemDirection)
    case quarter(NotationStemDirection)
    case eighth(NotationStemDirection)
    case sixteenth(NotationStemDirection)
    case thirtySecond(NotationStemDirection)

    init?(duration: NotationDuration, stemDirection: NotationStemDirection = .up) {
        switch duration.denominator {
        case 1:
            self = .whole
        case 2:
            self = .half(stemDirection)
        case 4:
            self = .quarter(stemDirection)
        case 8:
            self = .eighth(stemDirection)
        case 16:
            self = .sixteenth(stemDirection)
        case 32:
            self = .thirtySecond(stemDirection)
        default:
            return nil
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .whole:
            return 0xE1D2
        case .half(let direction):
            return Self.directionalCodepoint(up: 0xE1D3, direction: direction)
        case .quarter(let direction):
            return Self.directionalCodepoint(up: 0xE1D5, direction: direction)
        case .eighth(let direction):
            return Self.directionalCodepoint(up: 0xE1D7, direction: direction)
        case .sixteenth(let direction):
            return Self.directionalCodepoint(up: 0xE1D9, direction: direction)
        case .thirtySecond(let direction):
            return Self.directionalCodepoint(up: 0xE1DB, direction: direction)
        }
    }

    fileprivate var anchorReferenceCodepoint: UInt32? {
        switch self {
        case .whole:
            return nil
        case .half:
            return 0xE0A3
        case .quarter, .eighth, .sixteenth, .thirtySecond:
            return 0xE0A4
        }
    }

    var glyph: String {
        guard let scalar = UnicodeScalar(codepoint) else { return "" }
        return String(Character(scalar))
    }

    private static func directionalCodepoint(
        up: UInt32,
        direction: NotationStemDirection
    ) -> UInt32 {
        up + (direction == .down ? 1 : 0)
    }
}

enum NotationNoteheadSymbol: Equatable {
    case whole
    case half
    case black

    init(duration: NotationDuration) {
        switch duration.denominator {
        case 1: self = .whole
        case 2: self = .half
        default: self = .black
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .whole: return 0xE0A2
        case .half: return 0xE0A3
        case .black: return 0xE0A4
        }
    }
}

enum NotationDrumNoteheadSymbol: Equatable {
    case x
    case circleX

    var codepoint: UInt32 {
        switch self {
        case .x: return 0xE0A9
        case .circleX: return 0xE0B3
        }
    }
}

enum NotationFlagSymbol: Equatable {
    case eighth(NotationStemDirection)
    case sixteenth(NotationStemDirection)
    case thirtySecond(NotationStemDirection)

    init?(duration: NotationDuration, stemDirection: NotationStemDirection) {
        switch duration.denominator {
        case 8: self = .eighth(stemDirection)
        case 16: self = .sixteenth(stemDirection)
        case 32: self = .thirtySecond(stemDirection)
        default: return nil
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .eighth(let direction): return direction == .up ? 0xE240 : 0xE241
        case .sixteenth(let direction): return direction == .up ? 0xE242 : 0xE243
        case .thirtySecond(let direction): return direction == .up ? 0xE244 : 0xE245
        }
    }
}

enum NotationFlagLayout {
    static let attachmentAnchor = CGPoint.zero

    static func transform(
        for glyphPath: NotationSMuFLGlyphPath,
        attachmentPoint: CGPoint
    ) -> CGAffineTransform {
        glyphPath.anchoredTransform(
            anchor: attachmentAnchor,
            target: attachmentPoint
        )
    }
}

enum NotationClefSymbol: Equatable {
    case treble
    case bass
    case bass8
    case drums

    init(_ clef: Clef) {
        switch clef {
        case .treble:
            self = .treble
        case .bass:
            self = .bass
        case .bass8:
            self = .bass8
        case .drums:
            self = .drums
        }
    }

    var codepoint: UInt32 {
        switch self {
        case .treble:
            return 0xE050
        case .bass:
            return 0xE062
        case .bass8:
            // The requested mark uses Leland's pictured F clef with 8 above.
            // Sounding-octave-down semantics are carried separately by Clef.
            return 0xE065
        case .drums:
            return 0xE069
        }
    }

    var referenceStaffLineFromTop: Int {
        switch self {
        case .treble:
            return 3
        case .bass, .bass8:
            return 1
        case .drums:
            return 2
        }
    }
}

enum NotationClefLayout {
    static let referenceAnchorY: CGFloat = 0

    static var frameSize: CGSize {
        CGSize(
            width: AppTheme.Timeline.notationClefWidth,
            height: AppTheme.Timeline.notationAttributeStaffTopInset * 2
                + AppTheme.Timeline.notationStaffLineSpacing * 4
        )
    }

    static func targetY(for symbol: NotationClefSymbol) -> CGFloat {
        AppTheme.Timeline.notationAttributeStaffTopInset
            + CGFloat(symbol.referenceStaffLineFromTop)
                * AppTheme.Timeline.notationStaffLineSpacing
    }

    static func target(
        for symbol: NotationClefSymbol,
        in size: CGSize
    ) -> CGPoint {
        CGPoint(x: size.width / 2, y: targetY(for: symbol))
    }

    static func referenceAnchor(for glyphPath: NotationSMuFLGlyphPath) -> CGPoint {
        CGPoint(x: glyphPath.bounds.midX, y: referenceAnchorY)
    }

    static func transform(
        for glyphPath: NotationSMuFLGlyphPath,
        symbol: NotationClefSymbol,
        in size: CGSize
    ) -> CGAffineTransform {
        glyphPath.anchoredTransform(
            anchor: referenceAnchor(for: glyphPath),
            target: target(for: symbol, in: size)
        )
    }
}

enum NotationMusicFontRegistry {
    static let fallbackFontName = "Leland"
    private static let glyphPathCache = NSCache<NSString, NotationSMuFLGlyphPathBox>()

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

    static func glyphPath(
        for symbol: NotationStaffNoteSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationNoteheadSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationDrumNoteheadSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationFlagSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationAugmentationDotSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for accidental: NotationAccidental,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: accidental.codepoint, fontSize: fontSize)
    }

    static func glyphPath(
        for symbol: NotationClefSymbol,
        fontSize: CGFloat
    ) -> NotationSMuFLGlyphPath? {
        glyphPath(forCodepoint: symbol.codepoint, fontSize: fontSize)
    }

    static func noteheadAnchor(
        for symbol: NotationStaffNoteSymbol,
        fontSize: CGFloat
    ) -> CGPoint? {
        let glyphPath: NotationSMuFLGlyphPath?
        if let anchorCodepoint = symbol.anchorReferenceCodepoint {
            glyphPath = self.glyphPath(forCodepoint: anchorCodepoint, fontSize: fontSize)
        } else {
            glyphPath = self.glyphPath(for: symbol, fontSize: fontSize)
        }

        return glyphPath.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
    }

    private static func glyphPath(forCodepoint codepoint: UInt32, fontSize: CGFloat) -> NotationSMuFLGlyphPath? {
        let cacheKey = NSString(string: "\(codepoint)-\(fontSize)")
        if let cached = glyphPathCache.object(forKey: cacheKey) {
            return cached.value
        }

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

        let glyphPath = NotationSMuFLGlyphPath(path: path, bounds: bounds)
        glyphPathCache.setObject(NotationSMuFLGlyphPathBox(glyphPath), forKey: cacheKey)
        return glyphPath
    }
}

private final class NotationSMuFLGlyphPathBox {
    let value: NotationSMuFLGlyphPath

    init(_ value: NotationSMuFLGlyphPath) {
        self.value = value
    }
}

struct NotationSMuFLGlyphPath {
    var path: CGPath
    var bounds: CGRect

    func centeredTransform(in size: CGSize) -> CGAffineTransform {
        // CoreText glyph paths use a y-up coordinate space; SwiftUI Canvas draws y-down.
        CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: size.width / 2 - bounds.midX,
            ty: size.height / 2 + bounds.midY
        )
    }

    func anchoredTransform(anchor: CGPoint, target: CGPoint) -> CGAffineTransform {
        // CoreText glyph paths use y-up coordinates; Canvas uses y-down.
        CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: target.x - anchor.x,
            ty: target.y + anchor.y
        )
    }
}

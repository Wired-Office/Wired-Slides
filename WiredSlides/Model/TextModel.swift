import AppKit

/// Which theme font a run uses when it has no explicit family.
enum FontRole: String, Codable, CaseIterable { case heading, body }

/// Character formatting. `nil` means "inherit" (from the text body's defaults and the theme).
struct RunStyle: Codable, Hashable {
    var fontFamily: String?
    var size: Double?
    var bold: Bool?
    var italic: Bool?
    var underline = false
    var strikethrough = false
    var color: PaintColor?
    var highlight: RGBColor?
    /// 1 = superscript, -1 = subscript.
    var baseline = 0
    var link: String?
    var allCaps = false
    var smallCaps = false
    /// Extra spacing between characters, in points.
    var characterSpacing: Double = 0
    /// WordArt-style outline around the glyphs.
    var outlineColor: PaintColor?
    var outlineWidth: Double = 0
    var shadow = false

    static let plain = RunStyle()
}

struct TextRun: Codable, Hashable {
    var text: String
    var style: RunStyle = .plain
}

enum TextAlignment: String, Codable, CaseIterable {
    case left, center, right, justify

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justify: .justified
        }
    }

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center: self = .center
        case .right: self = .right
        case .justified: self = .justify
        default: self = .left
        }
    }
}

enum NumberingScheme: String, Codable, CaseIterable, Identifiable {
    case arabicPeriod, arabicParen, romanUpper, romanLower, alphaUpper, alphaLower
    var id: String { rawValue }

    var title: String {
        switch self {
        case .arabicPeriod: "1. 2. 3."
        case .arabicParen: "1) 2) 3)"
        case .romanUpper: "I. II. III."
        case .romanLower: "i. ii. iii."
        case .alphaUpper: "A. B. C."
        case .alphaLower: "a) b) c)"
        }
    }

    func label(_ n: Int) -> String {
        switch self {
        case .arabicPeriod: return "\(n)."
        case .arabicParen: return "\(n))"
        case .romanUpper: return Self.roman(n) + "."
        case .romanLower: return Self.roman(n).lowercased() + "."
        case .alphaUpper: return Self.alpha(n) + "."
        case .alphaLower: return Self.alpha(n).lowercased() + ")"
        }
    }

    var ooxml: String {
        switch self {
        case .arabicPeriod: "arabicPeriod"
        case .arabicParen: "arabicParenR"
        case .romanUpper: "romanUcPeriod"
        case .romanLower: "romanLcPeriod"
        case .alphaUpper: "alphaUcPeriod"
        case .alphaLower: "alphaLcParenR"
        }
    }

    static func fromOOXML(_ value: String) -> NumberingScheme {
        allCases.first { $0.ooxml == value } ?? .arabicPeriod
    }

    private static func roman(_ number: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = max(1, number), out = ""
        for (value, symbol) in table { while n >= value { out += symbol; n -= value } }
        return out
    }

    private static func alpha(_ number: Int) -> String {
        var n = max(1, number), out = ""
        while n > 0 { n -= 1; out = String(UnicodeScalar(65 + n % 26)!) + out; n /= 26 }
        return out
    }
}

enum Bullet: Codable, Hashable {
    case none
    case symbol(String)
    case numbered(NumberingScheme, start: Int = 1)

    var isNone: Bool { if case .none = self { return true }; return false }

    static let standardSymbols = ["•", "◦", "▪", "–", "➢", "✓", "◆", "★"]
}

struct ParagraphStyle: Codable, Hashable {
    var alignment: TextAlignment = .left
    /// Outline level, 0…8.
    var level = 0
    var bullet: Bullet = .none
    /// A multiple of single spacing.
    var lineSpacing: Double = 1
    var spaceBefore: Double = 0
    var spaceAfter: Double = 0
    var bulletColor: PaintColor?

    static let plain = ParagraphStyle()
    /// Left indent of the text (after the bullet) for a level, in points.
    static func indent(level: Int, hasBullet: Bool) -> CGFloat {
        CGFloat(level) * 28 + (hasBullet ? 22 : 0)
    }
}

struct Paragraph: Codable, Hashable {
    var runs: [TextRun]
    var style: ParagraphStyle = .plain

    init(runs: [TextRun], style: ParagraphStyle = .plain) {
        self.runs = runs
        self.style = style
    }

    init(_ text: String, style: ParagraphStyle = .plain, run: RunStyle = .plain) {
        runs = [TextRun(text: text, style: run)]
        self.style = style
    }

    var text: String { runs.map(\.text).joined() }
}

enum VerticalAnchor: String, Codable, CaseIterable { case top, middle, bottom }

enum AutoFit: String, Codable, CaseIterable, Identifiable {
    /// Text may overflow the shape.
    case none
    /// Shrink the text until it fits.
    case shrink
    /// Grow the shape's height to fit the text.
    case resizeShape
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Do not Autofit"
        case .shrink: "Shrink text on overflow"
        case .resizeShape: "Resize shape to fit text"
        }
    }
}

enum TextDirection: String, Codable, CaseIterable {
    case horizontal, rotated90, rotated270
}

/// The text inside a shape, text box, placeholder or table cell.
struct TextBody: Codable, Hashable {
    var paragraphs: [Paragraph] = [Paragraph(runs: [TextRun(text: "")])]
    var anchor: VerticalAnchor = .top
    var autofit: AutoFit = .none
    var wrap = true
    var columns = 1
    var direction: TextDirection = .horizontal
    var insets = EdgeInsetsValue(top: 3.6, left: 7.2, bottom: 3.6, right: 7.2)
    /// Defaults applied where runs don't say otherwise.
    var defaultSize: Double = 18
    var defaultColor: PaintColor = .theme(.dark1)
    var fontRole: FontRole = .body
    /// Shown in gray when the body is empty (placeholders).
    var prompt: String?

    init() {}

    init(_ text: String, size: Double = 18, role: FontRole = .body, alignment: TextAlignment = .left,
         anchor: VerticalAnchor = .top, color: PaintColor = .theme(.dark1), bold: Bool? = nil) {
        let lines = text.components(separatedBy: "\n")
        var run = RunStyle()
        run.bold = bold
        paragraphs = lines.map { Paragraph($0, style: ParagraphStyle(alignment: alignment), run: run) }
        defaultSize = size
        fontRole = role
        self.anchor = anchor
        defaultColor = color
    }

    var plainText: String { paragraphs.map(\.text).joined(separator: "\n") }
    var isEmpty: Bool { paragraphs.allSatisfy { $0.text.isEmpty } }

    /// Replaces all text, keeping the first paragraph's and run's formatting.
    mutating func setPlainText(_ text: String) {
        let style = paragraphs.first?.style ?? .plain
        let run = paragraphs.first?.runs.first?.style ?? .plain
        paragraphs = text.components(separatedBy: "\n").map { Paragraph($0, style: style, run: run) }
    }

    /// Applies a change to every run.
    mutating func updateRuns(_ change: (inout RunStyle) -> Void) {
        for p in paragraphs.indices {
            for r in paragraphs[p].runs.indices { change(&paragraphs[p].runs[r].style) }
        }
    }

    mutating func updateParagraphs(_ change: (inout ParagraphStyle) -> Void) {
        for p in paragraphs.indices { change(&paragraphs[p].style) }
    }

    /// The first run's style, for showing the current formatting.
    var firstRunStyle: RunStyle { paragraphs.first?.runs.first?.style ?? .plain }
    var firstParagraphStyle: ParagraphStyle { paragraphs.first?.style ?? .plain }

    var linkTargets: [String] { paragraphs.flatMap { $0.runs.compactMap(\.style.link) } }
}

struct EdgeInsetsValue: Codable, Hashable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
}

import AppKit

/// A plain sRGB color.
struct RGBColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .black
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent); a = Double(c.alphaComponent)
    }

    static let black = RGBColor(r: 0, g: 0, b: 0)
    static let white = RGBColor(r: 1, g: 1, b: 1)
    static let clear = RGBColor(r: 0, g: 0, b: 0, a: 0)

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    var hexString: String {
        String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func withAlpha(_ alpha: Double) -> RGBColor { RGBColor(r: r, g: g, b: b, a: alpha) }

    /// Mixes toward white (positive) or black (negative); `amount` in -1…1.
    func shaded(_ amount: Double) -> RGBColor {
        guard amount != 0 else { return self }
        if amount > 0 {
            return RGBColor(r: r + (1 - r) * amount, g: g + (1 - g) * amount, b: b + (1 - b) * amount, a: a)
        }
        let f = 1 + amount
        return RGBColor(r: r * f, g: g * f, b: b * f, a: a)
    }

    func mixed(with other: RGBColor, _ t: Double) -> RGBColor {
        RGBColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    /// Relative luminance, for picking legible text over a fill.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    var isDark: Bool { luminance < 0.5 }
}

/// The twelve named colors of a presentation theme, like PowerPoint's.
enum ThemeSlot: String, Codable, CaseIterable, Identifiable {
    case dark1, light1, dark2, light2, accent1, accent2, accent3, accent4, accent5, accent6, hyperlink, followedHyperlink
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark1: "Text/Background – Dark 1"
        case .light1: "Text/Background – Light 1"
        case .dark2: "Text/Background – Dark 2"
        case .light2: "Text/Background – Light 2"
        case .accent1: "Accent 1"
        case .accent2: "Accent 2"
        case .accent3: "Accent 3"
        case .accent4: "Accent 4"
        case .accent5: "Accent 5"
        case .accent6: "Accent 6"
        case .hyperlink: "Hyperlink"
        case .followedHyperlink: "Followed Hyperlink"
        }
    }

    /// Ten columns of the color palette, as PowerPoint shows them.
    static let paletteColumns: [ThemeSlot] = [.light1, .dark1, .light2, .dark2, .accent1, .accent2, .accent3, .accent4, .accent5, .accent6]

    /// The PPTX scheme color name.
    var ooxmlName: String {
        switch self {
        case .dark1: "dk1"
        case .light1: "lt1"
        case .dark2: "dk2"
        case .light2: "lt2"
        case .accent1: "accent1"
        case .accent2: "accent2"
        case .accent3: "accent3"
        case .accent4: "accent4"
        case .accent5: "accent5"
        case .accent6: "accent6"
        case .hyperlink: "hlink"
        case .followedHyperlink: "folHlink"
        }
    }

    static func fromOOXML(_ name: String) -> ThemeSlot? {
        switch name {
        case "tx1": return .dark1
        case "bg1": return .light1
        case "tx2": return .dark2
        case "bg2": return .light2
        default: return allCases.first { $0.ooxmlName == name }
        }
    }
}

/// A color that is either fixed or follows the theme, so changing the theme recolors the deck.
enum PaintColor: Codable, Hashable {
    case rgb(RGBColor)
    /// A theme color, lightened (positive) or darkened (negative) by `shade`, with an alpha.
    case theme(ThemeSlot, shade: Double, alpha: Double)

    static func theme(_ slot: ThemeSlot) -> PaintColor { .theme(slot, shade: 0, alpha: 1) }
    static let black = PaintColor.rgb(.black)
    static let white = PaintColor.rgb(.white)

    func resolve(_ colors: ThemeColors) -> RGBColor {
        switch self {
        case .rgb(let c): return c
        case .theme(let slot, let shade, let alpha): return colors[slot].shaded(shade).withAlpha(alpha)
        }
    }

    func withAlpha(_ alpha: Double, colors: ThemeColors) -> PaintColor {
        switch self {
        case .rgb(let c): return .rgb(c.withAlpha(alpha))
        case .theme(let slot, let shade, _): return .theme(slot, shade: shade, alpha: alpha)
        }
    }

    var alpha: Double {
        switch self {
        case .rgb(let c): return c.a
        case .theme(_, _, let alpha): return alpha
        }
    }
}

/// The color set of a theme.
struct ThemeColors: Codable, Hashable {
    var dark1: RGBColor
    var light1: RGBColor
    var dark2: RGBColor
    var light2: RGBColor
    var accent1: RGBColor
    var accent2: RGBColor
    var accent3: RGBColor
    var accent4: RGBColor
    var accent5: RGBColor
    var accent6: RGBColor
    var hyperlink: RGBColor
    var followedHyperlink: RGBColor

    subscript(slot: ThemeSlot) -> RGBColor {
        get {
            switch slot {
            case .dark1: dark1
            case .light1: light1
            case .dark2: dark2
            case .light2: light2
            case .accent1: accent1
            case .accent2: accent2
            case .accent3: accent3
            case .accent4: accent4
            case .accent5: accent5
            case .accent6: accent6
            case .hyperlink: hyperlink
            case .followedHyperlink: followedHyperlink
            }
        }
        set {
            switch slot {
            case .dark1: dark1 = newValue
            case .light1: light1 = newValue
            case .dark2: dark2 = newValue
            case .light2: light2 = newValue
            case .accent1: accent1 = newValue
            case .accent2: accent2 = newValue
            case .accent3: accent3 = newValue
            case .accent4: accent4 = newValue
            case .accent5: accent5 = newValue
            case .accent6: accent6 = newValue
            case .hyperlink: hyperlink = newValue
            case .followedHyperlink: followedHyperlink = newValue
            }
        }
    }

    init(dark1: RGBColor, light1: RGBColor, dark2: RGBColor, light2: RGBColor, accents: [RGBColor],
         hyperlink: RGBColor? = nil, followedHyperlink: RGBColor? = nil) {
        self.dark1 = dark1; self.light1 = light1; self.dark2 = dark2; self.light2 = light2
        let a = accents + Array(repeating: RGBColor(hex: 0x808080), count: max(0, 6 - accents.count))
        accent1 = a[0]; accent2 = a[1]; accent3 = a[2]; accent4 = a[3]; accent5 = a[4]; accent6 = a[5]
        self.hyperlink = hyperlink ?? RGBColor(hex: 0x1F63C6)
        self.followedHyperlink = followedHyperlink ?? RGBColor(hex: 0x6A3FA0)
    }

    var accents: [RGBColor] { [accent1, accent2, accent3, accent4, accent5, accent6] }
}

/// Standard colors offered under the theme colors in every palette.
enum StandardColors {
    static let all: [RGBColor] = [0xC00000, 0xFF0000, 0xFFC000, 0xFFFF00, 0x92D050, 0x00B050, 0x00B0F0, 0x0070C0, 0x002060, 0x7030A0]
        .map { RGBColor(hex: $0) }
    /// Tints and shades shown under each theme color.
    static let shades: [Double] = [0.8, 0.6, 0.4, -0.25, -0.5]
}

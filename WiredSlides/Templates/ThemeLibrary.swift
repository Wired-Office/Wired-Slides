import AppKit

/// The built-in designs.
enum ThemeLibrary {
    private static func deco(_ kind: ShapeKind, _ rect: CGRect, _ fill: Fill, rotation: Double = 0) -> SlideElement {
        var e = SlideElement.shape(kind, frame: rect, fill: fill, line: .none)
        e.name = "Decoration"
        e.rotation = rotation
        return e
    }

    private static func rule(_ from: CGPoint, _ to: CGPoint, _ color: PaintColor, width: Double = 1) -> SlideElement {
        var e = SlideElement.line(from: from, to: to, style: .solid(color, width: width))
        e.name = "Decoration"
        return e
    }

    private static func c(_ hex: UInt32) -> RGBColor { RGBColor(hex: hex) }

    private static func colors(_ dark1: UInt32, _ light1: UInt32, _ dark2: UInt32, _ light2: UInt32, _ accents: [UInt32]) -> ThemeColors {
        ThemeColors(dark1: c(dark1), light1: c(light1), dark2: c(dark2), light2: c(light2), accents: accents.map(c))
    }

    static let wired: PresentationTheme = {
        var t = PresentationTheme(
            id: "wired", name: "Wired",
            colors: colors(0x1C1C1E, 0xFFFFFF, 0x3A3A3C, 0xF4F2EE, [0xF57A1B, 0x2F6FDB, 0x1E9A5F, 0xD64545, 0x8E5CD9, 0x13A3A3]),
            headingFont: "Helvetica Neue", bodyFont: "Helvetica Neue")
        t.titleBold = true
        t.decorations = [
            deco(.ellipse, CGRect(x: 904, y: 26, width: 18, height: 18), .solid(.theme(.accent1))),
            rule(CGPoint(x: 60, y: 512), CGPoint(x: 900, y: 512), .theme(.dark1, shade: 0.85, alpha: 1)),
        ]
        t.titleDecorations = [
            deco(.ellipse, CGRect(x: 456, y: 70, width: 48, height: 48), .solid(.theme(.accent1))),
        ]
        t.bulletColor = .theme(.accent1)
        t.variants = [
            colors(0x1C1C1E, 0xFFFFFF, 0x3A3A3C, 0xEEF3FB, [0x2F6FDB, 0xF57A1B, 0x1E9A5F, 0xD64545, 0x8E5CD9, 0x13A3A3]),
            colors(0x1C1C1E, 0xFFFFFF, 0x3A3A3C, 0xEDF7F1, [0x1E9A5F, 0x2F6FDB, 0xF57A1B, 0xD64545, 0x8E5CD9, 0x13A3A3]),
            colors(0xF5F5F7, 0x161618, 0xD1D1D6, 0x2C2C2E, [0xF57A1B, 0x5E9BFF, 0x3CCB8A, 0xFF6B6B, 0xB48CFF, 0x3FD1D1]),
        ]
        return t
    }()

    static let clean: PresentationTheme = {
        var t = PresentationTheme(
            id: "clean", name: "Clean",
            colors: colors(0x000000, 0xFFFFFF, 0x44546A, 0xE7E6E6, [0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47]),
            headingFont: "Avenir Next", bodyFont: "Avenir Next")
        t.variants = [
            colors(0x000000, 0xFFFFFF, 0x0E2841, 0xE8E8E8, [0x156082, 0xE97132, 0x196B24, 0x0F9ED5, 0xA02B93, 0x4EA72E]),
            colors(0x000000, 0xFFFFFF, 0x323232, 0xE3DED1, [0xA5644E, 0xB58B80, 0xC3986D, 0xA19574, 0xC17529, 0x7A6A55]),
        ]
        return t
    }()

    static let graphite: PresentationTheme = {
        var t = PresentationTheme(
            id: "graphite", name: "Graphite",
            colors: colors(0xF2F2F2, 0x1E1F22, 0xBDBDC2, 0x2B2D31, [0xFF9F43, 0x54A0FF, 0x1DD1A1, 0xFF6B6B, 0xC8A2FF, 0x48DBFB]),
            headingFont: "Avenir Next", bodyFont: "Avenir Next")
        t.titleBold = true
        t.titleBackground = .gradient(GradientFill(kind: .radial, stops: [
            GradientStop(color: .theme(.light2), position: 0), GradientStop(color: .theme(.light1), position: 1)], angle: 0))
        t.decorations = [deco(.rect, CGRect(x: 0, y: 0, width: 8, height: 540), .solid(.theme(.accent1)))]
        t.titleDecorations = [deco(.rect, CGRect(x: 380, y: 300, width: 200, height: 4), .solid(.theme(.accent1)))]
        t.bulletColor = .theme(.accent1)
        t.variants = [
            colors(0xF2F2F2, 0x1E1F22, 0xBDBDC2, 0x2B2D31, [0x54A0FF, 0xFF9F43, 0x1DD1A1, 0xFF6B6B, 0xC8A2FF, 0x48DBFB]),
            colors(0xF2F2F2, 0x14201B, 0xBDC2BF, 0x22302A, [0x1DD1A1, 0x54A0FF, 0xFF9F43, 0xFF6B6B, 0xC8A2FF, 0x48DBFB]),
            colors(0xF2F2F2, 0x241A26, 0xC2BDC4, 0x33283A, [0xFF6B9A, 0x54A0FF, 0x1DD1A1, 0xFF9F43, 0xC8A2FF, 0x48DBFB]),
        ]
        return t
    }()

    static let ocean: PresentationTheme = {
        var t = PresentationTheme(
            id: "ocean", name: "Ocean",
            colors: colors(0xFFFFFF, 0x0B3D63, 0xD6E9F8, 0x0F5A8F, [0x4FC3F7, 0xFFD54F, 0x81C784, 0xFF8A65, 0xBA68C8, 0x4DD0E1]),
            headingFont: "Gill Sans", bodyFont: "Gill Sans")
        t.background = .gradient(.twoTone(.theme(.light2), .theme(.light1), angle: 60))
        t.decorations = [
            deco(.ellipse, CGRect(x: 760, y: -160, width: 380, height: 380), .solid(.theme(.accent1, shade: 0, alpha: 0.12))),
            deco(.ellipse, CGRect(x: -120, y: 430, width: 260, height: 260), .solid(.theme(.accent1, shade: 0, alpha: 0.10))),
        ]
        t.titleDecorations = [
            deco(.ellipse, CGRect(x: 640, y: -200, width: 520, height: 520), .solid(.theme(.accent1, shade: 0, alpha: 0.14))),
            deco(.ellipse, CGRect(x: -160, y: 360, width: 400, height: 400), .solid(.theme(.accent2, shade: 0, alpha: 0.10))),
        ]
        t.bulletColor = .theme(.accent1)
        t.variants = [
            colors(0xFFFFFF, 0x1B4332, 0xD8F3DC, 0x2D6A4F, [0x95D5B2, 0xFFD166, 0x74C69D, 0xFF8A65, 0xB7E4C7, 0x52B788]),
            colors(0xFFFFFF, 0x3C096C, 0xE0C3FC, 0x5A189A, [0xC77DFF, 0xFFD166, 0x7BDFF2, 0xFF8FAB, 0xE0AAFF, 0x9D4EDD]),
            colors(0xFFFFFF, 0x6A040F, 0xFFD6A5, 0x9D0208, [0xFFBA08, 0xFAA307, 0x90E0EF, 0xF48C06, 0xFFD6A5, 0xE85D04]),
        ]
        return t
    }()

    static let paper: PresentationTheme = {
        var t = PresentationTheme(
            id: "paper", name: "Paper",
            colors: colors(0x3D3226, 0xFBF7F0, 0x5C4B37, 0xEDE4D3, [0xA5644E, 0x6B8F71, 0xC3986D, 0x4F6D7A, 0xC17529, 0x7A6A55]),
            headingFont: "Baskerville", bodyFont: "Gill Sans")
        t.decorations = [
            deco(.frame, CGRect(x: 16, y: 16, width: 928, height: 508), .solid(.theme(.dark2, shade: 0.7, alpha: 1))),
        ]
        t.decorations[0].shape?.adjustments = [0.004]
        t.titleDecorations = [
            rule(CGPoint(x: 400, y: 300), CGPoint(x: 560, y: 300), .theme(.accent1), width: 1.5),
            deco(.frame, CGRect(x: 16, y: 16, width: 928, height: 508), .solid(.theme(.dark2, shade: 0.7, alpha: 1))),
        ]
        t.titleDecorations[1].shape?.adjustments = [0.004]
        t.bulletSymbol = "–"
        t.variants = [
            colors(0x2B2B2B, 0xF7F7F2, 0x4A4A4A, 0xE8E8DF, [0x8C3B3B, 0x3B5F8C, 0x8C7B3B, 0x3B8C6E, 0x6E3B8C, 0x8C5A3B]),
            colors(0x24323D, 0xF3F6F8, 0x3E5463, 0xDDE6EC, [0x3E7CB1, 0xD17A22, 0x5E9C76, 0xB74F6F, 0x7E6BAF, 0x4FA3A5]),
        ]
        return t
    }()

    static let sunset: PresentationTheme = {
        var t = PresentationTheme(
            id: "sunset", name: "Sunset",
            colors: colors(0x2D1E2F, 0xFFFFFF, 0x5B3758, 0xFFF1E6, [0xF76B1C, 0xE8365D, 0xFAB32B, 0x8E44AD, 0x16A085, 0x2980B9]),
            headingFont: "Futura", bodyFont: "Avenir Next")
        t.titleBackground = .gradient(.twoTone(.theme(.accent1), .theme(.accent2), angle: 45))
        t.titleColor = .theme(.dark1)
        t.decorations = [deco(.rect, CGRect(x: 0, y: 0, width: 960, height: 10),
                              .gradient(.twoTone(.theme(.accent1), .theme(.accent2), angle: 0)))]
        t.titleDecorations = [deco(.ellipse, CGRect(x: 700, y: 320, width: 360, height: 360), .solid(.rgb(RGBColor(r: 1, g: 1, b: 1, a: 0.12))))]
        t.titleCaps = true
        t.variants = [
            colors(0x1E2A3A, 0xFFFFFF, 0x34495E, 0xEAF2F8, [0x2E86DE, 0x10AC84, 0xFECA57, 0x5F27CD, 0xEE5253, 0x01A3A4]),
            colors(0x2C1B18, 0xFFFFFF, 0x5D4037, 0xFBE9E7, [0xFF7043, 0xFFCA28, 0xEF5350, 0x8D6E63, 0x26A69A, 0x5C6BC0]),
        ]
        return t
    }()

    static let mono: PresentationTheme = {
        var t = PresentationTheme(
            id: "mono", name: "Mono",
            colors: colors(0x000000, 0xFFFFFF, 0x222222, 0xF0F0F0, [0x000000, 0x555555, 0x888888, 0xBBBBBB, 0xE63946, 0x1D3557]),
            headingFont: "Futura", bodyFont: "Helvetica Neue")
        t.titleBold = true
        t.titleCaps = true
        t.decorations = [deco(.rect, CGRect(x: 60, y: 126, width: 60, height: 6), .solid(.theme(.dark1)))]
        t.titleBackground = .solid(.theme(.dark1))
        t.titleColor = .theme(.light1)
        t.titleDecorations = [deco(.rect, CGRect(x: 450, y: 300, width: 60, height: 6), .solid(.theme(.accent5)))]
        t.bulletSymbol = "▪"
        return t
    }()

    static let blueprint: PresentationTheme = {
        var t = PresentationTheme(
            id: "blueprint", name: "Blueprint",
            colors: colors(0xE8F1FF, 0x0D2B52, 0xA9C5EB, 0x123A6D, [0x6FB1FF, 0xFFD166, 0x06D6A0, 0xEF476F, 0xC3A6FF, 0x7AE7FF]),
            headingFont: "Avenir Next Condensed", bodyFont: "Avenir Next")
        t.background = .pattern(PatternFill(kind: .grid, foreground: .theme(.dark1, shade: 0, alpha: 0.07), background: .theme(.light1)))
        t.titleBold = true
        t.decorations = [rule(CGPoint(x: 60, y: 128), CGPoint(x: 900, y: 128), .theme(.accent1), width: 1.5)]
        t.titleDecorations = [deco(.frame, CGRect(x: 40, y: 40, width: 880, height: 460), .solid(.theme(.accent1, shade: 0, alpha: 0.5)))]
        t.titleDecorations[0].shape?.adjustments = [0.006]
        t.bulletColor = .theme(.accent1)
        return t
    }()

    static let pastel: PresentationTheme = {
        var t = PresentationTheme(
            id: "pastel", name: "Pastel",
            colors: colors(0x3A3550, 0xFBF8FF, 0x5E5878, 0xF1EBFF, [0x9C89FF, 0xFF9AA2, 0x7FD8BE, 0xFFD3A5, 0x8EC5FF, 0xF7A8E0]),
            headingFont: "Avenir Next", bodyFont: "Avenir Next")
        t.decorations = [
            deco(.ellipse, CGRect(x: 850, y: -60, width: 180, height: 180), .solid(.theme(.accent1, shade: 0, alpha: 0.25))),
            deco(.ellipse, CGRect(x: 905, y: 90, width: 70, height: 70), .solid(.theme(.accent2, shade: 0, alpha: 0.35))),
        ]
        t.titleDecorations = [
            deco(.ellipse, CGRect(x: -100, y: -100, width: 320, height: 320), .solid(.theme(.accent1, shade: 0, alpha: 0.25))),
            deco(.ellipse, CGRect(x: 760, y: 360, width: 280, height: 280), .solid(.theme(.accent2, shade: 0, alpha: 0.3))),
            deco(.ellipse, CGRect(x: 820, y: 60, width: 90, height: 90), .solid(.theme(.accent3, shade: 0, alpha: 0.35))),
        ]
        t.bulletColor = .theme(.accent1)
        return t
    }()

    static let forest: PresentationTheme = {
        var t = PresentationTheme(
            id: "forest", name: "Forest",
            colors: colors(0x1F2D24, 0xFFFFFF, 0x2F4A39, 0xEEF4EF, [0x2E7D4F, 0xC9A227, 0x5FA777, 0xA4572B, 0x3E6A8A, 0x8AA05A]),
            headingFont: "Georgia", bodyFont: "Gill Sans")
        t.titleBackground = .solid(.theme(.dark2))
        t.titleColor = .theme(.light1)
        t.decorations = [deco(.rect, CGRect(x: 0, y: 0, width: 24, height: 540), .solid(.theme(.accent1)))]
        t.titleDecorations = [
            deco(.triangle, CGRect(x: 700, y: 330, width: 300, height: 210), .solid(.theme(.accent1, shade: 0, alpha: 0.6))),
            deco(.triangle, CGRect(x: 800, y: 260, width: 220, height: 280), .solid(.theme(.accent3, shade: 0, alpha: 0.5))),
        ]
        return t
    }()

    static let midnight: PresentationTheme = {
        var t = PresentationTheme(
            id: "midnight", name: "Midnight",
            colors: colors(0xF2F2F7, 0x0F172A, 0xCBD5E1, 0x1E293B, [0xF59E0B, 0x60A5FA, 0x34D399, 0xF87171, 0xA78BFA, 0x22D3EE]),
            headingFont: "Helvetica Neue", bodyFont: "Helvetica Neue")
        t.titleBold = true
        t.background = .gradient(.twoTone(.theme(.light1), .theme(.light2), angle: 90))
        t.decorations = [deco(.ellipse, CGRect(x: 896, y: 28, width: 16, height: 16), .solid(.theme(.accent1)))]
        t.titleDecorations = [
            deco(.donut, CGRect(x: 660, y: 240, width: 420, height: 420), .solid(.theme(.accent1, shade: 0, alpha: 0.15))),
            deco(.ellipse, CGRect(x: 120, y: 90, width: 24, height: 24), .solid(.theme(.accent1))),
        ]
        t.titleDecorations[0].shape?.adjustments = [0.08]
        t.bulletColor = .theme(.accent1)
        return t
    }()

    static let facet: PresentationTheme = {
        var t = PresentationTheme(
            id: "facet", name: "Facet",
            colors: colors(0x213F21, 0xFFFFFF, 0x2C3C43, 0xEBEBEB, [0x90C226, 0x54A021, 0xE6B91E, 0xE76618, 0xC42F1A, 0x918655]),
            headingFont: "Trebuchet MS", bodyFont: "Trebuchet MS")
        t.titleColor = .theme(.accent2, shade: -0.25, alpha: 1)
        t.decorations = [
            deco(.rtTriangle, CGRect(x: 880, y: 380, width: 80, height: 160), .solid(.theme(.accent1)), rotation: 0),
            deco(.rtTriangle, CGRect(x: 840, y: 460, width: 120, height: 80), .solid(.theme(.accent2, shade: 0, alpha: 0.8))),
        ]
        t.decorations[0].flipH = true
        t.decorations[1].flipH = true
        t.titleDecorations = [
            deco(.rtTriangle, CGRect(x: 760, y: 220, width: 200, height: 320), .solid(.theme(.accent1))),
            deco(.rtTriangle, CGRect(x: 680, y: 380, width: 280, height: 160), .solid(.theme(.accent2, shade: 0, alpha: 0.85))),
        ]
        t.titleDecorations[0].flipH = true
        t.titleDecorations[1].flipH = true
        t.bulletColor = .theme(.accent1)
        return t
    }()

    static let all: [PresentationTheme] = [wired, clean, graphite, ocean, paper, sunset, mono, blueprint, pastel, forest, midnight, facet]

    static var `default`: PresentationTheme { all.first { $0.id == AppSettings.shared.defaultThemeID } ?? wired }
}

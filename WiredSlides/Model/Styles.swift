import AppKit

struct GradientStop: Codable, Hashable {
    var color: PaintColor
    var position: Double
}

struct GradientFill: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable { case linear, radial }
    var kind: Kind = .linear
    var stops: [GradientStop]
    /// Degrees, 0 = left to right, 90 = top to bottom.
    var angle: Double = 90

    static func twoTone(_ a: PaintColor, _ b: PaintColor, angle: Double = 90) -> GradientFill {
        GradientFill(stops: [GradientStop(color: a, position: 0), GradientStop(color: b, position: 1)], angle: angle)
    }
}

struct ImageFill: Codable, Hashable {
    enum Mode: String, Codable, CaseIterable { case stretch, tile, fit }
    var mediaID: String
    var mode: Mode = .stretch
    var transparency: Double = 0
}

enum PatternKind: String, Codable, CaseIterable, Identifiable {
    case horizontal, vertical, diagonalUp, diagonalDown, grid, dots, checker
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .diagonalUp: "Diagonal Up"
        case .diagonalDown: "Diagonal Down"
        case .grid: "Grid"
        case .dots: "Dots"
        case .checker: "Checkerboard"
        }
    }
}

struct PatternFill: Codable, Hashable {
    var kind: PatternKind
    var foreground: PaintColor
    var background: PaintColor
}

enum Fill: Codable, Hashable {
    case none
    case solid(PaintColor)
    case gradient(GradientFill)
    case image(ImageFill)
    case pattern(PatternFill)

    var isNone: Bool { if case .none = self { return true }; return false }

    var solidColor: PaintColor? { if case .solid(let c) = self { return c }; return nil }

    /// A representative color, for swatches and contrast decisions.
    func representative(_ colors: ThemeColors) -> RGBColor? {
        switch self {
        case .none, .image: return nil
        case .solid(let c): return c.resolve(colors)
        case .gradient(let g): return g.stops.first?.color.resolve(colors)
        case .pattern(let p): return p.background.resolve(colors)
        }
    }

    var mediaIDs: [String] { if case .image(let f) = self { return [f.mediaID] }; return [] }
}

enum DashStyle: String, Codable, CaseIterable, Identifiable {
    case solid, roundDot, squareDot, dash, dashDot, longDash, longDashDot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .roundDot: "Round Dot"
        case .squareDot: "Square Dot"
        case .dash: "Dash"
        case .dashDot: "Dash Dot"
        case .longDash: "Long Dash"
        case .longDashDot: "Long Dash Dot"
        }
    }

    func pattern(width: CGFloat) -> [CGFloat] {
        let w = max(width, 1)
        switch self {
        case .solid: return []
        case .roundDot: return [0.01, w * 2]
        case .squareDot: return [w, w]
        case .dash: return [w * 4, w * 3]
        case .dashDot: return [w * 4, w * 3, w, w * 3]
        case .longDash: return [w * 8, w * 3]
        case .longDashDot: return [w * 8, w * 3, w, w * 3]
        }
    }

    var ooxml: String {
        switch self {
        case .solid: "solid"
        case .roundDot: "sysDot"
        case .squareDot: "sysDash"
        case .dash: "dash"
        case .dashDot: "dashDot"
        case .longDash: "lgDash"
        case .longDashDot: "lgDashDot"
        }
    }

    static func fromOOXML(_ value: String) -> DashStyle {
        allCases.first { $0.ooxml == value } ?? (value == "sysDashDot" ? .dashDot : .solid)
    }
}

enum ArrowHead: String, Codable, CaseIterable, Identifiable {
    case none, triangle, open, stealth, diamond, oval
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .triangle: "Arrow"
        case .open: "Open Arrow"
        case .stealth: "Stealth Arrow"
        case .diamond: "Diamond"
        case .oval: "Oval"
        }
    }

    var ooxml: String {
        switch self {
        case .none: "none"
        case .triangle: "triangle"
        case .open: "arrow"
        case .stealth: "stealth"
        case .diamond: "diamond"
        case .oval: "oval"
        }
    }

    static func fromOOXML(_ value: String) -> ArrowHead {
        allCases.first { $0.ooxml == value } ?? .none
    }
}

struct LineStyle: Codable, Hashable {
    var color: PaintColor?
    var width: Double = 1
    var dash: DashStyle = .solid
    var head: ArrowHead = .none
    var tail: ArrowHead = .none
    var roundCaps = false

    static let none = LineStyle(color: nil)
    static func solid(_ color: PaintColor, width: Double = 1) -> LineStyle { LineStyle(color: color, width: width) }

    var isVisible: Bool { color != nil && width > 0 }
}

struct ShadowEffect: Codable, Hashable {
    var color: RGBColor = .black
    var opacity: Double = 0.35
    var blur: Double = 8
    var distance: Double = 4
    /// Degrees, direction the shadow falls; 90 = straight down.
    var angle: Double = 45

    static let outer = ShadowEffect()
    static let soft = ShadowEffect(opacity: 0.25, blur: 18, distance: 6, angle: 90)
}

struct GlowEffect: Codable, Hashable {
    var color: PaintColor = .theme(.accent1, shade: 0, alpha: 0.6)
    var radius: Double = 8
}

struct ReflectionEffect: Codable, Hashable {
    var opacity: Double = 0.4
    /// Fraction of the shape that is reflected.
    var size: Double = 0.4
    var distance: Double = 2
}

struct Effects: Codable, Hashable {
    var shadow: ShadowEffect?
    var glow: GlowEffect?
    var reflection: ReflectionEffect?
    /// Softens the edges, in points.
    var softEdges: Double = 0

    static let none = Effects()
    var isEmpty: Bool { shadow == nil && glow == nil && reflection == nil && softEdges == 0 }
}

/// Picture adjustments.
struct ImageAdjustments: Codable, Hashable {
    var brightness: Double = 0     // -1…1
    var contrast: Double = 0       // -1…1
    var saturation: Double = 1     // 0 = grayscale
    var transparency: Double = 0   // 0…1
    var sepia = false

    var isIdentity: Bool { brightness == 0 && contrast == 0 && saturation == 1 && !sepia }
}

/// Fractions of the image cropped away on each side.
struct CropInsets: Codable, Hashable {
    var left: Double = 0
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0

    var isZero: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }
}

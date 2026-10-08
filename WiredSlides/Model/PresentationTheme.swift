import AppKit

/// A design: colors, fonts, background and decorative graphics, like a PowerPoint theme + master.
struct PresentationTheme: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var colors: ThemeColors
    var headingFont: String
    var bodyFont: String
    var background: Fill = .solid(.theme(.light1))
    /// Graphics drawn behind every content slide, laid out for a 960×540 slide and scaled.
    var decorations: [SlideElement] = []
    /// Graphics drawn behind title and section header slides.
    var titleDecorations: [SlideElement] = []
    /// A different background for title and section slides.
    var titleBackground: Fill?
    var titleColor: PaintColor = .theme(.dark1)
    var titleSize: Double = 40
    var titleBold = false
    var titleCaps = false
    var bodySize: Double = 24
    var bulletSymbol = "•"
    var bulletColor: PaintColor?
    /// Alternate color sets (Design ▸ Variants).
    var variants: [ThemeColors] = []

    var mediaIDs: [String] {
        background.mediaIDs + (titleBackground?.mediaIDs ?? []) + decorations.flatMap(\.mediaIDs) + titleDecorations.flatMap(\.mediaIDs)
    }

    func font(for role: FontRole) -> String { role == .heading ? headingFont : bodyFont }
}

/// Named font pairs (Design ▸ Fonts).
struct FontPair: Hashable, Identifiable {
    let name: String
    let heading: String
    let body: String
    var id: String { name }

    static let all: [FontPair] = [
        FontPair(name: "Helvetica Neue", heading: "Helvetica Neue", body: "Helvetica Neue"),
        FontPair(name: "Avenir", heading: "Avenir Next", body: "Avenir Next"),
        FontPair(name: "Georgia", heading: "Georgia", body: "Georgia"),
        FontPair(name: "Classic", heading: "Baskerville", body: "Gill Sans"),
        FontPair(name: "Futura", heading: "Futura", body: "Avenir"),
        FontPair(name: "Didot", heading: "Didot", body: "Helvetica Neue"),
        FontPair(name: "Rockwell", heading: "Rockwell", body: "Gill Sans"),
        FontPair(name: "Optima", heading: "Optima", body: "Optima"),
        FontPair(name: "Palatino", heading: "Palatino", body: "Palatino"),
        FontPair(name: "System", heading: "SF Pro Display", body: "SF Pro Text"),
        FontPair(name: "Menlo", heading: "Menlo", body: "Menlo"),
        FontPair(name: "American Typewriter", heading: "American Typewriter", body: "Courier New"),
        FontPair(name: "Calibri", heading: "Calibri Light", body: "Calibri"),
        FontPair(name: "Arial", heading: "Arial", body: "Arial"),
    ]
}

/// Named color sets (Design ▸ Colors).
enum ColorSchemes {
    static let all: [(name: String, colors: ThemeColors)] = [
        ("Wired", ThemeColors(dark1: RGBColor(hex: 0x1C1C1E), light1: .white, dark2: RGBColor(hex: 0x3A3A3C), light2: RGBColor(hex: 0xF2F0EC),
                              accents: [0xF57A1B, 0x2F6FDB, 0x1E9A5F, 0xD64545, 0x8E5CD9, 0x13A3A3].map { RGBColor(hex: $0) })),
        ("Office", ThemeColors(dark1: .black, light1: .white, dark2: RGBColor(hex: 0x44546A), light2: RGBColor(hex: 0xE7E6E6),
                               accents: [0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47].map { RGBColor(hex: $0) })),
        ("Blue", ThemeColors(dark1: RGBColor(hex: 0x17406D), light1: .white, dark2: RGBColor(hex: 0x0F6FC6), light2: RGBColor(hex: 0xDBEFF9),
                             accents: [0x0F6FC6, 0x009DD9, 0x0BD0D9, 0x10CF9B, 0x7CCA62, 0xA5C249].map { RGBColor(hex: $0) })),
        ("Green", ThemeColors(dark1: RGBColor(hex: 0x1D3A26), light1: .white, dark2: RGBColor(hex: 0x455F51), light2: RGBColor(hex: 0xE3DED1),
                              accents: [0x549E39, 0x8AB833, 0xC0CF3A, 0x029676, 0x4AB5C4, 0x0989B1].map { RGBColor(hex: $0) })),
        ("Red Orange", ThemeColors(dark1: RGBColor(hex: 0x3B1E12), light1: .white, dark2: RGBColor(hex: 0x505046), light2: RGBColor(hex: 0xEEECE1),
                                   accents: [0xE84C22, 0xFFBD47, 0xB64926, 0xFF8427, 0xCC9900, 0xB22600].map { RGBColor(hex: $0) })),
        ("Violet", ThemeColors(dark1: RGBColor(hex: 0x2E1A47), light1: .white, dark2: RGBColor(hex: 0x373545), light2: RGBColor(hex: 0xDCD8DC),
                               accents: [0xAD84C6, 0x8784C7, 0x5D739A, 0x6997AF, 0x84ACB6, 0x6F8183].map { RGBColor(hex: $0) })),
        ("Paper", ThemeColors(dark1: RGBColor(hex: 0x3D3226), light1: RGBColor(hex: 0xFBF7F0), dark2: RGBColor(hex: 0x5C4B37), light2: RGBColor(hex: 0xEDE4D3),
                              accents: [0xA5644E, 0xB58B80, 0xC3986D, 0xA19574, 0xC17529, 0x7A6A55].map { RGBColor(hex: $0) })),
        ("Grayscale", ThemeColors(dark1: .black, light1: .white, dark2: .black, light2: RGBColor(hex: 0xF8F8F8),
                                  accents: [0xDDDDDD, 0xB2B2B2, 0x969696, 0x808080, 0x5F5F5F, 0x4D4D4D].map { RGBColor(hex: $0) })),
        ("Midnight", ThemeColors(dark1: RGBColor(hex: 0xF2F2F7), light1: RGBColor(hex: 0x111827), dark2: RGBColor(hex: 0xC7CBD6), light2: RGBColor(hex: 0x1F2937),
                                 accents: [0xF59E0B, 0x60A5FA, 0x34D399, 0xF87171, 0xA78BFA, 0x22D3EE].map { RGBColor(hex: $0) })),
        ("Marquee", ThemeColors(dark1: RGBColor(hex: 0x1F2A33), light1: .white, dark2: RGBColor(hex: 0x5E5E5E), light2: RGBColor(hex: 0xDDDDDD),
                                accents: [0x418AB3, 0xA6B727, 0xF69200, 0x838383, 0xFEC306, 0xDF5327].map { RGBColor(hex: $0) })),
    ]
}

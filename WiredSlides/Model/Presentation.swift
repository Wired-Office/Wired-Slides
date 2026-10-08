import AppKit

struct SlideComment: Codable, Hashable, Identifiable {
    var id = UUID()
    var author: String
    var date: Date
    var text: String
    var resolved = false
    var replies: [SlideComment] = []
    /// Where the marker sits on the slide.
    var position = CGPoint(x: 10, y: 10)
}

struct Slide: Codable, Hashable, Identifiable {
    var id = UUID()
    var layout: LayoutKind
    var elements: [SlideElement] = []
    /// Overrides the theme background.
    var background: Fill?
    var notes = ""
    var transition = Transition()
    var animations: [SlideAnimation] = []
    var hidden = false
    var comments: [SlideComment] = []
    /// Hides the theme's decorative graphics on this slide.
    var hideBackgroundGraphics = false

    init(layout: LayoutKind) {
        self.layout = layout
    }

    func element(_ id: UUID) -> SlideElement? {
        for e in elements { if let found = e.find(id) { return found } }
        return nil
    }

    func index(of id: UUID) -> Int? { elements.firstIndex { $0.id == id } }

    var title: String {
        let titled = elements.first { $0.placeholder?.isTitle == true }?.text?.plainText
            ?? elements.first { $0.hasText }?.text?.plainText
        return titled?.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    var mediaIDs: [String] { elements.flatMap(\.mediaIDs) + (background?.mediaIDs ?? []) }

    /// Animations whose element still exists, in order.
    var validAnimations: [SlideAnimation] { animations.filter { element($0.elementID) != nil } }
}

struct SlideSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// The section starts at this slide.
    var firstSlideID: UUID
}

struct MediaItem: Codable, Hashable {
    var filename: String
    var data: Data

    var isImage: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "bmp", "webp", "pdf", "svg"].contains(ext)
    }
}

struct HeaderFooter: Codable, Hashable {
    var showDate = false
    /// Fixed date text; nil updates automatically.
    var fixedDate: String?
    var showSlideNumber = false
    var showFooter = false
    var footerText = ""
    var hideOnTitleSlide = true
}

struct SlideShowSettings: Codable, Hashable {
    var loopUntilEscape = false
    var showWithoutAnimation = false
    var useTimings = true
    var usePresenterView = true
    var penColor: RGBColor = RGBColor(hex: 0xE53935)
    var laserColor: RGBColor = RGBColor(hex: 0xFF1E1E)
}

struct Presentation: Codable, Hashable {
    var slides: [Slide]
    var theme: PresentationTheme
    var slideSize = CGSize(width: 960, height: 540)
    var sections: [SlideSection] = []
    var headerFooter = HeaderFooter()
    var showSettings = SlideShowSettings()
    var title = ""
    var author = ""
    var created = Date()
    /// Media (pictures, video, audio) by id, stored once and referenced from elements.
    var media: [String: MediaItem] = [:]

    init(theme: PresentationTheme = ThemeLibrary.default, slides: [Slide]? = nil) {
        self.theme = theme
        self.slides = slides ?? []
        if self.slides.isEmpty {
            self.slides = [LayoutBuilder.makeSlide(.title, theme: theme, size: slideSize)]
        }
    }

    func slideIndex(_ id: UUID) -> Int? { slides.firstIndex { $0.id == id } }

    /// Removes media no element uses any more.
    mutating func pruneMedia() {
        let used = Set(slides.flatMap(\.mediaIDs) + theme.mediaIDs)
        media = media.filter { used.contains($0.key) }
    }

    mutating func addMedia(_ data: Data, filename: String) -> String {
        // Reuse identical data.
        if let existing = media.first(where: { $0.value.data == data })?.key { return existing }
        let ext = (filename as NSString).pathExtension.lowercased()
        let id = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        media[id] = MediaItem(filename: filename, data: data)
        return id
    }

    /// The section containing a slide.
    func section(forSlideAt index: Int) -> SlideSection? {
        var current: SlideSection?
        for (i, slide) in slides.enumerated() where i <= index {
            if let s = sections.first(where: { $0.firstSlideID == slide.id }) { current = s }
        }
        return current
    }

    /// Visible slide indices for a slide show.
    var visibleSlideIndices: [Int] { slides.indices.filter { !slides[$0].hidden } }

    static let standardSizes: [(name: String, size: CGSize)] = [
        ("Widescreen (16:9)", CGSize(width: 960, height: 540)),
        ("Standard (4:3)", CGSize(width: 720, height: 540)),
        ("16:10", CGSize(width: 960, height: 600)),
        ("Letter Paper (8.5×11 in)", CGSize(width: 720, height: 540)),
        ("A4 Paper (210×297 mm)", CGSize(width: 780, height: 540)),
        ("Square (1:1)", CGSize(width: 720, height: 720)),
        ("Portrait (9:16)", CGSize(width: 540, height: 960)),
        ("Banner", CGSize(width: 576, height: 72)),
    ]
}

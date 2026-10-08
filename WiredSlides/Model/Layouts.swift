import AppKit

enum LayoutKind: String, Codable, CaseIterable, Identifiable {
    case title, titleContent, sectionHeader, twoContent, comparison, titleOnly, blank, contentCaption, pictureCaption, quote, bigNumber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: "Title Slide"
        case .titleContent: "Title and Content"
        case .sectionHeader: "Section Header"
        case .twoContent: "Two Content"
        case .comparison: "Comparison"
        case .titleOnly: "Title Only"
        case .blank: "Blank"
        case .contentCaption: "Content with Caption"
        case .pictureCaption: "Picture with Caption"
        case .quote: "Quote"
        case .bigNumber: "Big Number"
        }
    }

    /// Uses the theme's title-slide background and decorations.
    var isTitleStyle: Bool { self == .title || self == .sectionHeader }

    var ooxmlType: String {
        switch self {
        case .title: "title"
        case .titleContent: "obj"
        case .sectionHeader: "secHead"
        case .twoContent: "twoObj"
        case .comparison: "twoTxTwoObj"
        case .titleOnly: "titleOnly"
        case .blank: "blank"
        case .contentCaption: "objTx"
        case .pictureCaption: "picTx"
        case .quote: "obj"
        case .bigNumber: "obj"
        }
    }

    static func fromOOXML(_ type: String?) -> LayoutKind {
        allCases.first { $0.ooxmlType == type } ?? .titleContent
    }
}

/// Builds the placeholders of each layout for a theme and slide size.
enum LayoutBuilder {
    struct Spec {
        var role: PlaceholderRole
        var rect: CGRect           // in a 960×540 design space
        var prompt: String
        var size: Double
        var heading: Bool
        var alignment: TextAlignment = .left
        var anchor: VerticalAnchor = .top
        var bullets = false
        var bold = false
        var colorShade: Double = 0
    }

    static func specs(_ layout: LayoutKind, theme: PresentationTheme) -> [Spec] {
        let t = theme.titleSize, b = theme.bodySize
        let title = Spec(role: .title, rect: CGRect(x: 60, y: 30, width: 840, height: 96), prompt: "Click to add title", size: t, heading: true, anchor: .middle)
        switch layout {
        case .title:
            return [
                Spec(role: .centeredTitle, rect: CGRect(x: 120, y: 120, width: 720, height: 170), prompt: "Click to add title",
                     size: t * 1.4, heading: true, alignment: .center, anchor: .bottom),
                Spec(role: .subtitle, rect: CGRect(x: 120, y: 304, width: 720, height: 110), prompt: "Click to add subtitle",
                     size: b, heading: false, alignment: .center, colorShade: 0.25),
            ]
        case .titleContent:
            return [title, Spec(role: .body, rect: CGRect(x: 60, y: 140, width: 840, height: 350), prompt: "Click to add text", size: b, heading: false, bullets: true)]
        case .sectionHeader:
            return [
                Spec(role: .title, rect: CGRect(x: 66, y: 130, width: 828, height: 200), prompt: "Click to add section title",
                     size: t * 1.4, heading: true, anchor: .bottom),
                Spec(role: .body, rect: CGRect(x: 66, y: 340, width: 828, height: 90), prompt: "Click to add text",
                     size: b * 0.85, heading: false, colorShade: 0.3),
            ]
        case .twoContent:
            return [
                title,
                Spec(role: .body, rect: CGRect(x: 60, y: 140, width: 410, height: 350), prompt: "Click to add text", size: b * 0.9, heading: false, bullets: true),
                Spec(role: .body, rect: CGRect(x: 490, y: 140, width: 410, height: 350), prompt: "Click to add text", size: b * 0.9, heading: false, bullets: true),
            ]
        case .comparison:
            return [
                title,
                Spec(role: .body, rect: CGRect(x: 60, y: 136, width: 410, height: 52), prompt: "Click to add text", size: b, heading: false, anchor: .bottom, bold: true),
                Spec(role: .body, rect: CGRect(x: 60, y: 194, width: 410, height: 296), prompt: "Click to add text", size: b * 0.85, heading: false, bullets: true),
                Spec(role: .body, rect: CGRect(x: 490, y: 136, width: 410, height: 52), prompt: "Click to add text", size: b, heading: false, anchor: .bottom, bold: true),
                Spec(role: .body, rect: CGRect(x: 490, y: 194, width: 410, height: 296), prompt: "Click to add text", size: b * 0.85, heading: false, bullets: true),
            ]
        case .titleOnly:
            return [title]
        case .blank:
            return []
        case .contentCaption:
            return [
                Spec(role: .title, rect: CGRect(x: 60, y: 40, width: 320, height: 120), prompt: "Click to add title", size: t * 0.75, heading: true, anchor: .bottom),
                Spec(role: .body, rect: CGRect(x: 420, y: 40, width: 480, height: 450), prompt: "Click to add text", size: b, heading: false, bullets: true),
                Spec(role: .body, rect: CGRect(x: 60, y: 175, width: 320, height: 315), prompt: "Click to add text", size: b * 0.65, heading: false, colorShade: 0.2),
            ]
        case .pictureCaption:
            return [
                Spec(role: .title, rect: CGRect(x: 60, y: 40, width: 320, height: 120), prompt: "Click to add title", size: t * 0.75, heading: true, anchor: .bottom),
                Spec(role: .picture, rect: CGRect(x: 420, y: 40, width: 480, height: 450), prompt: "Click icon to add picture", size: b, heading: false, alignment: .center, anchor: .middle),
                Spec(role: .body, rect: CGRect(x: 60, y: 175, width: 320, height: 315), prompt: "Click to add text", size: b * 0.65, heading: false, colorShade: 0.2),
            ]
        case .quote:
            return [
                Spec(role: .title, rect: CGRect(x: 120, y: 110, width: 720, height: 220), prompt: "\u{201C}Click to add a quote\u{201D}",
                     size: t * 0.9, heading: true, alignment: .center, anchor: .middle),
                Spec(role: .body, rect: CGRect(x: 120, y: 350, width: 720, height: 60), prompt: "— Click to add source", size: b * 0.8,
                     heading: false, alignment: .center, colorShade: 0.3),
            ]
        case .bigNumber:
            return [
                Spec(role: .title, rect: CGRect(x: 60, y: 90, width: 840, height: 220), prompt: "100%", size: 120, heading: true,
                     alignment: .center, anchor: .bottom, bold: true),
                Spec(role: .body, rect: CGRect(x: 60, y: 320, width: 840, height: 100), prompt: "Click to add text", size: b,
                     heading: false, alignment: .center, colorShade: 0.25),
            ]
        }
    }

    static func scaled(_ rect: CGRect, to size: CGSize) -> CGRect {
        let sx = size.width / 960, sy = size.height / 540
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
    }

    static func placeholder(_ spec: Spec, theme: PresentationTheme, size: CGSize) -> SlideElement {
        var body = TextBody()
        var run = RunStyle()
        if spec.bold || (spec.heading && theme.titleBold) { run.bold = true }
        if spec.heading && theme.titleCaps { run.allCaps = true }
        var paragraph = ParagraphStyle(alignment: spec.alignment)
        if spec.bullets {
            paragraph.bullet = .symbol(theme.bulletSymbol)
            paragraph.bulletColor = theme.bulletColor
            paragraph.spaceBefore = 8
        }
        if spec.heading { paragraph.lineSpacing = 0.9 }
        body.paragraphs = [Paragraph(runs: [TextRun(text: "", style: run)], style: paragraph)]
        body.defaultSize = spec.size
        body.fontRole = spec.heading ? .heading : .body
        body.anchor = spec.anchor
        body.autofit = .shrink
        body.prompt = spec.prompt
        if spec.heading {
            body.defaultColor = theme.titleColor
        } else {
            body.defaultColor = spec.colorShade == 0 ? .theme(.dark1) : .theme(.dark1, shade: spec.colorShade, alpha: 1)
        }
        let name: String
        switch spec.role {
        case .title, .centeredTitle: name = "Title"
        case .subtitle: name = "Subtitle"
        case .picture: name = "Picture Placeholder"
        default: name = "Content Placeholder"
        }
        return SlideElement(name: name, frame: scaled(spec.rect, to: size),
                            content: .shape(ShapeContent(kind: .rect, fill: .none, line: .none, text: body)),
                            placeholder: spec.role)
    }

    static func makeSlide(_ layout: LayoutKind, theme: PresentationTheme, size: CGSize) -> Slide {
        var slide = Slide(layout: layout)
        var count: [PlaceholderRole: Int] = [:]
        slide.elements = specs(layout, theme: theme).map { spec in
            var element = placeholder(spec, theme: theme, size: size)
            count[spec.role, default: 0] += 1
            if count[spec.role]! > 1 { element.name += " \(count[spec.role]!)" }
            return element
        }
        return slide
    }

    /// Applies a different layout to a slide, moving existing placeholder text into the new placeholders.
    static func apply(_ layout: LayoutKind, to slide: inout Slide, theme: PresentationTheme, size: CGSize) {
        let fresh = makeSlide(layout, theme: theme, size: size).elements
        var oldPlaceholders = slide.elements.filter { $0.placeholder != nil }
        var others = slide.elements.filter { $0.placeholder == nil }
        var result: [SlideElement] = []
        for var target in fresh {
            let wantsTitle = target.placeholder!.isTitle
            if let i = oldPlaceholders.firstIndex(where: { ($0.placeholder!.isTitle == wantsTitle) && ($0.placeholder == .picture) == (target.placeholder == .picture) }) {
                let old = oldPlaceholders.remove(at: i)
                if let oldText = old.text, !oldText.isEmpty, var newText = target.text {
                    newText.paragraphs = oldText.paragraphs
                    target.text = newText
                } else if old.placeholder == .picture, !old.mediaIDs.isEmpty {
                    var moved = old
                    moved.frame = target.frame
                    result.append(moved)
                    continue
                }
                target.id = old.id
            }
            result.append(target)
        }
        // Placeholders with content that found no home become ordinary elements.
        for leftover in oldPlaceholders where leftover.hasText || leftover.isImage {
            var e = leftover
            e.placeholder = nil
            others.append(e)
        }
        slide.layout = layout
        slide.elements = result + others
    }

    /// Restores placeholder positions and formatting of the layout (Reset).
    static func reset(_ slide: inout Slide, theme: PresentationTheme, size: CGSize) {
        let fresh = makeSlide(slide.layout, theme: theme, size: size).elements
        var used = Set<UUID>()
        for i in slide.elements.indices {
            guard let role = slide.elements[i].placeholder else { continue }
            guard let match = fresh.first(where: { $0.placeholder == role && !used.contains($0.id) }) else { continue }
            used.insert(match.id)
            slide.elements[i].frame = match.frame
            slide.elements[i].rotation = 0
            if var text = slide.elements[i].text, let freshText = match.text {
                let paragraphStyle = freshText.paragraphs.first?.style ?? .plain
                let runStyle = freshText.paragraphs.first?.runs.first?.style ?? .plain
                text.paragraphs = text.paragraphs.map { p in
                    var style = paragraphStyle
                    style.level = p.style.level
                    return Paragraph(runs: p.runs.map { TextRun(text: $0.text, style: runStyle) }, style: style)
                }
                text.defaultSize = freshText.defaultSize
                text.defaultColor = freshText.defaultColor
                text.anchor = freshText.anchor
                text.fontRole = freshText.fontRole
                slide.elements[i].text = text
            }
            if case .shape(var s) = slide.elements[i].content {
                s.fill = .none
                s.line = .none
                s.effects = .none
                slide.elements[i].content = .shape(s)
            }
        }
    }
}

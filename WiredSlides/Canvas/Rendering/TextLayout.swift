import AppKit

extension NSAttributedString.Key {
    /// A `ParagraphBox` carrying the model's paragraph style (bullets and levels).
    static let wsParagraph = NSAttributedString.Key("WSParagraph")
    /// A `RunBox` carrying the model's run style (theme colors and fonts survive editing).
    static let wsRun = NSAttributedString.Key("WSRun")
}

final class ParagraphBox: NSObject {
    let style: ParagraphStyle
    let color: NSColor
    /// Where the list marker starts, from the left of the text container.
    let markerX: CGFloat
    init(_ style: ParagraphStyle, color: NSColor, markerX: CGFloat) {
        self.style = style
        self.color = color
        self.markerX = markerX
    }
    override func isEqual(_ object: Any?) -> Bool { (object as? ParagraphBox)?.style == style }
    override var hash: Int { style.hashValue }
}

final class RunBox: NSObject {
    let style: RunStyle
    init(_ style: RunStyle) { self.style = style }
    override func isEqual(_ object: Any?) -> Bool { (object as? RunBox)?.style == style }
    override var hash: Int { style.hashValue }
}

enum FontResolver {
    private static var cache: [String: NSFont] = [:]

    static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let key = "\(family)|\(size)|\(bold)|\(italic)"
        if let f = cache[key] { return f }
        let manager = NSFontManager.shared
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        var font = manager.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: size)
            ?? manager.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
        if font == nil {
            font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic, let f = font { font = manager.convert(f, toHaveTrait: .italicFontMask) }
        } else if let f = font {
            if bold && !manager.traits(of: f).contains(.boldFontMask) { font = manager.convert(f, toHaveTrait: .boldFontMask) }
            if italic && !manager.traits(of: f).contains(.italicFontMask) { font = manager.convert(font!, toHaveTrait: .italicFontMask) }
        }
        cache[key] = font!
        return font!
    }

    static func isAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}

/// Draws list markers (bullets and numbers) in the hanging indent of each paragraph.
final class BulletLayoutManager: NSLayoutManager {
    /// Show markers on empty paragraphs (while editing).
    var showsEmptyMarkers = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        let string = storage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var counters: [Int: Int] = [:]   // level → current number
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            defer { location = NSMaxRange(paragraph) }
            guard let box = storage.attribute(.wsParagraph, at: paragraph.location, effectiveRange: nil) as? ParagraphBox else {
                counters = [:]
                continue
            }
            let style = box.style
            // Numbering restarts after a shallower paragraph.
            counters = counters.filter { $0.key <= style.level }
            var label: String?
            switch style.bullet {
            case .none:
                counters[style.level] = nil
            case .symbol(let symbol):
                label = symbol
            case .numbered(let scheme, let start):
                let n = (counters[style.level] ?? (start - 1)) + 1
                counters[style.level] = n
                label = scheme.label(n)
            }
            guard let label else { continue }
            let isEmpty = paragraph.length == 0 || string.substring(with: paragraph).trimmingCharacters(in: .newlines).isEmpty
            if isEmpty && !showsEmptyMarkers { continue }
            guard NSLocationInRange(paragraph.location, NSRange(location: charRange.location, length: max(charRange.length, 1)))
                    || paragraph.location == charRange.location else { continue }
            let glyph = glyphIndexForCharacter(at: paragraph.location)
            guard glyph < numberOfGlyphs else { continue }
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            drawMarker(label, storage: storage, at: paragraph.location, style: style, box: box, line: line, glyph: glyph, origin: origin)
        }
        // The empty last paragraph (after a trailing newline) while editing.
        if showsEmptyMarkers, string.length > 0, string.character(at: string.length - 1) == 10, !extraLineFragmentRect.isEmpty,
           let box = storage.attribute(.wsParagraph, at: string.length - 1, effectiveRange: nil) as? ParagraphBox,
           case .symbol(let symbol) = box.style.bullet {
            drawMarker(symbol, storage: storage, at: string.length - 1, style: box.style, box: box, line: extraLineFragmentRect, glyph: nil, origin: origin)
        }
    }

    private func drawMarker(_ label: String, storage: NSTextStorage, at index: Int, style: ParagraphStyle, box: ParagraphBox,
                            line: CGRect, glyph: Int?, origin: NSPoint) {
        let textFont = (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 18)
        let textColor = (storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor) ?? box.color
        let isNumber: Bool = { if case .numbered = style.bullet { return true }; return false }()
        let markerFont = isNumber ? textFont : NSFont(descriptor: textFont.fontDescriptor, size: textFont.pointSize) ?? textFont
        let paragraphStyle = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        var x = origin.x + line.minX + box.markerX
        // Centered and right-aligned bulleted lines carry their marker with them.
        if let paragraphStyle, paragraphStyle.alignment != .left && paragraphStyle.alignment != .natural && paragraphStyle.alignment != .justified, let glyph {
            x = origin.x + line.minX + location(forGlyphAt: glyph).x - (paragraphStyle.headIndent - box.markerX)
        }
        let baseline: CGFloat
        if let glyph {
            baseline = line.minY + location(forGlyphAt: glyph).y
        } else {
            baseline = line.minY + markerFont.ascender + (line.height - (markerFont.ascender - markerFont.descender)) / 2
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: markerFont, .foregroundColor: style.bulletColor == nil ? textColor : box.color]
        let marker = NSAttributedString(string: label, attributes: attributes)
        marker.draw(at: NSPoint(x: x, y: origin.y + baseline - markerFont.ascender))
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// Builds TextKit text from the model, lays it out and draws it.
enum TextLayout {
    struct Context {
        var theme: PresentationTheme
        /// Autofit shrink factor applied to font sizes and spacing.
        var fontScale: CGFloat = 1
        var editing = false
        /// Replaces `<#slidenum#>` etc. in footers.
        var slideNumber: Int?
    }

    // MARK: Model → TextKit

    static func attributedString(_ body: TextBody, _ context: Context) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let colors = context.theme.colors
        for (index, paragraph) in body.paragraphs.enumerated() {
            let pStyle = makeParagraphStyle(paragraph.style, body: body, scale: context.fontScale)
            let pBox = paragraphBox(paragraph.style, body: body, context: context)
            var runs = paragraph.runs
            if runs.isEmpty { runs = [TextRun(text: "")] }
            let start = result.length
            for run in runs {
                var text = run.text
                if !context.editing && run.style.allCaps { text = text.uppercased() }
                if let n = context.slideNumber { text = text.replacingOccurrences(of: "‹#›", with: "\(n)") }
                result.append(NSAttributedString(string: text, attributes: runAttributes(run.style, body: body, context: context)))
            }
            let lastRunStyle = runs.last?.style ?? .plain
            if index < body.paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: runAttributes(lastRunStyle, body: body, context: context)))
            }
            let range = NSRange(location: start, length: result.length - start)
            if range.length > 0 {
                result.addAttributes([.paragraphStyle: pStyle, .wsParagraph: pBox], range: range)
            }
        }
        return result
    }

    /// Attributes for typing into an empty paragraph.
    static func typingAttributes(_ body: TextBody, paragraph: Int, _ context: Context) -> [NSAttributedString.Key: Any] {
        let p = body.paragraphs.indices.contains(paragraph) ? body.paragraphs[paragraph] : (body.paragraphs.last ?? Paragraph(""))
        var attributes = runAttributes(p.runs.first?.style ?? .plain, body: body, context: context)
        attributes[.paragraphStyle] = makeParagraphStyle(p.style, body: body, scale: context.fontScale)
        attributes[.wsParagraph] = paragraphBox(p.style, body: body, context: context)
        return attributes
    }

    static func paragraphBox(_ style: ParagraphStyle, body: TextBody, context: Context) -> ParagraphBox {
        let color = (style.bulletColor ?? body.defaultColor).resolve(context.theme.colors).nsColor
        return ParagraphBox(style, color: color, markerX: CGFloat(style.level) * 28 * indentUnit(body, scale: context.fontScale))
    }

    static func indentUnit(_ body: TextBody, scale: CGFloat) -> CGFloat {
        max(CGFloat(body.defaultSize) * scale / 24, 0.6)
    }

    static func makeParagraphStyle(_ style: ParagraphStyle, body: TextBody, scale: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = style.alignment.nsAlignment
        let hasBullet = !style.bullet.isNone
        let indent = (CGFloat(style.level) * 28 + (hasBullet ? 24 : 0)) * indentUnit(body, scale: scale)
        p.headIndent = indent
        p.firstLineHeadIndent = indent
        p.lineHeightMultiple = CGFloat(style.lineSpacing)
        p.paragraphSpacingBefore = CGFloat(style.spaceBefore) * scale
        p.paragraphSpacing = CGFloat(style.spaceAfter) * scale
        p.lineBreakMode = body.wrap ? .byWordWrapping : .byClipping
        return p
    }

    static func runAttributes(_ style: RunStyle, body: TextBody, context: Context) -> [NSAttributedString.Key: Any] {
        let theme = context.theme
        let family = style.fontFamily ?? theme.font(for: body.fontRole)
        var size = CGFloat(style.size ?? body.defaultSize) * context.fontScale
        if style.baseline != 0 { size *= 0.66 }
        let bold = style.bold ?? false
        let italic = style.italic ?? false
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FontResolver.font(family: family, size: max(size, 1), bold: bold, italic: italic),
            .foregroundColor: (style.color ?? body.defaultColor).resolve(theme.colors).nsColor,
            .wsRun: RunBox(style),
        ]
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let highlight = style.highlight { attributes[.backgroundColor] = highlight.nsColor }
        if style.baseline != 0 { attributes[.baselineOffset] = CGFloat(style.baseline) * size * 0.5 }
        if style.characterSpacing != 0 { attributes[.kern] = CGFloat(style.characterSpacing) * context.fontScale }
        if let link = style.link {
            attributes[.link] = URL(string: link) ?? link
            attributes[.foregroundColor] = (style.color ?? .theme(.hyperlink)).resolve(theme.colors).nsColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if let outline = style.outlineColor, style.outlineWidth > 0 {
            attributes[.strokeColor] = outline.resolve(theme.colors).nsColor
            // Negative stroke width fills and strokes.
            attributes[.strokeWidth] = -CGFloat(style.outlineWidth) / max(size, 1) * 100
        }
        if style.shadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowOffset = NSSize(width: size * 0.04, height: -size * 0.04)
            shadow.shadowBlurRadius = size * 0.08
            attributes[.shadow] = shadow
        }
        if style.smallCaps, let font = attributes[.font] as? NSFont {
            let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType, NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector]]])
            attributes[.font] = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }
        return attributes
    }

    // MARK: TextKit → Model

    /// Reads edited text back into the model, keeping theme references where the visible formatting still matches.
    static func textBody(from text: NSAttributedString, base: TextBody, _ context: Context) -> TextBody {
        var body = base
        let string = text.string as NSString
        var paragraphs: [Paragraph] = []
        var location = 0
        repeat {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            var contentRange = range
            // Drop the paragraph separator.
            while contentRange.length > 0, let c = UnicodeScalar(string.character(at: NSMaxRange(contentRange) - 1)),
                  CharacterSet.newlines.contains(c) {
                contentRange.length -= 1
            }
            let attrIndex = min(range.location, max(text.length - 1, 0))
            var pStyle = (text.length > 0 ? text.attribute(.wsParagraph, at: attrIndex, effectiveRange: nil) as? ParagraphBox : nil)?.style
                ?? base.paragraphs.last?.style ?? .plain
            if text.length > 0, let ns = text.attribute(.paragraphStyle, at: attrIndex, effectiveRange: nil) as? NSParagraphStyle {
                pStyle.alignment = TextAlignment(ns.alignment)
                pStyle.lineSpacing = Double(ns.lineHeightMultiple == 0 ? 1 : ns.lineHeightMultiple)
            }
            var runs: [TextRun] = []
            if contentRange.length > 0 {
                text.enumerateAttributes(in: contentRange) { attributes, runRange, _ in
                    let style = runStyle(from: attributes, body: base, context: context)
                    let piece = string.substring(with: runRange)
                    if let last = runs.last, last.style == style {
                        runs[runs.count - 1].text += piece
                    } else {
                        runs.append(TextRun(text: piece, style: style))
                    }
                }
            } else {
                let attributes = text.length > 0 ? text.attributes(at: attrIndex, effectiveRange: nil) : [:]
                runs = [TextRun(text: "", style: runStyle(from: attributes, body: base, context: context))]
            }
            paragraphs.append(Paragraph(runs: runs, style: pStyle))
            location = NSMaxRange(range)
        } while location < string.length
        // A trailing newline means an empty last paragraph.
        if string.length > 0, let c = UnicodeScalar(string.character(at: string.length - 1)), CharacterSet.newlines.contains(c) {
            let attributes = text.attributes(at: string.length - 1, effectiveRange: nil)
            let style = (attributes[.wsParagraph] as? ParagraphBox)?.style ?? paragraphs.last?.style ?? .plain
            paragraphs.append(Paragraph(runs: [TextRun(text: "", style: runStyle(from: attributes, body: base, context: context))], style: style))
        }
        body.paragraphs = paragraphs.isEmpty ? [Paragraph("")] : paragraphs
        return body
    }

    static func runStyle(from attributes: [NSAttributedString.Key: Any], body: TextBody, context: Context) -> RunStyle {
        var style = (attributes[.wsRun] as? RunBox)?.style ?? RunStyle()
        let theme = context.theme
        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            let family = font.familyName ?? font.fontName
            let themeFamily = theme.font(for: body.fontRole)
            let resolvedThemeFont = FontResolver.font(family: style.fontFamily ?? themeFamily, size: 12, bold: false, italic: false).familyName
            if family != resolvedThemeFont { style.fontFamily = family }
            var size = Double(font.pointSize / max(context.fontScale, 0.01))
            if style.baseline != 0 { size /= 0.66 }
            let inherited = style.size ?? body.defaultSize
            if abs(size - inherited) > 0.25 { style.size = (size * 2).rounded() / 2 }
            let isBold = traits.contains(.boldFontMask)
            if isBold != (style.bold ?? false) { style.bold = isBold }
            let isItalic = traits.contains(.italicFontMask)
            if isItalic != (style.italic ?? false) { style.italic = isItalic }
        }
        if let color = attributes[.foregroundColor] as? NSColor, attributes[.link] == nil {
            let current = (style.color ?? body.defaultColor).resolve(theme.colors)
            let edited = RGBColor(color)
            if !close(current, edited) { style.color = .rgb(edited) }
        }
        if let link = attributes[.link] {
            style.link = (link as? URL)?.absoluteString ?? (link as? String)
        } else {
            style.link = nil
            style.underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
        }
        style.strikethrough = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
        if let background = attributes[.backgroundColor] as? NSColor { style.highlight = RGBColor(background) } else { style.highlight = nil }
        if let superscript = attributes[.superscript] as? Int, superscript != 0 { style.baseline = superscript > 0 ? 1 : -1 }
        if let kern = attributes[.kern] as? CGFloat { style.characterSpacing = Double(kern / max(context.fontScale, 0.01)) }
        return style
    }

    private static func close(_ a: RGBColor, _ b: RGBColor) -> Bool {
        abs(a.r - b.r) < 0.01 && abs(a.g - b.g) < 0.01 && abs(a.b - b.b) < 0.01 && abs(a.a - b.a) < 0.02
    }

    // MARK: Layout

    final class Stack {
        let storage: NSTextStorage
        let layoutManager: BulletLayoutManager
        let container: NSTextContainer

        init(_ text: NSAttributedString, width: CGFloat, wrap: Bool) {
            storage = NSTextStorage(attributedString: text)
            layoutManager = BulletLayoutManager()
            layoutManager.usesFontLeading = true
            container = NSTextContainer(size: CGSize(width: wrap ? max(width, 1) : 100_000, height: 100_000))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)
        }

        var usedHeight: CGFloat {
            let used = layoutManager.usedRect(for: container)
            return ceil(used.height)
        }

        var usedWidth: CGFloat { ceil(layoutManager.usedRect(for: container).width) }
    }

    private static let fitCache = NSCache<NSString, NSNumber>()

    /// The shrink factor that makes the text fit its box.
    static func fittedScale(_ body: TextBody, size: CGSize, theme: PresentationTheme) -> CGFloat {
        guard body.autofit == .shrink, !body.isEmpty else { return 1 }
        let width = size.width - body.insets.left - body.insets.right
        let height = size.height - body.insets.top - body.insets.bottom
        guard width > 4, height > 4 else { return 1 }
        let key = "\(body.hashValue)|\(Int(width * 2))|\(Int(height * 2))|\(theme.headingFont)|\(theme.bodyFont)" as NSString
        if let cached = fitCache.object(forKey: key) { return CGFloat(cached.doubleValue) }
        func fits(_ s: CGFloat) -> Bool {
            Stack(attributedString(body, Context(theme: theme, fontScale: s)), width: width, wrap: body.wrap).usedHeight <= height + 0.5
        }
        var result: CGFloat = 1
        if !fits(1) {
            var lo: CGFloat = 0.25, hi: CGFloat = 1
            if fits(lo) {
                for _ in 0..<7 {
                    let mid = (lo + hi) / 2
                    if fits(mid) { lo = mid } else { hi = mid }
                }
            }
            result = lo
        }
        fitCache.setObject(NSNumber(value: Double(result)), forKey: key)
        return result
    }

    /// Height needed to show all the text at a width (for "Resize shape to fit text").
    static func requiredHeight(_ body: TextBody, width: CGFloat, theme: PresentationTheme) -> CGFloat {
        let inner = width - body.insets.left - body.insets.right
        let text = body.isEmpty
            ? attributedString(TextBody(" ", size: body.defaultSize, role: body.fontRole), Context(theme: theme))
            : attributedString(body, Context(theme: theme))
        let stack = Stack(text, width: inner, wrap: body.wrap)
        var height = stack.usedHeight
        if body.paragraphs.last?.text.isEmpty == true && body.paragraphs.count > 1 {
            height = max(height, stack.layoutManager.extraLineFragmentRect.maxY)
        }
        return ceil(height + body.insets.top + body.insets.bottom)
    }

    /// Width needed for unwrapped text.
    static func requiredWidth(_ body: TextBody, theme: PresentationTheme) -> CGFloat {
        let stack = Stack(attributedString(body, Context(theme: theme)), width: 100_000, wrap: false)
        return ceil(stack.usedWidth + body.insets.left + body.insets.right + 2)
    }

    /// The inner text frame for a box.
    static func contentRect(_ body: TextBody, in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + body.insets.left, y: rect.minY + body.insets.top,
               width: max(rect.width - body.insets.left - body.insets.right, 1),
               height: max(rect.height - body.insets.top - body.insets.bottom, 1))
    }

    /// Draws text into the current (flipped) graphics context.
    static func draw(_ body: TextBody, in rect: CGRect, theme: PresentationTheme, showPrompt: Bool = false,
                     slideNumber: Int? = nil, promptColor: NSColor? = nil) {
        var body = body
        if body.isEmpty {
            guard showPrompt, let prompt = body.prompt else { return }
            body.setPlainText(prompt)
            body.defaultColor = .rgb(RGBColor(promptColor ?? NSColor(white: 0.55, alpha: 1)))
            body.updateRuns { $0.color = nil }
            body.autofit = .shrink
        }
        var drawRect = rect
        var rotation: CGFloat = 0
        if body.direction != .horizontal {
            rotation = body.direction == .rotated90 ? .pi / 2 : -.pi / 2
            drawRect = CGRect(x: rect.midX - rect.height / 2, y: rect.midY - rect.width / 2, width: rect.height, height: rect.width)
        }
        let scale = fittedScale(body, size: drawRect.size, theme: theme)
        let content = contentRect(body, in: drawRect)
        let context = Context(theme: theme, fontScale: scale, slideNumber: slideNumber)
        let columns = max(1, body.columns)
        let gap: CGFloat = 14
        let columnWidth = (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let text = attributedString(body, context)

        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        if rotation != 0 {
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: rotation)
            cg.translateBy(x: -rect.midX, y: -rect.midY)
        }
        if columns == 1 {
            let stack = Stack(text, width: content.width, wrap: body.wrap)
            let used = stack.layoutManager.usedRect(for: stack.container)
            var y = content.minY
            switch body.anchor {
            case .top: break
            case .middle: y = content.midY - used.height / 2
            case .bottom: y = content.maxY - used.height
            }
            var x = content.minX
            if !body.wrap {
                // Unwrapped text is positioned by its alignment within the box.
                let alignment = body.firstParagraphStyle.alignment
                if alignment == .center { x = content.midX - 50_000 } else if alignment == .right { x = content.maxX - 100_000 }
            }
            let glyphs = stack.layoutManager.glyphRange(for: stack.container)
            stack.layoutManager.drawBackground(forGlyphRange: glyphs, at: CGPoint(x: x, y: y))
            stack.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: x, y: y))
        } else {
            let storage = NSTextStorage(attributedString: text)
            let manager = BulletLayoutManager()
            storage.addLayoutManager(manager)
            var containers: [NSTextContainer] = []
            for _ in 0..<columns {
                let c = NSTextContainer(size: CGSize(width: columnWidth, height: content.height))
                c.lineFragmentPadding = 0
                manager.addTextContainer(c)
                containers.append(c)
            }
            for (i, c) in containers.enumerated() {
                let glyphs = manager.glyphRange(for: c)
                let origin = CGPoint(x: content.minX + CGFloat(i) * (columnWidth + gap), y: content.minY)
                manager.drawBackground(forGlyphRange: glyphs, at: origin)
                manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
            }
        }
        cg.restoreGState()
    }
}

import AppKit

struct ElementDrawOptions {
    /// Show placeholder prompts and outlines (the editor, not the show or thumbnails).
    var editorChrome = false
    /// The element whose text is being edited (its text is drawn by the editor instead).
    var editingTextElement: UUID?
    var editingCell: (row: Int, column: Int)?
    var slideNumber: Int?
    /// Draw elements marked hidden (Selection pane).
    var drawHidden = false
}

enum ElementRenderer {
    static func draw(_ e: SlideElement, ctx: CGContext, env: RenderEnvironment, options: ElementDrawOptions, includeReflection: Bool = true) {
        if e.hidden && !options.drawHidden { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let r = e.frame
        let c = CGPoint(x: r.midX, y: r.midY)
        if e.rotation != 0 {
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(e.rotation * .pi / 180))
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        if includeReflection, let reflection = effects(of: e)?.reflection {
            drawReflection(e, reflection, ctx: ctx, env: env, options: options)
        }

        switch e.content {
        case .shape(let s): drawShape(e, s, ctx: ctx, env: env, options: options)
        case .image(let image): drawImage(e, image, ctx: ctx, env: env, options: options)
        case .line(let line): drawLine(e, line, ctx: ctx, env: env)
        case .table(let table): TableRenderer.draw(table, in: r, elementID: e.id, ctx: ctx, env: env, options: options)
        case .chart(let chart): ChartRenderer.draw(chart, in: r, ctx: ctx, env: env)
        case .icon(let icon): drawIcon(icon, in: r, flipH: e.flipH, flipV: e.flipV, ctx: ctx, env: env)
        case .media(let media): drawMedia(media, in: r, ctx: ctx, env: env)
        case .group(let group):
            if e.flipH || e.flipV {
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: e.flipH ? -1 : 1, y: e.flipV ? -1 : 1)
                ctx.translateBy(x: -c.x, y: -c.y)
            }
            for child in group.children { draw(child, ctx: ctx, env: env, options: options) }
        }
    }

    static func effects(of e: SlideElement) -> Effects? {
        switch e.content {
        case .shape(let s): s.effects
        case .image(let i): i.effects
        case .line(let l): l.effects
        default: nil
        }
    }

    /// Applies the flip around the frame's center (for geometry, not text).
    private static func applyFlip(_ e: SlideElement, ctx: CGContext) {
        guard e.flipH || e.flipV else { return }
        let c = CGPoint(x: e.frame.midX, y: e.frame.midY)
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: e.flipH ? -1 : 1, y: e.flipV ? -1 : 1)
        ctx.translateBy(x: -c.x, y: -c.y)
    }

    // MARK: Shapes

    static func geometry(_ e: SlideElement, _ s: ShapeContent) -> ShapeGeometry {
        ShapeGeometry.make(s.kind, in: e.frame, adjustments: s.resolvedAdjustments)
    }

    private static func drawShape(_ e: SlideElement, _ s: ShapeContent, ctx: CGContext, env: RenderEnvironment, options: ElementDrawOptions) {
        let geo = geometry(e, s)
        let hasFill = !s.fill.isNone
        let textOnly = !hasFill && !s.line.isVisible

        ctx.saveGState()
        applyFlip(e, ctx: ctx)
        if let glow = s.effects.glow {
            ctx.saveGState()
            Paint.applyGlow(glow, in: ctx, env: env)
            ctx.setFillColor(glow.color.resolve(env.colors).cgColor)
            ctx.setStrokeColor(glow.color.resolve(env.colors).cgColor)
            ctx.setLineWidth(CGFloat(glow.radius))
            ctx.addPath(geo.path)
            if hasFill { ctx.fillPath(using: .evenOdd) } else { ctx.strokePath() }
            ctx.restoreGState()
        }
        if let shadow = s.effects.shadow, !textOnly {
            Paint.applyShadow(shadow, in: ctx)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        Paint.fill(geo.path, with: s.fill, bounds: e.frame, in: ctx, env: env)
        for accent in geo.accents {
            Paint.fill(accent.path, with: s.fill.isNone ? .none : s.fill, bounds: e.frame, in: ctx, env: env, shade: accent.shade)
            Paint.stroke(accent.path, with: s.line, in: ctx, env: env)
        }
        Paint.stroke(geo.path, with: s.line, in: ctx, env: env)
        for detail in geo.details {
            var line = s.line
            if line.color == nil { line = LineStyle(color: .theme(.dark1, shade: 0, alpha: 0.6), width: max(1, e.frame.width / 60)) }
            Paint.stroke(detail, with: line, in: ctx, env: env)
        }
        if s.effects.shadow != nil, !textOnly { ctx.endTransparencyLayer() }
        ctx.restoreGState()

        // Text never mirrors; a vertical flip turns it upside down like PowerPoint.
        guard options.editingTextElement != e.id else { return }
        let isEmptyPlaceholder = e.placeholder != nil && s.text.isEmpty
        if isEmptyPlaceholder && options.editorChrome {
            drawPlaceholderChrome(e, s, geo: geo, ctx: ctx, env: env)
            return
        }
        guard !s.text.isEmpty else { return }
        ctx.saveGState()
        if e.flipV {
            ctx.translateBy(x: e.frame.midX, y: e.frame.midY)
            ctx.rotate(by: .pi)
            ctx.translateBy(x: -e.frame.midX, y: -e.frame.midY)
        }
        if textOnly, let shadow = s.effects.shadow { Paint.applyShadow(shadow, in: ctx) }
        withNSContext(ctx) {
            TextLayout.draw(s.text, in: textRect(e, s, geo: geo), theme: env.theme, slideNumber: options.slideNumber)
        }
        ctx.restoreGState()
    }

    /// The text area of a shape (text boxes use their whole frame).
    static func textRect(_ e: SlideElement, _ s: ShapeContent, geo: ShapeGeometry? = nil) -> CGRect {
        if s.kind == .rect || s.kind == .roundRect { return e.frame }
        return (geo ?? geometry(e, s)).textRect
    }

    private static func drawPlaceholderChrome(_ e: SlideElement, _ s: ShapeContent, geo: ShapeGeometry, ctx: CGContext, env: RenderEnvironment) {
        ctx.saveGState()
        let background = env.theme.background.representative(env.colors) ?? .white
        let ink = background.isDark ? NSColor(white: 1, alpha: 0.45) : NSColor(white: 0, alpha: 0.35)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(e.frame.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        withNSContext(ctx) {
            TextLayout.draw(s.text, in: textRect(e, s, geo: geo), theme: env.theme, showPrompt: true,
                            promptColor: background.isDark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0.45, alpha: 1))
        }
        if e.placeholder == .body || e.placeholder == .picture {
            PlaceholderIcons.draw(in: e.frame, pictureOnly: e.placeholder == .picture, ink: ink, ctx: ctx)
        }
    }

    // MARK: Pictures

    private static func drawImage(_ e: SlideElement, _ content: ImageContent, ctx: CGContext, env: RenderEnvironment, options: ElementDrawOptions) {
        let r = e.frame
        let clip: CGPath = content.maskShape.map { ShapeGeometry.make($0, in: r, adjustments: $0.defaultAdjustments).path } ?? CGPath(rect: r, transform: nil)
        ctx.saveGState()
        if let glow = content.effects.glow {
            ctx.saveGState()
            Paint.applyGlow(glow, in: ctx, env: env)
            ctx.setFillColor(glow.color.resolve(env.colors).cgColor)
            ctx.addPath(clip)
            ctx.fillPath()
            ctx.restoreGState()
        }
        if let shadow = content.effects.shadow {
            Paint.applyShadow(shadow, in: ctx)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        applyFlip(e, ctx: ctx)
        if let image = ImageCache.image(content.mediaID, env.media, adjustments: content.adjustments) {
            let size = image.size
            let crop = content.crop
            let source = CGRect(x: size.width * crop.left, y: size.height * crop.bottom,
                                width: size.width * max(1 - crop.left - crop.right, 0.01),
                                height: size.height * max(1 - crop.top - crop.bottom, 0.01))
            withNSContext(ctx) {
                image.draw(in: r, from: source, operation: .sourceOver, fraction: 1 - content.adjustments.transparency, respectFlipped: true, hints: nil)
            }
        } else {
            ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
            ctx.fill(r)
            drawSymbol("photo", in: r.insetBy(dx: r.width * 0.35, dy: r.height * 0.35), color: NSColor(white: 0.5, alpha: 1), ctx: ctx)
        }
        ctx.restoreGState()
        Paint.stroke(clip, with: content.line, in: ctx, env: env)
        if content.effects.shadow != nil { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    // MARK: Lines

    static func linePath(_ e: SlideElement, _ content: LineContent, start: CGPoint? = nil, end: CGPoint? = nil) -> CGPath {
        let ends = e.lineEndpoints
        let a = start ?? ends.start, b = end ?? ends.end
        let p = CGMutablePath()
        p.move(to: a)
        switch content.kind {
        case .straight:
            p.addLine(to: b)
        case .elbow:
            let midX = (a.x + b.x) / 2
            p.addLine(to: CGPoint(x: midX, y: a.y))
            p.addLine(to: CGPoint(x: midX, y: b.y))
            p.addLine(to: b)
        case .curved:
            let midX = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
        }
        return p
    }

    private static func drawLine(_ e: SlideElement, _ content: LineContent, ctx: CGContext, env: RenderEnvironment) {
        guard let color = content.line.color else { return }
        let ends = e.lineEndpoints
        // Directions at each end, for arrowheads.
        var startFrom = ends.end, endFrom = ends.start
        if content.kind != .straight {
            let midX = (ends.start.x + ends.end.x) / 2
            startFrom = CGPoint(x: midX, y: ends.start.y)
            endFrom = CGPoint(x: midX, y: ends.end.y)
            if abs(ends.start.x - ends.end.x) < 0.5 { startFrom = ends.end; endFrom = ends.start }
        }
        func pulled(_ p: CGPoint, toward q: CGPoint, by d: CGFloat) -> CGPoint {
            let len = hypot(q.x - p.x, q.y - p.y)
            guard len > d, d > 0 else { return p }
            return CGPoint(x: p.x + (q.x - p.x) / len * d, y: p.y + (q.y - p.y) / len * d)
        }
        let start = pulled(ends.start, toward: startFrom, by: Paint.arrowInset(content.line.head, width: content.line.width))
        let end = pulled(ends.end, toward: endFrom, by: Paint.arrowInset(content.line.tail, width: content.line.width))
        ctx.saveGState()
        if let glow = content.effects.glow { Paint.applyGlow(glow, in: ctx, env: env) }
        if let shadow = content.effects.shadow { Paint.applyShadow(shadow, in: ctx) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        Paint.stroke(linePath(e, content, start: start, end: end), with: content.line, in: ctx, env: env)
        let cg = color.resolve(env.colors).cgColor
        Paint.arrowhead(content.line.head, tip: ends.start, from: startFrom, width: content.line.width, color: cg, in: ctx)
        Paint.arrowhead(content.line.tail, tip: ends.end, from: endFrom, width: content.line.width, color: cg, in: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: Icons and media

    static func drawSymbol(_ name: String, in rect: CGRect, color: NSColor, ctx: CGContext, flipH: Bool = false, flipV: Bool = false) {
        let config = NSImage.SymbolConfiguration(pointSize: max(rect.height, 8), weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = min(rect.width / max(image.size.width, 1), rect.height / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        ctx.saveGState()
        if flipH || flipV {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        withNSContext(ctx) {
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        ctx.restoreGState()
    }

    private static func drawIcon(_ icon: IconContent, in rect: CGRect, flipH: Bool, flipV: Bool, ctx: CGContext, env: RenderEnvironment) {
        drawSymbol(icon.symbol, in: rect, color: icon.color.resolve(env.colors).nsColor, ctx: ctx, flipH: flipH, flipV: flipV)
    }

    private static func drawMedia(_ media: MediaContent, in rect: CGRect, ctx: CGContext, env: RenderEnvironment) {
        if let poster = media.posterID, let image = ImageCache.image(poster, env.media) {
            withNSContext(ctx) { image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        } else if media.kind == .video {
            ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
            ctx.fill(rect)
            drawSymbol("film", in: rect.insetBy(dx: rect.width * 0.38, dy: rect.height * 0.38), color: NSColor(white: 0.7, alpha: 1), ctx: ctx)
        } else {
            drawSymbol("speaker.wave.2.circle.fill", in: rect, color: env.colors.accent1.nsColor, ctx: ctx)
        }
        if media.kind == .video {
            let d = min(rect.width, rect.height) * 0.18
            let play = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
            if media.posterID != nil {
                drawSymbol("play.circle.fill", in: play, color: NSColor(white: 1, alpha: 0.85), ctx: ctx)
            }
        }
    }

    // MARK: Reflection

    private static let reflectionMask: CGImage = {
        let width = 1, height = 256
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for y in 0..<height {
            // Row 0 is the image's bottom, which a flipped context shows on top: opaque near the shape.
            ctx.setFillColor(gray: 1 - CGFloat(y) / CGFloat(height - 1), alpha: 1)
            ctx.fill(CGRect(x: 0, y: y, width: 1, height: 1))
        }
        return ctx.makeImage()!
    }()

    private static func drawReflection(_ e: SlideElement, _ reflection: ReflectionEffect, ctx: CGContext, env: RenderEnvironment, options: ElementDrawOptions) {
        let r = e.frame
        let top = r.maxY + CGFloat(reflection.distance)
        let height = r.height * CGFloat(reflection.size)
        guard height > 1 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(reflection.opacity))
        ctx.clip(to: CGRect(x: r.minX - 20, y: top, width: r.width + 40, height: height), mask: reflectionMask)
        ctx.translateBy(x: 0, y: r.maxY + top)
        ctx.scaleBy(x: 1, y: -1)
        var copy = e
        copy.rotation = 0
        draw(copy, ctx: ctx, env: env, options: options, includeReflection: false)
        ctx.restoreGState()
    }

    static func withNSContext(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The insert-content icons shown in empty content placeholders.
enum PlaceholderIcons {
    static let items: [(symbol: String, kind: String)] = [
        ("tablecells", "table"), ("chart.bar", "chart"), ("square.grid.3x1.below.line.grid.1x2", "smartart"),
        ("photo", "picture"), ("star.square.on.square", "icon"), ("film", "video"),
    ]

    static func frames(in rect: CGRect, pictureOnly: Bool) -> [(CGRect, String)] {
        let list = pictureOnly ? [items[3]] : items
        let size = min(28, rect.width / 8, rect.height / 4)
        guard size >= 12 else { return [] }
        let gap = size * 0.5
        let columns = pictureOnly ? 1 : 3
        let rows = pictureOnly ? 1 : 2
        let totalW = CGFloat(columns) * size + CGFloat(columns - 1) * gap
        let totalH = CGFloat(rows) * size + CGFloat(rows - 1) * gap
        let origin = CGPoint(x: rect.midX - totalW / 2, y: rect.midY - totalH / 2 + (pictureOnly ? 0 : size * 0.6))
        return list.enumerated().map { i, item in
            let col = i % columns, row = i / columns
            return (CGRect(x: origin.x + CGFloat(col) * (size + gap), y: origin.y + CGFloat(row) * (size + gap), width: size, height: size), item.kind)
        }
    }

    static func draw(in rect: CGRect, pictureOnly: Bool, ink: NSColor, ctx: CGContext) {
        for (frame, kind) in frames(in: rect, pictureOnly: pictureOnly) {
            let symbol = items.first { $0.kind == kind }!.symbol
            ElementRenderer.drawSymbol(symbol, in: frame.insetBy(dx: 3, dy: 3), color: ink, ctx: ctx)
        }
    }
}

import AppKit

struct SlideDrawOptions {
    var element = ElementDrawOptions()
    /// Elements not to draw (the slide show draws animated ones separately).
    var skip: Set<UUID> = []
    var drawBackground = true
    var drawElements = true
    var drawFooters = true
}

/// Draws whole slides: background, theme graphics, elements and footers.
enum SlideRenderer {
    static func background(for slide: Slide, theme: PresentationTheme) -> Fill {
        slide.background ?? (slide.layout.isTitleStyle ? (theme.titleBackground ?? theme.background) : theme.background)
    }

    static func decorations(for slide: Slide, theme: PresentationTheme, size: CGSize) -> [SlideElement] {
        guard !slide.hideBackgroundGraphics else { return [] }
        let source = slide.layout.isTitleStyle ? theme.titleDecorations : theme.decorations
        guard size != CGSize(width: 960, height: 540) else { return source }
        let sx = size.width / 960, sy = size.height / 540
        return source.map { e in
            var e = e
            e.setFrame(CGRect(x: e.frame.minX * sx, y: e.frame.minY * sy, width: e.frame.width * sx, height: e.frame.height * sy))
            return e
        }
    }

    /// Draws a slide into a flipped context whose units are slide points.
    static func draw(_ slide: Slide, number: Int, presentation: Presentation, ctx: CGContext, options: SlideDrawOptions = SlideDrawOptions()) {
        let env = RenderEnvironment(presentation)
        let bounds = CGRect(origin: .zero, size: presentation.slideSize)
        ctx.saveGState()
        ctx.clip(to: bounds)
        if options.drawBackground {
            ctx.setFillColor(RGBColor.white.cgColor)
            ctx.fill(bounds)
            Paint.fill(CGPath(rect: bounds, transform: nil), with: background(for: slide, theme: presentation.theme), bounds: bounds, in: ctx, env: env)
            for d in decorations(for: slide, theme: presentation.theme, size: presentation.slideSize) {
                ElementRenderer.draw(d, ctx: ctx, env: env, options: ElementDrawOptions())
            }
        }
        var elementOptions = options.element
        elementOptions.slideNumber = number
        if options.drawElements {
            for e in slide.elements where !options.skip.contains(e.id) {
                ElementRenderer.draw(e, ctx: ctx, env: env, options: elementOptions)
            }
        }
        if options.drawFooters {
            for footer in footers(for: slide, number: number, presentation: presentation) {
                ElementRenderer.draw(footer, ctx: ctx, env: env, options: elementOptions)
            }
        }
        ctx.restoreGState()
    }

    /// Date, footer and slide-number text boxes from Header & Footer settings.
    static func footers(for slide: Slide, number: Int, presentation: Presentation) -> [SlideElement] {
        let hf = presentation.headerFooter
        if hf.hideOnTitleSlide && slide.layout == .title { return [] }
        let size = presentation.slideSize
        let y = size.height - 34 * size.height / 540
        let h = 24 * size.height / 540
        let color = PaintColor.theme(.dark1, shade: 0.45, alpha: 1)
        var result: [SlideElement] = []
        func box(_ text: String, x: CGFloat, width: CGFloat, alignment: TextAlignment) -> SlideElement {
            var e = SlideElement.textBox(text, frame: CGRect(x: x * size.width / 960, y: y, width: width * size.width / 960, height: h),
                                         size: 11, alignment: alignment, color: color, anchor: .middle)
            e.text?.autofit = .none
            e.name = "Footer"
            return e
        }
        if hf.showDate {
            let text = hf.fixedDate ?? DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
            result.append(box(text, x: 60, width: 220, alignment: .left))
        }
        if hf.showFooter, !hf.footerText.isEmpty { result.append(box(hf.footerText, x: 320, width: 320, alignment: .center)) }
        if hf.showSlideNumber { result.append(box("\(number)", x: 760, width: 140, alignment: .right)) }
        return result
    }

    // MARK: Images

    /// Renders a slide to a bitmap `pixelWidth` wide.
    static func cgImage(_ slide: Slide, number: Int, presentation: Presentation, pixelWidth: CGFloat, options: SlideDrawOptions = SlideDrawOptions()) -> CGImage? {
        let size = presentation.slideSize
        let scale = pixelWidth / size.width
        let w = max(Int(pixelWidth.rounded()), 1), h = max(Int((size.height * scale).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(slide, number: number, presentation: presentation, ctx: ctx, options: options)
        return ctx.makeImage()
    }

    static func image(_ slide: Slide, number: Int, presentation: Presentation, pixelWidth: CGFloat, options: SlideDrawOptions = SlideDrawOptions()) -> NSImage {
        let size = presentation.slideSize
        guard let cg = cgImage(slide, number: number, presentation: presentation, pixelWidth: pixelWidth, options: options) else {
            return NSImage(size: size)
        }
        let points = NSSize(width: pixelWidth / 2, height: pixelWidth / 2 * size.height / size.width)
        return NSImage(cgImage: cg, size: points)
    }

    static func pngData(_ slide: Slide, number: Int, presentation: Presentation, pixelWidth: CGFloat) -> Data? {
        guard let cg = cgImage(slide, number: number, presentation: presentation, pixelWidth: pixelWidth) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Renders a single element (for drag images and slide-show layers), padded for effects.
    static func elementImage(_ e: SlideElement, presentation: Presentation, scale: CGFloat, padding: CGFloat = 0, slideNumber: Int? = nil) -> CGImage? {
        let bounds = visualBounds(e).insetBy(dx: -padding, dy: -padding)
        let w = max(Int((bounds.width * scale).rounded(.up)), 1), h = max(Int((bounds.height * scale).rounded(.up)), 1)
        guard w * h < 40_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        var options = ElementDrawOptions()
        options.slideNumber = slideNumber
        ElementRenderer.draw(e, ctx: ctx, env: RenderEnvironment(presentation), options: options)
        return ctx.makeImage()
    }

    /// The area an element covers once rotated, plus room for shadows and glow.
    static func visualBounds(_ e: SlideElement) -> CGRect {
        var r = rotatedBounds(e.frame, rotation: e.rotation)
        if case .line(let l) = e.content { r = r.insetBy(dx: -CGFloat(l.line.width) * 3 - 6, dy: -CGFloat(l.line.width) * 3 - 6) }
        if let fx = ElementRenderer.effects(of: e) {
            var pad: CGFloat = 0
            if let s = fx.shadow { pad = max(pad, CGFloat(s.blur * 2 + s.distance)) }
            if let g = fx.glow { pad = max(pad, CGFloat(g.radius * 2.5)) }
            r = r.insetBy(dx: -pad, dy: -pad)
            if let reflection = fx.reflection { r.size.height += e.frame.height * CGFloat(reflection.size) + CGFloat(reflection.distance) }
        }
        return r.insetBy(dx: -2, dy: -2)
    }

    static func rotatedBounds(_ r: CGRect, rotation: Double) -> CGRect {
        guard rotation != 0 else { return r }
        let c = CGPoint(x: r.midX, y: r.midY)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(rotation * .pi / 180)).translatedBy(x: -c.x, y: -c.y)
        return r.applying(t)
    }
}

/// Caches slide thumbnails by content.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 600 }

    func thumbnail(_ slide: Slide, number: Int, presentation: Presentation, width: CGFloat) -> NSImage {
        var hasher = Hasher()
        hasher.combine(slide)
        hasher.combine(number)
        hasher.combine(presentation.theme)
        hasher.combine(presentation.slideSize.width)
        hasher.combine(presentation.slideSize.height)
        hasher.combine(presentation.headerFooter)
        hasher.combine(Int(width))
        let key = String(hasher.finalize()) as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = SlideRenderer.image(slide, number: number, presentation: presentation, pixelWidth: width * 2)
        cache.setObject(image, forKey: key)
        return image
    }
}

import AppKit
import CoreImage

/// What drawing needs besides the element itself.
struct RenderEnvironment {
    var theme: PresentationTheme
    var media: [String: MediaItem]
    var slideSize: CGSize

    init(_ presentation: Presentation) {
        theme = presentation.theme
        media = presentation.media
        slideSize = presentation.slideSize
    }

    init(theme: PresentationTheme, media: [String: MediaItem], slideSize: CGSize) {
        self.theme = theme
        self.media = media
        self.slideSize = slideSize
    }

    var colors: ThemeColors { theme.colors }
}

/// Decoded pictures, by media id (ids are unique, so the cache can be shared).
enum ImageCache {
    private static let images = NSCache<NSString, NSImage>()
    private static let adjusted = NSCache<NSString, NSImage>()
    private static let context = CIContext()

    static func image(_ id: String, _ media: [String: MediaItem]) -> NSImage? {
        if let cached = images.object(forKey: id as NSString) { return cached }
        guard let item = media[id], let image = NSImage(data: item.data) else { return nil }
        images.setObject(image, forKey: id as NSString)
        return image
    }

    /// Pixel or point size of a picture.
    static func size(_ id: String, _ media: [String: MediaItem]) -> CGSize? {
        guard let image = image(id, media) else { return nil }
        if let rep = image.representations.first as? NSBitmapImageRep, rep.pixelsWide > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    static func image(_ id: String, _ media: [String: MediaItem], adjustments: ImageAdjustments) -> NSImage? {
        guard !adjustments.isIdentity else { return image(id, media) }
        let key = "\(id)|\(adjustments.hashValue)" as NSString
        if let cached = adjusted.object(forKey: key) { return cached }
        guard let base = image(id, media), let tiff = base.tiffRepresentation, var ci = CIImage(data: tiff) else { return nil }
        let controls = CIFilter(name: "CIColorControls")!
        controls.setValue(ci, forKey: kCIInputImageKey)
        controls.setValue(adjustments.brightness * 0.5, forKey: kCIInputBrightnessKey)
        controls.setValue(1 + adjustments.contrast, forKey: kCIInputContrastKey)
        controls.setValue(adjustments.saturation, forKey: kCIInputSaturationKey)
        ci = controls.outputImage ?? ci
        if adjustments.sepia, let sepia = CIFilter(name: "CISepiaTone") {
            sepia.setValue(ci, forKey: kCIInputImageKey)
            sepia.setValue(0.85, forKey: kCIInputIntensityKey)
            ci = sepia.outputImage ?? ci
        }
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return base }
        let result = NSImage(cgImage: cg, size: base.size)
        adjusted.setObject(result, forKey: key)
        return result
    }
}

/// Fills and strokes paths with the model's fill and line styles.
enum Paint {
    static func fill(_ path: CGPath, with fill: Fill, bounds: CGRect, in ctx: CGContext, env: RenderEnvironment, shade: Double = 0) {
        switch fill {
        case .none:
            return
        case .solid(let color):
            ctx.setFillColor(color.resolve(env.colors).shaded(shade).cgColor)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        case .gradient(let gradient):
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            drawGradient(gradient, in: bounds, ctx: ctx, env: env, shade: shade)
            ctx.restoreGState()
        case .image(let image):
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            if let picture = ImageCache.image(image.mediaID, env.media) {
                drawImage(picture, mode: image.mode, in: bounds, ctx: ctx, alpha: 1 - image.transparency)
            }
            ctx.restoreGState()
        case .pattern(let pattern):
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(pattern.background.resolve(env.colors).shaded(shade).cgColor)
            ctx.fill(bounds)
            drawPattern(pattern.kind, color: pattern.foreground.resolve(env.colors).shaded(shade).cgColor, in: bounds, ctx: ctx)
            ctx.restoreGState()
        }
    }

    static func drawGradient(_ gradient: GradientFill, in rect: CGRect, ctx: CGContext, env: RenderEnvironment, shade: Double = 0) {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        guard stops.count >= 1 else { return }
        let colors = stops.map { $0.color.resolve(env.colors).shaded(shade).cgColor } as CFArray
        var locations = stops.map { CGFloat($0.position) }
        guard let cgGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: &locations) else { return }
        switch gradient.kind {
        case .linear:
            let angle = gradient.angle * .pi / 180
            let dx = cos(angle), dy = sin(angle)
            let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawLinearGradient(cgGradient, start: CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                                   end: CGPoint(x: c.x + dx * half, y: c.y + dy * half), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(cgGradient, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: hypot(rect.width, rect.height) / 2, options: [.drawsAfterEndLocation])
        }
    }

    static func drawImage(_ image: NSImage, mode: ImageFill.Mode, in rect: CGRect, ctx: CGContext, alpha: Double) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        switch mode {
        case .stretch:
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        case .fit:
            let s = max(rect.width / max(image.size.width, 1), rect.height / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * s, height: image.size.height * s)
            image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        case .tile:
            let tile = image.size
            guard tile.width > 2, tile.height > 2 else { break }
            var y = rect.minY
            while y < rect.maxY {
                var x = rect.minX
                while x < rect.maxX {
                    image.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: tile), from: .zero, operation: .sourceOver,
                               fraction: alpha, respectFlipped: true, hints: nil)
                    x += tile.width
                }
                y += tile.height
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawPattern(_ kind: PatternKind, color: CGColor, in rect: CGRect, ctx: CGContext) {
        let step: CGFloat = 12
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(1)
        switch kind {
        case .horizontal, .grid:
            var y = rect.minY
            while y <= rect.maxY { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step * (kind == .grid ? 2 : 1) }
            if kind == .grid {
                var x = rect.minX
                while x <= rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step * 2 }
            }
            ctx.strokePath()
        case .vertical:
            var x = rect.minX
            while x <= rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
            ctx.strokePath()
        case .diagonalUp, .diagonalDown:
            var d = -rect.height
            while d <= rect.width {
                if kind == .diagonalDown {
                    ctx.move(to: CGPoint(x: rect.minX + d, y: rect.minY))
                    ctx.addLine(to: CGPoint(x: rect.minX + d + rect.height, y: rect.maxY))
                } else {
                    ctx.move(to: CGPoint(x: rect.minX + d, y: rect.maxY))
                    ctx.addLine(to: CGPoint(x: rect.minX + d + rect.height, y: rect.minY))
                }
                d += step
            }
            ctx.strokePath()
        case .dots:
            var y = rect.minY + step / 2
            while y < rect.maxY {
                var x = rect.minX + step / 2
                while x < rect.maxX { ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)); x += step }
                y += step
            }
        case .checker:
            var row = 0
            var y = rect.minY
            while y < rect.maxY {
                var x = rect.minX + (row % 2 == 0 ? 0 : step)
                while x < rect.maxX { ctx.fill(CGRect(x: x, y: y, width: step, height: step)); x += step * 2 }
                y += step
                row += 1
            }
        }
    }

    static func stroke(_ path: CGPath, with line: LineStyle, in ctx: CGContext, env: RenderEnvironment) {
        guard let color = line.color, line.width > 0 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.resolve(env.colors).cgColor)
        ctx.setLineWidth(CGFloat(line.width))
        ctx.setLineJoin(.round)
        ctx.setLineCap(line.roundCaps || line.dash == .roundDot ? .round : .butt)
        let dash = line.dash.pattern(width: CGFloat(line.width))
        if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Draws an arrowhead at `tip`, pointing away from `from`.
    static func arrowhead(_ kind: ArrowHead, tip: CGPoint, from: CGPoint, width: Double, color: CGColor, in ctx: CGContext) {
        guard kind != .none else { return }
        let size = CGFloat(max(width, 1)) * 3 + 4
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        ctx.saveGState()
        ctx.translateBy(x: tip.x, y: tip.y)
        ctx.rotate(by: angle)
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineJoin(.round)
        switch kind {
        case .none: break
        case .triangle:
            ctx.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: -size, y: -size / 2), CGPoint(x: -size, y: size / 2)])
            ctx.closePath()
            ctx.fillPath()
        case .stealth:
            ctx.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: -size, y: -size / 2), CGPoint(x: -size * 0.65, y: 0), CGPoint(x: -size, y: size / 2)])
            ctx.closePath()
            ctx.fillPath()
        case .open:
            ctx.addLines(between: [CGPoint(x: -size, y: -size / 2), CGPoint(x: 0, y: 0), CGPoint(x: -size, y: size / 2)])
            ctx.strokePath()
        case .diamond:
            ctx.addLines(between: [CGPoint(x: size / 2, y: 0), CGPoint(x: 0, y: -size / 2), CGPoint(x: -size / 2, y: 0), CGPoint(x: 0, y: size / 2)])
            ctx.closePath()
            ctx.fillPath()
        case .oval:
            ctx.fillEllipse(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
        }
        ctx.restoreGState()
    }

    /// How far to pull a line end back so it doesn't poke through its arrowhead.
    static func arrowInset(_ kind: ArrowHead, width: Double) -> CGFloat {
        switch kind {
        case .triangle, .stealth: return (CGFloat(max(width, 1)) * 3 + 4) * 0.6
        default: return 0
        }
    }

    // MARK: Effects

    /// The scale from user space to device space (shadow offsets and blur are in device space).
    static func deviceScale(_ ctx: CGContext) -> CGFloat {
        let m = ctx.userSpaceToDeviceSpaceTransform
        return sqrt(abs(m.a * m.d - m.b * m.c))
    }

    static func applyShadow(_ shadow: ShadowEffect, in ctx: CGContext) {
        let scale = deviceScale(ctx)
        let angle = shadow.angle * .pi / 180
        // Device space has y pointing up, whatever the context's flip.
        let offset = CGSize(width: CGFloat(cos(angle) * shadow.distance) * scale, height: -CGFloat(sin(angle) * shadow.distance) * scale)
        ctx.setShadow(offset: offset, blur: CGFloat(shadow.blur) * scale, color: shadow.color.withAlpha(shadow.opacity).cgColor)
    }

    static func applyGlow(_ glow: GlowEffect, in ctx: CGContext, env: RenderEnvironment) {
        let scale = deviceScale(ctx)
        ctx.setShadow(offset: .zero, blur: CGFloat(glow.radius) * scale * 1.5, color: glow.color.resolve(env.colors).cgColor)
    }
}

import AppKit

/// Hit testing and handle geometry in slide coordinates.
enum CanvasGeometry {
    enum Handle: Hashable {
        case resize(Int)        // 0…7 clockwise from top-left
        case rotate
        case adjust
        case lineStart, lineEnd

        var cursor: NSCursor {
            switch self {
            case .rotate: return .crosshair
            case .adjust, .lineStart, .lineEnd: return .crosshair
            case .resize(let i):
                switch i {
                case 1, 5: return .resizeUpDown
                case 3, 7: return .resizeLeftRight
                default: return .crosshair
                }
            }
        }
    }

    static func rotationTransform(_ e: SlideElement) -> CGAffineTransform {
        let c = CGPoint(x: e.frame.midX, y: e.frame.midY)
        return CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(e.rotation * .pi / 180)).translatedBy(x: -c.x, y: -c.y)
    }

    /// The point in the element's unrotated space.
    static func localPoint(_ p: CGPoint, in e: SlideElement) -> CGPoint {
        guard e.rotation != 0 else { return p }
        return p.applying(rotationTransform(e).inverted())
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    static func contains(_ e: SlideElement, _ point: CGPoint, tolerance: CGFloat) -> Bool {
        let p = localPoint(point, in: e)
        switch e.content {
        case .line(let line):
            let path = ElementRenderer.linePath(e, line)
            let hit = path.copy(strokingWithWidth: max(CGFloat(line.line.width), 1) + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
            return hit.contains(p)
        case .shape(let s):
            let frame = e.frame.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
            guard frame.contains(p) else { return false }
            if s.kind == .rect || s.fill.isNone || !s.text.isEmpty { return true }
            let geo = ElementRenderer.geometry(e, s)
            return geo.path.contains(p, using: .evenOdd) || geo.path.copy(strokingWithWidth: tolerance * 2 + CGFloat(s.line.width), lineCap: .round, lineJoin: .round, miterLimit: 4).contains(p)
        case .group(let g):
            return g.children.contains { contains($0, p, tolerance: tolerance) }
        default:
            return e.frame.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(p)
        }
    }

    /// The topmost element at a point (locked elements can't be picked).
    static func hit(_ elements: [SlideElement], at point: CGPoint, tolerance: CGFloat, includeLocked: Bool = false) -> SlideElement? {
        elements.reversed().first { !$0.hidden && (includeLocked || !$0.locked) && contains($0, point, tolerance: tolerance) }
    }

    /// Corners and edge midpoints of a frame, clockwise from top-left, in slide space (rotated).
    static func handlePoints(_ e: SlideElement) -> [CGPoint] {
        let r = e.frame
        let local = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                     CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
        let t = rotationTransform(e)
        return local.map { $0.applying(t) }
    }

    static func rotateHandlePoint(_ e: SlideElement, offset: CGFloat) -> CGPoint {
        CGPoint(x: e.frame.midX, y: e.frame.minY - offset).applying(rotationTransform(e))
    }

    static func adjustHandlePoint(_ e: SlideElement) -> CGPoint? {
        guard case .shape(let s) = e.content, let p = ShapeGeometry.adjustHandle(s.kind, in: e.frame, adjustments: s.resolvedAdjustments) else { return nil }
        return p.applying(rotationTransform(e))
    }

    /// Resizes a frame by dragging handle `index` to `point` (in the element's unrotated space).
    static func resize(_ frame: CGRect, handle index: Int, to point: CGPoint, keepAspect: Bool, fromCenter: Bool) -> CGRect {
        var minX = frame.minX, minY = frame.minY, maxX = frame.maxX, maxY = frame.maxY
        switch index {
        case 0: minX = point.x; minY = point.y
        case 1: minY = point.y
        case 2: maxX = point.x; minY = point.y
        case 3: maxX = point.x
        case 4: maxX = point.x; maxY = point.y
        case 5: maxY = point.y
        case 6: minX = point.x; maxY = point.y
        case 7: minX = point.x
        default: break
        }
        if fromCenter {
            switch index {
            case 0, 6, 7: maxX = frame.maxX + (frame.minX - minX)
            case 2, 3, 4: minX = frame.minX - (maxX - frame.maxX)
            default: break
            }
            switch index {
            case 0, 1, 2: maxY = frame.maxY + (frame.minY - minY)
            case 4, 5, 6: minY = frame.minY - (maxY - frame.maxY)
            default: break
            }
        }
        var r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        if keepAspect, frame.width > 0, frame.height > 0 {
            let aspect = frame.width / frame.height
            if [1, 5].contains(index) {
                let w = r.height * aspect
                r = CGRect(x: frame.midX - w / 2, y: r.minY, width: w, height: r.height)
            } else if [3, 7].contains(index) {
                let h = r.width / aspect
                r = CGRect(x: r.minX, y: frame.midY - h / 2, width: r.width, height: h)
            } else {
                if r.width / max(r.height, 0.01) > aspect { r.size.width = r.height * aspect } else { r.size.height = r.width / aspect }
                // Keep the opposite corner fixed.
                if index == 0 || index == 6 { r.origin.x = (fromCenter ? frame.midX + (frame.midX - r.minX) : frame.maxX) - r.width }
                if index == 0 || index == 2 { r.origin.y = (fromCenter ? frame.midY + (frame.midY - r.minY) : frame.maxY) - r.height }
                if fromCenter { r.origin = CGPoint(x: frame.midX - r.width / 2, y: frame.midY - r.height / 2) }
            }
        }
        return r
    }
}

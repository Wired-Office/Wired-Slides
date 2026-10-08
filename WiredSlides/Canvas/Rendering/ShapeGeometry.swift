import AppKit

/// The outline of a preset shape inside a rectangle (y grows downward), plus
/// shaded accent faces (cube sides, cylinder top) and the area text flows into.
struct ShapeGeometry {
    var path: CGPath
    /// Extra faces, each drawn with the fill shaded by the given amount (-1…1).
    var accents: [(path: CGPath, shade: Double)] = []
    /// Strokes drawn without fill (face details).
    var details: [CGPath] = []
    var textRect: CGRect

    static func make(_ kind: ShapeKind, in r: CGRect, adjustments adj: [Double]) -> ShapeGeometry {
        func a(_ i: Int) -> Double { i < adj.count ? adj[i] : (i < kind.defaultAdjustments.count ? kind.defaultAdjustments[i] : 0) }
        let w = r.width, h = r.height, ss = min(w, h)
        let x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY, cx = r.midX, cy = r.midY
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func poly(_ points: [CGPoint]) -> CGPath {
            let p = CGMutablePath()
            p.addLines(between: points)
            p.closeSubpath()
            return p
        }
        /// Points given as fractions of the rect.
        func npoly(_ points: [(Double, Double)]) -> CGPath {
            poly(points.map { P(x0 + w * $0.0, y0 + h * $0.1) })
        }
        func regular(_ n: Int, rotation: Double = -Double.pi / 2) -> CGPath {
            poly((0..<n).map { i in
                let t = rotation + Double(i) * 2 * .pi / Double(n)
                return P(cx + w / 2 * cos(t), cy + h / 2 * sin(t))
            })
        }
        func star(_ n: Int, inner: Double) -> CGPath {
            poly((0..<(2 * n)).map { i in
                let t = -Double.pi / 2 + Double(i) * .pi / Double(n)
                let k = i % 2 == 0 ? 1 : inner
                return P(cx + w / 2 * k * cos(t), cy + h / 2 * k * sin(t))
            })
        }
        var text = r
        let path: CGPath
        var accents: [(CGPath, Double)] = []
        var details: [CGPath] = []

        switch kind {
        case .rect, .flowChartProcess:
            path = CGPath(rect: r, transform: nil)
        case .roundRect, .flowChartAlternateProcess:
            let radius = min(a(0) * ss, ss / 2)
            path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            text = r.insetBy(dx: radius * 0.29, dy: radius * 0.29)
        case .snip1Rect:
            let s = a(0) * ss
            path = poly([P(x0, y0), P(x1 - s, y0), P(x1, y0 + s), P(x1, y1), P(x0, y1)])
        case .snip2SameRect:
            let s = a(0) * ss
            path = poly([P(x0 + s, y0), P(x1 - s, y0), P(x1, y0 + s), P(x1, y1), P(x0, y1), P(x0, y0 + s)])
        case .round2SameRect:
            let s = min(a(0) * ss, ss / 2)
            let p = CGMutablePath()
            p.move(to: P(x0, y1))
            p.addArc(tangent1End: P(x0, y0), tangent2End: P(x1, y0), radius: s)
            p.addArc(tangent1End: P(x1, y0), tangent2End: P(x1, y1), radius: s)
            p.addLine(to: P(x1, y1))
            p.closeSubpath()
            path = p
        case .ellipse, .flowChartConnector:
            path = CGPath(ellipseIn: r, transform: nil)
            text = r.insetBy(dx: w * 0.146, dy: h * 0.146)
        case .triangle:
            path = poly([P(cx, y0), P(x1, y1), P(x0, y1)])
            text = CGRect(x: x0 + w * 0.25, y: y0 + h * 0.5, width: w * 0.5, height: h * 0.5)
        case .rtTriangle:
            path = poly([P(x0, y0), P(x1, y1), P(x0, y1)])
            text = CGRect(x: x0 + w * 0.08, y: y0 + h * 0.5, width: w * 0.5, height: h * 0.45)
        case .parallelogram, .flowChartInputOutput:
            let s = min(a(0) * ss, w * 0.9)
            path = poly([P(x0 + s, y0), P(x1, y0), P(x1 - s, y1), P(x0, y1)])
            text = r.insetBy(dx: s * 0.6, dy: 0)
        case .trapezoid:
            let s = min(a(0) * ss, w / 2)
            path = poly([P(x0 + s, y0), P(x1 - s, y0), P(x1, y1), P(x0, y1)])
            text = r.insetBy(dx: s * 0.6, dy: 0)
        case .flowChartManualInput:
            path = poly([P(x0, y0 + h * 0.2), P(x1, y0), P(x1, y1), P(x0, y1)])
            text = CGRect(x: x0, y: y0 + h * 0.2, width: w, height: h * 0.8)
        case .diamond, .flowChartDecision:
            path = poly([P(cx, y0), P(x1, cy), P(cx, y1), P(x0, cy)])
            text = r.insetBy(dx: w / 4, dy: h / 4)
        case .pentagon:
            path = npoly([(0.5, 0), (1, 0.382), (0.809, 1), (0.191, 1), (0, 0.382)])
            text = r.insetBy(dx: w * 0.2, dy: h * 0.2).offsetBy(dx: 0, dy: h * 0.1)
        case .hexagon:
            let s = min(a(0) * ss, w / 2)
            path = poly([P(x0 + s, y0), P(x1 - s, y0), P(x1, cy), P(x1 - s, y1), P(x0 + s, y1), P(x0, cy)])
            text = r.insetBy(dx: s * 0.6, dy: 0)
        case .octagon:
            let s = a(0) * ss
            path = poly([P(x0 + s, y0), P(x1 - s, y0), P(x1, y0 + s), P(x1, y1 - s), P(x1 - s, y1), P(x0 + s, y1), P(x0, y1 - s), P(x0, y0 + s)])
            text = r.insetBy(dx: s * 0.5, dy: s * 0.5)
        case .decagon:
            path = regular(10, rotation: 0)
            text = r.insetBy(dx: w * 0.12, dy: h * 0.12)
        case .pie, .chord:
            let start = a(0) * .pi / 180, end = a(1) * .pi / 180
            let p = CGMutablePath()
            let t = CGAffineTransform(translationX: cx, y: cy).scaledBy(x: w / 2, y: h / 2)
            if kind == .pie { p.move(to: .zero, transform: t) }
            p.addArc(center: .zero, radius: 1, startAngle: start, endAngle: end, clockwise: false, transform: t)
            p.closeSubpath()
            path = p
            text = r.insetBy(dx: w * 0.15, dy: h * 0.15)
        case .teardrop:
            let circle = CGMutablePath()
            circle.addEllipse(in: r)
            path = circle.union(poly([P(cx, y0), P(x1, y0), P(x1, cy), P(cx, cy)]))
            text = r.insetBy(dx: w * 0.146, dy: h * 0.146)
        case .frame:
            let t = a(0) * ss
            let p = CGMutablePath()
            p.addRect(r)
            p.addRect(r.insetBy(dx: t, dy: t))
            path = p
            text = r.insetBy(dx: t, dy: t)
        case .donut:
            let t = a(0) * ss
            let p = CGMutablePath()
            p.addEllipse(in: r)
            p.addEllipse(in: r.insetBy(dx: t, dy: t))
            path = p
        case .noSmoking:
            let t = a(0) * ss
            let ring = CGMutablePath()
            ring.addEllipse(in: r)
            ring.addEllipse(in: r.insetBy(dx: t, dy: t))
            let bar = CGMutablePath()
            let half = t / 2
            bar.addLines(between: [P(x0 + w * 0.15 - half, y0 + h * 0.15 + half), P(x0 + w * 0.15 + half, y0 + h * 0.15 - half),
                                   P(x1 - w * 0.15 + half, y1 - h * 0.15 - half), P(x1 - w * 0.15 - half, y1 - h * 0.15 + half)])
            bar.closeSubpath()
            let clipped = bar.intersection(CGPath(ellipseIn: r, transform: nil))
            path = ring.normalized(using: .evenOdd).union(clipped)
        case .can:
            let e = a(0) * ss
            let p = CGMutablePath()
            p.move(to: P(x0, y0 + e / 2))
            p.addLine(to: P(x0, y1 - e / 2))
            p.addCurve(to: P(x1, y1 - e / 2), control1: P(x0, y1 + e / 6), control2: P(x1, y1 + e / 6))
            p.addLine(to: P(x1, y0 + e / 2))
            p.addCurve(to: P(x0, y0 + e / 2), control1: P(x1, y0 - e / 6), control2: P(x0, y0 - e / 6))
            p.closeSubpath()
            path = p
            accents.append((CGPath(ellipseIn: CGRect(x: x0, y: y0, width: w, height: e), transform: nil), 0.25))
            text = CGRect(x: x0, y: y0 + e, width: w, height: h - e * 1.5)
        case .cube:
            let d = a(0) * ss
            path = poly([P(x0, y0 + d), P(x0 + d, y0), P(x1, y0), P(x1, y1 - d), P(x1 - d, y1), P(x0, y1)])
            accents.append((poly([P(x0, y0 + d), P(x0 + d, y0), P(x1, y0), P(x1 - d, y0 + d)]), 0.25))
            accents.append((poly([P(x1 - d, y0 + d), P(x1, y0), P(x1, y1 - d), P(x1 - d, y1)]), -0.2))
            text = CGRect(x: x0, y: y0 + d, width: w - d, height: h - d)
        case .heart:
            let p = CGMutablePath()
            p.move(to: P(cx, y0 + h * 0.25))
            p.addCurve(to: P(cx, y1), control1: P(cx + w * 0.55, y0 - h * 0.25), control2: P(x1 + w * 0.3, y0 + h * 0.45))
            p.addCurve(to: P(cx, y0 + h * 0.25), control1: P(x0 - w * 0.3, y0 + h * 0.45), control2: P(cx - w * 0.55, y0 - h * 0.25))
            p.closeSubpath()
            path = p
            text = r.insetBy(dx: w * 0.2, dy: h * 0.2)
        case .lightningBolt:
            path = npoly([(0.39, 0), (0.62, 0.32), (0.55, 0.35), (0.79, 0.6), (0.72, 0.63), (1, 1), (0.42, 0.7), (0.5, 0.67),
                          (0.17, 0.48), (0.26, 0.44), (0, 0.2)])
            text = r.insetBy(dx: w * 0.3, dy: h * 0.3)
        case .sun:
            let p = CGMutablePath()
            let core = r.insetBy(dx: w * 0.25, dy: h * 0.25)
            p.addEllipse(in: core)
            for i in 0..<8 {
                let t = Double(i) * .pi / 4
                let tip = P(cx + w / 2 * cos(t), cy + h / 2 * sin(t))
                let b1 = P(cx + w * 0.34 * cos(t - 0.18), cy + h * 0.34 * sin(t - 0.18))
                let b2 = P(cx + w * 0.34 * cos(t + 0.18), cy + h * 0.34 * sin(t + 0.18))
                p.addLines(between: [b1, tip, b2])
                p.closeSubpath()
            }
            path = p
            text = core.insetBy(dx: core.width * 0.15, dy: core.height * 0.15)
        case .moon:
            let k = a(0)
            let p = CGMutablePath()
            p.move(to: P(x1, y0))
            p.addCurve(to: P(x1, y1), control1: P(x0 - w * 0.33, y0), control2: P(x0 - w * 0.33, y1))
            p.addCurve(to: P(x1, y0), control1: P(x1 - w * k * 1.33, y1 - h * 0.1), control2: P(x1 - w * k * 1.33, y0 + h * 0.1))
            p.closeSubpath()
            path = p
            text = CGRect(x: x0 + w * 0.1, y: y0 + h * 0.3, width: w * 0.4, height: h * 0.4)
        case .cloud, .cloudCallout:
            var body = CGPath(ellipseIn: r.insetBy(dx: w * 0.12, dy: h * 0.16), transform: nil)
            let bumps: [(Double, Double, Double)] = [(0.2, 0.3, 0.42), (0.42, 0.2, 0.46), (0.66, 0.22, 0.42), (0.84, 0.42, 0.36),
                                                    (0.75, 0.72, 0.4), (0.5, 0.8, 0.42), (0.24, 0.72, 0.4), (0.12, 0.5, 0.32)]
            for (bx, by, size) in bumps {
                let bw = w * size, bh = h * size
                body = body.union(CGPath(ellipseIn: CGRect(x: x0 + w * bx - bw / 2, y: y0 + h * by - bh / 2, width: bw, height: bh), transform: nil))
            }
            if kind == .cloudCallout {
                let tip = P(x0 + w * a(0), y0 + h * a(1))
                for (i, s) in [0.07, 0.045, 0.03].enumerated() {
                    let t = 0.55 + Double(i) * 0.18
                    let c = P(cx + (tip.x - cx) * t, cy + (tip.y - cy) * t)
                    body = body.union(CGPath(ellipseIn: CGRect(x: c.x - ss * s, y: c.y - ss * s, width: ss * s * 2, height: ss * s * 2), transform: nil))
                }
            }
            path = body
            text = r.insetBy(dx: w * 0.2, dy: h * 0.22)
        case .smileyFace:
            path = CGPath(ellipseIn: r, transform: nil)
            let eye = CGSize(width: w * 0.1, height: h * 0.1)
            let eyes = CGMutablePath()
            eyes.addEllipse(in: CGRect(x: x0 + w * 0.3, y: y0 + h * 0.3, width: eye.width, height: eye.height))
            eyes.addEllipse(in: CGRect(x: x0 + w * 0.6, y: y0 + h * 0.3, width: eye.width, height: eye.height))
            accents.append((eyes, -0.35))
            let mouth = CGMutablePath()
            mouth.move(to: P(x0 + w * 0.27, y0 + h * 0.65))
            mouth.addQuadCurve(to: P(x0 + w * 0.73, y0 + h * 0.65), control: P(cx, y0 + h * 0.85))
            details.append(mouth)
            text = r.insetBy(dx: w * 0.2, dy: h * 0.2)
        case .plaque:
            let s = a(0) * ss
            let p = CGMutablePath()
            p.move(to: P(x0 + s, y0))
            p.addLine(to: P(x1 - s, y0))
            p.addArc(center: P(x1, y0), radius: s, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
            p.addLine(to: P(x1, y1 - s))
            p.addArc(center: P(x1, y1), radius: s, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
            p.addLine(to: P(x0 + s, y1))
            p.addArc(center: P(x0, y1), radius: s, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            p.addLine(to: P(x0, y0 + s))
            p.addArc(center: P(x0, y0), radius: s, startAngle: .pi / 2, endAngle: 0, clockwise: true)
            p.closeSubpath()
            path = p
            text = r.insetBy(dx: s * 0.7, dy: s * 0.7)
        case .rightArrow, .leftArrow, .notchedRightArrow:
            let shaft = a(0) * h, head = min(a(1) * ss, w)
            let top = cy - shaft / 2, bottom = cy + shaft / 2
            var pts = [P(x0, top), P(x1 - head, top), P(x1 - head, y0), P(x1, cy), P(x1 - head, y1), P(x1 - head, bottom), P(x0, bottom)]
            if kind == .notchedRightArrow { pts.append(P(x0 + shaft / 2, cy)) }
            if kind == .leftArrow { pts = pts.map { P(x0 + x1 - $0.x, $0.y) } }
            path = poly(pts)
            text = CGRect(x: kind == .leftArrow ? x0 + head * 0.5 : x0, y: top, width: w - head * 0.5, height: shaft)
        case .upArrow, .downArrow:
            let shaft = a(0) * w, head = min(a(1) * ss, h)
            let left = cx - shaft / 2, right = cx + shaft / 2
            var pts = [P(left, y1), P(left, y0 + head), P(x0, y0 + head), P(cx, y0), P(x1, y0 + head), P(right, y0 + head), P(right, y1)]
            if kind == .downArrow { pts = pts.map { P($0.x, y0 + y1 - $0.y) } }
            path = poly(pts)
            text = CGRect(x: left, y: kind == .upArrow ? y0 + head * 0.5 : y0, width: shaft, height: h - head * 0.5)
        case .leftRightArrow:
            let shaft = a(0) * h, head = min(a(1) * ss, w / 2)
            let top = cy - shaft / 2, bottom = cy + shaft / 2
            path = poly([P(x0, cy), P(x0 + head, y0), P(x0 + head, top), P(x1 - head, top), P(x1 - head, y0), P(x1, cy),
                         P(x1 - head, y1), P(x1 - head, bottom), P(x0 + head, bottom), P(x0 + head, y1)])
            text = CGRect(x: x0 + head * 0.5, y: top, width: w - head, height: shaft)
        case .upDownArrow:
            let shaft = a(0) * w, head = min(a(1) * ss, h / 2)
            let left = cx - shaft / 2, right = cx + shaft / 2
            path = poly([P(cx, y0), P(x1, y0 + head), P(right, y0 + head), P(right, y1 - head), P(x1, y1 - head), P(cx, y1),
                         P(x0, y1 - head), P(left, y1 - head), P(left, y0 + head), P(x0, y0 + head)])
            text = CGRect(x: left, y: y0 + head * 0.5, width: shaft, height: h - head)
        case .quadArrow:
            let s = a(0) * ss / 2, head = ss * 0.22
            path = poly([
                P(cx, y0), P(cx + head, y0 + head), P(cx + s, y0 + head), P(cx + s, cy - s), P(x1 - head, cy - s), P(x1 - head, cy - head),
                P(x1, cy), P(x1 - head, cy + head), P(x1 - head, cy + s), P(cx + s, cy + s), P(cx + s, y1 - head), P(cx + head, y1 - head),
                P(cx, y1), P(cx - head, y1 - head), P(cx - s, y1 - head), P(cx - s, cy + s), P(x0 + head, cy + s), P(x0 + head, cy + head),
                P(x0, cy), P(x0 + head, cy - head), P(x0 + head, cy - s), P(cx - s, cy - s), P(cx - s, y0 + head), P(cx - head, y0 + head),
            ])
            text = CGRect(x: cx - s, y: cy - s, width: s * 2, height: s * 2)
        case .chevron:
            let d = min(a(0) * ss, w)
            path = poly([P(x0, y0), P(x1 - d, y0), P(x1, cy), P(x1 - d, y1), P(x0, y1), P(x0 + d, cy)])
            text = r.insetBy(dx: d, dy: 0)
        case .homePlate:
            let d = min(a(0) * ss, w)
            path = poly([P(x0, y0), P(x1 - d, y0), P(x1, cy), P(x1 - d, y1), P(x0, y1)])
            text = CGRect(x: x0, y: y0, width: w - d * 0.5, height: h)
        case .mathPlus:
            let t = a(0) * ss / 2
            path = poly([P(cx - t, y0), P(cx + t, y0), P(cx + t, cy - t), P(x1, cy - t), P(x1, cy + t), P(cx + t, cy + t),
                         P(cx + t, y1), P(cx - t, y1), P(cx - t, cy + t), P(x0, cy + t), P(x0, cy - t), P(cx - t, cy - t)])
            text = CGRect(x: cx - t, y: cy - t, width: t * 2, height: t * 2)
        case .mathMinus:
            let t = a(0) * h / 2
            path = CGPath(rect: CGRect(x: x0, y: cy - t, width: w, height: t * 2), transform: nil)
        case .mathMultiply:
            let t = a(0) * ss / 2
            let plus = poly([P(cx - t, y0), P(cx + t, y0), P(cx + t, cy - t), P(x1, cy - t), P(x1, cy + t), P(cx + t, cy + t),
                             P(cx + t, y1), P(cx - t, y1), P(cx - t, cy + t), P(x0, cy + t), P(x0, cy - t), P(cx - t, cy - t)])
            var tr = CGAffineTransform(translationX: cx, y: cy).rotated(by: .pi / 4).scaledBy(x: 0.75, y: 0.75).translatedBy(x: -cx, y: -cy)
            path = plus.copy(using: &tr) ?? plus
            text = CGRect(x: cx - t, y: cy - t, width: t * 2, height: t * 2)
        case .mathDivide:
            let t = a(0) * h / 2
            let p = CGMutablePath()
            p.addRect(CGRect(x: x0, y: cy - t / 2, width: w, height: t))
            let d = min(t * 1.6, h * 0.2)
            p.addEllipse(in: CGRect(x: cx - d / 2, y: y0 + h * 0.12, width: d, height: d))
            p.addEllipse(in: CGRect(x: cx - d / 2, y: y1 - h * 0.12 - d, width: d, height: d))
            path = p
        case .mathEqual, .mathNotEqual:
            let t = a(0) * h / 3
            let p = CGMutablePath()
            p.addRect(CGRect(x: x0, y: cy - t * 1.5, width: w, height: t))
            p.addRect(CGRect(x: x0, y: cy + t * 0.5, width: w, height: t))
            if kind == .mathNotEqual {
                let slash = poly([P(cx + w * 0.12, y0), P(cx + w * 0.12 + t, y0), P(cx - w * 0.12 + t, y1), P(cx - w * 0.12, y1)])
                path = p.union(slash)
            } else {
                path = p
            }
        case .flowChartPredefinedProcess:
            path = CGPath(rect: r, transform: nil)
            let lines = CGMutablePath()
            lines.addLines(between: [P(x0 + w * 0.1, y0), P(x0 + w * 0.1, y1)])
            lines.addLines(between: [P(x1 - w * 0.1, y0), P(x1 - w * 0.1, y1)])
            details.append(lines)
            text = r.insetBy(dx: w * 0.1, dy: 0)
        case .flowChartDocument:
            let p = CGMutablePath()
            p.move(to: P(x0, y0))
            p.addLine(to: P(x1, y0))
            p.addLine(to: P(x1, y1 - h * 0.17))
            p.addCurve(to: P(x0, y1 - h * 0.08), control1: P(x0 + w * 0.7, y1 - h * 0.4), control2: P(x0 + w * 0.3, y1 + h * 0.2))
            p.closeSubpath()
            path = p
            text = CGRect(x: x0, y: y0, width: w, height: h * 0.8)
        case .flowChartTerminator:
            let radius = min(h / 2, w / 2)
            path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            text = r.insetBy(dx: radius * 0.3, dy: 0)
        case .flowChartPreparation:
            let s = min(w * 0.2, h)
            path = poly([P(x0 + s, y0), P(x1 - s, y0), P(x1, cy), P(x1 - s, y1), P(x0 + s, y1), P(x0, cy)])
            text = r.insetBy(dx: s, dy: 0)
        case .flowChartDelay:
            let p = CGMutablePath()
            p.move(to: P(x0, y0))
            p.addLine(to: P(cx, y0))
            p.addArc(center: .zero, radius: 1, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false,
                     transform: CGAffineTransform(translationX: cx, y: cy).scaledBy(x: w / 2, y: h / 2))
            p.addLine(to: P(x0, y1))
            p.closeSubpath()
            path = p
            text = r.insetBy(dx: w * 0.05, dy: h * 0.15)
        case .star4, .star5, .star6, .star8, .star12, .star24:
            let n: Int
            switch kind {
            case .star4: n = 4
            case .star5: n = 5
            case .star6: n = 6
            case .star8: n = 8
            case .star12: n = 12
            default: n = 24
            }
            path = star(n, inner: a(0))
            let k = max(a(0), 0.3)
            text = r.insetBy(dx: w * (1 - k * 0.8) / 2, dy: h * (1 - k * 0.8) / 2)
        case .irregularSeal1:
            path = npoly([(0.5, 0.18), (0.6, 0), (0.64, 0.2), (0.86, 0.08), (0.78, 0.3), (1, 0.34), (0.82, 0.5), (0.98, 0.7), (0.76, 0.66),
                          (0.8, 0.94), (0.6, 0.76), (0.5, 1), (0.42, 0.78), (0.2, 0.92), (0.26, 0.68), (0, 0.66), (0.18, 0.5), (0.02, 0.28),
                          (0.26, 0.32), (0.22, 0.06), (0.4, 0.24)])
            text = r.insetBy(dx: w * 0.28, dy: h * 0.28)
        case .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout:
            let tip = P(x0 + w * a(0), y0 + h * a(1))
            let body: CGPath
            switch kind {
            case .wedgeEllipseCallout: body = CGPath(ellipseIn: r, transform: nil)
            case .wedgeRoundRectCallout: body = CGPath(roundedRect: r, cornerWidth: ss * 0.1667, cornerHeight: ss * 0.1667, transform: nil)
            default: body = CGPath(rect: r, transform: nil)
            }
            // A wedge from the center region toward the tip.
            let dx = tip.x - cx, dy = tip.y - cy
            let len = max(hypot(dx, dy), 1)
            let nx = -dy / len, ny = dx / len
            let base = ss * 0.12
            let start = P(cx + dx * 0.2, cy + dy * 0.2)
            let wedge = poly([P(start.x + nx * base, start.y + ny * base), tip, P(start.x - nx * base, start.y - ny * base)])
            path = body.union(wedge)
            text = kind == .wedgeEllipseCallout ? r.insetBy(dx: w * 0.146, dy: h * 0.146) : r
        }
        return ShapeGeometry(path: path, accents: accents, details: details, textRect: text)
    }

    /// Where the yellow adjustment handle sits, in the shape's rect.
    static func adjustHandle(_ kind: ShapeKind, in r: CGRect, adjustments adj: [Double]) -> CGPoint? {
        guard kind.hasAdjustHandle else { return nil }
        func a(_ i: Int) -> Double { i < adj.count ? adj[i] : (i < kind.defaultAdjustments.count ? kind.defaultAdjustments[i] : 0) }
        let ss = min(r.width, r.height)
        switch kind {
        case .roundRect, .round2SameRect, .plaque: return CGPoint(x: r.minX + a(0) * ss, y: r.minY)
        case .snip1Rect, .snip2SameRect: return CGPoint(x: r.maxX - a(0) * ss, y: r.minY)
        case .parallelogram, .trapezoid, .hexagon, .flowChartInputOutput: return CGPoint(x: r.minX + a(0) * ss, y: r.minY)
        case .octagon: return CGPoint(x: r.minX + a(0) * ss, y: r.minY)
        case .chevron, .homePlate: return CGPoint(x: r.maxX - a(0) * ss, y: r.minY)
        case .frame: return CGPoint(x: r.minX + a(0) * ss, y: r.minY)
        case .donut, .noSmoking: return CGPoint(x: r.minX + a(0) * ss, y: r.midY)
        case .can, .cube: return CGPoint(x: r.midX, y: r.minY + a(0) * ss)
        case .moon: return CGPoint(x: r.maxX - a(0) * r.width, y: r.midY)
        case .star4, .star5, .star6, .star8, .star12, .star24: return CGPoint(x: r.midX, y: r.midY - a(0) * r.height / 2)
        case .rightArrow, .notchedRightArrow, .leftRightArrow: return CGPoint(x: r.maxX - a(1) * ss, y: r.minY)
        case .leftArrow: return CGPoint(x: r.minX + a(1) * ss, y: r.minY)
        case .upArrow, .upDownArrow: return CGPoint(x: r.minX, y: r.minY + a(1) * ss)
        case .downArrow: return CGPoint(x: r.minX, y: r.maxY - a(1) * ss)
        case .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout, .cloudCallout:
            return CGPoint(x: r.minX + a(0) * r.width, y: r.minY + a(1) * r.height)
        default: return nil
        }
    }

    /// The adjustments after dragging the handle to `point`.
    static func adjust(_ kind: ShapeKind, in r: CGRect, adjustments adj: [Double], to point: CGPoint) -> [Double] {
        var values = kind.defaultAdjustments.indices.map { $0 < adj.count ? adj[$0] : kind.defaultAdjustments[$0] }
        let ss = max(min(r.width, r.height), 1)
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        switch kind {
        case .roundRect, .round2SameRect, .plaque: values[0] = clamp((point.x - r.minX) / ss, 0, 0.5)
        case .snip1Rect, .snip2SameRect: values[0] = clamp((r.maxX - point.x) / ss, 0, 0.5)
        case .parallelogram, .trapezoid, .hexagon, .flowChartInputOutput: values[0] = clamp((point.x - r.minX) / ss, 0, r.width / ss * 0.5)
        case .octagon: values[0] = clamp((point.x - r.minX) / ss, 0, 0.5)
        case .chevron, .homePlate: values[0] = clamp((r.maxX - point.x) / ss, 0, r.width / ss)
        case .frame: values[0] = clamp((point.x - r.minX) / ss, 0, 0.5)
        case .donut, .noSmoking: values[0] = clamp((point.x - r.minX) / ss, 0.02, 0.5)
        case .can, .cube: values[0] = clamp((point.y - r.minY) / ss, 0, 1)
        case .moon: values[0] = clamp((r.maxX - point.x) / max(r.width, 1), 0.05, 0.9)
        case .star4, .star5, .star6, .star8, .star12, .star24: values[0] = clamp((r.midY - point.y) / max(r.height / 2, 1), 0.05, 0.95)
        case .rightArrow, .notchedRightArrow, .leftRightArrow: values[1] = clamp((r.maxX - point.x) / ss, 0, r.width / ss)
        case .leftArrow: values[1] = clamp((point.x - r.minX) / ss, 0, r.width / ss)
        case .upArrow, .upDownArrow: values[1] = clamp((point.y - r.minY) / ss, 0, r.height / ss)
        case .downArrow: values[1] = clamp((r.maxY - point.y) / ss, 0, r.height / ss)
        case .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout, .cloudCallout:
            values[0] = (point.x - r.minX) / max(r.width, 1)
            values[1] = (point.y - r.minY) / max(r.height, 1)
        default: break
        }
        return values
    }
}

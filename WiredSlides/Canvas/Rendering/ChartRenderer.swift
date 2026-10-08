import AppKit

/// Draws charts with Core Graphics, in theme colors.
enum ChartRenderer {
    static func seriesColor(_ chart: ChartContent, _ index: Int, colors: ThemeColors) -> RGBColor {
        if !chart.kind.isRound, index < chart.series.count, let c = chart.series[index].color { return c.resolve(colors) }
        let accents = colors.accents
        let base = accents[index % accents.count]
        let round = index / accents.count
        return round == 0 ? base : base.shaded(round % 2 == 1 ? -0.3 : 0.35)
    }

    static func draw(_ chart: ChartContent, in rect: CGRect, ctx: CGContext, env: RenderEnvironment) {
        ElementRenderer.withNSContext(ctx) {
            drawChart(chart, in: rect, ctx: ctx, env: env)
        }
    }

    private static func drawChart(_ chart: ChartContent, in rect: CGRect, ctx: CGContext, env: RenderEnvironment) {
        let colors = env.colors
        Paint.fill(CGPath(rect: rect, transform: nil), with: chart.background, bounds: rect, in: ctx, env: env)
        let textColor = chart.textColor.resolve(colors).nsColor
        let fontName = env.theme.bodyFont
        let fs = CGFloat(chart.fontSize)
        func font(_ size: CGFloat, bold: Bool = false) -> NSFont { FontResolver.font(family: fontName, size: size, bold: bold, italic: false) }
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: font(fs), .foregroundColor: textColor]
        var plot = rect.insetBy(dx: 8, dy: 8)

        if let title = chart.title, !title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: font(fs * 1.5), .foregroundColor: textColor]
            let size = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: plot.minY), withAttributes: attrs)
            plot.origin.y += size.height + 6
            plot.size.height -= size.height + 6
        }

        let legendItems: [(String, NSColor)] = chart.kind.isRound
            ? chart.categories.enumerated().map { ($0.element, seriesColor(chart, $0.offset, colors: colors).nsColor) }
            : chart.series.enumerated().map { ($0.element.name, seriesColor(chart, $0.offset, colors: colors).nsColor) }
        if chart.legend != .none, !legendItems.isEmpty {
            plot = drawLegend(legendItems, position: chart.legend, in: plot, attrs: labelAttrs, ctx: ctx)
        }
        guard plot.width > 20, plot.height > 20 else { return }

        switch chart.kind {
        case .pie, .doughnut: drawPie(chart, in: plot, ctx: ctx, colors: colors, attrs: labelAttrs)
        default: drawCartesian(chart, in: plot, ctx: ctx, colors: colors, attrs: labelAttrs, textColor: textColor)
        }
    }

    private static func drawLegend(_ items: [(String, NSColor)], position: LegendPosition, in plot: CGRect,
                                   attrs: [NSAttributedString.Key: Any], ctx: CGContext) -> CGRect {
        let font = attrs[.font] as! NSFont
        let swatch = font.pointSize * 0.75
        let spacing = font.pointSize
        let widths = items.map { ($0.0 as NSString).size(withAttributes: attrs).width + swatch + 5 }
        let lineHeight = font.pointSize * 1.4
        var plot = plot
        func drawItem(_ i: Int, at p: CGPoint) {
            ctx.setFillColor(items[i].1.cgColor)
            ctx.fill(CGRect(x: p.x, y: p.y + (lineHeight - swatch) / 2, width: swatch, height: swatch))
            (items[i].0 as NSString).draw(at: CGPoint(x: p.x + swatch + 5, y: p.y + (lineHeight - font.pointSize * 1.2) / 2), withAttributes: attrs)
        }
        switch position {
        case .none:
            break
        case .top, .bottom:
            // Wrap items into centered rows.
            var rows: [[Int]] = [[]]
            var x: CGFloat = 0
            for (i, w) in widths.enumerated() {
                if x + w > plot.width, !rows[rows.count - 1].isEmpty { rows.append([]); x = 0 }
                rows[rows.count - 1].append(i)
                x += w + spacing
            }
            let total = CGFloat(rows.count) * lineHeight
            var y = position == .top ? plot.minY : plot.maxY - total
            for row in rows {
                let rowWidth = row.map { widths[$0] }.reduce(0, +) + spacing * CGFloat(row.count - 1)
                var x = plot.midX - rowWidth / 2
                for i in row { drawItem(i, at: CGPoint(x: x, y: y)); x += widths[i] + spacing }
                y += lineHeight
            }
            if position == .top { plot.origin.y += total + 6 }
            plot.size.height -= total + 6
        case .left, .right:
            let column = (widths.max() ?? 0) + 8
            let total = CGFloat(items.count) * lineHeight
            let x = position == .left ? plot.minX : plot.maxX - column + 8
            var y = plot.midY - total / 2
            for i in items.indices { drawItem(i, at: CGPoint(x: x, y: y)); y += lineHeight }
            if position == .left { plot.origin.x += column }
            plot.size.width -= column + 4
        }
        return plot
    }

    private static func drawPie(_ chart: ChartContent, in plot: CGRect, ctx: CGContext, colors: ThemeColors, attrs: [NSAttributedString.Key: Any]) {
        guard let series = chart.series.first else { return }
        let values = series.values.map { max($0, 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return }
        let d = min(plot.width, plot.height)
        let circle = CGRect(x: plot.midX - d / 2, y: plot.midY - d / 2, width: d, height: d)
        let center = CGPoint(x: circle.midX, y: circle.midY)
        var angle = -CGFloat.pi / 2
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = CGFloat(v / total) * 2 * .pi
            let p = CGMutablePath()
            if chart.kind == .doughnut {
                p.addArc(center: center, radius: d / 2, startAngle: angle, endAngle: angle + sweep, clockwise: false)
                p.addArc(center: center, radius: d / 4, startAngle: angle + sweep, endAngle: angle, clockwise: true)
            } else {
                p.move(to: center)
                p.addArc(center: center, radius: d / 2, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            }
            p.closeSubpath()
            ctx.setFillColor(seriesColor(chart, i, colors: colors).cgColor)
            ctx.addPath(p)
            ctx.fillPath()
            ctx.setStrokeColor(colors.light1.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(p)
            ctx.strokePath()
            if chart.showDataLabels {
                let mid = angle + sweep / 2
                let r = chart.kind == .doughnut ? d * 0.38 : d * 0.32
                let label = "\(Int((v / total * 100).rounded()))%" as NSString
                var a = attrs
                a[.foregroundColor] = seriesColor(chart, i, colors: colors).isDark ? NSColor.white : NSColor.black
                let size = label.size(withAttributes: a)
                label.draw(at: CGPoint(x: center.x + cos(mid) * r - size.width / 2, y: center.y + sin(mid) * r - size.height / 2), withAttributes: a)
            }
            angle += sweep
        }
    }

    /// A rounded axis range and step.
    static func niceScale(min lo: Double, max hi: Double, ticks: Int = 5) -> (min: Double, max: Double, step: Double) {
        var lo = lo, hi = hi
        if lo == hi { hi = lo + 1; if lo > 0 { lo = 0 } }
        let range = hi - lo
        let rough = range / Double(ticks)
        let magnitude = pow(10, floor(log10(rough)))
        let residual = rough / magnitude
        let step = (residual > 5 ? 10 : residual > 2 ? 5 : residual > 1 ? 2 : 1) * magnitude
        return (floor(lo / step) * step, ceil(hi / step) * step, step)
    }

    static func format(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "%gM", v / 1_000_000) }
        if abs(v) >= 10_000 { return String(format: "%gK", v / 1000) }
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%g", (v * 1000).rounded() / 1000)
    }

    private static func drawCartesian(_ chart: ChartContent, in plotRect: CGRect, ctx: CGContext, colors: ThemeColors,
                                      attrs: [NSAttributedString.Key: Any], textColor: NSColor) {
        let kind = chart.kind
        let horizontal = kind == .bar || kind == .stackedBar
        let stacked = kind == .stackedColumn || kind == .stackedBar
        let n = max(chart.categories.count, chart.series.map(\.values.count).max() ?? 0)
        guard n > 0, !chart.series.isEmpty else { return }
        func value(_ s: Int, _ i: Int) -> Double { i < chart.series[s].values.count ? chart.series[s].values[i] : 0 }

        // Value range.
        var lo = 0.0, hi = 0.0
        if kind == .scatter {
            for s in chart.series.indices { for i in 0..<n { lo = min(lo, value(s, i)); hi = max(hi, value(s, i)) } }
        } else if stacked {
            for i in 0..<n {
                let pos = chart.series.indices.map { max(value($0, i), 0) }.reduce(0, +)
                let neg = chart.series.indices.map { min(value($0, i), 0) }.reduce(0, +)
                hi = max(hi, pos); lo = min(lo, neg)
            }
        } else {
            for s in chart.series.indices { for i in 0..<n { lo = min(lo, value(s, i)); hi = max(hi, value(s, i)) } }
        }
        let scale = niceScale(min: lo, max: hi)
        let font = attrs[.font] as! NSFont
        var ticks: [Double] = []
        var t = scale.min
        while t <= scale.max + scale.step / 2 { ticks.append(t); t += scale.step }
        let tickLabelWidth = ticks.map { (format($0) as NSString).size(withAttributes: attrs).width }.max() ?? 0
        let categoryLabelHeight = font.pointSize * 1.4
        let categoryLabelWidth = chart.categories.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0

        var plot = plotRect
        if horizontal {
            plot.origin.x += categoryLabelWidth + 8
            plot.size.width -= categoryLabelWidth + 8
            plot.size.height -= categoryLabelHeight
        } else {
            plot.origin.x += tickLabelWidth + 8
            plot.size.width -= tickLabelWidth + 8
            plot.size.height -= categoryLabelHeight
        }
        guard plot.width > 10, plot.height > 10 else { return }

        func valuePos(_ v: Double) -> CGFloat {
            let f = CGFloat((v - scale.min) / (scale.max - scale.min))
            return horizontal ? plot.minX + f * plot.width : plot.maxY - f * plot.height
        }

        // Gridlines and value labels.
        ctx.setLineWidth(0.75)
        for tick in ticks {
            let p = valuePos(tick)
            if chart.showGridlines {
                ctx.setStrokeColor(textColor.withAlphaComponent(0.15).cgColor)
                if horizontal {
                    ctx.strokeLineSegments(between: [CGPoint(x: p, y: plot.minY), CGPoint(x: p, y: plot.maxY)])
                } else {
                    ctx.strokeLineSegments(between: [CGPoint(x: plot.minX, y: p), CGPoint(x: plot.maxX, y: p)])
                }
            }
            let label = format(tick) as NSString
            let size = label.size(withAttributes: attrs)
            if horizontal {
                label.draw(at: CGPoint(x: p - size.width / 2, y: plot.maxY + 3), withAttributes: attrs)
            } else {
                label.draw(at: CGPoint(x: plot.minX - size.width - 6, y: p - size.height / 2), withAttributes: attrs)
            }
        }
        // Axis line at zero.
        ctx.setStrokeColor(textColor.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(1)
        let zero = valuePos(max(scale.min, min(0, scale.max)))
        if horizontal {
            ctx.strokeLineSegments(between: [CGPoint(x: zero, y: plot.minY), CGPoint(x: zero, y: plot.maxY)])
        } else {
            ctx.strokeLineSegments(between: [CGPoint(x: plot.minX, y: zero), CGPoint(x: plot.maxX, y: zero)])
        }

        // Category labels.
        let band = (horizontal ? plot.height : plot.width) / CGFloat(n)
        for i in 0..<min(n, chart.categories.count) {
            let label = chart.categories[i] as NSString
            let size = label.size(withAttributes: attrs)
            if horizontal {
                label.draw(at: CGPoint(x: plot.minX - size.width - 6, y: plot.minY + band * (CGFloat(i) + 0.5) - size.height / 2), withAttributes: attrs)
            } else if kind == .scatter {
                continue
            } else {
                let maxWidth = band - 4
                let drawn = size.width > maxWidth ? label.truncated(to: maxWidth, attrs: attrs) : label
                let s2 = drawn.size(withAttributes: attrs)
                drawn.draw(at: CGPoint(x: plot.minX + band * (CGFloat(i) + 0.5) - s2.width / 2, y: plot.maxY + 3), withAttributes: attrs)
            }
        }

        let seriesCount = chart.series.count
        switch kind {
        case .column, .bar, .stackedColumn, .stackedBar:
            let groupWidth = band * 0.7
            let barWidth = stacked ? groupWidth : groupWidth / CGFloat(seriesCount)
            for i in 0..<n {
                var posBase = 0.0, negBase = 0.0
                for s in 0..<seriesCount {
                    let v = value(s, i)
                    var from = 0.0, to = v
                    if stacked {
                        if v >= 0 { from = posBase; to = posBase + v; posBase = to } else { from = negBase; to = negBase + v; negBase = to }
                    }
                    let start = (horizontal ? plot.minY : plot.minX) + band * CGFloat(i) + (band - groupWidth) / 2 + (stacked ? 0 : barWidth * CGFloat(s))
                    let a = valuePos(from), b = valuePos(to)
                    let r = horizontal
                        ? CGRect(x: min(a, b), y: start, width: abs(b - a), height: barWidth * 0.92)
                        : CGRect(x: start, y: min(a, b), width: barWidth * 0.92, height: abs(b - a))
                    let color = seriesColor(chart, s, colors: colors)
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(r)
                    if chart.showDataLabels {
                        let label = format(v) as NSString
                        let size = label.size(withAttributes: attrs)
                        let p = horizontal
                            ? CGPoint(x: r.maxX + 3, y: r.midY - size.height / 2)
                            : CGPoint(x: r.midX - size.width / 2, y: stacked ? r.midY - size.height / 2 : r.minY - size.height - 1)
                        label.draw(at: p, withAttributes: attrs)
                    }
                }
            }
        case .line, .lineMarkers, .area:
            for s in (0..<seriesCount).reversed() {
                let color = seriesColor(chart, s, colors: colors)
                let points = (0..<n).map { CGPoint(x: plot.minX + band * (CGFloat($0) + 0.5), y: valuePos(value(s, $0))) }
                if kind == .area {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: points[0].x, y: zero))
                    p.addLines(between: points)
                    p.addLine(to: CGPoint(x: points[points.count - 1].x, y: zero))
                    p.closeSubpath()
                    ctx.setFillColor(color.withAlpha(0.75).cgColor)
                    ctx.addPath(p)
                    ctx.fillPath()
                } else {
                    ctx.setStrokeColor(color.cgColor)
                    ctx.setLineWidth(max(2, font.pointSize / 5))
                    ctx.setLineJoin(.round)
                    ctx.addLines(between: points)
                    ctx.strokePath()
                    if kind == .lineMarkers {
                        ctx.setFillColor(color.cgColor)
                        for p in points { ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)) }
                    }
                }
                if chart.showDataLabels {
                    for (i, p) in points.enumerated() {
                        let label = format(value(s, i)) as NSString
                        let size = label.size(withAttributes: attrs)
                        label.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height - 4), withAttributes: attrs)
                    }
                }
            }
        case .scatter:
            // Category positions are 1…n on the x axis.
            for s in 0..<seriesCount {
                let color = seriesColor(chart, s, colors: colors)
                ctx.setFillColor(color.cgColor)
                for i in 0..<n {
                    let p = CGPoint(x: plot.minX + plot.width * CGFloat(i + 1) / CGFloat(n + 1), y: valuePos(value(s, i)))
                    ctx.fillEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
                }
            }
        case .pie, .doughnut:
            break
        }
    }
}

private extension NSString {
    func truncated(to width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> NSString {
        var s = self as String
        while s.count > 1, ((s + "…") as NSString).size(withAttributes: attrs).width > width { s.removeLast() }
        return (s + "…") as NSString
    }
}

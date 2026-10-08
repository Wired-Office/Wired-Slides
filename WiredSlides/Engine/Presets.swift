import AppKit

/// Shape Styles gallery presets (theme-colored, so they follow the design).
struct ShapeStylePreset: Identifiable {
    let id: String
    let fill: Fill
    let line: LineStyle
    let effects: Effects
    let textColor: PaintColor

    static func presets() -> [ShapeStylePreset] {
        let accents: [ThemeSlot] = [.dark1, .accent1, .accent2, .accent3, .accent4, .accent5, .accent6]
        var result: [ShapeStylePreset] = []
        for (n, slot) in accents.enumerated() {
            // Colored outline only.
            result.append(ShapeStylePreset(id: "outline-\(n)", fill: .solid(.theme(.light1)), line: .solid(.theme(slot), width: 1.5),
                                           effects: .none, textColor: .theme(.dark1)))
        }
        for (n, slot) in accents.enumerated() {
            // Solid fill.
            result.append(ShapeStylePreset(id: "solid-\(n)", fill: .solid(.theme(slot)), line: .solid(.theme(slot, shade: -0.25, alpha: 1), width: 1),
                                           effects: .none, textColor: .theme(.light1)))
        }
        for (n, slot) in accents.enumerated() {
            // Light tint.
            result.append(ShapeStylePreset(id: "light-\(n)", fill: .solid(.theme(slot, shade: 0.8, alpha: 1)), line: .solid(.theme(slot), width: 1),
                                           effects: .none, textColor: .theme(.dark1)))
        }
        for (n, slot) in accents.enumerated() {
            // Gradient with shadow.
            result.append(ShapeStylePreset(id: "intense-\(n)",
                                           fill: .gradient(.twoTone(.theme(slot, shade: 0.25, alpha: 1), .theme(slot, shade: -0.2, alpha: 1))),
                                           line: .none, effects: Effects(shadow: .soft), textColor: .theme(.light1)))
        }
        return result
    }
}

/// WordArt styles.
struct WordArtPreset: Identifiable {
    let id: String
    let apply: (inout RunStyle) -> Void

    static let all: [WordArtPreset] = [
        WordArtPreset(id: "fill-dark") { $0.color = .theme(.dark1); $0.bold = true },
        WordArtPreset(id: "fill-accent") { $0.color = .theme(.accent1); $0.bold = true },
        WordArtPreset(id: "fill-accent-shadow") { $0.color = .theme(.accent1); $0.bold = true; $0.shadow = true },
        WordArtPreset(id: "outline-accent") { $0.color = .theme(.light1); $0.outlineColor = .theme(.accent1); $0.outlineWidth = 1.5; $0.bold = true },
        WordArtPreset(id: "outline-dark") { $0.color = .rgb(.clear); $0.outlineColor = .theme(.dark1); $0.outlineWidth = 1.25 },
        WordArtPreset(id: "fill-accent2-shadow") { $0.color = .theme(.accent2); $0.bold = true; $0.shadow = true },
        WordArtPreset(id: "fill-white-outline") { $0.color = .theme(.light1); $0.outlineColor = .theme(.dark1); $0.outlineWidth = 2; $0.bold = true; $0.shadow = true },
        WordArtPreset(id: "caps-spaced") { $0.color = .theme(.accent1); $0.allCaps = true; $0.characterSpacing = 6; $0.bold = true },
        WordArtPreset(id: "fill-accent3") { $0.color = .theme(.accent3); $0.bold = true; $0.italic = true },
    ]
}

enum SmartArtKind: String, CaseIterable, Identifiable {
    case basicList, process, cycle, hierarchy, pyramid, venn, chevrons, timeline, matrix
    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicList: "Basic Block List"
        case .process: "Basic Process"
        case .cycle: "Basic Cycle"
        case .hierarchy: "Hierarchy"
        case .pyramid: "Basic Pyramid"
        case .venn: "Basic Venn"
        case .chevrons: "Chevron Process"
        case .timeline: "Basic Timeline"
        case .matrix: "Basic Matrix"
        }
    }

    var symbol: String {
        switch self {
        case .basicList: "square.grid.3x1.below.line.grid.1x2"
        case .process: "arrow.right.square"
        case .cycle: "arrow.triangle.2.circlepath"
        case .hierarchy: "point.3.connected.trianglepath.dotted"
        case .pyramid: "triangle"
        case .venn: "circle.circle"
        case .chevrons: "chevron.right.2"
        case .timeline: "timeline.selection"
        case .matrix: "square.grid.2x2"
        }
    }

    var category: String {
        switch self {
        case .basicList: "List"
        case .process, .chevrons, .timeline: "Process"
        case .cycle: "Cycle"
        case .hierarchy: "Hierarchy"
        case .pyramid: "Pyramid"
        case .venn, .matrix: "Relationship"
        }
    }

    var sampleItems: [String] {
        switch self {
        case .hierarchy: ["Leader", "Team A", "Team B", "Team C"]
        case .timeline: ["2023", "2024", "2025", "2026"]
        case .venn: ["Design", "Engineering", "Business"]
        case .matrix: ["Strengths", "Weaknesses", "Opportunities", "Threats"]
        case .pyramid: ["Vision", "Strategy", "Execution"]
        default: ["Plan", "Build", "Test", "Launch"]
        }
    }
}

/// Builds SmartArt-style diagrams as editable grouped shapes.
enum SmartArtBuilder {
    static func build(_ kind: SmartArtKind, items rawItems: [String], in frame: CGRect) -> SlideElement {
        let items = rawItems.isEmpty ? kind.sampleItems : rawItems
        let n = items.count
        let accents: [ThemeSlot] = [.accent1, .accent2, .accent3, .accent4, .accent5, .accent6]
        func color(_ i: Int) -> PaintColor { .theme(accents[i % accents.count], shade: 0, alpha: 1) }
        func box(_ kind: ShapeKind, _ rect: CGRect, _ text: String, _ i: Int, alpha: Double = 1, textColor: PaintColor = .theme(.light1)) -> SlideElement {
            var e = SlideElement.shape(kind, frame: rect, fill: .solid(alpha < 1 ? .theme(accents[i % accents.count], shade: 0, alpha: alpha) : color(i)),
                                       line: .solid(.theme(.light1), width: 1.5), text: text)
            e.text?.defaultColor = textColor
            e.text?.defaultSize = Double(min(24, max(12, rect.height / 4)))
            e.text?.autofit = .shrink
            e.name = "\(kind.title) \(i + 1)"
            return e
        }
        var children: [SlideElement] = []
        let f = frame
        switch kind {
        case .basicList:
            let columns = min(n, 3), rows = Int(ceil(Double(n) / Double(columns)))
            let gap: CGFloat = 16
            let w = (f.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let h = min((f.height - gap * CGFloat(rows - 1)) / CGFloat(rows), w * 0.6)
            for (i, item) in items.enumerated() {
                let r = i / columns, c = i % columns
                children.append(box(.rect, CGRect(x: f.minX + CGFloat(c) * (w + gap), y: f.minY + CGFloat(r) * (h + gap), width: w, height: h), item, i))
            }
        case .process, .chevrons:
            let arrowW: CGFloat = kind == .process ? 34 : -18
            let w = (f.width - arrowW * CGFloat(n - 1)) / CGFloat(n)
            let h = min(f.height, w * 0.65)
            let y = f.midY - h / 2
            for (i, item) in items.enumerated() {
                let x = f.minX + CGFloat(i) * (w + arrowW)
                if kind == .process {
                    children.append(box(.roundRect, CGRect(x: x, y: y, width: w, height: h), item, i))
                    if i < n - 1 {
                        var arrow = SlideElement.shape(.rightArrow, frame: CGRect(x: x + w + 6, y: f.midY - 12, width: arrowW - 12, height: 24),
                                                       fill: .solid(.theme(.dark1, shade: 0.6, alpha: 1)), line: .none)
                        arrow.name = "Arrow \(i + 1)"
                        children.append(arrow)
                    }
                } else {
                    children.append(box(i == 0 ? .homePlate : .chevron, CGRect(x: x, y: y, width: w, height: h), item, i))
                }
            }
        case .cycle:
            let radius = min(f.width, f.height) / 2 - 50
            let c = CGPoint(x: f.midX, y: f.midY)
            let d = min(120, radius * 1.1)
            for (i, item) in items.enumerated() {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * radius, y: c.y + CGFloat(sin(a)) * radius)
                children.append(box(.ellipse, CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d), item, i))
                let mid = a + .pi / Double(n)
                let q = CGPoint(x: c.x + CGFloat(cos(mid)) * radius, y: c.y + CGFloat(sin(mid)) * radius)
                var arrow = SlideElement.shape(.rightArrow, frame: CGRect(x: q.x - 14, y: q.y - 10, width: 28, height: 20),
                                               fill: .solid(.theme(.dark1, shade: 0.6, alpha: 1)), line: .none)
                arrow.rotation = (mid + .pi / 2) * 180 / .pi
                arrow.name = "Arrow \(i + 1)"
                children.append(arrow)
            }
        case .hierarchy:
            let top = items.first ?? ""
            let rest = Array(items.dropFirst())
            let h = min(f.height / 3, 70)
            let topW = min(f.width / 3, 220)
            let topRect = CGRect(x: f.midX - topW / 2, y: f.minY + 10, width: topW, height: h)
            let gap: CGFloat = 20
            let count = max(rest.count, 1)
            let w = min((f.width - gap * CGFloat(count - 1)) / CGFloat(count), 200)
            let total = w * CGFloat(count) + gap * CGFloat(count - 1)
            let y = f.maxY - h - 10
            let busY = (topRect.maxY + y) / 2
            func connector(_ a: CGPoint, _ b: CGPoint) {
                var line = SlideElement.line(from: a, to: b, style: .solid(.theme(.dark1, shade: 0.5, alpha: 1), width: 1.5))
                line.name = "Connector"
                children.append(line)
            }
            if !rest.isEmpty { connector(CGPoint(x: topRect.midX, y: topRect.maxY), CGPoint(x: topRect.midX, y: busY)) }
            for (i, item) in rest.enumerated() {
                let r = CGRect(x: f.midX - total / 2 + CGFloat(i) * (w + gap), y: y, width: w, height: h)
                connector(CGPoint(x: r.midX, y: busY), CGPoint(x: r.midX, y: r.minY))
                children.append(box(.roundRect, r, item, i + 1))
            }
            if rest.count > 1 {
                let first = f.midX - total / 2 + w / 2, last = f.midX + total / 2 - w / 2
                connector(CGPoint(x: first, y: busY), CGPoint(x: last, y: busY))
            }
            children.append(box(.roundRect, topRect, top, 0))
        case .pyramid:
            let h = f.height / CGFloat(n)
            for (i, item) in items.enumerated() {
                let topFrac = CGFloat(i) / CGFloat(n), bottomFrac = CGFloat(i + 1) / CGFloat(n)
                let wTop = f.width * 0.8 * topFrac, wBottom = f.width * 0.8 * bottomFrac
                let r = CGRect(x: f.midX - wBottom / 2, y: f.minY + CGFloat(i) * h, width: wBottom, height: h - 4)
                var e = box(i == 0 ? .triangle : .trapezoid, r, item, i)
                if i > 0 { e.shape?.adjustments = [Double((wBottom - wTop) / 2 / max(min(r.width, r.height), 1))] }
                children.append(e)
            }
        case .venn:
            let d = min(f.height * 0.8, f.width / CGFloat(max(n, 1)) * 1.4)
            let c = CGPoint(x: f.midX, y: f.midY)
            let spread = d * 0.32
            for (i, item) in items.prefix(4).enumerated() {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(min(n, 4))
                let p = n == 1 ? c : CGPoint(x: c.x + CGFloat(cos(a)) * spread, y: c.y + CGFloat(sin(a)) * spread)
                children.append(box(.ellipse, CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d), item, i, alpha: 0.55, textColor: .theme(.dark1)))
            }
        case .timeline:
            let y = f.midY
            var line = SlideElement.line(from: CGPoint(x: f.minX, y: y), to: CGPoint(x: f.maxX, y: y), style: .solid(.theme(.dark1, shade: 0.5, alpha: 1), width: 3))
            line.line?.tail = .triangle
            line.name = "Timeline"
            children.append(line)
            let step = f.width / CGFloat(n)
            for (i, item) in items.enumerated() {
                let x = f.minX + step * (CGFloat(i) + 0.5)
                var dot = SlideElement.shape(.ellipse, frame: CGRect(x: x - 11, y: y - 11, width: 22, height: 22), fill: .solid(color(i)), line: .solid(.theme(.light1), width: 2))
                dot.name = "Milestone \(i + 1)"
                children.append(dot)
                let above = i % 2 == 0
                var label = SlideElement.textBox(item, frame: CGRect(x: x - step / 2, y: above ? y - 70 : y + 22, width: step, height: 44),
                                                 size: 20, alignment: .center, color: .theme(.dark1), bold: true, anchor: above ? .bottom : .top)
                label.text?.autofit = .none
                children.append(label)
            }
        case .matrix:
            let gap: CGFloat = 8
            let s = min(f.width, f.height * 1.6)
            let w = (s - gap) / 2, h = (f.height - gap) / 2
            let x0 = f.midX - s / 2
            for (i, item) in items.prefix(4).enumerated() {
                let r = i / 2, c = i % 2
                children.append(box(.rect, CGRect(x: x0 + CGFloat(c) * (w + gap), y: f.minY + CGFloat(r) * (h + gap), width: w, height: h), item, i))
            }
        }
        let bounds = children.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return SlideElement(name: kind.title, frame: bounds, content: .group(GroupContent(children: children)))
    }
}

private extension SlideElement {
    var line: LineStyle? {
        get { if case .line(let l) = content { return l.line }; return nil }
        set { if let newValue, case .line(var l) = content { l.line = newValue; content = .line(l) } }
    }
}

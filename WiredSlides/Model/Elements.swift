import AppKit

/// Which layout placeholder an element fills.
enum PlaceholderRole: String, Codable, CaseIterable {
    case title, centeredTitle, subtitle, body, picture, date, footer, slideNumber

    var ooxml: String {
        switch self {
        case .title: "title"
        case .centeredTitle: "ctrTitle"
        case .subtitle: "subTitle"
        case .body: "body"
        case .picture: "pic"
        case .date: "dt"
        case .footer: "ftr"
        case .slideNumber: "sldNum"
        }
    }

    static func fromOOXML(_ value: String?) -> PlaceholderRole {
        switch value {
        case "title": .title
        case "ctrTitle": .centeredTitle
        case "subTitle": .subtitle
        case "pic": .picture
        case "dt": .date
        case "ftr": .footer
        case "sldNum": .slideNumber
        default: .body
        }
    }

    var isTitle: Bool { self == .title || self == .centeredTitle }
}

/// What happens when an element is clicked during a slide show.
enum ElementAction: Codable, Hashable {
    case url(String)
    case slide(UUID)
    case nextSlide, previousSlide, firstSlide, lastSlide, endShow

    var title: String {
        switch self {
        case .url(let url): url
        case .slide: "Slide"
        case .nextSlide: "Next Slide"
        case .previousSlide: "Previous Slide"
        case .firstSlide: "First Slide"
        case .lastSlide: "Last Slide"
        case .endShow: "End Show"
        }
    }
}

struct ShapeContent: Codable, Hashable {
    var kind: ShapeKind
    var fill: Fill
    var line: LineStyle
    var effects: Effects = .none
    var text: TextBody = TextBody()
    var adjustments: [Double] = []

    var resolvedAdjustments: [Double] {
        let defaults = kind.defaultAdjustments
        return defaults.indices.map { $0 < adjustments.count ? adjustments[$0] : defaults[$0] }
    }

    func adjustment(_ index: Int) -> Double {
        let values = resolvedAdjustments
        return index < values.count ? values[index] : 0
    }
}

struct ImageContent: Codable, Hashable {
    var mediaID: String
    var crop = CropInsets()
    var line: LineStyle = .none
    var effects: Effects = .none
    var adjustments = ImageAdjustments()
    /// Crop to a shape other than a rectangle.
    var maskShape: ShapeKind?
}

struct LineContent: Codable, Hashable {
    var kind: ConnectorKind = .straight
    var line: LineStyle
    var effects: Effects = .none
    /// Shapes the ends are glued to (connectors follow them when they move).
    var startElement: UUID?
    var endElement: UUID?
}

struct TableCell: Codable, Hashable {
    var text: TextBody
    var fill: Fill?
    var rowSpan = 1
    var columnSpan = 1
    /// Covered by a merged neighbor.
    var isMerged = false
}

struct TableStyleOptions: Codable, Hashable {
    var headerRow = true
    var totalRow = false
    var bandedRows = true
    var firstColumn = false
    var lastColumn = false
    var bandedColumns = false
    var color: PaintColor = .theme(.accent1)
    /// 0 = medium (colored header, tinted bands), 1 = light (lines only), 2 = dark (strong fills).
    var intensity = 0
    var borderColor: PaintColor?
    var borderWidth: Double = 1
}

struct TableContent: Codable, Hashable {
    var rows: [[TableCell]]
    var columnWidths: [Double]
    var rowHeights: [Double]
    var style = TableStyleOptions()

    var rowCount: Int { rows.count }
    var columnCount: Int { columnWidths.count }

    static func make(rows: Int, columns: Int, width: Double, rowHeight: Double = 37) -> TableContent {
        let cell = TableCell(text: TableContent.cellBody(""))
        return TableContent(
            rows: Array(repeating: Array(repeating: cell, count: columns), count: rows),
            columnWidths: Array(repeating: width / Double(columns), count: columns),
            rowHeights: Array(repeating: rowHeight, count: rows)
        )
    }

    static func cellBody(_ text: String) -> TextBody {
        var body = TextBody(text, size: 16)
        body.insets = EdgeInsetsValue(top: 4, left: 7, bottom: 4, right: 7)
        body.anchor = .middle
        return body
    }
}

enum ChartKind: String, Codable, CaseIterable, Identifiable {
    case column, stackedColumn, bar, stackedBar, line, lineMarkers, area, pie, doughnut, scatter
    var id: String { rawValue }

    var title: String {
        switch self {
        case .column: "Clustered Column"
        case .stackedColumn: "Stacked Column"
        case .bar: "Clustered Bar"
        case .stackedBar: "Stacked Bar"
        case .line: "Line"
        case .lineMarkers: "Line with Markers"
        case .area: "Area"
        case .pie: "Pie"
        case .doughnut: "Doughnut"
        case .scatter: "Scatter"
        }
    }

    var symbol: String {
        switch self {
        case .column, .stackedColumn: "chart.bar"
        case .bar, .stackedBar: "chart.bar.xaxis"
        case .line, .lineMarkers: "chart.xyaxis.line"
        case .area: "chart.line.uptrend.xyaxis"
        case .pie: "chart.pie"
        case .doughnut: "circle.circle"
        case .scatter: "chart.dots.scatter"
        }
    }

    var isRound: Bool { self == .pie || self == .doughnut }
}

enum LegendPosition: String, Codable, CaseIterable { case none, bottom, right, top, left }

struct ChartSeries: Codable, Hashable {
    var name: String
    var values: [Double]
    var color: PaintColor?
}

struct ChartContent: Codable, Hashable {
    var kind: ChartKind
    var title: String?
    var categories: [String]
    var series: [ChartSeries]
    var legend: LegendPosition = .bottom
    var showDataLabels = false
    var showGridlines = true
    var fontSize: Double = 12
    var textColor: PaintColor = .theme(.dark1, shade: 0.25, alpha: 1)
    var background: Fill = .none

    static func sample(_ kind: ChartKind) -> ChartContent {
        ChartContent(
            kind: kind,
            title: "Chart Title",
            categories: ["Category 1", "Category 2", "Category 3", "Category 4"],
            series: kind.isRound
                ? [ChartSeries(name: "Sales", values: [8.2, 3.2, 1.4, 1.2])]
                : [ChartSeries(name: "Series 1", values: [4.3, 2.5, 3.5, 4.5]),
                   ChartSeries(name: "Series 2", values: [2.4, 4.4, 1.8, 2.8]),
                   ChartSeries(name: "Series 3", values: [2, 2, 3, 5])]
        )
    }
}

struct IconContent: Codable, Hashable {
    var symbol: String
    var color: PaintColor = .theme(.accent1)
}

struct MediaContent: Codable, Hashable {
    enum Kind: String, Codable { case video, audio }
    var kind: Kind
    var mediaID: String
    var posterID: String?
    var autoplay = false
    var loop = false
    var volume: Double = 1
    var hideWhenNotPlaying = false
}

struct GroupContent: Codable, Hashable {
    var children: [SlideElement]
}

indirect enum ElementContent: Codable, Hashable {
    case shape(ShapeContent)
    case image(ImageContent)
    case line(LineContent)
    case table(TableContent)
    case chart(ChartContent)
    case icon(IconContent)
    case media(MediaContent)
    case group(GroupContent)
}

/// Anything placed on a slide.
struct SlideElement: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var frame: CGRect
    /// Degrees clockwise.
    var rotation: Double = 0
    var flipH = false
    var flipV = false
    var locked = false
    var hidden = false
    var lockAspectRatio = false
    var placeholder: PlaceholderRole?
    var action: ElementAction?
    var altText = ""
    var content: ElementContent

    init(id: UUID = UUID(), name: String, frame: CGRect, content: ElementContent, placeholder: PlaceholderRole? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.content = content
        self.placeholder = placeholder
    }

    // MARK: Convenience accessors

    var shape: ShapeContent? {
        get { if case .shape(let s) = content { return s }; return nil }
        set { if let newValue { content = .shape(newValue) } }
    }

    var isLine: Bool { if case .line = content { return true }; return false }
    var isGroup: Bool { if case .group = content { return true }; return false }
    var isTable: Bool { if case .table = content { return true }; return false }
    var isImage: Bool { if case .image = content { return true }; return false }
    var isChart: Bool { if case .chart = content { return true }; return false }

    /// The editable text of shapes (tables manage their own cells).
    var text: TextBody? {
        get { shape?.text }
        set {
            guard let newValue, var s = shape else { return }
            s.text = newValue
            content = .shape(s)
        }
    }

    var hasText: Bool { if let t = text { return !t.isEmpty }; return false }

    var kindName: String {
        switch content {
        case .shape(let s):
            if placeholder != nil { return placeholder!.isTitle ? "Title" : "Placeholder" }
            return s.fill.isNone && !s.line.isVisible ? "Text Box" : s.kind.title
        case .image: return "Picture"
        case .line: return "Line"
        case .table: return "Table"
        case .chart: return "Chart"
        case .icon: return "Icon"
        case .media(let m): return m.kind == .video ? "Video" : "Audio"
        case .group: return "Group"
        }
    }

    var symbol: String {
        switch content {
        case .shape(let s): return s.fill.isNone && !s.line.isVisible ? "character.textbox" : "square.on.circle"
        case .image: return "photo"
        case .line: return "line.diagonal"
        case .table: return "tablecells"
        case .chart: return "chart.bar"
        case .icon(let i): return i.symbol
        case .media(let m): return m.kind == .video ? "film" : "speaker.wave.2"
        case .group: return "square.on.square.dashed"
        }
    }

    /// Every media item this element (and its children) references.
    var mediaIDs: [String] {
        switch content {
        case .shape(let s): return s.fill.mediaIDs
        case .image(let i): return [i.mediaID]
        case .media(let m): return [m.mediaID] + (m.posterID.map { [$0] } ?? [])
        case .group(let g): return g.children.flatMap(\.mediaIDs)
        case .table(let t): return t.rows.flatMap { $0.flatMap { $0.fill?.mediaIDs ?? [] } }
        default: return []
        }
    }

    /// Searchable text.
    var allText: [String] {
        switch content {
        case .shape(let s): return [s.text.plainText]
        case .table(let t): return t.rows.flatMap { $0.map(\.text.plainText) }
        case .group(let g): return g.children.flatMap(\.allText)
        case .chart(let c): return [c.title ?? ""]
        default: return []
        }
    }

    /// Moves the element (and group children) by an offset.
    mutating func offset(by d: CGSize) {
        frame = frame.offsetBy(dx: d.width, dy: d.height)
        if case .group(var g) = content {
            for i in g.children.indices { g.children[i].offset(by: d) }
            content = .group(g)
        }
    }

    /// Resizes to a new frame, scaling group children and table geometry along.
    mutating func setFrame(_ newFrame: CGRect) {
        let old = frame
        frame = newFrame
        switch content {
        case .group(var g):
            let sx = old.width > 0 ? newFrame.width / old.width : 1
            let sy = old.height > 0 ? newFrame.height / old.height : 1
            for i in g.children.indices {
                let c = g.children[i].frame
                g.children[i].setFrame(CGRect(
                    x: newFrame.minX + (c.minX - old.minX) * sx,
                    y: newFrame.minY + (c.minY - old.minY) * sy,
                    width: c.width * sx, height: c.height * sy))
            }
            content = .group(g)
        case .table(var t):
            let total = t.columnWidths.reduce(0, +)
            if total > 0 { t.columnWidths = t.columnWidths.map { $0 * newFrame.width / total } }
            let totalH = t.rowHeights.reduce(0, +)
            if totalH > 0, abs(newFrame.height - old.height) > 0.5 {
                t.rowHeights = t.rowHeights.map { $0 * newFrame.height / totalH }
            }
            content = .table(t)
        default:
            break
        }
    }

    /// A copy with fresh identifiers (children included).
    func duplicated() -> SlideElement {
        var copy = self
        copy.id = UUID()
        if case .group(var g) = copy.content {
            g.children = g.children.map { $0.duplicated() }
            copy.content = .group(g)
        }
        return copy
    }

    /// Finds an element by id among this element and its descendants.
    func find(_ id: UUID) -> SlideElement? {
        if self.id == id { return self }
        if case .group(let g) = content {
            for child in g.children { if let found = child.find(id) { return found } }
        }
        return nil
    }
}

extension SlideElement {
    static func textBox(_ text: String, frame: CGRect, size: Double = 18, role: FontRole = .body, alignment: TextAlignment = .left,
                        color: PaintColor = .theme(.dark1), bold: Bool? = nil, anchor: VerticalAnchor = .top) -> SlideElement {
        var body = TextBody(text, size: size, role: role, alignment: alignment, anchor: anchor, color: color, bold: bold)
        body.autofit = .resizeShape
        return SlideElement(name: "TextBox", frame: frame,
                            content: .shape(ShapeContent(kind: .rect, fill: .none, line: .none, text: body)))
    }

    static func shape(_ kind: ShapeKind, frame: CGRect, fill: Fill = .solid(.theme(.accent1)),
                      line: LineStyle = .solid(.theme(.accent1, shade: -0.25, alpha: 1), width: 1), text: String = "") -> SlideElement {
        var body = TextBody(text, size: 18, alignment: .center, anchor: .middle, color: .theme(.light1))
        body.insets = EdgeInsetsValue(top: 3.6, left: 7.2, bottom: 3.6, right: 7.2)
        return SlideElement(name: kind.title, frame: frame,
                            content: .shape(ShapeContent(kind: kind, fill: fill, line: line, text: body)))
    }

    static func line(from a: CGPoint, to b: CGPoint, style: LineStyle, kind: ConnectorKind = .straight) -> SlideElement {
        var element = SlideElement(name: kind == .straight ? "Straight Connector" : "Connector",
                                   frame: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)),
                                   content: .line(LineContent(kind: kind, line: style)))
        element.flipH = b.x < a.x
        element.flipV = b.y < a.y
        return element
    }

    /// Endpoints of a line element in slide coordinates (flips choose the corners).
    var lineEndpoints: (start: CGPoint, end: CGPoint) {
        let f = frame
        let sx = flipH ? f.maxX : f.minX, ex = flipH ? f.minX : f.maxX
        let sy = flipV ? f.maxY : f.minY, ey = flipV ? f.minY : f.maxY
        return (CGPoint(x: sx, y: sy), CGPoint(x: ex, y: ey))
    }

    mutating func setLineEndpoints(_ a: CGPoint, _ b: CGPoint) {
        frame = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        flipH = b.x < a.x
        flipV = b.y < a.y
    }
}

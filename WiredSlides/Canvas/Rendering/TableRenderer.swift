import AppKit

/// Column and row positions of a table placed in a frame.
struct TableGeometry {
    let xs: [CGFloat]   // left edge of each column, plus the right edge
    let ys: [CGFloat]   // top edge of each row, plus the bottom edge

    init(_ table: TableContent, in frame: CGRect) {
        var x = frame.minX
        var xs = [x]
        let totalW = max(table.columnWidths.reduce(0, +), 1)
        for w in table.columnWidths { x += CGFloat(w) / totalW * frame.width; xs.append(x) }
        var y = frame.minY
        var ys = [y]
        for h in table.rowHeights { y += CGFloat(h); ys.append(y) }
        self.xs = xs
        self.ys = ys
    }

    func rect(row: Int, column: Int, rowSpan: Int = 1, columnSpan: Int = 1) -> CGRect {
        let r2 = min(row + rowSpan, ys.count - 1), c2 = min(column + columnSpan, xs.count - 1)
        return CGRect(x: xs[column], y: ys[row], width: xs[c2] - xs[column], height: ys[r2] - ys[row])
    }

    func cell(at point: CGPoint) -> (row: Int, column: Int)? {
        guard let column = (0..<(xs.count - 1)).first(where: { point.x >= xs[$0] && point.x < xs[$0 + 1] }),
              let row = (0..<(ys.count - 1)).first(where: { point.y >= ys[$0] && point.y < ys[$0 + 1] }) else { return nil }
        return (row, column)
    }
}

enum TableRenderer {
    enum Band { case header, total, odd, even }

    /// The style a cell gets from the table's style options.
    static func cellAppearance(_ table: TableContent, row: Int, column: Int, colors: ThemeColors)
        -> (fill: RGBColor?, text: PaintColor?, bold: Bool) {
        let s = table.style
        let base = s.color.resolve(colors)
        let isHeader = s.headerRow && row == 0
        let isTotal = s.totalRow && row == table.rowCount - 1
        let isFirstColumn = s.firstColumn && column == 0
        let isLastColumn = s.lastColumn && column == table.columnCount - 1
        let bodyRow = row - (s.headerRow ? 1 : 0)
        let banded = s.bandedRows && bodyRow % 2 == 0
        let bandedColumn = s.bandedColumns && column % 2 == 0
        switch s.intensity {
        case 1:
            if isHeader { return (nil, .rgb(base.shaded(-0.25)), true) }
            if isTotal { return (nil, nil, true) }
            return ((banded || bandedColumn) ? base.shaded(0.85) : nil, nil, isFirstColumn || isLastColumn)
        case 2:
            if isHeader || isTotal { return (colors.dark1.isDark ? colors.dark1 : colors.light1, .theme(.light1), true) }
            if isFirstColumn || isLastColumn { return (base.shaded(-0.3), .theme(.light1), true) }
            return ((banded || bandedColumn) ? base.shaded(-0.15) : base, .theme(.light1), false)
        default:
            if isHeader { return (base, .theme(.light1), true) }
            if isTotal { return (base.shaded(0.6), nil, true) }
            if isFirstColumn || isLastColumn { return (base.shaded(0.6), nil, true) }
            return ((banded || bandedColumn) ? base.shaded(0.75) : base.shaded(0.88), nil, false)
        }
    }

    static func draw(_ table: TableContent, in frame: CGRect, elementID: UUID, ctx: CGContext, env: RenderEnvironment, options: ElementDrawOptions) {
        let geo = TableGeometry(table, in: frame)
        let colors = env.colors
        let base = table.style.color.resolve(colors)
        for row in 0..<table.rowCount {
            for column in 0..<table.columnCount {
                let cell = table.rows[row][column]
                guard !cell.isMerged else { continue }
                let rect = geo.rect(row: row, column: column, rowSpan: cell.rowSpan, columnSpan: cell.columnSpan)
                let look = cellAppearance(table, row: row, column: column, colors: colors)
                if let fill = cell.fill {
                    Paint.fill(CGPath(rect: rect, transform: nil), with: fill, bounds: rect, in: ctx, env: env)
                } else if let color = look.fill {
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                }
                if let editing = options.editingCell, options.editingTextElement == elementID, editing.row == row, editing.column == column { continue }
                var body = cell.text
                guard !body.isEmpty else { continue }
                if let text = look.text { body.defaultColor = text }
                if look.bold { body.updateRuns { if $0.bold == nil { $0.bold = true } } }
                ElementRenderer.withNSContext(ctx) {
                    TextLayout.draw(body, in: rect, theme: env.theme)
                }
            }
        }
        // Borders.
        ctx.saveGState()
        let width = CGFloat(table.style.borderWidth)
        if let border = table.style.borderColor {
            ctx.setStrokeColor(border.resolve(colors).cgColor)
            ctx.setLineWidth(width)
            for row in 0..<table.rowCount {
                for column in 0..<table.columnCount {
                    let cell = table.rows[row][column]
                    guard !cell.isMerged else { continue }
                    ctx.stroke(geo.rect(row: row, column: column, rowSpan: cell.rowSpan, columnSpan: cell.columnSpan))
                }
            }
        } else {
            switch table.style.intensity {
            case 1:
                ctx.setStrokeColor(base.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeLineSegments(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                                                 CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)])
                if table.style.headerRow, geo.ys.count > 1 {
                    ctx.setLineWidth(1)
                    ctx.strokeLineSegments(between: [CGPoint(x: frame.minX, y: geo.ys[1]), CGPoint(x: frame.maxX, y: geo.ys[1])])
                }
            default:
                ctx.setStrokeColor(table.style.intensity == 2 ? colors.light1.withAlpha(0.35).cgColor : RGBColor.white.cgColor)
                ctx.setLineWidth(1)
                var segments: [CGPoint] = []
                for y in geo.ys.dropFirst().dropLast() { segments += [CGPoint(x: frame.minX, y: y), CGPoint(x: frame.maxX, y: y)] }
                for x in geo.xs.dropFirst().dropLast() { segments += [CGPoint(x: x, y: frame.minY), CGPoint(x: x, y: frame.maxY)] }
                ctx.strokeLineSegments(between: segments)
                if table.style.totalRow, geo.ys.count > 2 {
                    ctx.setStrokeColor(base.cgColor)
                    ctx.setLineWidth(2)
                    let y = geo.ys[geo.ys.count - 2]
                    ctx.strokeLineSegments(between: [CGPoint(x: frame.minX, y: y), CGPoint(x: frame.maxX, y: y)])
                }
            }
        }
        ctx.restoreGState()
    }

    /// Row heights after growing rows whose text no longer fits.
    static func fittedRowHeights(_ table: TableContent, width: CGFloat, theme: PresentationTheme) -> [Double] {
        var heights = table.rowHeights
        let totalW = max(table.columnWidths.reduce(0, +), 1)
        for row in 0..<table.rowCount {
            var needed: Double = 0
            for column in 0..<table.columnCount {
                let cell = table.rows[row][column]
                guard !cell.isMerged, cell.rowSpan == 1 else { continue }
                let span = (column..<min(column + cell.columnSpan, table.columnCount)).reduce(0.0) { $0 + table.columnWidths[$1] }
                let cellWidth = CGFloat(span) / CGFloat(totalW) * width
                needed = max(needed, Double(TextLayout.requiredHeight(cell.text, width: cellWidth, theme: theme)))
            }
            heights[row] = max(heights[row], needed)
        }
        return heights
    }
}

import AppKit

extension PresentationController {
    // MARK: - Tables

    var selectedTable: (id: UUID, table: TableContent)? {
        guard let e = primaryElement, case .table(let t) = e.content else { return nil }
        return (e.id, t)
    }

    /// The cell range table commands act on.
    var activeCellRange: TableCellRange? {
        if let range = cellSelection { return range }
        if let cell = editingCell { return TableCellRange(start: cell, end: cell) }
        return nil
    }

    func changeTable(_ name: String, _ body: @escaping (inout TableContent, inout CGRect) -> Void) {
        guard let (id, _) = selectedTable else { return }
        commitTextEditing()
        let theme = self.theme
        changeElements([id], name) { e in
            guard case .table(var t) = e.content else { return }
            var frame = e.frame
            body(&t, &frame)
            t.rowHeights = TableRenderer.fittedRowHeights(t, width: frame.width, theme: theme)
            frame.size.height = CGFloat(t.rowHeights.reduce(0, +))
            e.frame = frame
            e.content = .table(t)
        }
    }

    func insertTableRow(below: Bool) {
        let row = below ? (activeCellRange?.rows.upperBound ?? (selectedTable?.table.rowCount ?? 1) - 1) + 1 : (activeCellRange?.rows.lowerBound ?? 0)
        changeTable(below ? "Insert Row Below" : "Insert Row Above") { t, _ in
            let template = t.rows[min(max(row - (below ? 1 : 0), 0), t.rowCount - 1)]
            let newRow = template.map { cell -> TableCell in
                var c = TableCell(text: cell.text)
                c.text.setPlainText("")
                c.fill = cell.fill
                return c
            }
            t.rows.insert(newRow, at: min(row, t.rowCount))
            t.rowHeights.insert(t.rowHeights[min(max(row - 1, 0), t.rowHeights.count - 1)], at: min(row, t.rowHeights.count))
        }
        cellSelection = nil
    }

    func insertTableColumn(right: Bool) {
        let column = right ? (activeCellRange?.columns.upperBound ?? (selectedTable?.table.columnCount ?? 1) - 1) + 1 : (activeCellRange?.columns.lowerBound ?? 0)
        changeTable(right ? "Insert Column Right" : "Insert Column Left") { t, frame in
            let width = t.columnWidths[min(max(column - (right ? 1 : 0), 0), t.columnCount - 1)]
            for r in t.rows.indices {
                var c = TableCell(text: t.rows[r][min(max(column - (right ? 1 : 0), 0), t.columnCount - 1)].text)
                c.text.setPlainText("")
                t.rows[r].insert(c, at: min(column, t.rows[r].count))
            }
            t.columnWidths.insert(width, at: min(column, t.columnWidths.count))
            // Keep the table on the slide: widen, then scale if needed.
            frame.size.width += CGFloat(width)
            let maxWidth = self.slideSize.width - frame.minX - 10
            if frame.width > maxWidth { frame.size.width = max(maxWidth, 100) }
        }
        cellSelection = nil
    }

    func deleteTableRows() {
        guard let range = activeCellRange, let table = selectedTable?.table else { deleteSelection(); return }
        if range.rows.count >= table.rowCount { deleteSelection(); return }
        changeTable("Delete Rows") { t, _ in
            t.rows.removeSubrange(range.rows)
            t.rowHeights.removeSubrange(range.rows)
            Self.normalizeMerges(&t)
        }
        cellSelection = nil
        editingCell = nil
    }

    func deleteTableColumns() {
        guard let range = activeCellRange, let table = selectedTable?.table else { deleteSelection(); return }
        if range.columns.count >= table.columnCount { deleteSelection(); return }
        changeTable("Delete Columns") { t, frame in
            let removed = range.columns.reduce(0.0) { $0 + t.columnWidths[$1] }
            let total = t.columnWidths.reduce(0, +)
            for r in t.rows.indices { t.rows[r].removeSubrange(range.columns) }
            t.columnWidths.removeSubrange(range.columns)
            frame.size.width *= CGFloat((total - removed) / max(total, 1))
            Self.normalizeMerges(&t)
        }
        cellSelection = nil
        editingCell = nil
    }

    func mergeCells() {
        guard let range = activeCellRange, !range.isSingle else { return }
        changeTable("Merge Cells") { t, _ in
            let top = range.rows.lowerBound, left = range.columns.lowerBound
            var texts: [Paragraph] = []
            for r in range.rows {
                for c in range.columns {
                    let cell = t.rows[r][c]
                    if !cell.text.isEmpty { texts += cell.text.paragraphs }
                    t.rows[r][c].isMerged = !(r == top && c == left)
                    t.rows[r][c].rowSpan = 1
                    t.rows[r][c].columnSpan = 1
                    if r != top || c != left { t.rows[r][c].text.setPlainText("") }
                }
            }
            t.rows[top][left].rowSpan = range.rows.count
            t.rows[top][left].columnSpan = range.columns.count
            if !texts.isEmpty { t.rows[top][left].text.paragraphs = texts }
        }
        cellSelection = TableCellRange(start: range.start, end: range.start)
    }

    func splitCells() {
        guard let range = activeCellRange else { return }
        changeTable("Split Cells") { t, _ in
            for r in range.rows {
                for c in range.columns where !t.rows[r][c].isMerged {
                    let cell = t.rows[r][c]
                    for rr in r..<min(r + cell.rowSpan, t.rowCount) {
                        for cc in c..<min(c + cell.columnSpan, t.columnCount) { t.rows[rr][cc].isMerged = false }
                    }
                    t.rows[r][c].rowSpan = 1
                    t.rows[r][c].columnSpan = 1
                }
            }
        }
    }

    /// Clears merges that no longer fit after rows or columns were deleted.
    static func normalizeMerges(_ t: inout TableContent) {
        for r in t.rows.indices {
            for c in t.rows[r].indices {
                t.rows[r][c].rowSpan = min(t.rows[r][c].rowSpan, t.rowCount - r)
                t.rows[r][c].columnSpan = min(t.rows[r][c].columnSpan, t.columnCount - c)
            }
        }
        var covered = Set<TableCellAddress>()
        for r in t.rows.indices {
            for c in t.rows[r].indices where !t.rows[r][c].isMerged {
                let cell = t.rows[r][c]
                for rr in r..<(r + cell.rowSpan) { for cc in c..<(c + cell.columnSpan) where rr != r || cc != c { covered.insert(TableCellAddress(row: rr, column: cc)) } }
            }
        }
        for r in t.rows.indices { for c in t.rows[r].indices { t.rows[r][c].isMerged = covered.contains(TableCellAddress(row: r, column: c)) } }
    }

    func setTableStyle(_ change: @escaping (inout TableStyleOptions) -> Void) {
        changeTable("Table Style") { t, _ in change(&t.style) }
    }

    func setCellFill(_ fill: Fill?) {
        let range = activeCellRange
        changeTable("Cell Shading") { t, _ in
            for r in t.rows.indices {
                for c in t.rows[r].indices where range == nil || (range!.rows.contains(r) && range!.columns.contains(c)) {
                    t.rows[r][c].fill = fill
                }
            }
        }
    }

    func distributeTable(rows: Bool) {
        changeTable(rows ? "Distribute Rows" : "Distribute Columns") { t, _ in
            if rows {
                let avg = t.rowHeights.reduce(0, +) / Double(max(t.rowCount, 1))
                t.rowHeights = Array(repeating: avg, count: t.rowCount)
            } else {
                let avg = t.columnWidths.reduce(0, +) / Double(max(t.columnCount, 1))
                t.columnWidths = Array(repeating: avg, count: t.columnCount)
            }
        }
    }

    // MARK: - Charts

    func setChart(_ id: UUID, _ change: @escaping (inout ChartContent) -> Void) {
        changeElements([id], "Edit Chart") { e in
            if case .chart(var c) = e.content { change(&c); e.content = .chart(c) }
        }
    }

    func setSelectedChart(_ change: @escaping (inout ChartContent) -> Void) {
        guard let e = primaryElement, e.isChart else { return }
        setChart(e.id, change)
    }

    // MARK: - Animations

    var currentAnimations: [SlideAnimation] { currentSlide.validAnimations }

    func addAnimation(_ effect: AnimationEffect, replacing: Bool) {
        let ids = selection
        guard !ids.isEmpty else { NSSound.beep(); return }
        changeSlide(replacing ? "Animation" : "Add Animation") { slide in
            if replacing { slide.animations.removeAll { ids.contains($0.elementID) } }
            for (i, id) in ids.enumerated() {
                var animation = SlideAnimation(elementID: id, effect: effect, trigger: i == 0 ? .onClick : .withPrevious)
                if effect.category == .entrance || effect.category == .exit { animation.direction = effect == .flyIn ? .fromBottom : .fromBottom }
                slide.animations.append(animation)
            }
        }
        selectedAnimation = currentSlide.animations.last?.id
    }

    func removeAnimations(for ids: [UUID]) {
        changeSlide("Remove Animation") { slide in slide.animations.removeAll { ids.contains($0.elementID) } }
    }

    func removeAnimation(_ id: UUID) {
        changeSlide("Remove Animation") { slide in slide.animations.removeAll { $0.id == id } }
    }

    func updateAnimation(_ id: UUID, _ change: @escaping (inout SlideAnimation) -> Void) {
        changeSlide("Animation Timing") { slide in
            if let i = slide.animations.firstIndex(where: { $0.id == id }) { change(&slide.animations[i]) }
        }
    }

    /// Updates the animations of the selected elements (or the selected animation).
    func updateSelectedAnimations(_ change: @escaping (inout SlideAnimation) -> Void) {
        let ids = Set(selection)
        let selected = selectedAnimation
        changeSlide("Animation Timing") { slide in
            for i in slide.animations.indices where slide.animations[i].id == selected || (selected == nil && ids.contains(slide.animations[i].elementID)) {
                change(&slide.animations[i])
            }
        }
    }

    func moveAnimation(_ id: UUID, by offset: Int) {
        changeSlide("Reorder Animation") { slide in
            guard let i = slide.animations.firstIndex(where: { $0.id == id }) else { return }
            let j = max(0, min(slide.animations.count - 1, i + offset))
            let a = slide.animations.remove(at: i)
            slide.animations.insert(a, at: j)
        }
    }

    /// The animations that apply to what's selected.
    var selectionAnimations: [SlideAnimation] {
        if let id = selectedAnimation, let a = currentSlide.animations.first(where: { $0.id == id }) { return [a] }
        let ids = Set(selection)
        return currentSlide.animations.filter { ids.contains($0.elementID) }
    }

    // MARK: - Find and replace

    struct FindOptions: Equatable {
        var text = ""
        var replacement = ""
        var matchCase = false
        var wholeWords = false
    }

    private func matches(_ haystack: String, _ options: FindOptions) -> [Range<String.Index>] {
        guard !options.text.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var start = haystack.startIndex
        let compareOptions: String.CompareOptions = options.matchCase ? [] : [.caseInsensitive]
        while start < haystack.endIndex, let r = haystack.range(of: options.text, options: compareOptions, range: start..<haystack.endIndex) {
            var ok = true
            if options.wholeWords {
                let before = r.lowerBound > haystack.startIndex ? haystack[haystack.index(before: r.lowerBound)] : " "
                let after = r.upperBound < haystack.endIndex ? haystack[r.upperBound] : " "
                ok = !before.isLetter && !before.isNumber && !after.isLetter && !after.isNumber
            }
            if ok { result.append(r) }
            start = r.upperBound
        }
        return result
    }

    /// Selects the next element containing the text. Returns false if none.
    @discardableResult
    func findNext(_ options: FindOptions, backwards: Bool = false) -> Bool {
        commitTextEditing()
        let n = slides.count
        // Search order: the rest of the current slide, then other slides.
        let currentElements = currentSlide.elements
        let startIndex = selection.last.flatMap { id in currentElements.firstIndex { $0.id == id } } ?? -1
        for step in 0...n {
            let slideIndex = ((currentSlideIndex + (backwards ? -step : step)) % n + n) % n
            let elements = presentation.slides[slideIndex].elements
            var order = Array(elements.indices)
            if backwards { order.reverse() }
            for i in order {
                if step == 0 && (backwards ? i >= startIndex : i <= startIndex) && startIndex >= 0 { continue }
                if elements[i].allText.contains(where: { !matches($0, options).isEmpty }) {
                    setCurrentSlide(slideIndex)
                    select([elements[i].id])
                    return true
                }
            }
            if step == n { break }
        }
        return false
    }

    @discardableResult
    func replaceAll(_ options: FindOptions) -> Int {
        guard !options.text.isEmpty else { return 0 }
        var count = 0
        change("Replace All") { p in
            for s in p.slides.indices {
                for e in p.slides[s].elements.indices {
                    Self.replaceText(in: &p.slides[s].elements[e]) { text in
                        let ranges = matches(text, options)
                        guard !ranges.isEmpty else { return text }
                        count += ranges.count
                        var result = text
                        for r in ranges.reversed() { result.replaceSubrange(r, with: options.replacement) }
                        return result
                    }
                }
            }
        }
        return count
    }

    /// Replaces in the selected element only, then finds the next match.
    func replaceCurrent(_ options: FindOptions) {
        guard let id = selection.first, let e = currentSlide.element(id), e.allText.contains(where: { !matches($0, options).isEmpty }) else {
            findNext(options)
            return
        }
        var replaced = false
        changeElements([id], "Replace") { element in
            Self.replaceText(in: &element) { text in
                guard !replaced, let r = self.matches(text, options).first else { return text }
                replaced = true
                var result = text
                result.replaceSubrange(r, with: options.replacement)
                return result
            }
        }
        findNext(options)
    }

    /// Applies a transform to every run of text in an element (paragraph by paragraph, so matches can span runs).
    static func replaceText(in e: inout SlideElement, _ transform: (String) -> String) {
        func apply(_ body: inout TextBody) {
            for p in body.paragraphs.indices {
                let original = body.paragraphs[p].text
                let updated = transform(original)
                guard updated != original else { continue }
                if body.paragraphs[p].runs.count == 1 {
                    body.paragraphs[p].runs[0].text = updated
                } else {
                    // Keep the first run's formatting for the replaced paragraph.
                    let style = body.paragraphs[p].runs.first?.style ?? .plain
                    body.paragraphs[p].runs = [TextRun(text: updated, style: style)]
                }
            }
        }
        switch e.content {
        case .shape(var s): apply(&s.text); e.content = .shape(s)
        case .table(var t):
            for r in t.rows.indices { for c in t.rows[r].indices { apply(&t.rows[r][c].text) } }
            e.content = .table(t)
        case .group(var g):
            for i in g.children.indices { replaceText(in: &g.children[i], transform) }
            e.content = .group(g)
        default: break
        }
    }

    /// Replaces one font with another everywhere (Replace Fonts).
    func replaceFont(_ old: String, with new: String) {
        change("Replace Fonts") { p in
            if p.theme.headingFont == old { p.theme.headingFont = new }
            if p.theme.bodyFont == old { p.theme.bodyFont = new }
            for s in p.slides.indices {
                for e in p.slides[s].elements.indices {
                    Self.updateAllRuns(in: &p.slides[s].elements[e]) { if $0.fontFamily == old { $0.fontFamily = new } }
                }
            }
        }
    }

    static func updateAllRuns(in e: inout SlideElement, _ change: (inout RunStyle) -> Void) {
        switch e.content {
        case .shape(var s): s.text.updateRuns(change); e.content = .shape(s)
        case .table(var t):
            for r in t.rows.indices { for c in t.rows[r].indices { t.rows[r][c].text.updateRuns(change) } }
            e.content = .table(t)
        case .group(var g):
            for i in g.children.indices { updateAllRuns(in: &g.children[i], change) }
            e.content = .group(g)
        default: break
        }
    }

    /// Every font family used, for Replace Fonts.
    var usedFonts: [String] {
        var fonts: Set<String> = [theme.headingFont, theme.bodyFont]
        func collect(_ e: SlideElement) {
            switch e.content {
            case .shape(let s): for p in s.text.paragraphs { for r in p.runs { if let f = r.style.fontFamily { fonts.insert(f) } } }
            case .table(let t): for row in t.rows { for c in row { for p in c.text.paragraphs { for r in p.runs { if let f = r.style.fontFamily { fonts.insert(f) } } } } }
            case .group(let g): g.children.forEach(collect)
            default: break
            }
        }
        presentation.slides.forEach { $0.elements.forEach(collect) }
        return fonts.sorted()
    }
}

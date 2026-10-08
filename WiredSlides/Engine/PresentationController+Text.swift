import AppKit

enum TextCase: String, CaseIterable {
    case sentence, lower, upper, capitalize, toggle

    var title: String {
        switch self {
        case .sentence: "Sentence case."
        case .lower: "lowercase"
        case .upper: "UPPERCASE"
        case .capitalize: "Capitalize Each Word"
        case .toggle: "tOGGLE cASE"
        }
    }

    func apply(_ s: String) -> String {
        switch self {
        case .sentence:
            var result = "", capitalizeNext = true
            for ch in s.lowercased() {
                if capitalizeNext, ch.isLetter { result += ch.uppercased(); capitalizeNext = false } else { result.append(ch) }
                if ".!?\n".contains(ch) { capitalizeNext = true }
            }
            return result
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .capitalize: return s.capitalized
        case .toggle: return String(s.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) })
        }
    }
}

extension PresentationController {
    // MARK: - Current formatting (for the ribbon)

    var currentRunStyle: RunStyle {
        if let editor = textEditor { return editor.currentRunStyle }
        if let cell = selectedTableCells.first { return cell.text.firstRunStyle }
        return primaryElement?.text?.firstRunStyle ?? RunStyle()
    }

    var currentParagraphStyle: ParagraphStyle {
        if let editor = textEditor { return editor.currentParagraphStyle }
        if let cell = selectedTableCells.first { return cell.text.firstParagraphStyle }
        return primaryElement?.text?.firstParagraphStyle ?? ParagraphStyle()
    }

    /// The text body of the primary target (for box-level settings).
    var currentTextBody: TextBody? {
        if let cell = selectedTableCells.first { return cell.text }
        return primaryElement?.text
    }

    /// Resolved font family shown in the ribbon.
    var currentFontFamily: String {
        let run = currentRunStyle
        if let family = run.fontFamily { return family }
        let role = currentTextBody?.fontRole ?? .body
        return theme.font(for: role)
    }

    var currentFontSize: Double {
        currentRunStyle.size ?? currentTextBody?.defaultSize ?? 18
    }

    var hasTextTarget: Bool {
        textEditor != nil || targetElements.contains { $0.text != nil || $0.isTable || $0.isGroup }
    }

    /// Cells of the selected table that formatting applies to (the cell selection, or every cell).
    var selectedTableCells: [TableCell] {
        guard textEditor == nil, let e = primaryElement, case .table(let t) = e.content else { return [] }
        if let range = cellSelection {
            return range.rows.flatMap { r in range.columns.compactMap { c in t.rows.indices.contains(r) && t.rows[r].indices.contains(c) ? t.rows[r][c] : nil } }
        }
        return t.rows.flatMap { $0 }
    }

    // MARK: - Applying text formatting

    /// Changes every text body the command targets (shapes, group members, table cells).
    func changeTextBodies(_ name: String, _ body: @escaping (inout TextBody) -> Void) {
        let theme = self.theme
        let range = cellSelection
        changeTargets(name) { e in
            Self.changeText(&e, range: range, theme: theme, body)
        }
    }

    private static func changeText(_ e: inout SlideElement, range: TableCellRange?, theme: PresentationTheme, _ body: (inout TextBody) -> Void) {
        switch e.content {
        case .shape(var s):
            body(&s.text)
            e.content = .shape(s)
            fitHeight(&e, theme: theme)
        case .table(var t):
            for r in t.rows.indices {
                for c in t.rows[r].indices where range == nil || (range!.rows.contains(r) && range!.columns.contains(c)) {
                    body(&t.rows[r][c].text)
                }
            }
            t.rowHeights = TableRenderer.fittedRowHeights(t, width: e.frame.width, theme: theme)
            e.content = .table(t)
            e.frame.size.height = CGFloat(t.rowHeights.reduce(0, +))
        case .group(var g):
            for i in g.children.indices { changeText(&g.children[i], range: nil, theme: theme, body) }
            e.content = .group(g)
        case .chart(var c):
            var probe = TextBody()
            probe.defaultSize = c.fontSize
            body(&probe)
            c.fontSize = probe.paragraphs.first?.runs.first?.style.size ?? probe.defaultSize
            e.content = .chart(c)
        default:
            break
        }
    }

    func applyRunStyle(_ name: String, _ change: @escaping (inout RunStyle) -> Void) {
        if let editor = textEditor {
            editor.applyRunStyle(change)
            textSelectionRevision += 1
            return
        }
        changeTextBodies(name) { $0.updateRuns(change) }
    }

    func applyParagraphStyle(_ name: String, _ change: @escaping (inout ParagraphStyle) -> Void) {
        if let editor = textEditor {
            editor.applyParagraphStyle(change)
            textSelectionRevision += 1
            return
        }
        changeTextBodies(name) { $0.updateParagraphs(change) }
    }

    func setFontFamily(_ family: String) {
        let themeFamily = FontResolver.font(family: theme.headingFont, size: 12, bold: false, italic: false).familyName
        let bodyFamily = FontResolver.font(family: theme.bodyFont, size: 12, bold: false, italic: false).familyName
        applyRunStyle("Font") { r in
            r.fontFamily = (family == themeFamily || family == bodyFamily) && r.fontFamily == nil ? nil : family
            if family == "+Headings" || family == "+Body" { r.fontFamily = nil }
        }
    }

    func setFontSize(_ size: Double) {
        applyRunStyle("Font Size") { $0.size = max(1, min(size, 999)) }
    }

    func growFont(_ larger: Bool) {
        let steps = [8.0, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96]
        let current = currentFontSize
        let next = larger ? (steps.first { $0 > current + 0.01 } ?? current * 1.2) : (steps.last { $0 < current - 0.01 } ?? max(1, current / 1.2))
        if textEditor != nil {
            applyRunStyle("Font Size") { $0.size = next }
            return
        }
        changeTextBodies(larger ? "Increase Font Size" : "Decrease Font Size") { body in
            body.defaultSize = (larger ? steps.first { $0 > body.defaultSize + 0.01 } : steps.last { $0 < body.defaultSize - 0.01 }) ?? body.defaultSize
            body.updateRuns { r in
                if let s = r.size { r.size = (larger ? steps.first { $0 > s + 0.01 } : steps.last { $0 < s - 0.01 }) ?? s }
            }
        }
    }

    func toggleBold() { let on = !(currentRunStyle.bold ?? false); applyRunStyle("Bold") { $0.bold = on } }
    func toggleItalic() { let on = !(currentRunStyle.italic ?? false); applyRunStyle("Italic") { $0.italic = on } }
    func toggleUnderline() { let on = !currentRunStyle.underline; applyRunStyle("Underline") { $0.underline = on } }
    func toggleStrikethrough() { let on = !currentRunStyle.strikethrough; applyRunStyle("Strikethrough") { $0.strikethrough = on } }
    func toggleShadow() { let on = !currentRunStyle.shadow; applyRunStyle("Text Shadow") { $0.shadow = on } }

    func setBaseline(_ value: Int) {
        let target = currentRunStyle.baseline == value ? 0 : value
        applyRunStyle(value > 0 ? "Superscript" : "Subscript") { $0.baseline = target }
    }

    func setTextColor(_ color: PaintColor?) { applyRunStyle("Font Color") { $0.color = color } }
    func setHighlight(_ color: RGBColor?) { applyRunStyle("Highlight") { $0.highlight = color } }
    func setCharacterSpacing(_ value: Double) { applyRunStyle("Character Spacing") { $0.characterSpacing = value } }

    func setTextOutline(_ color: PaintColor?, width: Double) {
        applyRunStyle("Text Outline") { r in
            r.outlineColor = color
            r.outlineWidth = color == nil ? 0 : width
        }
    }

    func clearFormatting() {
        applyRunStyle("Clear Formatting") { r in
            let link = r.link
            r = RunStyle()
            r.link = link
        }
    }

    func changeCase(_ mode: TextCase) {
        if let editor = textEditor {
            let text = editor.selectedText
            guard !text.isEmpty else { return }
            editor.insertText(mode.apply(text))
            return
        }
        changeTextBodies("Change Case") { body in
            for p in body.paragraphs.indices {
                for r in body.paragraphs[p].runs.indices { body.paragraphs[p].runs[r].text = mode.apply(body.paragraphs[p].runs[r].text) }
            }
        }
    }

    func setAlignment(_ alignment: TextAlignment) {
        applyParagraphStyle("Align Text") { $0.alignment = alignment }
    }

    func toggleBullets(_ symbol: String? = nil) {
        let current = currentParagraphStyle.bullet
        let target: Bullet
        if let symbol { target = .symbol(symbol) } else if case .symbol = current { target = .none } else { target = .symbol(theme.bulletSymbol) }
        applyParagraphStyle("Bullets") { $0.bullet = target }
    }

    func toggleNumbering(_ scheme: NumberingScheme? = nil) {
        let current = currentParagraphStyle.bullet
        let target: Bullet
        if let scheme { target = .numbered(scheme, start: 1) } else if case .numbered = current { target = .none } else { target = .numbered(.arabicPeriod, start: 1) }
        applyParagraphStyle("Numbering") { $0.bullet = target }
    }

    func changeIndent(_ delta: Int) {
        applyParagraphStyle(delta > 0 ? "Increase List Level" : "Decrease List Level") { $0.level = max(0, min(8, $0.level + delta)) }
    }

    func setLineSpacing(_ value: Double) { applyParagraphStyle("Line Spacing") { $0.lineSpacing = value } }

    func setParagraphSpacing(before: Double?, after: Double?) {
        applyParagraphStyle("Paragraph Spacing") { p in
            if let before { p.spaceBefore = before }
            if let after { p.spaceAfter = after }
        }
    }

    // MARK: - Text box settings

    func setTextBox(_ name: String, _ change: @escaping (inout TextBody) -> Void) {
        commitTextEditing()
        changeTextBodies(name, change)
    }

    func setVerticalAnchor(_ anchor: VerticalAnchor) { setTextBox("Align Text") { $0.anchor = anchor } }
    func setTextDirection(_ direction: TextDirection) { setTextBox("Text Direction") { $0.direction = direction } }
    func setColumns(_ count: Int) { setTextBox("Columns") { $0.columns = max(1, min(count, 6)) } }
    func setAutofit(_ fit: AutoFit) { setTextBox("Autofit") { $0.autofit = fit } }
    func setWrap(_ wrap: Bool) { setTextBox("Wrap Text") { $0.wrap = wrap } }

    // MARK: - Hyperlinks

    func setHyperlink(_ url: String?) {
        let link = url?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if textEditor != nil && (textEditor?.hasSelection ?? false) {
            applyRunStyle("Hyperlink") { $0.link = link }
        } else if textEditor != nil, let link {
            textEditor?.insertText(link)
        } else if selection.isEmpty, let link {
            var box = SlideElement.textBox(link, frame: centeredFrame(CGSize(width: 360, height: 40)))
            box.text?.updateRuns { $0.link = link }
            insert([box], name: "Insert Hyperlink")
        } else {
            setAction(link.map { .url($0) })
        }
    }

    var currentLink: String? {
        if let editor = textEditor { return editor.currentRunStyle.link }
        if case .url(let u) = primaryElement?.action { return u }
        return primaryElement?.text?.linkTargets.first
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

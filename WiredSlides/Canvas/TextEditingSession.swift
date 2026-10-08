import AppKit

/// The text view used for editing on the slide.
final class SlideTextView: NSTextView {
    weak var session: TextEditingSession?

    override func cancelOperation(_ sender: Any?) {
        session?.endFromKeyboard()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        return result
    }

    /// Plain-text paste keeps the slide's formatting (⌥⇧⌘V is Paste and Match Style).
    override func pasteAsPlainText(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        insertText(s, replacementRange: selectedRange())
    }

    override var acceptsFirstResponder: Bool { true }
}

/// Edits the text of one shape or table cell in place, through an NSTextView
/// laid over the slide at the same scale and layout as the renderer.
final class TextEditingSession: NSObject, NSTextViewDelegate, SlideTextEditing {
    unowned let canvas: SlideCanvasView
    private var controller: PresentationController { canvas.controller }
    private(set) var textView: SlideTextView?
    private(set) var elementID: UUID?
    private(set) var cell: TableCellAddress?
    private var base = TextBody()
    private var original = TextBody()
    private var boxRect: CGRect = .zero
    private var fontScale: CGFloat = 1
    private let undo = UndoManager()
    private var rebuilding = false

    init(canvas: SlideCanvasView) {
        self.canvas = canvas
    }

    private var context: TextLayout.Context {
        TextLayout.Context(theme: controller.theme, fontScale: fontScale, editing: true)
    }

    // MARK: - Starting and ending

    func begin(_ id: UUID, cell: TableCellAddress?, selectAll: Bool) {
        end(save: true)
        guard let element = controller.currentSlide.element(id) else { return }
        var body: TextBody
        let rect: CGRect
        if let cell, case .table(let table) = element.content {
            guard table.rows.indices.contains(cell.row), table.rows[cell.row].indices.contains(cell.column) else { return }
            let tableCell = table.rows[cell.row][cell.column]
            body = tableCell.text
            let look = TableRenderer.cellAppearance(table, row: cell.row, column: cell.column, colors: controller.theme.colors)
            if let text = look.text { body.defaultColor = text }
            rect = TableGeometry(table, in: element.frame).rect(row: cell.row, column: cell.column, rowSpan: tableCell.rowSpan, columnSpan: tableCell.columnSpan)
            original = tableCell.text
        } else if case .shape(let shape) = element.content {
            body = shape.text
            rect = ElementRenderer.textRect(element, shape)
            original = shape.text
        } else {
            return
        }
        base = body
        boxRect = rect
        fontScale = TextLayout.fittedScale(body, size: rect.size, theme: controller.theme)
        elementID = id
        self.cell = cell

        let tv = SlideTextView(frame: CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 10), height: max(rect.height, 10)))
        tv.session = self
        let manager = BulletLayoutManager()
        manager.showsEmptyMarkers = true
        tv.textContainer?.replaceLayoutManager(manager)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = .zero
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = !body.wrap
        tv.usesFontPanel = true
        tv.usesFindBar = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.isAutomaticLinkDetectionEnabled = false
        tv.focusRingType = .none
        tv.delegate = self
        tv.textStorage?.setAttributedString(TextLayout.attributedString(body, context))
        tv.typingAttributes = TextLayout.typingAttributes(body, paragraph: body.paragraphs.count - 1, context)
        if let color = tv.typingAttributes[.foregroundColor] as? NSColor { tv.insertionPointColor = color }
        canvas.editorHost.addSubview(tv)
        textView = tv
        controller.editingElement = id
        controller.editingCell = cell
        controller.textEditor = self
        relayout()
        canvas.window?.makeFirstResponder(tv)
        if selectAll { tv.selectAll(nil) } else { tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0)) }
        canvas.needsDisplay = true
        controller.textSelectionRevision += 1
    }

    /// Writes the text back to the model and removes the editor.
    func commit() { end(save: true) }

    func cancel() { end(save: false) }

    /// Escape: stop editing but keep the object selected.
    func endFromKeyboard() {
        let id = elementID
        end(save: true)
        if let id, controller.currentSlide.elements.contains(where: { $0.id == id }) { controller.select([id]) }
        canvas.window?.makeFirstResponder(canvas)
    }

    private func end(save: Bool) {
        guard let tv = textView, let id = elementID else { return }
        let edited = save ? currentBody() : original
        let changed = save && edited != original
        let editedCell = cell
        textView = nil
        elementID = nil
        cell = nil
        tv.delegate = nil
        let hadFocus = canvas.window?.firstResponder === tv
        tv.removeFromSuperview()
        if hadFocus { canvas.window?.makeFirstResponder(canvas) }
        undo.removeAllActions()
        controller.textEditor = nil
        controller.finishTextEditing(elementID: id, cell: editedCell, text: edited, changed: changed)
        canvas.needsDisplay = true
    }

    private func currentBody() -> TextBody {
        guard let storage = textView?.textStorage else { return base }
        var body = TextLayout.textBody(from: storage, base: base, context)
        // Table cells keep their stored default color (the style color was only for display).
        body.defaultColor = original.defaultColor
        return body
    }

    // MARK: - Layout

    func relayout() {
        guard let tv = textView, let manager = tv.layoutManager, let container = tv.textContainer else { return }
        var rect = boxRect
        if base.autofit == .resizeShape, cell == nil {
            let needed = TextLayout.requiredHeight(currentBody(), width: rect.width, theme: controller.theme)
            if needed > rect.height { rect.size.height = needed }
        }
        let content = TextLayout.contentRect(base, in: rect)
        tv.frame.size.width = base.wrap ? content.width : max(content.width, 4000)
        manager.ensureLayout(for: container)
        var used = manager.usedRect(for: container).height
        if !manager.extraLineFragmentRect.isEmpty { used = max(used, manager.extraLineFragmentRect.maxY) }
        used = max(used, 4)
        var y = content.minY
        switch base.anchor {
        case .top: break
        case .middle: y = content.midY - used / 2
        case .bottom: y = content.maxY - used
        }
        var x = content.minX
        if !base.wrap {
            switch base.firstParagraphStyle.alignment {
            case .center: x = content.midX - tv.frame.width / 2
            case .right: x = content.maxX - tv.frame.width
            default: break
            }
        }
        tv.frame = CGRect(x: x, y: y, width: tv.frame.width, height: used)
    }

    // MARK: - Delegate

    func textDidChange(_ notification: Notification) {
        guard !rebuilding else { return }
        if base.autofit == .shrink, cell == nil {
            let body = currentBody()
            let scale = TextLayout.fittedScale(body, size: boxRect.size, theme: controller.theme)
            if abs(scale - fontScale) > 0.015, let tv = textView {
                let selection = tv.selectedRange()
                rebuilding = true
                fontScale = scale
                tv.textStorage?.setAttributedString(TextLayout.attributedString(body, context))
                tv.setSelectedRange(NSRange(location: min(selection.location, tv.string.utf16.count), length: 0))
                rebuilding = false
            }
        }
        relayout()
        canvas.needsDisplay = true
        controller.textSelectionRevision += 1
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        controller.textSelectionRevision += 1
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            if cell != nil { moveCell(by: 1); return true }
            if !currentParagraphStyle.bullet.isNone || currentParagraphStyle.level > 0, atParagraphStart(textView) {
                applyParagraphStyle { $0.level = min($0.level + 1, 8) }
                return true
            }
            return false
        case #selector(NSResponder.insertBacktab(_:)):
            if cell != nil { moveCell(by: -1); return true }
            applyParagraphStyle { $0.level = max($0.level - 1, 0) }
            return true
        case #selector(NSResponder.insertLineBreak(_:)):
            textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Return on an empty bulleted line ends the list, like PowerPoint.
            if !currentParagraphStyle.bullet.isNone, currentParagraphIsEmpty(textView) {
                applyParagraphStyle { $0.bullet = .none; $0.level = 0 }
                return true
            }
            return false
        default:
            return false
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard NSEvent.modifierFlags.contains(.command) else { return true }
        if let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        return true
    }

    private func atParagraphStart(_ tv: NSTextView) -> Bool {
        let s = tv.string as NSString
        let r = tv.selectedRange()
        return r.location == s.paragraphRange(for: NSRange(location: r.location, length: 0)).location
    }

    private func currentParagraphIsEmpty(_ tv: NSTextView) -> Bool {
        let s = tv.string as NSString
        let p = s.paragraphRange(for: NSRange(location: tv.selectedRange().location, length: 0))
        return s.substring(with: p).trimmingCharacters(in: .newlines).isEmpty
    }

    /// Tab between table cells; Tab in the last cell adds a row.
    private func moveCell(by offset: Int) {
        guard let id = elementID, let cell, let e = controller.currentSlide.element(id), case .table(let t) = e.content else { return }
        var index = cell.row * t.columnCount + cell.column
        var next: TableCellAddress?
        repeat {
            index += offset
            guard index >= 0 else { return }
            if index >= t.rowCount * t.columnCount {
                end(save: true)
                controller.cellSelection = TableCellRange(start: cell, end: cell)
                controller.insertTableRow(below: true)
                next = TableCellAddress(row: t.rowCount, column: 0)
                break
            }
            let r = index / t.columnCount, c = index % t.columnCount
            if !t.rows[r][c].isMerged { next = TableCellAddress(row: r, column: c) }
        } while next == nil
        guard let target = next else { return }
        controller.cellSelection = TableCellRange(start: target, end: target)
        canvas.beginEditing(id, cell: target, selectAll: true)
    }

    // MARK: - Caret placement

    func placeCaret(atSlidePoint p: CGPoint) {
        guard let tv = textView, let manager = tv.layoutManager, let container = tv.textContainer else { return }
        let local = canvas.editorHost.convert(p, to: tv)
        var fraction: CGFloat = 0
        let index = manager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let location = min(index + (fraction > 0.5 ? 1 : 0), tv.string.utf16.count)
        tv.setSelectedRange(NSRange(location: location, length: 0))
    }

    func selectWord(atSlidePoint p: CGPoint) {
        guard let tv = textView, !tv.string.isEmpty else { return }
        placeCaret(atSlidePoint: p)
        tv.setSelectedRange(tv.selectionRange(forProposedRange: tv.selectedRange(), granularity: .selectByWord))
    }

    // MARK: - SlideTextEditing

    var hasSelection: Bool { (textView?.selectedRange().length ?? 0) > 0 }

    var selectedText: String {
        guard let tv = textView else { return "" }
        return (tv.string as NSString).substring(with: tv.selectedRange())
    }

    private var currentAttributes: [NSAttributedString.Key: Any] {
        guard let tv = textView, let storage = tv.textStorage else { return [:] }
        let r = tv.selectedRange()
        if r.length > 0 { return storage.attributes(at: r.location, effectiveRange: nil) }
        return tv.typingAttributes
    }

    var currentRunStyle: RunStyle {
        TextLayout.runStyle(from: currentAttributes, body: base, context: context)
    }

    var currentParagraphStyle: ParagraphStyle {
        (currentAttributes[.wsParagraph] as? ParagraphBox)?.style ?? base.firstParagraphStyle
    }

    func applyRunStyle(_ change: @escaping (inout RunStyle) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let ctx = context
        func restyle(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var style = TextLayout.runStyle(from: attributes, body: base, context: ctx)
            change(&style)
            var updated = TextLayout.runAttributes(style, body: base, context: ctx)
            updated[.paragraphStyle] = attributes[.paragraphStyle]
            updated[.wsParagraph] = attributes[.wsParagraph]
            return updated
        }
        if range.length == 0 {
            tv.typingAttributes = restyle(tv.typingAttributes)
        } else if tv.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttributes(in: range) { attributes, sub, _ in
                storage.setAttributes(restyle(attributes), range: sub)
            }
            storage.endEditing()
            tv.didChangeText()
        }
        controller.textSelectionRevision += 1
    }

    func applyParagraphStyle(_ change: @escaping (inout ParagraphStyle) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ctx = context
        let string = storage.string as NSString
        let selection = tv.selectedRange()
        let paragraphs = string.paragraphRange(for: selection)
        func restyle(_ old: ParagraphStyle) -> [NSAttributedString.Key: Any] {
            var style = old
            change(&style)
            return [.paragraphStyle: TextLayout.makeParagraphStyle(style, body: base, scale: fontScale),
                    .wsParagraph: TextLayout.paragraphBox(style, body: base, context: ctx)]
        }
        if paragraphs.length > 0, tv.shouldChangeText(in: paragraphs, replacementString: nil) {
            storage.beginEditing()
            var location = paragraphs.location
            while location < NSMaxRange(paragraphs) {
                let p = string.paragraphRange(for: NSRange(location: location, length: 0))
                let old = (storage.attribute(.wsParagraph, at: p.location, effectiveRange: nil) as? ParagraphBox)?.style ?? .plain
                storage.addAttributes(restyle(old), range: p)
                location = NSMaxRange(p)
                if p.length == 0 { break }
            }
            storage.endEditing()
            tv.didChangeText()
        }
        let old = (tv.typingAttributes[.wsParagraph] as? ParagraphBox)?.style ?? .plain
        tv.typingAttributes.merge(restyle(old)) { $1 }
        relayout()
        canvas.needsDisplay = true
        controller.textSelectionRevision += 1
    }

    func insertText(_ text: String) {
        guard let tv = textView else { return }
        tv.insertText(text, replacementRange: tv.selectedRange())
    }
}

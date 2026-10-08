import AppKit
import Combine

extension NSPasteboard.PasteboardType {
    static let wsSlideRows = NSPasteboard.PasteboardType("com.wiredslides.slide-rows")
}

/// The thumbnail list on the left of Normal view.
final class SlideNavigatorView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum Row {
        case section(SlideSection)
        case slide(Int)
    }

    let controller: PresentationController
    let tableView = NavigatorTableView()
    private let scrollView = NSScrollView()
    private var rows: [Row] = []
    private var cancellables = Set<AnyCancellable>()
    private var syncingSelection = false

    init(controller: PresentationController) {
        self.controller = controller
        super.init(frame: .zero)
        tableView.navigator = self
        tableView.headerView = nil
        tableView.backgroundColor = Theme.paneBackground
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.allowsMultipleSelection = true
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("slide"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([.wsSlideRows, .fileURL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.menu = NSMenu()
        tableView.menu?.delegate = tableView

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.paneBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        controller.$revision.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &cancellables)
        controller.$currentSlideIndex.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncSelection(scroll: true) }.store(in: &cancellables)
        controller.$selectedSlides.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncSelection(scroll: false) }.store(in: &cancellables)
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
    }

    func reload() {
        var result: [Row] = []
        let ranges = controller.sectionRanges()
        for i in controller.slides.indices {
            if let section = ranges.first(where: { $0.range.lowerBound == i })?.section { result.append(.section(section)) }
            result.append(.slide(i))
        }
        rows = result
        syncingSelection = true
        tableView.reloadData()
        syncingSelection = false
        syncSelection(scroll: false)
    }

    private func row(forSlide index: Int) -> Int? {
        rows.firstIndex { if case .slide(let i) = $0 { return i == index }; return false }
    }

    func slideIndex(forRow row: Int) -> Int? {
        guard rows.indices.contains(row), case .slide(let i) = rows[row] else { return nil }
        return i
    }

    private func syncSelection(scroll: Bool) {
        let wanted = IndexSet(controller.selectedSlides.compactMap { row(forSlide: $0) })
        syncingSelection = true
        if tableView.selectedRowIndexes != wanted { tableView.selectRowIndexes(wanted, byExtendingSelection: false) }
        syncingSelection = false
        tableView.enumerateAvailableRowViews { view, row in view.needsDisplay = true; view.subviews.forEach { $0.needsDisplay = true } }
        if scroll, let row = row(forSlide: controller.currentSlideIndex) { tableView.scrollRowToVisible(row) }
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 20 }
        switch rows[row] {
        case .section: return 24
        case .slide:
            let width = max(bounds.width - SlideThumbnailCell.leading - 14, 40)
            return width * controller.slideSize.height / max(controller.slideSize.width, 1) + 8
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let section):
            let cell = (tableView.makeView(withIdentifier: SectionHeaderCell.identifier, owner: nil) as? SectionHeaderCell) ?? SectionHeaderCell()
            cell.configure(section, count: controller.sectionRanges().first { $0.section.id == section.id }?.range.count ?? 0)
            return cell
        case .slide(let index):
            let cell = (tableView.makeView(withIdentifier: SlideThumbnailCell.identifier, owner: nil) as? SlideThumbnailCell) ?? SlideThumbnailCell()
            cell.configure(controller: controller, index: index)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection else { return }
        var slides = IndexSet()
        for row in tableView.selectedRowIndexes {
            switch rows[row] {
            case .slide(let i): slides.insert(i)
            case .section(let section):
                if let range = controller.sectionRanges().first(where: { $0.section.id == section.id })?.range { slides.formUnion(IndexSet(integersIn: range)) }
            }
        }
        guard !slides.isEmpty else { syncSelection(scroll: false); return }
        let clicked = tableView.clickedRow >= 0 ? slideIndex(forRow: tableView.clickedRow) : nil
        let current = clicked.flatMap { slides.contains($0) ? $0 : nil } ?? (slides.contains(controller.currentSlideIndex) ? controller.currentSlideIndex : slides.first!)
        controller.setCurrentSlide(current, extendSelection: true)
        controller.selectedSlides = slides
        tableView.enumerateAvailableRowViews { view, _ in view.subviews.forEach { $0.needsDisplay = true } }
    }

    // MARK: Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let index = slideIndex(forRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(index), forType: .wsSlideRows)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        if op == .on { tableView.setDropRow(row, dropOperation: .above) }
        if info.draggingPasteboard.availableType(from: [.wsSlideRows]) != nil, info.draggingSource as? NSTableView === tableView { return .move }
        if info.draggingPasteboard.availableType(from: [.fileURL]) != nil { return .copy }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // The slide index a drop above `row` lands at.
        let destination = (row..<rows.count).compactMap { slideIndex(forRow: $0) }.first ?? controller.slides.count
        if info.draggingSource as? NSTableView === tableView {
            let indices = IndexSet((info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .wsSlideRows).flatMap(Int.init) })
            guard !indices.isEmpty else { return false }
            controller.moveSlides(indices, to: destination)
            return true
        }
        if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            // Dropping pictures makes one slide per picture.
            for url in urls {
                guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { continue }
                controller.setCurrentSlide(max(destination - 1, 0))
                controller.addSlide(layout: .blank)
                controller.insertPicture(data, filename: url.lastPathComponent, at: CGPoint(x: controller.slideSize.width / 2, y: controller.slideSize.height / 2))
            }
            return true
        }
        return false
    }

    // MARK: Menu

    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        if row >= 0, case .section(let section) = rows[row] {
            menu.add("Rename Section…", symbol: "pencil") { [weak self] in self?.renameSection(section) }
            menu.add("Remove Section", symbol: "minus.circle") { [weak self] in self?.controller.removeSection(section.id) }
            menu.add("Remove Section & Slides", symbol: "trash") { [weak self] in self?.controller.removeSection(section.id, deleteSlides: true) }
            menu.add("Remove All Sections", symbol: "xmark.circle") { [weak self] in self?.controller.removeAllSections() }
            return
        }
        if row >= 0, let index = slideIndex(forRow: row), !controller.selectedSlides.contains(index) {
            controller.setCurrentSlide(index)
        }
        menu.add("Cut", symbol: "scissors") { [weak self] in self?.controller.copySlides(cut: true) }
        menu.add("Copy", symbol: "doc.on.doc") { [weak self] in self?.controller.copySlides() }
        menu.add("Paste", symbol: "doc.on.clipboard", enabled: controller.canPaste) { [weak self] in self?.controller.paste() }
        menu.addItem(.separator())
        menu.add("New Slide", symbol: "plus.rectangle") { [weak self] in self?.controller.addSlide() }
        menu.add("Duplicate Slide", symbol: "plus.rectangle.on.rectangle") { [weak self] in self?.controller.duplicateSlides() }
        menu.add("Delete Slide", symbol: "trash") { [weak self] in self?.controller.deleteSlides() }
        menu.addItem(.separator())
        menu.add("Add Section", symbol: "rectangle.split.1x2") { [weak self] in self?.addSection() }
        let layouts = NSMenu(title: "Layout")
        for layout in LayoutKind.allCases {
            layouts.add(layout.title, checked: controller.currentSlide.layout == layout) { [weak self] in self?.controller.setLayout(layout) }
        }
        menu.addSubmenu(layouts)
        menu.add("Reset Slide", symbol: "arrow.counterclockwise") { [weak self] in self?.controller.resetSlides() }
        menu.add("Format Background…", symbol: "paintpalette") { [weak self] in
            self?.controller.sidePane = .format
            NotificationCenter.default.post(name: .wsShowBackgroundFormat, object: nil)
        }
        menu.addItem(.separator())
        let hidden = controller.selectedSlides.allSatisfy { controller.slides[$0].hidden }
        menu.add(hidden ? "Show Slide" : "Hide Slide", symbol: hidden ? "eye" : "eye.slash") { [weak self] in self?.controller.toggleHideSlides() }
    }

    func addSection() {
        prompt("Add Section", message: "Section name:", value: "Untitled Section") { [weak self] name in self?.controller.addSection(name: name) }
    }

    func renameSection(_ section: SlideSection) {
        prompt("Rename Section", message: "Section name:", value: section.name) { [weak self] name in self?.controller.renameSection(section.id, to: name) }
    }

    private func prompt(_ title: String, message: String, value: String, _ done: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn, !field.stringValue.isEmpty { done(field.stringValue) }
        }
    }
}

/// Forwards editing keys and commands to the slides.
final class NavigatorTableView: NSTableView, NSMenuDelegate {
    weak var navigator: SlideNavigatorView?
    private var controller: PresentationController? { navigator?.controller }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .delete?, .deleteForward?, .backspace?: controller?.deleteSlides()
        case .carriageReturn?, .enter?: controller?.addSlide()
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) { controller?.copySlides() }
    @objc func cut(_ sender: Any?) { controller?.copySlides(cut: true) }
    @objc func paste(_ sender: Any?) { controller?.paste() }
    @objc func delete(_ sender: Any?) { controller?.deleteSlides() }
    @objc func duplicate(_ sender: Any?) { controller?.duplicateSlides() }

    override func selectAll(_ sender: Any?) {
        guard let controller else { return }
        controller.selectedSlides = IndexSet(integersIn: 0..<controller.slides.count)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { navigator?.buildMenu(menu) }
}

final class SlideThumbnailCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("SlideThumbnailCell")
    static let leading: CGFloat = 30

    private weak var controller: PresentationController?
    private var index = 0

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(controller: PresentationController, index: Int) {
        self.controller = controller
        self.index = index
        toolTip = controller.slides.indices.contains(index) ? controller.slides[index].title : nil
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, controller.slides.indices.contains(index) else { return }
        let slide = controller.slides[index]
        let width = bounds.width - Self.leading - 14
        let height = width * controller.slideSize.height / max(controller.slideSize.width, 1)
        let frame = CGRect(x: Self.leading, y: 4, width: width, height: height)
        let selected = controller.selectedSlides.contains(index)
        let current = controller.currentSlideIndex == index

        // Number and markers.
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: current ? .bold : .regular),
            .foregroundColor: current ? Theme.accent : NSColor.secondaryLabelColor,
        ]
        let number = "\(index + 1)" as NSString
        let size = number.size(withAttributes: numberAttrs)
        number.draw(at: CGPoint(x: Self.leading - size.width - 8, y: frame.minY + 2), withAttributes: numberAttrs)
        if slide.hidden, let ctx = NSGraphicsContext.current?.cgContext {
            ElementRenderer.drawSymbol("eye.slash", in: CGRect(x: Self.leading - 22, y: frame.minY + 18, width: 13, height: 11), color: .secondaryLabelColor, ctx: ctx)
        }
        if slide.transition.kind != .none || !slide.animations.isEmpty, let ctx = NSGraphicsContext.current?.cgContext {
            ElementRenderer.drawSymbol("star.fill", in: CGRect(x: Self.leading - 20, y: frame.minY + (slide.hidden ? 34 : 18), width: 10, height: 10),
                                       color: .tertiaryLabelColor, ctx: ctx)
        }
        if !slide.comments.isEmpty, let ctx = NSGraphicsContext.current?.cgContext {
            ElementRenderer.drawSymbol("text.bubble.fill", in: CGRect(x: frame.maxX - 16, y: frame.maxY - 14, width: 13, height: 11), color: Theme.accent, ctx: ctx)
        }

        let image = ThumbnailCache.shared.thumbnail(slide, number: index + 1, presentation: controller.presentation, width: width)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        frame.fill()
        NSGraphicsContext.restoreGraphicsState()
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: slide.hidden ? 0.45 : 1, respectFlipped: true, hints: nil)

        if selected || current {
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: -3, dy: -3), xRadius: 4, yRadius: 4)
            path.lineWidth = current ? 2.5 : 1.5
            (current ? Theme.accent : Theme.accent.withAlphaComponent(0.55)).setStroke()
            path.stroke()
        } else {
            Theme.separator.setStroke()
            NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5)).stroke()
        }
    }
}

final class SectionHeaderCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("SectionHeaderCell")
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ section: SlideSection, count: Int) {
        label.stringValue = "▾ \(section.name)  (\(count))"
    }
}

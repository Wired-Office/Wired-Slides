import AppKit
import Combine

enum ViewMode: String, CaseIterable, Identifiable {
    case normal, outline, sorter, notesPage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .outline: "Outline View"
        case .sorter: "Slide Sorter"
        case .notesPage: "Notes Page"
        }
    }

    var symbol: String {
        switch self {
        case .normal: "rectangle.split.3x1"
        case .outline: "list.bullet.indent"
        case .sorter: "square.grid.3x2"
        case .notesPage: "note.text"
        }
    }
}

enum SidePane: String, CaseIterable, Identifiable {
    case format, animations, selection, comments, designer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .format: "Format"
        case .animations: "Animation Pane"
        case .selection: "Selection"
        case .comments: "Comments"
        case .designer: "Design Ideas"
        }
    }
}

/// Copied formatting waiting to be painted onto another object (Format Painter).
struct FormatPainter {
    var element: SlideElement
    var runStyle: RunStyle?
    var sticky = false
}

/// Asks the view layer to show dialogs.
protocol SheetPresenting: AnyObject {
    func presentInsertTable()
    func presentChartEditor(_ elementID: UUID)
    func presentHyperlink()
    func presentFindReplace(replace: Bool)
    func presentHeaderFooter()
    func presentSlideSize()
    func presentInsertIcon()
    func presentSmartArt()
    func presentAction()
    func presentSetUpShow()
    func presentSpelling()
    func startSlideShow(from index: Int, presenter: Bool, rehearse: Bool)
    func insertPicturesFromFile()
    func insertMediaFromFile()
}

/// The heart of an open presentation: the model, selection and every editing command.
/// Views observe it; menus, the ribbon and the canvas call into it.
///
/// All model changes go through `change(_:_:)`, which snapshots the presentation for undo.
final class PresentationController: ObservableObject {
    weak var document: SlidesDocument?
    weak var presenter: SheetPresenting?

    private(set) var presentation: Presentation

    /// Bumped after every model change.
    @Published private(set) var revision = 0
    @Published private(set) var currentSlideIndex = 0
    /// Slides selected in the navigator (always includes the current slide).
    @Published var selectedSlides: IndexSet = [0]
    /// Elements selected on the current slide (top-level ids).
    @Published var selection: [UUID] = []
    /// A child selected inside a group (click again on a group to drill in).
    @Published var selectedChild: UUID?
    /// The element whose text is being edited.
    @Published var editingElement: UUID?
    @Published var editingCell: TableCellAddress?
    /// Selected cells of the table being edited.
    @Published var cellSelection: TableCellRange?
    @Published var zoom: Double = 1
    @Published var fitToWindow = true
    @Published var viewMode: ViewMode = .normal
    @Published var sidePane: SidePane?
    @Published var formatPainter: FormatPainter?
    @Published var statusMessage: String?
    @Published var showGridlines = false
    @Published var showGuides = false
    /// The shape tool waiting for a drag on the canvas.
    @Published var pendingInsert: PendingInsert?
    /// The animation selected in the Animation pane.
    @Published var selectedAnimation: UUID?
    /// Bumped when the text editor's selection or typing attributes change.
    @Published var textSelectionRevision = 0
    /// The active text editor (while editing), for formatting commands.
    weak var textEditor: SlideTextEditing?

    /// Called when the canvas must redraw.
    var onCanvasChange: (() -> Void)?
    /// Asks the canvas to start editing an element's text (or a table cell).
    var onBeginEditing: ((UUID, TableCellAddress?) -> Void)?
    private var interactiveSnapshot: (presentation: Presentation, selection: [UUID], slide: Int)?

    let documentID = UUID()

    init(presentation: Presentation) {
        self.presentation = presentation
    }

    var undoManager: UndoManager? { document?.undoManager }

    // MARK: - Loading

    func load(_ presentation: Presentation) {
        self.presentation = presentation
        currentSlideIndex = 0
        selectedSlides = [0]
        selection = []
        editingElement = nil
        revision += 1
        onCanvasChange?()
    }

    // MARK: - Accessors

    var slides: [Slide] { presentation.slides }
    var theme: PresentationTheme { presentation.theme }
    var slideSize: CGSize { presentation.slideSize }

    var currentSlide: Slide {
        presentation.slides[min(currentSlideIndex, presentation.slides.count - 1)]
    }

    var selectedElements: [SlideElement] { selection.compactMap { currentSlide.element($0) } }

    /// The element formatting commands act on: the drilled-in child, else the selection.
    var targetIDs: [UUID] {
        if let child = selectedChild { return [child] }
        return selection
    }

    var targetElements: [SlideElement] { targetIDs.compactMap { currentSlide.element($0) } }

    var primaryElement: SlideElement? { targetElements.first }

    // MARK: - Changes

    /// Applies a change with undo support.
    func change(_ actionName: String, _ body: (inout Presentation) throws -> Void) rethrows {
        commitTextEditing()
        let before = presentation
        let beforeSelection = selection
        let beforeSlide = currentSlideIndex
        var updated = presentation
        try body(&updated)
        guard updated != before else { return }
        commit(updated)
        registerUndo(actionName, restoring: before, selection: beforeSelection, slide: beforeSlide)
    }

    /// Changes the current slide.
    func changeSlide(_ actionName: String, _ body: (inout Slide) throws -> Void) rethrows {
        let index = currentSlideIndex
        try change(actionName) { p in try body(&p.slides[index]) }
    }

    /// Changes elements on the current slide (descending into groups for child ids).
    func changeElements(_ ids: [UUID], _ actionName: String, _ body: (inout SlideElement) -> Void) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        changeSlide(actionName) { slide in
            for i in slide.elements.indices { Self.update(&slide.elements[i], ids: set, body) }
        }
    }

    /// Changes the elements formatting commands target.
    func changeTargets(_ actionName: String, _ body: (inout SlideElement) -> Void) {
        changeElements(targetIDs, actionName, body)
    }

    private static func update(_ e: inout SlideElement, ids: Set<UUID>, _ body: (inout SlideElement) -> Void) {
        if ids.contains(e.id) { body(&e); return }
        if case .group(var g) = e.content {
            for i in g.children.indices { update(&g.children[i], ids: ids, body) }
            let frame = g.children.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            e.content = .group(g)
            if !frame.isNull { e.frame = frame }
        }
    }

    private func registerUndo(_ name: String, restoring snapshot: Presentation, selection: [UUID], slide: Int) {
        guard let undoManager else { return }
        let redoSnapshot = presentation
        let redoSelection = self.selection
        let redoSlide = currentSlideIndex
        undoManager.registerUndo(withTarget: self) { controller in
            controller.restore(snapshot, selection: selection, slide: slide)
            controller.registerUndo(name, restoring: redoSnapshot, selection: redoSelection, slide: redoSlide)
        }
        undoManager.setActionName(name)
    }

    private func restore(_ snapshot: Presentation, selection: [UUID], slide: Int) {
        cancelTextEditing()
        commit(snapshot)
        setCurrentSlide(min(slide, snapshot.slides.count - 1), keepSelection: true)
        self.selection = selection.filter { currentSlide.element($0) != nil }
    }

    private func commit(_ updated: Presentation) {
        presentation = updated
        if currentSlideIndex >= presentation.slides.count { currentSlideIndex = max(presentation.slides.count - 1, 0) }
        selectedSlides = IndexSet(selectedSlides.filter { $0 < presentation.slides.count })
        if selectedSlides.isEmpty { selectedSlides = [currentSlideIndex] }
        selection = selection.filter { currentSlide.element($0) != nil }
        if let child = selectedChild, currentSlide.element(child) == nil { selectedChild = nil }
        revision += 1
        onCanvasChange?()
    }

    // MARK: Interactive changes (drags)

    /// Starts a change that updates live and becomes one undo step when it ends.
    func beginInteractiveChange() {
        interactiveSnapshot = (presentation, selection, currentSlideIndex)
    }

    func updateInteractive(_ body: (inout Presentation) -> Void) {
        var updated = presentation
        body(&updated)
        presentation = updated
        revision += 1
        onCanvasChange?()
    }

    func endInteractiveChange(_ actionName: String) {
        guard let snapshot = interactiveSnapshot else { return }
        interactiveSnapshot = nil
        guard snapshot.presentation != presentation else { return }
        commit(presentation)
        registerUndo(actionName, restoring: snapshot.presentation, selection: snapshot.selection, slide: snapshot.slide)
    }

    func cancelInteractiveChange() {
        guard let snapshot = interactiveSnapshot else { return }
        interactiveSnapshot = nil
        commit(snapshot.presentation)
    }

    var isInteracting: Bool { interactiveSnapshot != nil }

    // MARK: - Slide navigation

    func setCurrentSlide(_ index: Int, keepSelection: Bool = false, extendSelection: Bool = false) {
        guard presentation.slides.indices.contains(index) else { return }
        if index != currentSlideIndex { commitTextEditing() }
        let changed = index != currentSlideIndex
        currentSlideIndex = index
        if !extendSelection { selectedSlides = [index] } else { selectedSlides.insert(index) }
        if changed && !keepSelection {
            selection = []
            selectedChild = nil
        }
        onCanvasChange?()
    }

    func nextSlide() { setCurrentSlide(min(currentSlideIndex + 1, slides.count - 1)) }
    func previousSlide() { setCurrentSlide(max(currentSlideIndex - 1, 0)) }

    // MARK: - Element selection

    func select(_ ids: [UUID], extend: Bool = false) {
        if editingElement != nil, !ids.contains(where: { $0 == editingElement }) { commitTextEditing() }
        selectedChild = nil
        if extend {
            var current = selection
            for id in ids {
                if let i = current.firstIndex(of: id) { current.remove(at: i) } else { current.append(id) }
            }
            selection = current
        } else {
            selection = ids
        }
        onCanvasChange?()
    }

    func selectChild(_ id: UUID?) {
        selectedChild = id
        onCanvasChange?()
    }

    func clearSelection() {
        commitTextEditing()
        selection = []
        selectedChild = nil
        onCanvasChange?()
    }

    func selectAllElements() {
        selection = currentSlide.elements.filter { !$0.locked && !$0.hidden }.map(\.id)
        onCanvasChange?()
    }

    // MARK: - Text editing state

    /// Finishes any text editing, writing the text back to the model.
    func commitTextEditing() {
        guard editingElement != nil else { return }
        textEditor?.commit()
    }

    func cancelTextEditing() {
        guard editingElement != nil else { return }
        textEditor?.cancel()
        editingElement = nil
        editingCell = nil
    }

    var isEditingText: Bool { editingElement != nil }

    func beginEditing(_ id: UUID, cell: TableCellAddress? = nil) {
        if selection != [id] { select([id]) }
        onBeginEditing?(id, cell)
    }

    /// Called by the text editor when editing ends with the new text.
    func finishTextEditing(elementID: UUID, cell: TableCellAddress?, text: TextBody, changed: Bool) {
        editingElement = nil
        editingCell = nil
        guard changed else { onCanvasChange?(); return }
        let index = currentSlideIndex
        let theme = presentation.theme
        change("Typing") { p in
            guard p.slides.indices.contains(index) else { return }
            for i in p.slides[index].elements.indices {
                Self.update(&p.slides[index].elements[i], ids: [elementID]) { e in
                    if let cell, case .table(var t) = e.content {
                        guard t.rows.indices.contains(cell.row), t.rows[cell.row].indices.contains(cell.column) else { return }
                        t.rows[cell.row][cell.column].text = text
                        t.rowHeights = TableRenderer.fittedRowHeights(t, width: e.frame.width, theme: theme)
                        e.content = .table(t)
                        e.frame.size.height = CGFloat(t.rowHeights.reduce(0, +))
                    } else {
                        e.text = text
                        Self.fitHeight(&e, theme: theme)
                    }
                }
            }
        }
    }

    /// Grows or shrinks "resize shape to fit text" boxes to their text.
    static func fitHeight(_ e: inout SlideElement, theme: PresentationTheme) {
        guard let body = e.text, body.autofit == .resizeShape else { return }
        let needed = TextLayout.requiredHeight(body, width: e.frame.width, theme: theme)
        guard abs(needed - e.frame.height) > 0.5 else { return }
        switch body.anchor {
        case .top: e.frame.size.height = needed
        case .middle:
            e.frame.origin.y += (e.frame.height - needed) / 2
            e.frame.size.height = needed
        case .bottom:
            e.frame.origin.y += e.frame.height - needed
            e.frame.size.height = needed
        }
    }

    // MARK: - Status

    func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}

struct TableCellAddress: Hashable {
    var row: Int
    var column: Int
}

struct TableCellRange: Hashable {
    var start: TableCellAddress
    var end: TableCellAddress

    var rows: ClosedRange<Int> { min(start.row, end.row)...max(start.row, end.row) }
    var columns: ClosedRange<Int> { min(start.column, end.column)...max(start.column, end.column) }
    var isSingle: Bool { start == end }
}

/// Something waiting to be drawn on the canvas.
enum PendingInsert: Equatable {
    case shape(ShapeKind)
    case textBox
    case verticalTextBox
    case line(ConnectorKind, arrow: Bool)
}

/// The text editor the controller talks to for formatting.
protocol SlideTextEditing: AnyObject {
    func commit()
    func cancel()
    /// Formatting at the insertion point or of the selection.
    var currentRunStyle: RunStyle { get }
    var currentParagraphStyle: ParagraphStyle { get }
    var hasSelection: Bool { get }
    func applyRunStyle(_ change: @escaping (inout RunStyle) -> Void)
    func applyParagraphStyle(_ change: @escaping (inout ParagraphStyle) -> Void)
    func insertText(_ text: String)
    var selectedText: String { get }
}

import AppKit
import Combine

/// The editing surface: draws the current slide with selection handles and
/// handles every mouse and keyboard interaction with its objects.
final class SlideCanvasView: NSView {
    let controller: PresentationController
    /// Holds the text editor; its bounds are in slide points, so the editor scales with zoom.
    let editorHost = FlippedView()
    lazy var textSession = TextEditingSession(canvas: self)

    static let margin: CGFloat = 36
    static let handleSize: CGFloat = 9
    static let rotateOffset: CGFloat = 26

    enum DragMode {
        case none
        case pendingMove(start: CGPoint, duplicate: Bool)
        case move(start: CGPoint, originals: [SlideElement])
        case resize(handle: Int, original: SlideElement)
        case rotate(original: SlideElement, startAngle: CGFloat)
        case adjust(original: SlideElement)
        case lineEnd(start: Bool, original: SlideElement)
        case marquee(start: CGPoint, current: CGPoint, extend: Bool)
        case draw(start: CGPoint, current: CGPoint, insert: PendingInsert)
        case cells(elementID: UUID, start: TableCellAddress)
        case column(elementID: UUID, index: Int, original: SlideElement)
    }

    var dragMode: DragMode = .none
    /// Smart guide lines to draw while dragging (slide coordinates).
    var guides: [(CGPoint, CGPoint)] = []
    /// Whether to show animation order badges (Animations tab).
    var showsAnimationBadges = false
    private var cancellables = Set<AnyCancellable>()
    private var trackingArea: NSTrackingArea?

    init(controller: PresentationController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        editorHost.wantsLayer = false
        addSubview(editorHost)
        registerForDraggedTypes([.fileURL, .png, .tiff, .pdf, .URL])
        controller.$selection.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        controller.$selectedChild.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        controller.$cellSelection.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        controller.$showGridlines.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        controller.$showGuides.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        controller.$pendingInsert.sink { [weak self] _ in self?.window?.invalidateCursorRects(for: self!) }.store(in: &cancellables)
        controller.onBeginEditing = { [weak self] id, cell in self?.beginEditing(id, cell: cell, selectAll: false) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Geometry

    var zoom: CGFloat { CGFloat(controller.zoom) }
    var slideSize: CGSize { controller.slideSize }

    /// The slide's rectangle in view coordinates (centered when there's room).
    var slideRect: CGRect {
        let w = slideSize.width * zoom, h = slideSize.height * zoom
        let x = max(Self.margin, (bounds.width - w) / 2)
        let y = max(Self.margin, (bounds.height - h) / 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The view size needed at the current zoom.
    var contentSize: CGSize {
        CGSize(width: slideSize.width * zoom + Self.margin * 2, height: slideSize.height * zoom + Self.margin * 2)
    }

    func toSlide(_ p: CGPoint) -> CGPoint {
        let r = slideRect
        return CGPoint(x: (p.x - r.minX) / zoom, y: (p.y - r.minY) / zoom)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        let r = slideRect
        return CGPoint(x: r.minX + p.x * zoom, y: r.minY + p.y * zoom)
    }

    func toView(_ rect: CGRect) -> CGRect {
        let o = toView(rect.origin)
        return CGRect(x: o.x, y: o.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    override func layout() {
        super.layout()
        layoutEditorHost()
    }

    func layoutEditorHost() {
        let r = slideRect
        editorHost.frame = r
        editorHost.bounds = CGRect(origin: .zero, size: slideSize)
        textSession.relayout()
    }

    func refresh() {
        needsDisplay = true
        layoutEditorHost()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Theme.canvasBackground.setFill()
        dirtyRect.fill()
        let r = slideRect
        let slide = controller.currentSlide

        // The slide with a soft shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 10, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: zoom, y: zoom)
        var options = SlideDrawOptions()
        options.element.editorChrome = true
        options.element.editingTextElement = controller.editingElement
        options.element.editingCell = controller.editingCell.map { ($0.row, $0.column) }
        SlideRenderer.draw(slide, number: controller.currentSlideIndex + 1, presentation: controller.presentation, ctx: ctx, options: options)
        drawGrid(ctx)
        ctx.restoreGState()

        if slide.hidden {
            let label = "Hidden Slide" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
            label.draw(at: CGPoint(x: r.minX, y: r.maxY + 6), withAttributes: attrs)
        }
        drawSelection(ctx)
        drawCellSelection(ctx)
        drawGuides(ctx)
        drawDragFeedback(ctx)
        drawCommentMarkers(ctx)
        if showsAnimationBadges { drawAnimationBadges(ctx) }
    }

    private func drawGrid(_ ctx: CGContext) {
        let size = slideSize
        if controller.showGridlines {
            let step = CGFloat(AppSettings.shared.gridSpacing) * 2
            ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.25).cgColor)
            ctx.setLineWidth(0.5 / zoom)
            var x = step
            while x < size.width { ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)]); x += step }
            var y = step
            while y < size.height { ctx.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]); y += step }
        }
        if controller.showGuides {
            ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            ctx.strokeLineSegments(between: [CGPoint(x: size.width / 2, y: 0), CGPoint(x: size.width / 2, y: size.height),
                                             CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)])
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    private func outlinePath(_ e: SlideElement) -> CGPath {
        let t = CanvasGeometry.rotationTransform(e)
        let corners = [CGPoint(x: e.frame.minX, y: e.frame.minY), CGPoint(x: e.frame.maxX, y: e.frame.minY),
                       CGPoint(x: e.frame.maxX, y: e.frame.maxY), CGPoint(x: e.frame.minX, y: e.frame.maxY)].map { toView($0.applying(t)) }
        let p = CGMutablePath()
        p.addLines(between: corners)
        p.closeSubpath()
        return p
    }

    private func drawSelection(_ ctx: CGContext) {
        let accent = Theme.selection.cgColor
        let elements = controller.selectedElements
        let single = elements.count == 1 && controller.selectedChild == nil
        for e in elements {
            ctx.saveGState()
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1)
            if controller.editingElement == e.id {
                ctx.setLineDash(phase: 0, lengths: [4, 3])
            }
            if case .line = e.content {
                let ends = e.lineEndpoints
                if !single {
                    ctx.setLineWidth(1)
                    ctx.strokeLineSegments(between: [toView(ends.start.applying(CanvasGeometry.rotationTransform(e))), toView(ends.end.applying(CanvasGeometry.rotationTransform(e)))])
                }
            } else {
                ctx.addPath(outlinePath(e))
                ctx.strokePath()
            }
            ctx.restoreGState()
            if e.locked {
                let p = toView(CanvasGeometry.handlePoints(e)[2])
                ElementRenderer.drawSymbol("lock.fill", in: CGRect(x: p.x + 2, y: p.y - 14, width: 11, height: 11), color: NSColor.secondaryLabelColor, ctx: ctx)
            }
            guard single, !e.locked, controller.editingElement != e.id || !e.isTable else { continue }
            drawHandles(e, ctx: ctx)
        }
        if let child = controller.selectedChild, let e = controller.currentSlide.element(child) {
            ctx.saveGState()
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5)
            ctx.addPath(outlinePath(e))
            ctx.strokePath()
            ctx.restoreGState()
            drawHandles(e, ctx: ctx)
        }
    }

    private func drawHandles(_ e: SlideElement, ctx: CGContext) {
        let accent = Theme.selection.cgColor
        let s = Self.handleSize
        func handle(_ p: CGPoint, round: Bool = false, fill: CGColor = .white) {
            let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
            ctx.setFillColor(fill)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1)
            if round { ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r) } else { ctx.fill(r); ctx.stroke(r) }
        }
        if case .line = e.content {
            let t = CanvasGeometry.rotationTransform(e)
            let ends = e.lineEndpoints
            handle(toView(ends.start.applying(t)), round: true)
            handle(toView(ends.end.applying(t)), round: true)
            return
        }
        // Rotation handle.
        let top = toView(CanvasGeometry.handlePoints(e)[1])
        let rot = rotateHandleView(e)
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: [top, rot])
        ElementRenderer.drawSymbol("arrow.clockwise", in: CGRect(x: rot.x - 7, y: rot.y - 7, width: 14, height: 14), color: Theme.selection, ctx: ctx)
        let points = CanvasGeometry.handlePoints(e).map(toView)
        let tiny = e.frame.width * zoom < 24 || e.frame.height * zoom < 24
        for (i, p) in points.enumerated() where !(tiny && i % 2 == 1) {
            handle(p, round: i % 2 == 0)
        }
        if let adjust = CanvasGeometry.adjustHandlePoint(e) {
            handle(toView(adjust), round: true, fill: NSColor.systemYellow.cgColor)
        }
    }

    func rotateHandleView(_ e: SlideElement) -> CGPoint {
        let top = toView(CanvasGeometry.handlePoints(e)[1])
        let center = toView(CGPoint(x: e.frame.midX, y: e.frame.midY))
        let dx = top.x - center.x, dy = top.y - center.y
        let len = max(hypot(dx, dy), 0.01)
        return CGPoint(x: top.x + dx / len * Self.rotateOffset, y: top.y + dy / len * Self.rotateOffset)
    }

    private func drawCellSelection(_ ctx: CGContext) {
        guard let range = controller.cellSelection, let (id, table) = controller.selectedTable,
              let e = controller.currentSlide.element(id), !range.isSingle || controller.editingCell == nil else { return }
        let geo = TableGeometry(table, in: e.frame)
        let rect = geo.rect(row: range.rows.lowerBound, column: range.columns.lowerBound,
                            rowSpan: range.rows.count, columnSpan: range.columns.count)
        let v = toView(rect)
        ctx.setFillColor(Theme.selection.withAlphaComponent(0.18).cgColor)
        ctx.fill(v)
        ctx.setStrokeColor(Theme.selection.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(v)
    }

    private func drawGuides(_ ctx: CGContext) {
        guard !guides.isEmpty else { return }
        ctx.setStrokeColor(Theme.guide.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        for (a, b) in guides { ctx.strokeLineSegments(between: [toView(a), toView(b)]) }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawDragFeedback(_ ctx: CGContext) {
        switch dragMode {
        case .marquee(let start, let current, _):
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
            let v = toView(r)
            ctx.setFillColor(Theme.selection.withAlphaComponent(0.1).cgColor)
            ctx.fill(v)
            ctx.setStrokeColor(Theme.selection.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(v)
        case .draw(let start, let current, let insert):
            ctx.setStrokeColor(Theme.selection.cgColor)
            ctx.setLineWidth(1.5)
            let a = toView(start), b = toView(constrained(start, current, insert: insert))
            if case .line = insert {
                ctx.strokeLineSegments(between: [a, b])
            } else {
                let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                if case .shape(let kind) = insert {
                    let geo = ShapeGeometry.make(kind, in: r, adjustments: kind.defaultAdjustments)
                    ctx.setFillColor(Theme.selection.withAlphaComponent(0.15).cgColor)
                    ctx.addPath(geo.path)
                    ctx.drawPath(using: .eoFillStroke)
                } else {
                    ctx.setLineDash(phase: 0, lengths: [4, 3])
                    ctx.stroke(r)
                }
            }
        default:
            break
        }
    }

    private func drawCommentMarkers(_ ctx: CGContext) {
        for comment in controller.currentSlide.comments where !comment.resolved {
            let p = toView(comment.position)
            let r = CGRect(x: p.x, y: p.y - 22, width: 22, height: 20)
            ElementRenderer.drawSymbol("text.bubble.fill", in: r, color: Theme.accent, ctx: ctx)
        }
    }

    private func drawAnimationBadges(_ ctx: CGContext) {
        var step = 0
        var badges: [UUID: [Int]] = [:]
        for (i, a) in controller.currentAnimations.enumerated() {
            if a.trigger == .onClick || i == 0 { step += a.trigger == .onClick ? 1 : 0 }
            badges[a.elementID, default: []].append(step)
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white]
        for (id, steps) in badges {
            guard let e = controller.currentSlide.element(id) else { continue }
            let label = Array(Set(steps)).sorted().map(String.init).joined(separator: ",") as NSString
            let size = label.size(withAttributes: attrs)
            let p = toView(CGPoint(x: e.frame.minX, y: e.frame.minY))
            let r = CGRect(x: p.x - size.width - 10, y: p.y, width: size.width + 8, height: 15)
            let selected = controller.selectionAnimations.contains { $0.elementID == id }
            ctx.setFillColor((selected ? Theme.selection : NSColor.systemGray).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.fillPath()
            label.draw(at: CGPoint(x: r.minX + 4, y: r.minY + 1), withAttributes: attrs)
        }
    }

    // MARK: - Cursors

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if controller.pendingInsert != nil { NSCursor.crosshair.set(); return }
        if controller.formatPainter != nil { NSCursor.pointingHand.set(); return }
        if let (_, handle) = handleHit(p) { handle.cursor.set(); return }
        if let (id, _) = controller.selectedTable, let e = controller.currentSlide.element(id), columnBorder(at: toSlide(p), in: e) != nil {
            NSCursor.resizeLeftRight.set(); return
        }
        let sp = toSlide(p)
        if let e = CanvasGeometry.hit(controller.currentSlide.elements, at: sp, tolerance: 4 / zoom), e.action != nil || e.text?.linkTargets.isEmpty == false {
            NSCursor.arrow.set(); return
        }
        NSCursor.arrow.set()
    }

    // MARK: - Hit testing handles

    func handleHit(_ viewPoint: CGPoint) -> (UUID, CanvasGeometry.Handle)? {
        let target: SlideElement?
        if let child = controller.selectedChild { target = controller.currentSlide.element(child) } else {
            let selected = controller.selectedElements
            target = selected.count == 1 ? selected[0] : nil
        }
        guard let e = target, !e.locked else { return nil }
        let s = Self.handleSize / 2 + 3
        func near(_ p: CGPoint) -> Bool { abs(p.x - viewPoint.x) <= s && abs(p.y - viewPoint.y) <= s }
        if case .line = e.content {
            let t = CanvasGeometry.rotationTransform(e)
            if near(toView(e.lineEndpoints.end.applying(t))) { return (e.id, .lineEnd) }
            if near(toView(e.lineEndpoints.start.applying(t))) { return (e.id, .lineStart) }
            return nil
        }
        if controller.editingElement == e.id && e.isTable { return nil }
        if let adjust = CanvasGeometry.adjustHandlePoint(e), near(toView(adjust)) { return (e.id, .adjust) }
        if near(rotateHandleView(e)) { return (e.id, .rotate) }
        for (i, p) in CanvasGeometry.handlePoints(e).enumerated() where near(toView(p)) {
            return (e.id, .resize(i))
        }
        return nil
    }

    /// A vertical border between table columns near a point.
    func columnBorder(at p: CGPoint, in e: SlideElement) -> Int? {
        guard case .table(let t) = e.content, e.frame.insetBy(dx: -2, dy: 0).contains(p), e.rotation == 0 else { return nil }
        let geo = TableGeometry(t, in: e.frame)
        for i in 1..<max(geo.xs.count - 1, 1) where abs(geo.xs[i] - p.x) < 3 / zoom { return i }
        return nil
    }

    func constrained(_ start: CGPoint, _ p: CGPoint, insert: PendingInsert) -> CGPoint {
        guard NSEvent.modifierFlags.contains(.shift) else { return p }
        let dx = p.x - start.x, dy = p.y - start.y
        if case .line = insert {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * len, y: start.y + sin(angle) * len)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }
}

/// A plain flipped view.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

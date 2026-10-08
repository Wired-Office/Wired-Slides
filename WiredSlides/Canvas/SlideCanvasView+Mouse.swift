import AppKit

extension SlideCanvasView {
    // MARK: - Mouse down

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = toSlide(viewPoint)
        let slide = controller.currentSlide
        let tolerance = 4 / zoom
        let shift = event.modifierFlags.contains(.shift), command = event.modifierFlags.contains(.command)
        window?.makeFirstResponder(self)

        if let insert = controller.pendingInsert {
            controller.commitTextEditing()
            dragMode = .draw(start: p, current: p, insert: insert)
            return
        }

        // Handles of the selection come first.
        if let (id, handle) = handleHit(viewPoint), let e = slide.element(id) {
            controller.commitTextEditing()
            controller.beginInteractiveChange()
            switch handle {
            case .resize(let i): dragMode = .resize(handle: i, original: e)
            case .rotate:
                let c = toView(CGPoint(x: e.frame.midX, y: e.frame.midY))
                dragMode = .rotate(original: e, startAngle: atan2(viewPoint.y - c.y, viewPoint.x - c.x))
            case .adjust: dragMode = .adjust(original: e)
            case .lineStart: dragMode = .lineEnd(start: true, original: e)
            case .lineEnd: dragMode = .lineEnd(start: false, original: e)
            }
            return
        }

        // Table borders and cells.
        if let (id, table) = controller.selectedTable, let e = slide.element(id) {
            if let column = columnBorder(at: p, in: e) {
                controller.commitTextEditing()
                controller.beginInteractiveChange()
                dragMode = .column(elementID: id, index: column, original: e)
                return
            }
            if CanvasGeometry.contains(e, p, tolerance: 0), let cell = TableGeometry(table, in: e.frame).cell(at: CanvasGeometry.localPoint(p, in: e)) {
                let address = mergedOrigin(table, TableCellAddress(row: cell.row, column: cell.column))
                if shift, let range = controller.cellSelection {
                    controller.commitTextEditing()
                    controller.cellSelection = TableCellRange(start: range.start, end: address)
                    return
                }
                controller.cellSelection = TableCellRange(start: address, end: address)
                if controller.editingCell != address || controller.editingElement != id {
                    beginEditing(id, cell: address, selectAll: false)
                    textSession.placeCaret(atSlidePoint: p)
                }
                dragMode = .cells(elementID: id, start: address)
                return
            }
        }

        // Clicking the insert icons of an empty content placeholder.
        if let (placeholder, kind) = placeholderIcon(at: p) {
            controller.select([placeholder.id])
            runPlaceholderAction(kind, placeholder: placeholder)
            return
        }

        if let comment = slide.comments.first(where: { !$0.resolved && CGRect(x: $0.position.x, y: $0.position.y - 22 / zoom, width: 22 / zoom, height: 20 / zoom).contains(p) }) {
            controller.sidePane = .comments
            NotificationCenter.default.post(name: .wsFocusComment, object: comment.id)
            return
        }

        guard let hit = CanvasGeometry.hit(slide.elements, at: p, tolerance: tolerance) else {
            controller.commitTextEditing()
            if !shift && !command { controller.clearSelection() }
            controller.cellSelection = nil
            dragMode = .marquee(start: p, current: p, extend: shift || command)
            return
        }

        if controller.formatPainter != nil {
            controller.paintFormat(onto: controller.selectedChild ?? hit.id)
            return
        }

        if event.clickCount >= 2 {
            doubleClick(hit, at: p)
            return
        }

        if shift || command {
            controller.select([hit.id], extend: true)
            return
        }

        // A click on a selected group drills into the member under the pointer.
        if hit.isGroup, controller.selection == [hit.id], case .group(let g) = hit.content {
            let local = CanvasGeometry.localPoint(p, in: hit)
            if let child = CanvasGeometry.hit(g.children, at: local, tolerance: tolerance) {
                controller.selectChild(child.id)
                return
            }
        }
        // A click in the text of a selected text box goes straight into editing.
        if controller.selection == [hit.id], controller.editingElement != hit.id, hit.text != nil, !hit.isGroup,
           ElementRenderer.textRect(hit, hit.shape!).insetBy(dx: 4, dy: 4).contains(CanvasGeometry.localPoint(p, in: hit)),
           hit.hasText || hit.placeholder != nil {
            beginEditing(hit.id, cell: nil, selectAll: false)
            textSession.placeCaret(atSlidePoint: p)
            return
        }
        if controller.editingElement != nil && controller.editingElement != hit.id { controller.commitTextEditing() }
        if !controller.selection.contains(hit.id) {
            controller.select([hit.id])
        } else if controller.selectedChild != nil, !hit.isGroup {
            controller.selectChild(nil)
        }
        controller.cellSelection = nil
        dragMode = .pendingMove(start: p, duplicate: event.modifierFlags.contains(.option))
    }

    private func mergedOrigin(_ table: TableContent, _ cell: TableCellAddress) -> TableCellAddress {
        guard table.rows[cell.row][cell.column].isMerged else { return cell }
        for r in stride(from: cell.row, through: 0, by: -1) {
            for c in stride(from: cell.column, through: 0, by: -1) {
                let candidate = table.rows[r][c]
                if !candidate.isMerged && r + candidate.rowSpan > cell.row && c + candidate.columnSpan > cell.column {
                    return TableCellAddress(row: r, column: c)
                }
            }
        }
        return cell
    }

    private func doubleClick(_ e: SlideElement, at p: CGPoint) {
        switch e.content {
        case .shape:
            beginEditing(e.id, cell: nil, selectAll: !e.hasText)
            textSession.selectWord(atSlidePoint: p)
        case .chart:
            controller.select([e.id])
            controller.presenter?.presentChartEditor(e.id)
        case .group(let g):
            let local = CanvasGeometry.localPoint(p, in: e)
            if let child = CanvasGeometry.hit(g.children, at: local, tolerance: 4 / zoom) {
                controller.select([e.id])
                controller.selectChild(child.id)
                if child.text != nil { beginEditing(child.id, cell: nil, selectAll: false) }
            }
        case .image, .media, .icon, .line:
            controller.select([e.id])
            controller.sidePane = .format
        case .table:
            break
        }
    }

    // MARK: - Dragging

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        var p = toSlide(viewPoint)
        autoscroll(with: event)
        switch dragMode {
        case .none:
            return
        case .pendingMove(let start, let duplicate):
            guard hypot(p.x - start.x, p.y - start.y) * zoom > 3 else { return }
            let movable = controller.selectedElements.filter { !$0.locked }
            guard !movable.isEmpty else { dragMode = .none; return }
            controller.beginInteractiveChange()
            var originals = movable
            if duplicate {
                let copies = movable.map { e -> SlideElement in var c = e.duplicated(); c.placeholder = nil; return c }
                let index = controller.currentSlideIndex
                controller.updateInteractive { pres in pres.slides[index].elements.append(contentsOf: copies) }
                controller.selection = copies.map(\.id)
                originals = copies
            }
            dragMode = .move(start: start, originals: originals)
            mouseDragged(with: event)
        case .move(let start, let originals):
            var d = CGSize(width: p.x - start.x, height: p.y - start.y)
            if event.modifierFlags.contains(.shift) {
                if abs(d.width) > abs(d.height) { d.height = 0 } else { d.width = 0 }
            }
            let bounds = originals.map { SlideRenderer.rotatedBounds($0.frame, rotation: $0.rotation) }.reduce(CGRect.null) { $0.union($1) }
            let snapped = snap(bounds.offsetBy(dx: d.width, dy: d.height), excluding: Set(originals.map(\.id)), disable: event.modifierFlags.contains(.command))
            d.width += snapped.width
            d.height += snapped.height
            let index = controller.currentSlideIndex
            let ids = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) })
            controller.updateInteractive { pres in
                for i in pres.slides[index].elements.indices {
                    guard let original = ids[pres.slides[index].elements[i].id] else { continue }
                    var moved = original
                    moved.offset(by: d)
                    pres.slides[index].elements[i] = moved
                }
            }
            controller.statusMessage = String(format: "Position: %.0f, %.0f pt", (bounds.minX + d.width), (bounds.minY + d.height))
        case .resize(let handle, let original):
            let local = CanvasGeometry.localPoint(p, in: original)
            let keepAspect = event.modifierFlags.contains(.shift) != (original.lockAspectRatio && handle % 2 == 0)
            var frame = CanvasGeometry.resize(original.frame, handle: handle, to: snapPoint(local, excluding: [original.id], enabled: original.rotation == 0),
                                              keepAspect: keepAspect, fromCenter: event.modifierFlags.contains(.option))
            frame.size.width = max(frame.width, 1)
            frame.size.height = max(frame.height, 1)
            // Keep the opposite handle where it was when rotated.
            if original.rotation != 0 && !event.modifierFlags.contains(.option) {
                var temp = original
                temp.frame = frame
                let anchor = (handle + 4) % 8
                let before = CanvasGeometry.handlePoints(original)[anchor], after = CanvasGeometry.handlePoints(temp)[anchor]
                frame = frame.offsetBy(dx: before.x - after.x, dy: before.y - after.y)
            }
            let id = original.id
            let theme = controller.theme
            let s = controller.currentSlideIndex
            controller.updateInteractive { pres in
                Self.updateElement(&pres.slides[s], id) { e in
                    var resized = original
                    resized.setFrame(frame)
                    PresentationController.fitHeight(&resized, theme: theme)
                    e = resized
                }
            }
            controller.statusMessage = String(format: "Size: %.0f × %.0f pt", frame.width, frame.height)
        case .rotate(let original, let startAngle):
            let c = toView(CGPoint(x: original.frame.midX, y: original.frame.midY))
            let angle = atan2(viewPoint.y - c.y, viewPoint.x - c.x)
            var degrees = original.rotation + Double((angle - startAngle) * 180 / .pi)
            if event.modifierFlags.contains(.shift) { degrees = (degrees / 15).rounded() * 15 }
            degrees = degrees.truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            let id = original.id
            let s = controller.currentSlideIndex
            controller.updateInteractive { pres in Self.updateElement(&pres.slides[s], id) { $0.rotation = degrees } }
            controller.statusMessage = String(format: "Rotation: %.0f°", degrees)
        case .adjust(let original):
            guard case .shape(let shape) = original.content else { return }
            let local = CanvasGeometry.localPoint(p, in: original)
            let values = ShapeGeometry.adjust(shape.kind, in: original.frame, adjustments: shape.resolvedAdjustments, to: local)
            let s = controller.currentSlideIndex
            controller.updateInteractive { pres in
                Self.updateElement(&pres.slides[s], original.id) { e in
                    if case .shape(var sh) = e.content { sh.adjustments = values; e.content = .shape(sh) }
                }
            }
        case .lineEnd(let isStart, let original):
            let ends = original.lineEndpoints
            let t = CanvasGeometry.rotationTransform(original)
            let fixed = (isStart ? ends.end : ends.start).applying(t)
            if event.modifierFlags.contains(.shift) {
                let dx = p.x - fixed.x, dy = p.y - fixed.y
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let len = hypot(dx, dy)
                p = CGPoint(x: fixed.x + cos(angle) * len, y: fixed.y + sin(angle) * len)
            } else {
                p = snapToConnectionSite(p, excluding: original.id)
            }
            let s = controller.currentSlideIndex
            controller.updateInteractive { pres in
                Self.updateElement(&pres.slides[s], original.id) { e in
                    e.rotation = 0
                    if isStart { e.setLineEndpoints(p, fixed) } else { e.setLineEndpoints(fixed, p) }
                }
            }
        case .marquee(let start, _, let extend):
            dragMode = .marquee(start: start, current: p, extend: extend)
            needsDisplay = true
        case .draw(let start, _, let insert):
            dragMode = .draw(start: start, current: p, insert: insert)
            needsDisplay = true
        case .cells(let id, let start):
            guard let (_, table) = controller.selectedTable, let e = controller.currentSlide.element(id),
                  let cell = TableGeometry(table, in: e.frame).cell(at: CanvasGeometry.localPoint(p, in: e)) else { return }
            let end = TableCellAddress(row: cell.row, column: cell.column)
            if end != start {
                if controller.editingCell != nil { controller.commitTextEditing() }
                controller.select([id])
                controller.cellSelection = TableCellRange(start: start, end: end)
            }
        case .column(let id, let index, let original):
            guard case .table(var t) = original.content else { return }
            let geo = TableGeometry(t, in: original.frame)
            let minWidth: CGFloat = 12
            let x = max(geo.xs[index - 1] + minWidth, min(p.x, geo.xs[index + 1] - minWidth))
            let scale = Double(original.frame.width) / max(t.columnWidths.reduce(0, +), 1)
            let left = Double(x - geo.xs[index - 1]) / scale
            let pairTotal = t.columnWidths[index - 1] + t.columnWidths[index]
            t.columnWidths[index - 1] = left
            t.columnWidths[index] = pairTotal - left
            let theme = controller.theme
            t.rowHeights = TableRenderer.fittedRowHeights(t, width: original.frame.width, theme: theme)
            let s = controller.currentSlideIndex
            controller.updateInteractive { pres in
                Self.updateElement(&pres.slides[s], id) { e in
                    e.content = .table(t)
                    e.frame.size.height = CGFloat(t.rowHeights.reduce(0, +))
                }
            }
        }
    }

    static func updateElement(_ slide: inout Slide, _ id: UUID, _ body: (inout SlideElement) -> Void) {
        func visit(_ e: inout SlideElement) -> Bool {
            if e.id == id { body(&e); return true }
            if case .group(var g) = e.content {
                for i in g.children.indices where visit(&g.children[i]) {
                    e.content = .group(g)
                    e.frame = g.children.map(\.frame).reduce(CGRect.null) { $0.union($1) }
                    return true
                }
            }
            return false
        }
        for i in slide.elements.indices where visit(&slide.elements[i]) { return }
    }

    // MARK: - Mouse up

    override func mouseUp(with event: NSEvent) {
        let mode = dragMode
        dragMode = .none
        guides = []
        controller.statusMessage = nil
        switch mode {
        case .move(_, let originals):
            controller.endInteractiveChange(originals.count > 1 ? "Move Objects" : "Move")
        case .resize: controller.endInteractiveChange("Resize")
        case .rotate: controller.endInteractiveChange("Rotate")
        case .adjust: controller.endInteractiveChange("Adjust Shape")
        case .lineEnd: controller.endInteractiveChange("Move Line End")
        case .column: controller.endInteractiveChange("Column Width")
        case .marquee(let start, let current, let extend):
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
            if r.width * zoom > 2 || r.height * zoom > 2 {
                let ids = controller.currentSlide.elements.filter { e in
                    !e.locked && !e.hidden && r.contains(SlideRenderer.rotatedBounds(e.frame, rotation: e.rotation).insetBy(dx: 0.5, dy: 0.5))
                }.map(\.id)
                controller.select(ids, extend: extend)
            }
        case .draw(let start, let current, let insert):
            finishDrawing(start: start, end: constrained(start, current, insert: insert), insert: insert, keepTool: event.modifierFlags.contains(.command))
        case .pendingMove(let start, _):
            // A plain click on a link in the slide follows it with ⌘.
            if event.modifierFlags.contains(.command), let e = CanvasGeometry.hit(controller.currentSlide.elements, at: start, tolerance: 4 / zoom),
               case .url(let url) = e.action, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        default:
            break
        }
        needsDisplay = true
    }

    private func finishDrawing(start: CGPoint, end: CGPoint, insert: PendingInsert, keepTool: Bool) {
        var rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let tiny = rect.width * zoom < 4 && rect.height * zoom < 4
        if !keepTool { controller.pendingInsert = nil }
        switch insert {
        case .shape(let kind):
            if tiny { rect = CGRect(x: start.x - 50, y: start.y - 50, width: 100, height: 100) }
            controller.insertShape(kind, frame: rect)
        case .textBox, .verticalTextBox:
            if tiny || rect.width < 20 { rect = CGRect(x: start.x, y: start.y, width: 240, height: 30) }
            controller.insertTextBox(frame: rect, vertical: insert == .verticalTextBox)
        case .line(let kind, let arrow):
            let e = tiny ? CGPoint(x: start.x + 120, y: start.y) : end
            controller.insertLine(from: start, to: e, kind: kind, arrow: arrow)
        }
    }

    // MARK: - Snapping

    /// Snaps a moving rectangle to the slide, other objects and the grid. Returns the extra offset.
    func snap(_ r: CGRect, excluding: Set<UUID>, disable: Bool) -> CGSize {
        guides = []
        guard !disable else { return .zero }
        let settings = AppSettings.shared
        let threshold = 5 / zoom
        var xs: [CGFloat] = [0, slideSize.width / 2, slideSize.width]
        var ys: [CGFloat] = [0, slideSize.height / 2, slideSize.height]
        let others = controller.currentSlide.elements.filter { !excluding.contains($0.id) && !$0.hidden }
        if settings.smartGuides {
            for e in others {
                let b = SlideRenderer.rotatedBounds(e.frame, rotation: e.rotation)
                xs += [b.minX, b.midX, b.maxX]
                ys += [b.minY, b.midY, b.maxY]
            }
        }
        var dx: CGFloat = 0, dy: CGFloat = 0
        var bestX = threshold, bestY = threshold
        var guideX: CGFloat?, guideY: CGFloat?
        for edge in [r.minX, r.midX, r.maxX] {
            for x in xs where abs(x - edge) < bestX { bestX = abs(x - edge); dx = x - edge; guideX = x }
        }
        for edge in [r.minY, r.midY, r.maxY] {
            for y in ys where abs(y - edge) < bestY { bestY = abs(y - edge); dy = y - edge; guideY = y }
        }
        if settings.snapToGrid {
            let g = CGFloat(settings.gridSpacing)
            if guideX == nil { dx = (r.minX / g).rounded() * g - r.minX }
            if guideY == nil { dy = (r.minY / g).rounded() * g - r.minY }
        }
        if let x = guideX { guides.append((CGPoint(x: x, y: 0), CGPoint(x: x, y: slideSize.height))) }
        if let y = guideY { guides.append((CGPoint(x: 0, y: y), CGPoint(x: slideSize.width, y: y))) }
        return CGSize(width: dx, height: dy)
    }

    /// Snaps a resize handle position to guides.
    func snapPoint(_ p: CGPoint, excluding: Set<UUID>, enabled: Bool) -> CGPoint {
        guard enabled, !NSEvent.modifierFlags.contains(.command) else { guides = []; return p }
        let d = snap(CGRect(origin: p, size: .zero), excluding: excluding, disable: false)
        return CGPoint(x: p.x + d.width, y: p.y + d.height)
    }

    /// Glues line ends to the edge midpoints and corners of shapes.
    func snapToConnectionSite(_ p: CGPoint, excluding: UUID) -> CGPoint {
        let threshold = 8 / zoom
        var best: CGPoint?
        var bestDistance = threshold
        for e in controller.currentSlide.elements where e.id != excluding && !e.isLine && !e.hidden {
            for site in CanvasGeometry.handlePoints(e).enumerated().filter({ $0.offset % 2 == 1 }).map(\.element) {
                let d = hypot(site.x - p.x, site.y - p.y)
                if d < bestDistance { bestDistance = d; best = site }
            }
        }
        guides = best.map { b in [(CGPoint(x: b.x - 6 / zoom, y: b.y), CGPoint(x: b.x + 6 / zoom, y: b.y)), (CGPoint(x: b.x, y: b.y - 6 / zoom), CGPoint(x: b.x, y: b.y + 6 / zoom))] } ?? []
        return best ?? p
    }

    // MARK: - Placeholder icons

    func placeholderIcon(at p: CGPoint) -> (SlideElement, String)? {
        for e in controller.currentSlide.elements where (e.placeholder == .body || e.placeholder == .picture) && !e.hasText {
            for (frame, kind) in PlaceholderIcons.frames(in: e.frame, pictureOnly: e.placeholder == .picture) where frame.contains(p) {
                return (e, kind)
            }
        }
        return nil
    }

    func runPlaceholderAction(_ kind: String, placeholder: SlideElement) {
        switch kind {
        case "table": controller.presenter?.presentInsertTable()
        case "chart": controller.insertChart(.column)
        case "smartart": controller.presenter?.presentSmartArt()
        case "picture": controller.presenter?.insertPicturesFromFile()
        case "icon": controller.presenter?.presentInsertIcon()
        case "video": controller.presenter?.insertMediaFromFile()
        default: break
        }
    }

    // MARK: - Text editing

    func beginEditing(_ id: UUID, cell: TableCellAddress?, selectAll: Bool) {
        guard let e = controller.currentSlide.element(id), !e.locked else { return }
        if controller.editingElement == id && controller.editingCell == cell { return }
        controller.commitTextEditing()
        if controller.selection != [id] && controller.selectedChild != id {
            if controller.currentSlide.elements.contains(where: { $0.id == id }) { controller.select([id]) }
        }
        textSession.begin(id, cell: cell, selectAll: selectAll)
        needsDisplay = true
    }

    // MARK: - Zoom gestures

    override func magnify(with event: NSEvent) {
        controller.fitToWindow = false
        controller.zoom = max(0.1, min(4, controller.zoom * (1 + Double(event.magnification))))
    }
}

extension Notification.Name {
    static let wsFocusComment = Notification.Name("WSFocusComment")
}

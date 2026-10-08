import AppKit

extension SlideCanvasView {
    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let selection = controller.selection
        let step: CGFloat = flags.contains(.shift) ? 10 : flags.contains(.option) ? 0.5 : 2
        switch event.specialKey {
        case .leftArrow?, .rightArrow?, .upArrow?, .downArrow?:
            guard !selection.isEmpty else {
                if event.specialKey == .leftArrow || event.specialKey == .upArrow { controller.previousSlide() } else { controller.nextSlide() }
                return
            }
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch event.specialKey {
            case .leftArrow?: dx = -step
            case .rightArrow?: dx = step
            case .upArrow?: dy = -step
            default: dy = step
            }
            if flags.contains(.command) {
                // ⌘-arrows rotate (left/right) like PowerPoint's ⌥-arrows.
                if dx != 0 { controller.rotate(by: dx > 0 ? 15 : -15) }
                return
            }
            controller.nudge(dx: dx, dy: dy)
        case .pageUp?:
            controller.previousSlide()
        case .pageDown?:
            controller.nextSlide()
        case .home?:
            controller.setCurrentSlide(0)
        case .end?:
            controller.setCurrentSlide(controller.slides.count - 1)
        case .delete?, .deleteForward?, .backspace?:
            if controller.cellSelection != nil, controller.selectedTable != nil {
                controller.changeTextBodies("Clear") { $0.setPlainText("") }
            } else {
                controller.deleteSelection()
            }
        case .tab?:
            cycleSelection(backwards: flags.contains(.shift))
        case .carriageReturn?, .enter?, .newline?:
            if let e = controller.primaryElement {
                if case .table = e.content {
                    beginEditing(e.id, cell: TableCellAddress(row: 0, column: 0), selectAll: true)
                } else if e.text != nil {
                    beginEditing(e.id, cell: nil, selectAll: true)
                } else if e.isChart {
                    controller.presenter?.presentChartEditor(e.id)
                }
            } else {
                controller.addSlide()
            }
        default:
            if event.keyCode == 53 { escape(); return }   // Escape
            // Typing with one text-capable object selected replaces its text.
            if flags.subtracting([.shift, .capsLock]).isEmpty, let chars = event.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
               let e = controller.primaryElement, controller.selection.count == 1, e.text != nil, !e.locked {
                beginEditing(e.id, cell: nil, selectAll: true)
                textSession.textView?.insertText(chars, replacementRange: textSession.textView?.selectedRange() ?? NSRange(location: 0, length: 0))
                return
            }
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { escape() }

    private func escape() {
        if controller.pendingInsert != nil { controller.pendingInsert = nil; return }
        if controller.formatPainter != nil { controller.formatPainter = nil; return }
        if controller.cellSelection != nil { controller.cellSelection = nil; return }
        if controller.selectedChild != nil { controller.selectChild(nil); return }
        controller.clearSelection()
    }

    private func cycleSelection(backwards: Bool) {
        let elements = controller.currentSlide.elements.filter { !$0.hidden }
        guard !elements.isEmpty else { return }
        let current = controller.selection.last.flatMap { id in elements.firstIndex { $0.id == id } }
        let next: Int
        if let current { next = (current + (backwards ? -1 : 1) + elements.count) % elements.count } else { next = backwards ? elements.count - 1 : 0 }
        controller.select([elements[next].id])
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = toSlide(convert(event.locationInWindow, from: nil))
        let menu = NSMenu()
        if let hit = CanvasGeometry.hit(controller.currentSlide.elements, at: p, tolerance: 4 / zoom, includeLocked: true) {
            if !controller.selection.contains(hit.id) { controller.select([hit.id]) }
            elementMenu(menu, hit)
        } else {
            controller.clearSelection()
            slideMenu(menu, at: p)
        }
        return menu
    }

    private func elementMenu(_ menu: NSMenu, _ e: SlideElement) {
        menu.add("Cut", symbol: "scissors") { [weak self] in self?.controller.copySelection(cut: true) }
        menu.add("Copy", symbol: "doc.on.doc") { [weak self] in self?.controller.copySelection() }
        menu.add("Paste", symbol: "doc.on.clipboard", enabled: controller.canPaste) { [weak self] in self?.controller.paste() }
        menu.addItem(.separator())
        if e.text != nil {
            menu.add("Edit Text", symbol: "character.cursor.ibeam") { [weak self] in self?.beginEditing(e.id, cell: nil, selectAll: false) }
        }
        if e.isChart {
            menu.add("Edit Data…", symbol: "tablecells") { [weak self] in self?.controller.presenter?.presentChartEditor(e.id) }
        }
        if e.isImage {
            menu.add("Change Picture…", symbol: "photo") { [weak self] in self?.controller.presenter?.insertPicturesFromFile() }
            menu.add("Reset Picture", symbol: "arrow.counterclockwise") { [weak self] in self?.controller.resetPicture(size: false) }
        }
        if controller.selection.count > 1 {
            menu.add("Group", symbol: "square.on.square.dashed") { [weak self] in self?.controller.group() }
        }
        if e.isGroup {
            menu.add("Ungroup", symbol: "square.on.square") { [weak self] in self?.controller.ungroup() }
        }
        let order = NSMenu(title: "Arrange")
        order.add("Bring to Front", symbol: "square.3.layers.3d.top.filled") { [weak self] in self?.controller.arrange(.front) }
        order.add("Bring Forward", symbol: "square.2.layers.3d.top.filled") { [weak self] in self?.controller.arrange(.forward) }
        order.add("Send Backward", symbol: "square.2.layers.3d.bottom.filled") { [weak self] in self?.controller.arrange(.backward) }
        order.add("Send to Back", symbol: "square.3.layers.3d.bottom.filled") { [weak self] in self?.controller.arrange(.back) }
        menu.addSubmenu(order)
        let align = NSMenu(title: "Align")
        for mode in AlignMode.allCases { align.add(mode.title, symbol: mode.symbol) { [weak self] in self?.controller.align(mode) } }
        align.addItem(.separator())
        align.add("Distribute Horizontally", symbol: "distribute.horizontal.center") { [weak self] in self?.controller.distribute(horizontally: true) }
        align.add("Distribute Vertically", symbol: "distribute.vertical.center") { [weak self] in self?.controller.distribute(horizontally: false) }
        menu.addSubmenu(align)
        menu.addItem(.separator())
        menu.add("Hyperlink…", symbol: "link") { [weak self] in self?.controller.presenter?.presentHyperlink() }
        menu.add("Action…", symbol: "cursorarrow.click.2") { [weak self] in self?.controller.presenter?.presentAction() }
        menu.add("New Comment", symbol: "text.bubble") { [weak self] in self?.controller.sidePane = .comments; NotificationCenter.default.post(name: .wsNewComment, object: nil) }
        menu.add("Animation…", symbol: "sparkles") { [weak self] in self?.controller.sidePane = .animations }
        menu.add(e.locked ? "Unlock" : "Lock", symbol: e.locked ? "lock.open" : "lock") { [weak self] in self?.controller.toggleLock() }
        menu.add("Save as Picture…", symbol: "square.and.arrow.down") { [weak self] in self?.saveSelectionAsPicture() }
        menu.addItem(.separator())
        menu.add("Format \(e.kindName)…", symbol: "paintbrush") { [weak self] in self?.controller.sidePane = .format }
    }

    private func slideMenu(_ menu: NSMenu, at p: CGPoint) {
        menu.add("Paste", symbol: "doc.on.clipboard", enabled: controller.canPaste) { [weak self] in self?.controller.paste() }
        menu.addItem(.separator())
        let layouts = NSMenu(title: "Layout")
        for layout in LayoutKind.allCases {
            layouts.add(layout.title, checked: controller.currentSlide.layout == layout) { [weak self] in self?.controller.setLayout(layout) }
        }
        menu.addSubmenu(layouts)
        menu.add("Reset Slide", symbol: "arrow.counterclockwise") { [weak self] in self?.controller.resetSlides() }
        menu.addItem(.separator())
        menu.add("Format Background…", symbol: "paintpalette") { [weak self] in
            self?.controller.sidePane = .format
            NotificationCenter.default.post(name: .wsShowBackgroundFormat, object: nil)
        }
        menu.add("Grid and Guides", symbol: "grid", checked: controller.showGridlines) { [weak self] in self?.controller.showGridlines.toggle() }
        menu.add("Guides", symbol: "plus.viewfinder", checked: controller.showGuides) { [weak self] in self?.controller.showGuides.toggle() }
        menu.addItem(.separator())
        menu.add("New Comment", symbol: "text.bubble") { [weak self] in
            self?.controller.sidePane = .comments
            NotificationCenter.default.post(name: .wsNewComment, object: NSValue(point: p))
        }
        menu.add("New Slide", symbol: "plus.rectangle") { [weak self] in self?.controller.addSlide() }
        menu.add(controller.currentSlide.hidden ? "Show Slide" : "Hide Slide", symbol: "eye.slash") { [weak self] in self?.controller.toggleHideSlides() }
    }

    private func saveSelectionAsPicture() {
        let elements = controller.selectedElements
        guard !elements.isEmpty, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (elements.first?.name ?? "Picture") + ".png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let bounds = elements.map { SlideRenderer.visualBounds($0) }.reduce(CGRect.null) { $0.union($1) }
            let scale: CGFloat = 4
            guard let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.translateBy(x: 0, y: bounds.height * scale)
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            let env = RenderEnvironment(self.controller.presentation)
            for e in elements { ElementRenderer.draw(e, ctx: ctx, env: env, options: ElementDrawOptions()) }
            if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let p = toSlide(convert(sender.draggingLocation, from: nil))
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            controller.insertFiles(urls, at: p)
            return true
        }
        if let type = pb.availableType(from: [.png, .tiff, .pdf]), let data = pb.data(forType: type) {
            controller.insertPicture(data, filename: "Dropped Image.\(type == .png ? "png" : type == .pdf ? "pdf" : "tiff")", at: p)
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let wsNewComment = Notification.Name("WSNewComment")
    static let wsShowBackgroundFormat = Notification.Name("WSShowBackgroundFormat")
}

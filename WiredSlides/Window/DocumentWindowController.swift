import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let contentController: PresentationViewController
    private var sizeLock: [NSLayoutConstraint] = []

    private static let undoItem = NSToolbarItem.Identifier("ws.undo")
    private static let redoItem = NSToolbarItem.Identifier("ws.redo")
    private static let saveItem = NSToolbarItem.Identifier("ws.save")
    private static let printItem = NSToolbarItem.Identifier("ws.print")
    private static let newSlideItem = NSToolbarItem.Identifier("ws.newSlide")
    private static let textItem = NSToolbarItem.Identifier("ws.text")
    private static let shapeItem = NSToolbarItem.Identifier("ws.shape")
    private static let tableItem = NSToolbarItem.Identifier("ws.table")
    private static let chartItem = NSToolbarItem.Identifier("ws.chart")
    private static let pictureItem = NSToolbarItem.Identifier("ws.picture")
    private static let playItem = NSToolbarItem.Identifier("ws.play")
    private static let shareItem = NSToolbarItem.Identifier("ws.share")
    private static let formatItem = NSToolbarItem.Identifier("ws.format")

    init(document: SlidesDocument) {
        contentController = PresentationViewController(controller: document.controller)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentController
        window.setContentSize(NSSize(width: 1320, height: 860))
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.tabbingIdentifier = "com.wiredslides.document-window"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = true
        window.backgroundColor = Theme.barBackground
        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "WiredSlidesToolbar1")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        shouldCascadeWindows = true
        window.center()
        lockContentSize(window.contentLayoutRect.size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Initial size

    /// AppKit's first constraint pass shrinks a new window to its fitting size; hold
    /// the intended size until that pass has run.
    private func lockContentSize(_ size: NSSize) {
        NSLayoutConstraint.deactivate(sizeLock)
        guard let content = window?.contentView else { return }
        sizeLock = [
            content.widthAnchor.constraint(equalToConstant: size.width),
            content.heightAnchor.constraint(equalToConstant: size.height),
        ]
        NSLayoutConstraint.activate(sizeLock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.releaseSizeLock() }
    }

    private func releaseSizeLock() {
        guard !sizeLock.isEmpty else { return }
        NSLayoutConstraint.deactivate(sizeLock)
        sizeLock = []
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.async { DispatchQueue.main.async { [weak self] in self?.releaseSizeLock() } }
    }

    func windowWillEnterFullScreen(_ notification: Notification) { releaseSizeLock() }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        if !sizeLock.isEmpty && !window.styleMask.contains(.fullScreen) {
            lockContentSize(window.contentLayoutRect.size)
        }
    }

    override var document: AnyObject? {
        didSet { updateSubtitle() }
    }

    func updateSubtitle() {
        guard let window, let document = document as? SlidesDocument else { return }
        var parts: [String] = []
        if let format = document.format, !format.isNative { parts.append(format.shortName) }
        if document.fileURL == nil { parts.append("Not saved") }
        window.subtitle = parts.joined(separator: " · ")
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        contentController.controller.commitTextEditing()
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.saveItem, Self.undoItem, Self.redoItem, .flexibleSpace, Self.newSlideItem, Self.textItem, Self.shapeItem, Self.tableItem,
         Self.chartItem, Self.pictureItem, .flexibleSpace, Self.formatItem, Self.playItem, Self.shareItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [Self.printItem, .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let vc = PresentationViewController.self
        func button(_ label: String, _ symbol: String, _ action: Selector, _ tip: String) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.isBordered = true
            return item
        }
        func menuItem(_ label: String, _ symbol: String, _ tip: String, _ build: () -> NSMenu) -> NSToolbarItem {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.menu = build()
            item.showsIndicator = true
            return item
        }
        switch identifier {
        case Self.saveItem: return button("Save", "square.and.arrow.down", #selector(NSDocument.save(_:)), "Save (⌘S)")
        case Self.undoItem: return button("Undo", "arrow.uturn.backward", Selector(("undo:")), "Undo (⌘Z)")
        case Self.redoItem: return button("Redo", "arrow.uturn.forward", Selector(("redo:")), "Redo (⇧⌘Z)")
        case Self.printItem: return button("Print", "printer", #selector(NSDocument.printDocument(_:)), "Print (⌘P)")
        case Self.newSlideItem: return button("New Slide", "plus.rectangle", #selector(vc.newSlide(_:)), "New Slide (⇧⌘N)")
        case Self.textItem: return button("Text Box", "character.textbox", #selector(vc.insertTextBox(_:)), "Draw a text box")
        case Self.tableItem: return button("Table", "tablecells", #selector(vc.insertTableDialog(_:)), "Insert a table")
        case Self.pictureItem: return button("Picture", "photo", #selector(vc.insertPicture(_:)), "Insert pictures")
        case Self.formatItem: return button("Format", "paintbrush", #selector(vc.formatPane(_:)), "Format pane")
        case Self.shapeItem:
            return menuItem("Shape", "square.on.circle", "Draw a shape") {
                let menu = NSMenu()
                for kind in [ShapeKind.rect, .roundRect, .ellipse, .triangle, .diamond, .rightArrow, .star5, .wedgeRoundRectCallout] {
                    let entry = NSMenuItem(title: kind.title, action: #selector(vc.insertShape(_:)), keyEquivalent: "")
                    entry.representedObject = kind.rawValue
                    entry.image = ShapeIcons.image(kind)
                    menu.addItem(entry)
                }
                menu.addItem(NSMenuItem(title: "Line", action: #selector(vc.insertLine(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Arrow", action: #selector(vc.insertArrow(_:)), keyEquivalent: ""))
                return menu
            }
        case Self.chartItem:
            return menuItem("Chart", "chart.bar", "Insert a chart") {
                let menu = NSMenu()
                for kind in ChartKind.allCases {
                    let entry = NSMenuItem(title: kind.title, action: #selector(vc.insertChart(_:)), keyEquivalent: "")
                    entry.representedObject = kind.rawValue
                    entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                    menu.addItem(entry)
                }
                return menu
            }
        case Self.playItem:
            let item = menuItem("Play", "play.fill", "Play the slide show") {
                let menu = NSMenu()
                menu.addItem(NSMenuItem(title: "Play from Beginning", action: #selector(vc.playFromBeginning(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Play from Current Slide", action: #selector(vc.playFromCurrent(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Presenter View", action: #selector(vc.playWithPresenter(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Reading View", action: #selector(vc.readingView(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Rehearse Timings", action: #selector(vc.rehearseTimings(_:)), keyEquivalent: ""))
                return menu
            }
            (item as? NSMenuToolbarItem)?.action = #selector(vc.playFromCurrent(_:))
            return item
        case Self.shareItem:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.label = "Share"
            item.delegate = self
            return item
        default:
            return nil
        }
    }
}

extension DocumentWindowController: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let document = document as? SlidesDocument, let url = document.fileURL else { return [] }
        return [url]
    }
}

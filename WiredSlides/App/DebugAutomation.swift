#if DEBUG
import AppKit

/// Appends a line to ws-debug.log in the temporary directory.
func debugLog(_ message: String) {
    let line = message + "\n"
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-debug.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

/// Debug-only launch hooks for exercising the UI without a mouse:
///
///     "Wired Slides.app/Contents/MacOS/Wired Slides" -WSTemplate pitch -WSScript "slide 2; snapshot /tmp/a.png"
///
/// Commands are separated by semicolons and run 0.6 seconds apart.
enum DebugAutomation {
    static func runIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        guard let templateID = defaults.string(forKey: "WSTemplate") else { return false }
        let template = (TemplateLibrary.content + TemplateLibrary.themes).first { $0.id == templateID } ?? TemplateLibrary.blank(ThemeLibrary.wired)
        if let path = defaults.string(forKey: "WSOpen") {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
        } else {
            (NSDocumentController.shared as? SlidesDocumentController)?.newDocument(from: template)
        }
        if let script = defaults.string(forKey: "WSScript") {
            let commands = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            run(commands, index: 0)
        }
        return true
    }

    private static func run(_ commands: [String], index: Int) {
        guard index < commands.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            perform(commands[index])
            run(commands, index: index + 1)
        }
    }

    /// Writes a window's contents to a PNG without screen recording permission.
    static func snapshot(_ window: NSWindow?, to path: String) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        debugLog("snapshot \(path)")
    }

    private static func perform(_ command: String) {
        let window = NSApp.orderedWindows.first { $0.windowController is DocumentWindowController }
        let vc = (window?.windowController as? DocumentWindowController)?.contentController
        let controller = vc?.controller
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "snapshot":
            snapshot(window, to: argument)
        case "snapshotkey":
            snapshot(NSApp.keyWindow ?? NSApp.orderedWindows.first, to: argument)
        case "snapshotall":
            for (i, w) in NSApp.orderedWindows.enumerated() where w.isVisible { snapshot(w, to: argument.replacingOccurrences(of: ".png", with: "-\(i).png")) }
        case "slide":
            controller?.setCurrentSlide((Int(argument) ?? 1) - 1)
        case "select":
            if let i = Int(argument), let c = controller, c.currentSlide.elements.indices.contains(i) { c.select([c.currentSlide.elements[i].id]) }
        case "edit":
            if let c = controller, let id = c.selection.first { c.beginEditing(id) }
        case "type":
            (window?.firstResponder as? NSTextView)?.insertText(argument, replacementRange: (window?.firstResponder as? NSTextView)?.selectedRange() ?? NSRange())
        case "commit":
            controller?.commitTextEditing()
        case "ribbon":
            if let tab = RibbonModel.Tab(rawValue: argument) { vc?.ribbonModel.tab = tab }
        case "pane":
            controller?.sidePane = SidePane(rawValue: argument)
        case "view":
            controller?.viewMode = ViewMode(rawValue: argument) ?? .normal
        case "theme":
            if let theme = ThemeLibrary.all.first(where: { $0.id == argument }) { controller?.applyTheme(theme) }
        case "shape":
            if let kind = ShapeKind(rawValue: argument) { controller?.insertShape(kind) }
        case "chart":
            if let kind = ChartKind(rawValue: argument) { controller?.insertChart(kind); vc?.dismiss(vc?.presentedViewControllers?.first ?? NSViewController()) }
        case "table":
            controller?.insertTable(rows: 4, columns: 3)
        case "smartart":
            if let kind = SmartArtKind(rawValue: argument) { controller?.insertSmartArt(kind, items: []) }
        case "transition":
            if let kind = TransitionKind(rawValue: argument) { controller?.setTransition({ $0.kind = kind }) }
        case "animate":
            if let effect = AnimationEffect(rawValue: argument) { controller?.addAnimation(effect, replacing: true) }
        case "show":
            vc?.startSlideShow(from: controller?.currentSlideIndex ?? 0, presenter: argument == "presenter", rehearse: false)
        case "next":
            NSApp.keyWindow?.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                                              windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                                              characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!)
        case "esc":
            NSApp.keyWindow?.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                                              windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                                              characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        case "save":
            if let doc = controller?.document {
                doc.save(to: URL(fileURLWithPath: argument), ofType: argument.hasSuffix(".pptx") ? DocumentFormat.pptx.typeIdentifier : DocumentFormat.wslides.typeIdentifier,
                         for: .saveToOperation) { error in debugLog("save \(argument): \(error?.localizedDescription ?? "ok")") }
            }
        case "pdf":
            if let p = controller?.presentation { try? PDFExporter.write(p, to: URL(fileURLWithPath: argument), options: PrintOptions.shared); debugLog("pdf \(argument)") }
        case "dark":
            NSApp.appearance = NSAppearance(named: argument == "off" ? .aqua : .darkAqua)
        case "zoom":
            controller?.fitToWindow = false
            controller?.zoom = Double(argument) ?? 1
        case "quit":
            NSApp.terminate(nil)
        default:
            debugLog("unknown command \(command)")
        }
    }
}
#endif

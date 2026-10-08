import AppKit
import UniformTypeIdentifiers

/// A presentation document. NSDocument supplies autosave, versions, crash recovery,
/// Open Recent, Duplicate/Rename/Move and Revert.
final class SlidesDocument: NSDocument {
    let controller: PresentationController
    /// The format the file was read from (or last saved as).
    private(set) var format: DocumentFormat?

    override init() {
        var presentation = Presentation(theme: ThemeLibrary.default)
        presentation.author = AppSettings.shared.authorName
        controller = PresentationController(presentation: presentation)
        super.init()
        controller.document = self
        undoManager?.levelsOfUndo = 200
    }

    override class var autosavesInPlace: Bool { AppSettings.shared.autoSave }
    override class var preservesVersions: Bool { true }

    override class var readableTypes: [String] { DocumentFormat.allCases.map(\.typeIdentifier) }
    override class var writableTypes: [String] { DocumentFormat.allCases.map(\.typeIdentifier) }
    override class func isNativeType(_ type: String) -> Bool { type == DocumentFormat.wslides.typeIdentifier }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: - Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let format = DocumentFormat.from(typeName: typeName) else {
            throw SlidesError.unsupportedFormat("Wired Slides can't open files of type \(typeName).")
        }
        let presentation = try format.read(data)
        self.format = format
        controller.load(presentation)
        undoManager?.removeAllActions()
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let format = DocumentFormat.from(typeName: typeName) else {
            throw SlidesError.unsupportedFormat("Wired Slides can't save files of type \(typeName).")
        }
        controller.commitTextEditing()
        return try format.write(controller.presentation)
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, saveOperation != .autosaveElsewhereOperation, saveOperation != .saveToOperation {
                self?.format = DocumentFormat.from(typeName: typeName)
                (self?.windowControllers.first as? DocumentWindowController)?.updateSubtitle()
            }
            completionHandler(error)
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.isExtensionHidden = false
        return true
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        (windowControllers.first as? DocumentWindowController)?.updateSubtitle()
    }

    var windowController: DocumentWindowController? { windowControllers.first as? DocumentWindowController }

    // MARK: - Printing and export

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        controller.commitTextEditing()
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        let options = PrintOptions.shared
        let view = PresentationPrintView(presentation: controller.presentation, printInfo: info, options: options)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsOrientation, .showsScaling, .showsPreview, .showsPaperSize, .showsPageRange, .showsCopies])
        operation.printPanel.addAccessoryController(PrintAccessoryController(view: view))
        return operation
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        controller.commitTextEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try PDFExporter.write(self.controller.presentation, to: url, options: PrintOptions.shared)
            } catch {
                self.presentError(error)
            }
        }
    }

    @objc func exportPowerPoint(_ sender: Any?) {
        export(.pptx)
    }

    func export(_ format: DocumentFormat) {
        guard let window = windowControllers.first?.window else { return }
        controller.commitTextEditing()
        let panel = NSSavePanel()
        if let type = UTType(format.typeIdentifier) { panel.allowedContentTypes = [type] }
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + "." + format.fileExtension
        if format == .pptx { panel.message = "Animations aren't exported. Charts and icons become pictures." }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try format.write(self.controller.presentation).write(to: url, options: .atomic)
            } catch {
                self.presentError(error)
            }
        }
    }

    /// Saves every slide as a PNG or JPEG into a folder.
    @objc func exportImages(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        controller.commitTextEditing()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for the slide images."
        let accessory = ImageExportAccessory()
        panel.accessoryView = accessory.view
        panel.isAccessoryViewDisclosed = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let folder = panel.url, let self else { return }
            let base = (self.displayName as NSString).deletingPathExtension
            let p = self.controller.presentation
            let width = accessory.width
            for (i, slide) in p.slides.enumerated() {
                guard let cg = SlideRenderer.cgImage(slide, number: i + 1, presentation: p, pixelWidth: width) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let data = accessory.jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) : rep.representation(using: .png, properties: [:])
                let name = String(format: "%@ %03d.%@", base, i + 1, accessory.jpeg ? "jpg" : "png")
                try? data?.write(to: folder.appendingPathComponent(name))
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// Exports the presentation as a movie with each slide's timing.
    @objc func exportMovie(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        controller.commitTextEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".mp4"
        panel.message = "Each slide shows for its \"After\" time (or 5 seconds), with fades between slides."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.controller.flash("Exporting movie…")
            MovieExporter.export(self.controller.presentation, to: url) { error in
                DispatchQueue.main.async {
                    if let error { self.presentError(error) } else {
                        self.controller.flash("Movie exported")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
    }

    @objc func exportOutline(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        controller.commitTextEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rtf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".rtf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let outline = OutlineExporter.attributedOutline(self.controller.presentation)
            if let data = try? outline.data(from: NSRange(location: 0, length: outline.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                try? data.write(to: url)
            }
        }
    }
}

/// Size and format choices for Export ▸ Images.
final class ImageExportAccessory {
    let view: NSView
    private let sizePopUp = NSPopUpButton()
    private let formatPopUp = NSPopUpButton()

    init() {
        sizePopUp.addItems(withTitles: ["1280 pixels wide (HD)", "1920 pixels wide (Full HD)", "3840 pixels wide (4K)"])
        sizePopUp.selectItem(at: 1)
        formatPopUp.addItems(withTitles: ["PNG", "JPEG"])
        let stack = NSStackView(views: [NSTextField(labelWithString: "Format:"), formatPopUp, NSTextField(labelWithString: "Size:"), sizePopUp])
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view = stack
    }

    var width: CGFloat { [1280, 1920, 3840][max(sizePopUp.indexOfSelectedItem, 0)] }
    var jpeg: Bool { formatPopUp.indexOfSelectedItem == 1 }
}

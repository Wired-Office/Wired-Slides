import AppKit
import AVKit
import CoreImage
import UniformTypeIdentifiers
import Vision

private func hostWindow(_ controller: PresentationController) -> NSWindow? {
    controller.document?.windowControllers.first?.window ?? NSApp.keyWindow
}

/// Creates one slide per picture.
enum PhotoAlbum {
    static func run(_ controller: PresentationController) {
        guard let window = hostWindow(controller) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose pictures for the album. Each picture gets its own slide."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            for url in panel.urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { continue }
                controller.addSlide(layout: .blank)
                var media = ""
                controller.change("Photo Album") { p in media = p.addMedia(data, filename: url.lastPathComponent) }
                let size = ImageCache.size(media, controller.presentation.media) ?? CGSize(width: 4, height: 3)
                let slide = controller.slideSize
                let s = min((slide.width - 60) / size.width, (slide.height - 60) / size.height)
                let frame = CGRect(x: (slide.width - size.width * s) / 2, y: (slide.height - size.height * s) / 2, width: size.width * s, height: size.height * s)
                var e = SlideElement(name: url.deletingPathExtension().lastPathComponent, frame: frame, content: .image(ImageContent(mediaID: media)))
                e.lockAspectRatio = true
                e.altText = url.deletingPathExtension().lastPathComponent
                controller.insert([e], name: "Photo Album")
            }
            controller.clearSelection()
        }
    }
}

/// Builds slides from a text outline: unindented lines are titles, indented lines bullets.
enum SlidesFromOutline {
    static func run(_ controller: PresentationController) {
        guard let window = hostWindow(controller) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .rtf, UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "Each line without indentation becomes a slide title; indented lines (or lines starting with -, * or •) become bullets."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let text: String
            if url.pathExtension.lowercased() == "rtf", let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                text = attributed.string
            } else {
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            insert(outline: text, into: controller)
        }
    }

    static func insert(outline text: String, into controller: PresentationController) {
        var slides: [(title: String, bullets: [(Int, String)])] = []
        for raw in text.components(separatedBy: .newlines) {
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indent = raw.prefix { $0 == "\t" || $0 == " " }
            let level = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 4
            var line = raw.trimmingCharacters(in: .whitespaces)
            let isBullet = level > 0 || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
            if line.hasPrefix("#") { line = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            if isBullet, !slides.isEmpty {
                for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) { line.removeFirst(2) }
                slides[slides.count - 1].bullets.append((max(level - 1, 0), line))
            } else {
                slides.append((line, []))
            }
        }
        guard !slides.isEmpty else { NSSound.beep(); return }
        let theme = controller.theme, size = controller.slideSize
        let insertAt = controller.currentSlideIndex + 1
        controller.change("Slides from Outline") { p in
            var new: [Slide] = []
            for entry in slides {
                var slide = LayoutBuilder.makeSlide(entry.bullets.isEmpty ? .sectionHeader : .titleContent, theme: theme, size: size)
                for i in slide.elements.indices {
                    if slide.elements[i].placeholder?.isTitle == true { slide.elements[i].text?.setPlainText(entry.title) }
                    if slide.elements[i].placeholder == .body, !entry.bullets.isEmpty, var body = slide.elements[i].text {
                        let style = body.paragraphs.first?.style ?? .plain
                        body.paragraphs = entry.bullets.map { level, text in
                            var s = style
                            s.level = level
                            return Paragraph(text, style: s)
                        }
                        slide.elements[i].text = body
                    }
                }
                new.append(slide)
            }
            p.slides.insert(contentsOf: new, at: insertAt)
        }
        controller.setCurrentSlide(insertAt)
    }
}

/// Inserts the slides of another presentation.
enum ReuseSlides {
    static func run(_ controller: PresentationController) {
        guard let window = hostWindow(controller) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentFormat.allCases.compactMap { UTType($0.typeIdentifier) }
        panel.message = "Choose a presentation. Its slides are inserted after the current slide, in this presentation's theme."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
                  let format = DocumentFormat.allCases.first(where: { $0.fileExtension == url.pathExtension.lowercased() }) else { return }
            do {
                let other = try format.read(data)
                let insertAt = controller.currentSlideIndex + 1
                controller.change("Reuse Slides") { p in
                    var map: [String: String] = [:]
                    for (id, item) in other.media { map[id] = p.addMedia(item.data, filename: item.filename) }
                    let slides = other.slides.map { slide -> Slide in
                        var s = slide
                        s.id = UUID()
                        for i in s.elements.indices { PresentationController.remapMedia(&s.elements[i], map) }
                        if case .image(var f)? = s.background, let n = map[f.mediaID] { f.mediaID = n; s.background = .image(f) }
                        return s
                    }
                    p.slides.insert(contentsOf: slides, at: insertAt)
                }
                controller.setCurrentSlide(insertAt)
            } catch {
                NSApp.presentError(error)
            }
        }
    }
}

/// Turns a bulleted text box into a SmartArt diagram.
enum SmartArtConversion {
    static func convertSelection(_ controller: PresentationController, to kind: SmartArtKind) {
        controller.commitTextEditing()
        guard let e = controller.primaryElement, let text = e.text, !text.isEmpty else {
            controller.presenter?.presentSmartArt()
            return
        }
        let items = text.paragraphs.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var group = SmartArtBuilder.build(kind, items: items, in: e.frame)
        group.name = kind.title
        let id = e.id
        controller.changeSlide("Convert to SmartArt") { slide in
            if let i = slide.index(of: id) { slide.elements[i] = group }
        }
        controller.select([group.id])
    }
}

enum ReplaceFonts {
    static func run(_ controller: PresentationController) {
        guard let window = hostWindow(controller) else { return }
        let alert = NSAlert()
        alert.messageText = "Replace Font"
        alert.informativeText = "Replace every use of one font with another."
        let from = NSPopUpButton(), to = NSPopUpButton()
        from.addItems(withTitles: controller.usedFonts)
        to.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        to.selectItem(withTitle: "Helvetica Neue")
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Replace:"), from], [NSTextField(labelWithString: "With:"), to]])
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        alert.accessoryView = grid
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, let a = from.titleOfSelectedItem, let b = to.titleOfSelectedItem else { return }
            controller.replaceFont(a, with: b)
        }
    }
}

enum WordCount {
    static func show(_ controller: PresentationController) {
        var words = 0, characters = 0, notesWords = 0
        for slide in controller.slides {
            for text in slide.elements.flatMap(\.allText) {
                words += text.split { $0.isWhitespace || $0.isNewline }.count
                characters += text.count
            }
            notesWords += slide.notes.split { $0.isWhitespace || $0.isNewline }.count
        }
        let alert = NSAlert()
        alert.messageText = "Word Count"
        alert.informativeText = """
        Slides: \(controller.slides.count) (\(controller.slides.filter(\.hidden).count) hidden)
        Words on slides: \(words)
        Characters on slides: \(characters)
        Words in notes: \(notesWords)
        Pictures and media: \(controller.presentation.media.count)
        """
        if let window = hostWindow(controller) { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

enum AccessibilityChecker {
    struct Issue {
        let slide: Int
        let element: UUID?
        let message: String
    }

    static func issues(_ p: Presentation) -> [Issue] {
        var result: [Issue] = []
        var titles: [String: Int] = [:]
        for (i, slide) in p.slides.enumerated() {
            let title = slide.title
            if !slide.elements.contains(where: { $0.placeholder?.isTitle == true && $0.hasText }) {
                result.append(Issue(slide: i, element: nil, message: "Slide \(i + 1) has no title."))
            } else if let first = titles[title] {
                result.append(Issue(slide: i, element: nil, message: "Slide \(i + 1) has the same title as slide \(first + 1)."))
            } else {
                titles[title] = i
            }
            for e in slide.elements where e.altText.isEmpty && !e.locked {
                switch e.content {
                case .image, .chart, .media, .icon, .group:
                    result.append(Issue(slide: i, element: e.id, message: "Slide \(i + 1): \(e.name) is missing alternative text."))
                default:
                    break
                }
            }
        }
        return result
    }

    static func show(_ controller: PresentationController) {
        let found = issues(controller.presentation)
        let alert = NSAlert()
        alert.messageText = found.isEmpty ? "No accessibility issues found" : "\(found.count) accessibility issue\(found.count == 1 ? "" : "s")"
        alert.informativeText = found.isEmpty ? "Every slide has a title and every picture, chart and media object has alt text."
            : found.prefix(14).map(\.message).joined(separator: "\n") + (found.count > 14 ? "\n…" : "")
        if let first = found.first {
            alert.addButton(withTitle: "Go to First Issue")
            alert.addButton(withTitle: "Close")
            if let window = hostWindow(controller) {
                alert.beginSheetModal(for: window) { response in
                    guard response == .alertFirstButtonReturn else { return }
                    controller.setCurrentSlide(first.slide)
                    if let id = first.element { controller.select([id]) }
                }
            }
        } else if let window = hostWindow(controller) {
            alert.beginSheetModal(for: window)
        }
    }
}

enum AltTextPrompt {
    static func show(_ controller: PresentationController) {
        guard let e = controller.primaryElement, let window = hostWindow(controller) else { return }
        let alert = NSAlert()
        alert.messageText = "Alt Text"
        alert.informativeText = "How would you describe this object to someone who can't see it?"
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 70))
        field.string = e.altText
        field.isRichText = false
        field.font = .systemFont(ofSize: 13)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 70))
        scroll.documentView = field
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { controller.setAltText(field.string) }
        }
    }
}

enum ChangePicture {
    static func run(_ controller: PresentationController) {
        guard let e = controller.primaryElement, e.isImage, let window = hostWindow(controller) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            var id = ""
            controller.change("Change Picture") { p in id = p.addMedia(data, filename: url.lastPathComponent) }
            controller.setImage({ $0.mediaID = id; $0.crop = CropInsets() }, name: "Change Picture")
        }
    }
}

/// Removes a picture's background with Vision's subject segmentation.
enum BackgroundRemover {
    static func run(_ controller: PresentationController) {
        guard let e = controller.primaryElement, case .image(let content) = e.content,
              let item = controller.presentation.media[content.mediaID],
              let source = CIImage(data: item.data) else { NSSound.beep(); return }
        controller.flash("Removing background…")
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: source)
            var output: Data?
            do {
                try handler.perform([request])
                if let result = request.results?.first {
                    let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
                    let maskImage = CIImage(cvPixelBuffer: mask)
                    let filter = CIFilter(name: "CIBlendWithMask")!
                    filter.setValue(source, forKey: kCIInputImageKey)
                    filter.setValue(CIImage(color: .clear).cropped(to: source.extent), forKey: kCIInputBackgroundImageKey)
                    filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                    if let composed = filter.outputImage, let cg = CIContext().createCGImage(composed, from: source.extent) {
                        output = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                    }
                }
            } catch {
                output = nil
            }
            DispatchQueue.main.async {
                guard let output else { controller.flash("No foreground subject was found"); return }
                var id = ""
                controller.change("Remove Background") { p in id = p.addMedia(output, filename: "Background Removed.png") }
                controller.setImage({ $0.mediaID = id }, name: "Remove Background")
                controller.flash("Background removed")
            }
        }
    }
}

/// Plays the selected media in a small window.
enum MediaPreview {
    static func play(_ controller: PresentationController) {
        guard let e = controller.primaryElement, case .media(let m) = e.content, let item = controller.presentation.media[m.mediaID] else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + item.filename)
        try? item.data.write(to: url)
        let player = AVPlayer(url: url)
        player.volume = Float(m.volume)
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: m.kind == .video ? 640 : 400, height: m.kind == .video ? 360 : 80),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = e.name
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        player.play()
        previews.append(window)
    }

    private static var previews: [NSWindow] = []
}

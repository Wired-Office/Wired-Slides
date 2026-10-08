import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let wsElements = NSPasteboard.PasteboardType("com.wiredslides.elements")
    static let wsSlides = NSPasteboard.PasteboardType("com.wiredslides.slides")
}

/// What goes on the pasteboard: elements or slides plus the media they use.
private struct ClipboardPayload: Codable {
    var elements: [SlideElement] = []
    var slides: [Slide] = []
    var media: [String: MediaItem] = [:]
    var theme: PresentationTheme?
    var source: UUID
}

extension PresentationController {
    var canPaste: Bool {
        let pb = NSPasteboard.general
        return pb.availableType(from: [.wsElements, .wsSlides, .png, .tiff, .pdf, .fileURL, .string]) != nil
    }

    // MARK: Copy

    func copySelection(cut: Bool = false) {
        if let editor = textEditor, editor.hasSelection {
            // The text view handles its own copy.
            return
        }
        let elements = selectedElements
        if elements.isEmpty {
            copySlides(cut: cut)
            return
        }
        var payload = ClipboardPayload(elements: elements, source: documentID)
        for id in elements.flatMap(\.mediaIDs) { payload.media[id] = presentation.media[id] }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = try? JSONEncoder().encode(payload) { pb.setData(data, forType: .wsElements) }
        // Other apps get a picture and the plain text.
        let bounds = elements.map { SlideRenderer.visualBounds($0) }.reduce(CGRect.null) { $0.union($1) }
        if !bounds.isNull, let png = renderPNG(elements, bounds: bounds) { pb.setData(png, forType: .png) }
        let text = elements.flatMap(\.allText).filter { !$0.isEmpty }.joined(separator: "\n")
        if !text.isEmpty { pb.setString(text, forType: .string) }
        if cut { deleteSelection() }
    }

    private func renderPNG(_ elements: [SlideElement], bounds: CGRect) -> Data? {
        let scale: CGFloat = 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, w * h < 40_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        let env = RenderEnvironment(presentation)
        for e in elements { ElementRenderer.draw(e, ctx: ctx, env: env, options: ElementDrawOptions()) }
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func copySlides(cut: Bool = false) {
        let indices = selectedSlides.sorted()
        guard !indices.isEmpty else { return }
        let slides = indices.map { presentation.slides[$0] }
        var payload = ClipboardPayload(slides: slides, theme: theme, source: documentID)
        for id in slides.flatMap(\.mediaIDs) { payload.media[id] = presentation.media[id] }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = try? JSONEncoder().encode(payload) { pb.setData(data, forType: .wsSlides) }
        if let first = slides.first, let png = SlideRenderer.pngData(first, number: indices[0] + 1, presentation: presentation, pixelWidth: 1920) {
            pb.setData(png, forType: .png)
        }
        if cut { deleteSlides() }
    }

    // MARK: Paste

    func paste() {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .wsElements), let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) {
            pasteElements(payload)
        } else if let data = pb.data(forType: .wsSlides), let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) {
            pasteSlides(payload)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            insertFiles(urls, at: nil)
        } else if let type = pb.availableType(from: [.png, .tiff, .pdf]), let data = pb.data(forType: type) {
            let ext = type == .png ? "png" : type == .pdf ? "pdf" : "tiff"
            if ext == "tiff", let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                insertPicture(png, filename: "Pasted Image.png")
            } else {
                insertPicture(data, filename: "Pasted Image.\(ext)")
            }
        } else if let string = pb.string(forType: .string), !string.isEmpty {
            if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true {
                setHyperlink(url.absoluteString)
            } else {
                insertTextBox(text: string)
                commitTextEditing()
            }
        }
    }

    /// Pastes slide content as plain picture (Paste Special ▸ Picture).
    func pasteAsPicture() {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { NSSound.beep(); return }
        insertPicture(data, filename: "Pasted Picture.png")
    }

    func pasteAsText() {
        guard let string = NSPasteboard.general.string(forType: .string) else { NSSound.beep(); return }
        if let editor = textEditor { editor.insertText(string); return }
        insertTextBox(text: string)
        commitTextEditing()
    }

    private func pasteElements(_ payload: ClipboardPayload) {
        var mediaMap: [String: String] = [:]
        if payload.source != documentID || payload.media.contains(where: { presentation.media[$0.key] == nil }) {
            change("Paste") { p in
                for (id, item) in payload.media where p.media[id] == nil { mediaMap[id] = p.addMedia(item.data, filename: item.filename) }
            }
        }
        // Pasting onto the same slide offsets the copies.
        let existing = currentSlide.elements.map(\.frame)
        var copies = payload.elements.map { e -> SlideElement in
            var copy = e.duplicated()
            copy.placeholder = nil
            Self.remapMedia(&copy, mediaMap)
            return copy
        }
        if copies.contains(where: { existing.contains($0.frame) }) {
            for i in copies.indices { copies[i].offset(by: CGSize(width: 18, height: 18)) }
        }
        insert(copies, name: "Paste")
    }

    private func pasteSlides(_ payload: ClipboardPayload) {
        let insertAt = currentSlideIndex + 1
        change("Paste Slides") { p in
            var mediaMap: [String: String] = [:]
            for (id, item) in payload.media where p.media[id] == nil { mediaMap[id] = p.addMedia(item.data, filename: item.filename) }
            let slides = payload.slides.map { slide -> Slide in
                var s = slide
                s.id = UUID()
                for i in s.elements.indices { Self.remapMedia(&s.elements[i], mediaMap) }
                return s
            }
            p.slides.insert(contentsOf: slides, at: min(insertAt, p.slides.count))
        }
        selectedSlides = IndexSet(insertAt..<(insertAt + payload.slides.count))
        setCurrentSlide(insertAt, extendSelection: true)
    }

    static func remapMedia(_ e: inout SlideElement, _ map: [String: String]) {
        guard !map.isEmpty else { return }
        switch e.content {
        case .image(var i): if let n = map[i.mediaID] { i.mediaID = n }; e.content = .image(i)
        case .media(var m):
            if let n = map[m.mediaID] { m.mediaID = n }
            if let poster = m.posterID, let n = map[poster] { m.posterID = n }
            e.content = .media(m)
        case .shape(var s):
            if case .image(var f) = s.fill, let n = map[f.mediaID] { f.mediaID = n; s.fill = .image(f) }
            e.content = .shape(s)
        case .group(var g):
            for i in g.children.indices { remapMedia(&g.children[i], map) }
            e.content = .group(g)
        default: break
        }
    }

    // MARK: Files

    /// Inserts dropped or pasted files: pictures, movies, sounds and text.
    func insertFiles(_ urls: [URL], at point: CGPoint?) {
        var offset: CGFloat = 0
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if type.conforms(to: .image) || type.conforms(to: .pdf) {
                if let data = try? Data(contentsOf: url) {
                    insertPicture(data, filename: url.lastPathComponent, at: point.map { CGPoint(x: $0.x + offset, y: $0.y + offset) })
                    offset += 24
                }
            } else if type.conforms(to: .movie) || type.conforms(to: .audio) {
                insertMedia(url)
            } else if type.conforms(to: .plainText), let text = try? String(contentsOf: url, encoding: .utf8) {
                insertTextBox(text: text)
                commitTextEditing()
            }
        }
    }
}

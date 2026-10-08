import AppKit
import AVFoundation
import SwiftUI

/// What to print or export to PDF.
final class PrintOptions: ObservableObject {
    static let shared = PrintOptions()

    enum Layout: String, CaseIterable, Identifiable {
        case slides, notes, outline, handout1, handout2, handout3, handout4, handout6, handout9
        var id: String { rawValue }

        var title: String {
            switch self {
            case .slides: "Full Page Slides"
            case .notes: "Notes Pages"
            case .outline: "Outline"
            case .handout1: "Handouts (1 slide per page)"
            case .handout2: "Handouts (2 slides per page)"
            case .handout3: "Handouts (3 slides per page, with lines)"
            case .handout4: "Handouts (4 slides per page)"
            case .handout6: "Handouts (6 slides per page)"
            case .handout9: "Handouts (9 slides per page)"
            }
        }

        var perPage: Int {
            switch self {
            case .handout2: 2
            case .handout3: 3
            case .handout4: 4
            case .handout6: 6
            case .handout9: 9
            default: 1
            }
        }

        var isHandout: Bool { rawValue.hasPrefix("handout") }
    }

    @Published var layout: Layout = .slides
    @Published var frameSlides = false
    @Published var printHidden = false
    @Published var grayscale = false
    @Published var pageNumbers = true
}

/// Lays out and draws printed pages (shared by printing and PDF export).
struct PageLayout {
    let presentation: Presentation
    let options: PrintOptions
    let paper: CGSize

    var slideIndices: [Int] {
        presentation.slides.indices.filter { options.printHidden || !presentation.slides[$0].hidden }
    }

    var pageCount: Int {
        switch options.layout {
        case .slides, .notes: return slideIndices.count
        case .outline: return outlinePages.count
        default: return Int(ceil(Double(slideIndices.count) / Double(options.layout.perPage)))
        }
    }

    /// Outline text split into pages.
    var outlinePages: [NSAttributedString] {
        let outline = OutlineExporter.attributedOutline(presentation)
        let storage = NSTextStorage(attributedString: outline)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var pages: [NSAttributedString] = []
        let size = CGSize(width: paper.width - 100, height: paper.height - 110)
        var location = 0
        while location < storage.length {
            let container = NSTextContainer(size: size)
            manager.addTextContainer(container)
            let range = manager.characterRange(forGlyphRange: manager.glyphRange(for: container), actualGlyphRange: nil)
            guard range.length > 0 else { break }
            pages.append(storage.attributedSubstring(from: range))
            location = NSMaxRange(range)
        }
        return pages.isEmpty ? [NSAttributedString(string: "")] : pages
    }

    func drawSlide(_ index: Int, in rect: CGRect, ctx: CGContext) {
        let slide = presentation.slides[index]
        let size = presentation.slideSize
        let s = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        let r = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: s, y: s)
        SlideRenderer.draw(slide, number: index + 1, presentation: presentation, ctx: ctx)
        ctx.restoreGState()
        if options.frameSlides || options.layout != .slides {
            ctx.setStrokeColor(NSColor(white: 0.55, alpha: 1).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(r)
        }
    }

    /// Draws page `n` (0-based) into a flipped context whose units are points of `paper`.
    func draw(page n: Int, ctx: CGContext) {
        let bounds = CGRect(origin: .zero, size: paper)
        let margin: CGFloat = 36
        let content = bounds.insetBy(dx: margin, dy: margin)
        let indices = slideIndices
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
        ElementRenderer.withNSContext(ctx) {
            switch options.layout {
            case .slides:
                guard indices.indices.contains(n) else { return }
                drawSlide(indices[n], in: bounds.insetBy(dx: 18, dy: 18), ctx: ctx)
            case .notes:
                guard indices.indices.contains(n) else { return }
                let index = indices[n]
                drawSlide(index, in: CGRect(x: content.minX + 20, y: content.minY + 10, width: content.width - 40, height: content.height * 0.42), ctx: ctx)
                let notes = presentation.slides[index].notes as NSString
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                notes.draw(with: CGRect(x: content.minX + 20, y: content.minY + content.height * 0.47, width: content.width - 40, height: content.height * 0.48),
                           options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black, .paragraphStyle: style])
            case .outline:
                let pages = outlinePages
                guard pages.indices.contains(n) else { return }
                pages[n].draw(with: CGRect(x: 50, y: 50, width: paper.width - 100, height: paper.height - 110), options: [.usesLineFragmentOrigin])
            default:
                let per = options.layout.perPage
                let start = n * per
                let pageIndices = Array(indices[min(start, indices.count)..<min(start + per, indices.count)])
                let header = (presentation.title.isEmpty ? "" : presentation.title) as NSString
                header.draw(at: CGPoint(x: content.minX, y: margin - 20), withAttributes: small)
                let columns: Int, rows: Int
                switch per {
                case 1: (columns, rows) = (1, 1)
                case 2: (columns, rows) = (1, 2)
                case 3: (columns, rows) = (1, 3)
                case 4: (columns, rows) = (2, 2)
                case 6: (columns, rows) = (2, 3)
                default: (columns, rows) = (3, 3)
                }
                let lined = options.layout == .handout3
                let gap: CGFloat = 18
                let cellW = (lined ? content.width * 0.5 : content.width - gap * CGFloat(columns - 1)) / (lined ? 1 : CGFloat(columns))
                let cellH = (content.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                for (i, index) in pageIndices.enumerated() {
                    let c = lined ? 0 : i % columns, r = lined ? i : i / columns
                    let cell = CGRect(x: content.minX + CGFloat(c) * (cellW + gap), y: content.minY + CGFloat(r) * (cellH + gap), width: cellW, height: cellH)
                    drawSlide(index, in: cell, ctx: ctx)
                    if lined {
                        ctx.setStrokeColor(NSColor(white: 0.7, alpha: 1).cgColor)
                        ctx.setLineWidth(0.5)
                        var y = cell.minY + 14
                        while y < cell.maxY {
                            ctx.strokeLineSegments(between: [CGPoint(x: content.midX + 14, y: y), CGPoint(x: content.maxX, y: y)])
                            y += 22
                        }
                    }
                }
            }
            if options.pageNumbers && options.layout != .slides {
                let label = "\(n + 1)" as NSString
                let size = label.size(withAttributes: small)
                label.draw(at: CGPoint(x: bounds.maxX - margin - size.width, y: bounds.maxY - margin + 8), withAttributes: small)
            }
        }
    }
}

/// The view NSPrintOperation paginates.
final class PresentationPrintView: NSView {
    let presentation: Presentation
    let options: PrintOptions
    private let printInfo: NSPrintInfo

    init(presentation: Presentation, printInfo: NSPrintInfo, options: PrintOptions) {
        self.presentation = presentation
        self.options = options
        self.printInfo = printInfo
        // Slides print landscape (or matching the slide) unless the layout is a handout.
        if options.layout == .slides {
            printInfo.orientation = presentation.slideSize.width >= presentation.slideSize.height ? .landscape : .portrait
        } else {
            printInfo.orientation = .portrait
        }
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        super.init(frame: .zero)
        updateFrame()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    private var pageSize: CGSize { printInfo.paperSize }

    var layoutModel: PageLayout { PageLayout(presentation: presentation, options: options, paper: pageSize) }

    func updateFrame() {
        let count = max(layoutModel.pageCount, 1)
        setFrameSize(NSSize(width: pageSize.width, height: pageSize.height * CGFloat(count)))
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(layoutModel.pageCount, 1))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * pageSize.height, width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let model = layoutModel
        let first = Int(dirtyRect.minY / pageSize.height), last = Int((dirtyRect.maxY - 1) / pageSize.height)
        for page in max(first, 0)...max(last, 0) where page < model.pageCount {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(page) * pageSize.height)
            NSColor.white.setFill()
            CGRect(origin: .zero, size: pageSize).fill()
            model.draw(page: page, ctx: ctx)
            ctx.restoreGState()
        }
        if options.grayscale {
            ctx.saveGState()
            ctx.setBlendMode(.saturation)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(dirtyRect)
            ctx.restoreGState()
        }
    }
}

/// The print panel's options for slides, handouts and notes.
final class PrintAccessoryController: NSViewController, NSPrintPanelAccessorizing {
    private let printView: PresentationPrintView

    init(view: PresentationPrintView) {
        printView = view
        super.init(nibName: nil, bundle: nil)
        title = "Wired Slides"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSHostingView(rootView: PrintOptionsView(options: PrintOptions.shared) { [weak self] in
            self?.printView.updateFrame()
            self?.willChangeValue(forKey: "localizedSummaryItems")
            self?.didChangeValue(forKey: "localizedSummaryItems")
        })
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 140)
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[.itemName: "Print", .itemDescription: PrintOptions.shared.layout.title]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> { ["localizedSummaryItems"] }
}

struct PrintOptionsView: View {
    @ObservedObject var options: PrintOptions
    let onChange: () -> Void

    var body: some View {
        Form {
            Picker("Print:", selection: $options.layout) {
                ForEach(PrintOptions.Layout.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Frame slides", isOn: $options.frameSlides)
            Toggle("Print hidden slides", isOn: $options.printHidden)
            Toggle("Grayscale", isOn: $options.grayscale)
        }
        .padding(12)
        .onChange(of: options.layout) { _, _ in onChange() }
        .onChange(of: options.printHidden) { _, _ in onChange() }
        .onChange(of: options.grayscale) { _, _ in onChange() }
        .onChange(of: options.frameSlides) { _, _ in onChange() }
    }
}

/// Writes a PDF: one page per slide at slide size, or the chosen handout layout on Letter paper.
enum PDFExporter {
    static func write(_ presentation: Presentation, to url: URL, options: PrintOptions) throws {
        let paper = options.layout == .slides ? presentation.slideSize : CGSize(width: 612, height: 792)
        var mediaBox = CGRect(origin: .zero, size: paper)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, [kCGPDFContextTitle as String: presentation.title, kCGPDFContextCreator as String: "Wired Slides"] as CFDictionary) else {
            throw SlidesError.corrupt("The PDF couldn't be created.")
        }
        let layout = PageLayout(presentation: presentation, options: options, paper: paper)
        for page in 0..<max(layout.pageCount, 1) {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: paper.height)
            ctx.scaleBy(x: 1, y: -1)
            if options.layout == .slides {
                let indices = layout.slideIndices
                if indices.indices.contains(page) {
                    SlideRenderer.draw(presentation.slides[indices[page]], number: indices[page] + 1, presentation: presentation, ctx: ctx)
                }
            } else {
                layout.draw(page: page, ctx: ctx)
            }
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}

/// The text outline of a presentation.
enum OutlineExporter {
    static func attributedOutline(_ p: Presentation) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (i, slide) in p.slides.enumerated() {
            let title = slide.title.isEmpty ? "Slide \(i + 1)" : slide.title
            result.append(NSAttributedString(string: "\(i + 1)  \(title)\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
            for e in slide.elements where e.placeholder?.isTitle != true {
                guard let text = e.text, !text.isEmpty else { continue }
                for paragraph in text.paragraphs where !paragraph.text.isEmpty {
                    let style = NSMutableParagraphStyle()
                    let indent = CGFloat(24 + paragraph.style.level * 20)
                    style.headIndent = indent
                    style.firstLineHeadIndent = indent - 12
                    result.append(NSAttributedString(string: "•  " + paragraph.text + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: style]))
                }
            }
            result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
        }
        return result
    }
}

/// Renders the slides into an H.264 movie with crossfades.
enum MovieExporter {
    static func export(_ p: Presentation, to url: URL, width: Int = 1920, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.removeItem(at: url)
                let height = Int((Double(width) * Double(p.slideSize.height / p.slideSize.width)).rounded() / 2) * 2
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                ])
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                ])
                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
                let fps: Int32 = 30
                var frame: Int64 = 0
                let slides = p.visibleSlideIndices
                let images: [CGImage] = slides.compactMap { i in
                    DispatchQueue.main.sync { SlideRenderer.cgImage(p.slides[i], number: i + 1, presentation: p, pixelWidth: CGFloat(width)) }
                }
                func append(_ image: CGImage, blend: CGImage?, alpha: CGFloat) throws {
                    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                    guard let pool = adaptor.pixelBufferPool else { throw SlidesError.corrupt("Couldn't create video frames.") }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let buffer else { throw SlidesError.corrupt("Couldn't create video frames.") }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                           bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                        let r = CGRect(x: 0, y: 0, width: width, height: height)
                        ctx.draw(image, in: r)
                        if let blend {
                            ctx.setAlpha(alpha)
                            ctx.draw(blend, in: r)
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps))
                    frame += 1
                }
                for (n, image) in images.enumerated() {
                    let slide = p.slides[slides[n]]
                    let hold = slide.transition.advanceAfter ?? 5
                    for _ in 0..<Int(hold * Double(fps)) { try append(image, blend: nil, alpha: 0) }
                    if n + 1 < images.count {
                        let next = p.slides[slides[n + 1]].transition
                        let fade = next.kind == .none ? 0 : max(next.duration, 0.3)
                        let count = Int(fade * Double(fps))
                        for f in 0..<count { try append(image, blend: images[n + 1], alpha: CGFloat(f + 1) / CGFloat(count)) }
                    }
                }
                input.markAsFinished()
                let group = DispatchGroup()
                group.enter()
                writer.finishWriting { group.leave() }
                group.wait()
                completion(writer.status == .completed ? nil : writer.error)
            } catch {
                completion(error)
            }
        }
    }
}

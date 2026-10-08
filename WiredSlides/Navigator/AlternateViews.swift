import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Slide Sorter

struct SlideSorterView: View {
    @ObservedObject var controller: PresentationController
    @AppStorage("WSSorterThumbnailWidth") private var thumbnailWidth: Double = 220
    @State private var dragging: Int?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                let ranges = controller.sectionRanges()
                LazyVStack(alignment: .leading, spacing: 18) {
                    if ranges.isEmpty || ranges.first?.range.lowerBound != 0 {
                        grid(Array(0..<(ranges.first?.range.lowerBound ?? controller.slides.count)))
                    }
                    ForEach(ranges, id: \.section.id) { entry in
                        Text(entry.section.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                        grid(Array(entry.range))
                    }
                }
                .padding(24)
            }
            .background(Color(nsColor: Theme.canvasBackground))
            HStack {
                Text("\(controller.selectedSlides.count) of \(controller.slides.count) selected")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "photo").font(.system(size: 9))
                Slider(value: $thumbnailWidth, in: 120...420).controlSize(.mini).frame(width: 120)
                Image(systemName: "photo").font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Color(nsColor: Theme.barBackground))
        }
    }

    private func grid(_ indices: [Int]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth + 40), spacing: 22)], alignment: .leading, spacing: 26) {
            ForEach(indices, id: \.self) { index in
                SorterCell(controller: controller, index: index, width: thumbnailWidth)
                    .onDrag {
                        dragging = index
                        if !controller.selectedSlides.contains(index) { controller.setCurrentSlide(index) }
                        return NSItemProvider(object: String(index) as NSString)
                    }
                    .onDrop(of: [.text], delegate: SorterDropDelegate(controller: controller, index: index, dragging: $dragging))
            }
        }
    }
}

private struct SorterDropDelegate: DropDelegate {
    let controller: PresentationController
    let index: Int
    @Binding var dragging: Int?

    func performDrop(info: DropInfo) -> Bool {
        guard dragging != nil else { return false }
        let selection = controller.selectedSlides
        controller.moveSlides(selection, to: index + (selection.contains(index) ? 0 : (selection.first ?? 0) < index ? 1 : 0))
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

private struct SorterCell: View {
    @ObservedObject var controller: PresentationController
    let index: Int
    let width: Double

    var body: some View {
        let slide = controller.slides[index]
        let selected = controller.selectedSlides.contains(index)
        let height = width * controller.slideSize.height / max(controller.slideSize.width, 1)
        VStack(alignment: .leading, spacing: 5) {
            Image(nsImage: ThumbnailCache.shared.thumbnail(slide, number: index + 1, presentation: controller.presentation, width: width))
                .resizable()
                .frame(width: width, height: height)
                .opacity(slide.hidden ? 0.45 : 1)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Theme.accentColor : .clear, lineWidth: 3).padding(-4))
            HStack(spacing: 6) {
                Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                if slide.hidden { Image(systemName: "eye.slash").font(.system(size: 10)) }
                if slide.transition.kind != .none { Image(systemName: "star.fill").font(.system(size: 9)).help(slide.transition.kind.title) }
                if let after = slide.transition.advanceAfter { Text(String(format: "%.0fs", after)).font(.system(size: 10)).monospacedDigit() }
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            controller.setCurrentSlide(index)
            controller.viewMode = .normal
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                var s = controller.selectedSlides
                if s.contains(index), s.count > 1 { s.remove(index) } else { s.insert(index) }
                controller.setCurrentSlide(index, extendSelection: true)
                controller.selectedSlides = s
            } else if flags.contains(.shift) {
                let a = min(controller.currentSlideIndex, index), b = max(controller.currentSlideIndex, index)
                let anchor = controller.currentSlideIndex
                controller.setCurrentSlide(index, extendSelection: true)
                controller.selectedSlides = IndexSet(a...b)
                _ = anchor
            } else {
                controller.setCurrentSlide(index)
            }
        }
        .contextMenu {
            Button("Cut") { controller.copySlides(cut: true) }
            Button("Copy") { controller.copySlides() }
            Button("Paste") { controller.paste() }
            Divider()
            Button("Duplicate Slide") { controller.duplicateSlides() }
            Button("Delete Slide") { controller.deleteSlides() }
            Button(slide.hidden ? "Show Slide" : "Hide Slide") { controller.toggleHideSlides() }
            Divider()
            Button("Add Section") { controller.addSection() }
        }
    }
}

// MARK: - Outline view

/// Titles and body text of every slide, editable as an outline.
struct OutlineView: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.slides.indices, id: \.self) { index in
                        OutlineRow(controller: controller, index: index)
                            .id(index)
                    }
                }
                .padding(14)
            }
            .onChange(of: controller.currentSlideIndex) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
        .background(Color(nsColor: Theme.paneBackground))
    }
}

private struct OutlineRow: View {
    @ObservedObject var controller: PresentationController
    let index: Int
    @State private var title = ""
    @State private var bodyText = ""
    @FocusState private var focused: Bool

    private var slide: Slide { controller.slides[index] }
    private var titleElement: SlideElement? { slide.elements.first { $0.placeholder?.isTitle == true } }
    private var bodyElement: SlideElement? { slide.elements.first { $0.placeholder == .body || $0.placeholder == .subtitle } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: "rectangle.fill").font(.system(size: 13))
                    .foregroundStyle(controller.currentSlideIndex == index ? Theme.accentColor : Color.secondary)
            }
            .frame(width: 26)
            .onTapGesture { controller.setCurrentSlide(index) }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(.plain)
                    .disabled(titleElement == nil)
                    .onSubmit(save)
                if bodyElement != nil {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 22)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($focused)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(controller.currentSlideIndex == index ? Theme.accentColor.opacity(0.08) : Color.clear))
        .onAppear(perform: load)
        .onChange(of: controller.revision) { _, _ in if !focused { load() } }
        .onChange(of: focused) { _, isFocused in
            if isFocused { controller.setCurrentSlide(index) } else { save() }
        }
    }

    private func load() {
        guard controller.slides.indices.contains(index) else { return }
        title = titleElement?.text?.plainText ?? ""
        bodyText = bodyElement?.text?.paragraphs.map { String(repeating: "\t", count: $0.style.level) + $0.text }.joined(separator: "\n") ?? ""
    }

    private func save() {
        guard controller.slides.indices.contains(index) else { return }
        let slideIndex = index
        let titleID = titleElement?.id, bodyID = bodyElement?.id
        let newTitle = title, newBody = bodyText
        guard newTitle != (titleElement?.text?.plainText ?? "") || newBody != (bodyElement?.text?.paragraphs.map { String(repeating: "\t", count: $0.style.level) + $0.text }.joined(separator: "\n") ?? "") else { return }
        controller.change("Edit Outline") { p in
            for i in p.slides[slideIndex].elements.indices {
                let id = p.slides[slideIndex].elements[i].id
                guard var text = p.slides[slideIndex].elements[i].text else { continue }
                if id == titleID {
                    text.setPlainText(newTitle)
                } else if id == bodyID {
                    let template = text.paragraphs.first?.style ?? .plain
                    let run = text.paragraphs.first?.runs.first?.style ?? .plain
                    text.paragraphs = newBody.components(separatedBy: "\n").map { line in
                        let level = line.prefix { $0 == "\t" }.count
                        var style = template
                        style.level = min(level, 8)
                        return Paragraph(String(line.dropFirst(level)), style: style, run: run)
                    }
                } else { continue }
                p.slides[slideIndex].elements[i].text = text
            }
        }
    }
}

// MARK: - Notes pane

/// Speaker notes under the slide.
final class NotesPaneView: NSView, NSTextViewDelegate {
    let controller: PresentationController
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var cancellables = Set<AnyCancellable>()
    private var loading = false
    private var editingSlide: UUID?

    init(controller: PresentationController) {
        self.controller = controller
        super.init(frame: .zero)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.delegate = self
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        controller.$currentSlideIndex.receive(on: RunLoop.main).sink { [weak self] _ in self?.load() }.store(in: &cancellables)
        controller.$revision.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, self.window?.firstResponder !== self.textView else { return }
            self.load()
        }.store(in: &cancellables)
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func load() {
        save()
        loading = true
        let slide = controller.currentSlide
        editingSlide = slide.id
        if textView.string != slide.notes { textView.string = slide.notes }
        textView.setAccessibilityLabel("Notes for slide \(controller.currentSlideIndex + 1)")
        placeholder = slide.notes.isEmpty
        loading = false
    }

    private var placeholder = false { didSet { needsDisplay = true; scrollView.needsDisplay = true } }

    func save() {
        guard !loading, let id = editingSlide, let index = controller.presentation.slideIndex(id) else { return }
        if controller.slides[index].notes != textView.string { controller.setNotes(textView.string, slideIndex: index) }
    }

    func textDidEndEditing(_ notification: Notification) { save() }

    func textDidChange(_ notification: Notification) {
        placeholder = textView.string.isEmpty
        // Save after a pause so autosave and the presenter view see notes promptly.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(deferredSave), object: nil)
        perform(#selector(deferredSave), with: nil, afterDelay: 1.2)
    }

    @objc private func deferredSave() { save() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        textView.setValue(NSAttributedString(string: "Click to add notes", attributes: [.foregroundColor: NSColor.placeholderTextColor, .font: NSFont.systemFont(ofSize: 13)]),
                          forKey: "placeholderAttributedString")
    }
}

// MARK: - Notes Page view

/// Each slide on a page with its notes, as they print.
struct NotesPageView: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 30) {
                    ForEach(controller.slides.indices, id: \.self) { index in
                        NotesPageCard(controller: controller, index: index).id(index)
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo(controller.currentSlideIndex, anchor: .top) }
        }
        .background(Color(nsColor: Theme.canvasBackground))
    }
}

private struct NotesPageCard: View {
    @ObservedObject var controller: PresentationController
    let index: Int
    @State private var notes = ""

    var body: some View {
        let width: CGFloat = 520
        let slide = controller.slides[index]
        VStack(spacing: 18) {
            Image(nsImage: ThumbnailCache.shared.thumbnail(slide, number: index + 1, presentation: controller.presentation, width: 440))
                .resizable()
                .aspectRatio(controller.slideSize.width / controller.slideSize.height, contentMode: .fit)
                .frame(width: 440)
                .border(Color.black.opacity(0.3), width: 0.5)
                .onTapGesture(count: 2) { controller.setCurrentSlide(index); controller.viewMode = .normal }
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.black)
                .frame(minHeight: 240, alignment: .top)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty { Text("Click to add notes").foregroundStyle(.gray).padding(.leading, 5).allowsHitTesting(false) }
                }
            HStack { Spacer(); Text("\(index + 1)").font(.system(size: 11)).foregroundStyle(.gray) }
        }
        .padding(40)
        .frame(width: width, height: width * 11 / 8.5)
        .background(Color.white)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .onAppear { notes = slide.notes }
        .onChange(of: notes) { _, value in
            if value != controller.slides[index].notes { controller.setNotes(value, slideIndex: index) }
        }
    }
}

import Combine

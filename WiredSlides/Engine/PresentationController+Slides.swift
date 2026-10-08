import AppKit

extension PresentationController {
    // MARK: - Slides

    /// Adds a slide after the current one. With no layout, uses the current slide's (Title Slide → Title and Content).
    func addSlide(layout: LayoutKind? = nil) {
        let current = currentSlide.layout
        let kind = layout ?? (current == .title ? .titleContent : (current == .blank ? .blank : current))
        let index = currentSlideIndex + 1
        var slide = LayoutBuilder.makeSlide(kind, theme: theme, size: slideSize)
        // New slides inherit the transition of the current one, like PowerPoint.
        slide.transition = currentSlide.transition
        change("New Slide") { p in p.slides.insert(slide, at: index) }
        setCurrentSlide(index)
    }

    func duplicateSlides() {
        let indices = selectedSlides.sorted()
        guard !indices.isEmpty else { return }
        let insertAt = (indices.last ?? currentSlideIndex) + 1
        var copies: [Slide] = []
        for i in indices {
            var copy = presentation.slides[i]
            copy.id = UUID()
            // Element ids stay the same so Morph can match them across the copies.
            copy.comments = []
            copies.append(copy)
        }
        change("Duplicate Slide") { p in p.slides.insert(contentsOf: copies, at: insertAt) }
        selectedSlides = IndexSet(insertAt..<(insertAt + copies.count))
        setCurrentSlide(insertAt, extendSelection: true)
    }

    func deleteSlides() {
        let indices = selectedSlides.sorted()
        guard !indices.isEmpty else { return }
        let deletedIDs = Set(indices.map { presentation.slides[$0].id })
        let newIndex = min(indices.first ?? 0, slides.count - indices.count - 1)
        change(indices.count > 1 ? "Delete Slides" : "Delete Slide") { p in
            for i in indices.reversed() { p.slides.remove(at: i) }
            if p.slides.isEmpty { p.slides = [LayoutBuilder.makeSlide(.title, theme: p.theme, size: p.slideSize)] }
            // Sections that started on a deleted slide move to the next survivor.
            p.sections = p.sections.compactMap { section in
                guard deletedIDs.contains(section.firstSlideID) else { return section }
                var s = section
                let oldIndex = presentation.slideIndex(section.firstSlideID) ?? 0
                guard let next = presentation.slides[oldIndex...].first(where: { !deletedIDs.contains($0.id) }) else { return nil }
                s.firstSlideID = next.id
                return s
            }
        }
        setCurrentSlide(max(newIndex, 0))
    }

    /// Moves the selected slides so they start at `destination` (an index in the current order).
    func moveSlides(_ indices: IndexSet, to destination: Int) {
        let sorted = indices.sorted()
        guard !sorted.isEmpty else { return }
        let moving = sorted.map { presentation.slides[$0] }
        let ids = Set(moving.map(\.id))
        let before = sorted.filter { $0 < destination }.count
        let target = max(0, min(destination - before, slides.count - moving.count))
        change("Move Slide") { p in
            p.slides.removeAll { ids.contains($0.id) }
            p.slides.insert(contentsOf: moving, at: target)
        }
        setCurrentSlide(target, keepSelection: true)
        selectedSlides = IndexSet(target..<(target + moving.count))
    }

    func moveSlideUp() {
        guard let first = selectedSlides.first, first > 0 else { return }
        moveSlides(selectedSlides, to: first - 1)
    }

    func moveSlideDown() {
        guard let last = selectedSlides.last, last < slides.count - 1 else { return }
        moveSlides(selectedSlides, to: last + 2)
    }

    func toggleHideSlides() {
        let indices = selectedSlides
        let hide = !indices.allSatisfy { presentation.slides[$0].hidden }
        change(hide ? "Hide Slide" : "Show Slide") { p in for i in indices { p.slides[i].hidden = hide } }
    }

    func setLayout(_ layout: LayoutKind) {
        let indices = selectedSlides
        let theme = self.theme, size = slideSize
        change("Layout") { p in for i in indices { LayoutBuilder.apply(layout, to: &p.slides[i], theme: theme, size: size) } }
    }

    func resetSlides() {
        let indices = selectedSlides
        let theme = self.theme, size = slideSize
        change("Reset Slide") { p in
            for i in indices {
                LayoutBuilder.reset(&p.slides[i], theme: theme, size: size)
                p.slides[i].background = nil
            }
        }
    }

    // MARK: - Sections

    func addSection(name: String = "Untitled Section") {
        let id = currentSlide.id
        change("Add Section") { p in
            p.sections.removeAll { $0.firstSlideID == id }
            p.sections.append(SlideSection(name: name, firstSlideID: id))
            let order = Dictionary(uniqueKeysWithValues: p.slides.enumerated().map { ($0.element.id, $0.offset) })
            p.sections.sort { (order[$0.firstSlideID] ?? 0) < (order[$1.firstSlideID] ?? 0) }
        }
    }

    func renameSection(_ id: UUID, to name: String) {
        change("Rename Section") { p in
            if let i = p.sections.firstIndex(where: { $0.id == id }) { p.sections[i].name = name }
        }
    }

    func removeSection(_ id: UUID, deleteSlides: Bool = false) {
        change(deleteSlides ? "Remove Section & Slides" : "Remove Section") { p in
            guard let i = p.sections.firstIndex(where: { $0.id == id }) else { return }
            if deleteSlides {
                let start = p.slideIndex(p.sections[i].firstSlideID) ?? 0
                let end = i + 1 < p.sections.count ? (p.slideIndex(p.sections[i + 1].firstSlideID) ?? p.slides.count) : p.slides.count
                p.slides.removeSubrange(start..<max(start, end))
                if p.slides.isEmpty { p.slides = [LayoutBuilder.makeSlide(.title, theme: p.theme, size: p.slideSize)] }
            }
            p.sections.remove(at: i)
        }
    }

    func removeAllSections() {
        change("Remove All Sections") { p in p.sections = [] }
    }

    /// Slide index ranges of each section.
    func sectionRanges() -> [(section: SlideSection, range: Range<Int>)] {
        let sections = presentation.sections.sorted { (presentation.slideIndex($0.firstSlideID) ?? 0) < (presentation.slideIndex($1.firstSlideID) ?? 0) }
        return sections.enumerated().compactMap { n, section in
            guard let start = presentation.slideIndex(section.firstSlideID) else { return nil }
            let end = n + 1 < sections.count ? (presentation.slideIndex(sections[n + 1].firstSlideID) ?? slides.count) : slides.count
            return (section, start..<max(start, end))
        }
    }

    // MARK: - Notes and comments

    func setNotes(_ notes: String, slideIndex: Int? = nil) {
        let index = slideIndex ?? currentSlideIndex
        guard presentation.slides.indices.contains(index), presentation.slides[index].notes != notes else { return }
        change("Edit Notes") { p in p.slides[index].notes = notes }
    }

    func addComment(_ text: String, at position: CGPoint? = nil) {
        let author = AppSettings.shared.authorName.isEmpty ? "Author" : AppSettings.shared.authorName
        var comment = SlideComment(author: author, date: Date(), text: text)
        if let position { comment.position = position } else if let e = selectedElements.first { comment.position = CGPoint(x: e.frame.maxX, y: e.frame.minY) }
        changeSlide("New Comment") { $0.comments.append(comment) }
        sidePane = .comments
    }

    func replyToComment(_ id: UUID, text: String) {
        let author = AppSettings.shared.authorName.isEmpty ? "Author" : AppSettings.shared.authorName
        changeSlide("Reply") { slide in
            if let i = slide.comments.firstIndex(where: { $0.id == id }) {
                slide.comments[i].replies.append(SlideComment(author: author, date: Date(), text: text))
            }
        }
    }

    func deleteComment(_ id: UUID) {
        changeSlide("Delete Comment") { slide in slide.comments.removeAll { $0.id == id } }
    }

    func resolveComment(_ id: UUID, resolved: Bool) {
        changeSlide(resolved ? "Resolve Comment" : "Reopen Comment") { slide in
            if let i = slide.comments.firstIndex(where: { $0.id == id }) { slide.comments[i].resolved = resolved }
        }
    }

    func deleteAllComments(onAllSlides: Bool) {
        let index = currentSlideIndex
        change("Delete Comments") { p in
            if onAllSlides { for i in p.slides.indices { p.slides[i].comments = [] } } else { p.slides[index].comments = [] }
        }
    }

    /// Moves to the next (or previous) slide with comments.
    func goToComment(forward: Bool) {
        let n = slides.count
        for step in 1...n {
            let i = ((currentSlideIndex + (forward ? step : -step)) % n + n) % n
            if !presentation.slides[i].comments.isEmpty {
                setCurrentSlide(i)
                sidePane = .comments
                return
            }
        }
        NSSound.beep()
    }

    // MARK: - Transitions

    func setTransition(_ change: @escaping (inout Transition) -> Void, name: String = "Transition") {
        let indices = selectedSlides
        self.change(name) { p in for i in indices { change(&p.slides[i].transition) } }
    }

    func applyTransitionToAll() {
        let transition = currentSlide.transition
        change("Apply To All") { p in for i in p.slides.indices { p.slides[i].transition = transition } }
    }

    // MARK: - Design

    /// Applies a theme, keeping each slide's content and re-laying out placeholders' look.
    func applyTheme(_ newTheme: PresentationTheme, toSelectedOnly: Bool = false) {
        change("Apply Theme") { p in
            let old = p.theme
            p.theme = newTheme
            for i in p.slides.indices {
                // Placeholder text picks up the new theme's title color, sizes and caps.
                for j in p.slides[i].elements.indices {
                    guard let role = p.slides[i].elements[j].placeholder, var text = p.slides[i].elements[j].text else { continue }
                    if role.isTitle {
                        if text.defaultColor == old.titleColor { text.defaultColor = newTheme.titleColor }
                        if role == .title, text.defaultSize == old.titleSize { text.defaultSize = newTheme.titleSize }
                        if role == .centeredTitle, text.defaultSize == old.titleSize * 1.4 { text.defaultSize = newTheme.titleSize * 1.4 }
                        text.updateRuns { r in
                            if r.allCaps == old.titleCaps { r.allCaps = newTheme.titleCaps }
                            if (r.bold ?? false) == old.titleBold { r.bold = newTheme.titleBold ? true : nil }
                        }
                    } else {
                        if text.defaultSize == old.bodySize { text.defaultSize = newTheme.bodySize }
                        text.updateParagraphs { para in
                            if case .symbol(let s) = para.bullet, s == old.bulletSymbol { para.bullet = .symbol(newTheme.bulletSymbol) }
                            if para.bulletColor == old.bulletColor { para.bulletColor = newTheme.bulletColor }
                        }
                    }
                    p.slides[i].elements[j].text = text
                }
            }
        }
    }

    func applyColors(_ colors: ThemeColors) {
        change("Theme Colors") { p in p.theme.colors = colors }
    }

    func applyFonts(_ pair: FontPair) {
        change("Theme Fonts") { p in
            p.theme.headingFont = pair.heading
            p.theme.bodyFont = pair.body
        }
    }

    func setBackground(_ fill: Fill?, applyToAll: Bool) {
        let indices = selectedSlides
        change("Format Background") { p in
            if applyToAll {
                if let fill { p.theme.background = fill; p.theme.titleBackground = nil }
                for i in p.slides.indices { p.slides[i].background = nil }
            } else {
                for i in indices { p.slides[i].background = fill }
            }
        }
    }

    func setHideBackgroundGraphics(_ hide: Bool) {
        let indices = selectedSlides
        change("Hide Background Graphics") { p in for i in indices { p.slides[i].hideBackgroundGraphics = hide } }
    }

    /// Changes the slide size, scaling content to fit (or keeping its size and centering).
    func setSlideSize(_ size: CGSize, scaleContent: Bool) {
        let old = slideSize
        guard size != old, size.width > 10, size.height > 10 else { return }
        change("Slide Size") { p in
            p.slideSize = size
            let sx = size.width / old.width, sy = size.height / old.height
            let s = scaleContent ? min(sx, sy) : max(sx, sy)
            let dx = (size.width - old.width * s) / 2, dy = (size.height - old.height * s) / 2
            for i in p.slides.indices {
                for j in p.slides[i].elements.indices {
                    var e = p.slides[i].elements[j]
                    let f = e.frame
                    e.setFrame(CGRect(x: f.minX * s + dx, y: f.minY * s + dy, width: f.width * s, height: f.height * s))
                    Self.scaleText(&e, by: s)
                    p.slides[i].elements[j] = e
                }
            }
        }
    }

    static func scaleText(_ e: inout SlideElement, by s: CGFloat) {
        guard abs(s - 1) > 0.01 else { return }
        switch e.content {
        case .shape(var shape):
            shape.text.defaultSize = (shape.text.defaultSize * Double(s) * 2).rounded() / 2
            shape.text.updateRuns { if let size = $0.size { $0.size = (size * Double(s) * 2).rounded() / 2 } }
            e.content = .shape(shape)
        case .group(var g):
            for i in g.children.indices { scaleText(&g.children[i], by: s) }
            e.content = .group(g)
        case .table(var t):
            for r in t.rows.indices {
                for c in t.rows[r].indices {
                    t.rows[r][c].text.defaultSize = (t.rows[r][c].text.defaultSize * Double(s) * 2).rounded() / 2
                }
            }
            t.rowHeights = t.rowHeights.map { $0 * Double(s) }
            e.content = .table(t)
        case .chart(var c):
            c.fontSize *= Double(s)
            e.content = .chart(c)
        default:
            break
        }
    }

    func setHeaderFooter(_ hf: HeaderFooter) {
        change("Header & Footer") { p in p.headerFooter = hf }
    }

    func setShowSettings(_ settings: SlideShowSettings) {
        change("Set Up Slide Show") { p in p.showSettings = settings }
    }

    func setProperties(title: String, author: String) {
        change("Properties") { p in
            p.title = title
            p.author = author
        }
    }
}

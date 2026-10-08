import AppKit
import AVFoundation

enum AlignMode: String, CaseIterable {
    case left, center, right, top, middle, bottom

    var title: String {
        switch self {
        case .left: "Align Left"
        case .center: "Align Center"
        case .right: "Align Right"
        case .top: "Align Top"
        case .middle: "Align Middle"
        case .bottom: "Align Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .left: "align.horizontal.left"
        case .center: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
}

enum ArrangeOrder { case front, forward, backward, back }

extension PresentationController {
    // MARK: - Inserting

    /// A frame centered on the slide.
    func centeredFrame(_ size: CGSize) -> CGRect {
        CGRect(x: (slideSize.width - size.width) / 2, y: (slideSize.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Adds elements to the current slide and selects them.
    func insert(_ elements: [SlideElement], name: String, editText: Bool = false) {
        guard !elements.isEmpty else { return }
        changeSlide(name) { slide in slide.elements.append(contentsOf: elements) }
        select(elements.map(\.id))
        if editText, let first = elements.first { beginEditing(first.id) }
    }

    func insertTextBox(frame: CGRect? = nil, text: String = "", vertical: Bool = false) {
        let r = frame ?? centeredFrame(CGSize(width: 300, height: 40))
        var box = SlideElement.textBox(text, frame: r, size: 18)
        box.name = "TextBox \(currentSlide.elements.count + 1)"
        if vertical { box.text?.direction = .rotated90; box.text?.autofit = .none }
        PresentationController.fitHeight(&box, theme: theme)
        insert([box], name: "Insert Text Box", editText: true)
    }

    func insertShape(_ kind: ShapeKind, frame: CGRect? = nil) {
        let size: CGSize = kind == .rect || kind.category == .arrows ? CGSize(width: 180, height: 110) : CGSize(width: 140, height: 140)
        var shape = SlideElement.shape(kind, frame: frame ?? centeredFrame(size))
        shape.name = "\(kind.title) \(currentSlide.elements.count + 1)"
        insert([shape], name: "Insert Shape")
    }

    func insertLine(from a: CGPoint, to b: CGPoint, kind: ConnectorKind = .straight, arrow: Bool = false) {
        var style = LineStyle.solid(.theme(.accent1), width: 1.5)
        if arrow { style.tail = .triangle }
        var line = SlideElement.line(from: a, to: b, style: style, kind: kind)
        line.name = (arrow ? "Arrow " : "Line ") + "\(currentSlide.elements.count + 1)"
        insert([line], name: "Insert Line")
    }

    /// Inserts a picture, fitted into a placeholder or the slide.
    func insertPicture(_ data: Data, filename: String, at point: CGPoint? = nil, replacing placeholderID: UUID? = nil) {
        guard let image = NSImage(data: data) else { NSSound.beep(); return }
        var mediaID = ""
        change("Insert Picture") { p in mediaID = p.addMedia(data, filename: filename) }
        let natural = image.size.width > 0 ? image.size : CGSize(width: 400, height: 300)
        var target: CGRect
        let placeholder = placeholderID.flatMap { currentSlide.element($0) }
            ?? (point == nil ? currentSlide.elements.first(where: { ($0.placeholder == .picture || $0.placeholder == .body) && !$0.hasText && !$0.isImage }) : nil)
        if let placeholder {
            // Fill the placeholder, cropping the overflow like PowerPoint.
            target = placeholder.frame
        } else {
            let maxSize = CGSize(width: slideSize.width * 0.7, height: slideSize.height * 0.7)
            let s = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
            let size = CGSize(width: natural.width * s, height: natural.height * s)
            target = point.map { CGRect(x: $0.x - size.width / 2, y: $0.y - size.height / 2, width: size.width, height: size.height) } ?? centeredFrame(size)
        }
        var content = ImageContent(mediaID: mediaID)
        if placeholder != nil {
            let imageAspect = natural.width / max(natural.height, 1), boxAspect = target.width / max(target.height, 1)
            if imageAspect > boxAspect {
                let excess = 1 - boxAspect / imageAspect
                content.crop.left = excess / 2; content.crop.right = excess / 2
            } else {
                let excess = 1 - imageAspect / boxAspect
                content.crop.top = excess / 2; content.crop.bottom = excess / 2
            }
        }
        var element = SlideElement(name: "Picture \(currentSlide.elements.count + 1)", frame: target, content: .image(content))
        element.lockAspectRatio = true
        element.altText = (filename as NSString).deletingPathExtension
        let replaced = placeholder?.id
        changeSlide("Insert Picture") { slide in
            if let replaced, let i = slide.index(of: replaced) {
                element.placeholder = slide.elements[i].placeholder == .picture ? .picture : nil
                slide.elements[i] = element
            } else {
                slide.elements.append(element)
            }
        }
        select([element.id])
    }

    func insertTable(rows: Int, columns: Int, frame: CGRect? = nil) {
        let width = frame?.width ?? min(slideSize.width - 120, CGFloat(columns) * 160)
        var table = TableContent.make(rows: rows, columns: columns, width: Double(width))
        table.style.color = .theme(.accent1)
        let height = CGFloat(table.rowHeights.reduce(0, +))
        let r = frame.map { CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: height) } ?? centeredFrame(CGSize(width: width, height: height))
        let element = SlideElement(name: "Table \(currentSlide.elements.count + 1)", frame: r, content: .table(table))
        replaceEmptyBodyPlaceholder(with: element, name: "Insert Table")
    }

    func insertChart(_ kind: ChartKind) {
        let element = SlideElement(name: "Chart \(currentSlide.elements.count + 1)", frame: centeredFrame(CGSize(width: 560, height: 340)),
                                   content: .chart(ChartContent.sample(kind)))
        replaceEmptyBodyPlaceholder(with: element, name: "Insert Chart")
        presenter?.presentChartEditor(element.id)
    }

    /// Puts content where an empty content placeholder is, like clicking its icon.
    func replaceEmptyBodyPlaceholder(with element: SlideElement, name: String) {
        var element = element
        if let placeholder = currentSlide.elements.first(where: { $0.placeholder == .body && !$0.hasText }) {
            if case .table(var t) = element.content {
                let f = placeholder.frame
                t.columnWidths = t.columnWidths.map { _ in Double(f.width) / Double(t.columnCount) }
                element.content = .table(t)
                element.frame = CGRect(x: f.minX, y: f.minY, width: f.width, height: element.frame.height)
            } else {
                element.frame = placeholder.frame
            }
            let id = placeholder.id
            changeSlide(name) { slide in
                if let i = slide.index(of: id) { slide.elements[i] = element }
            }
            select([element.id])
        } else {
            insert([element], name: name)
        }
    }

    func insertIcon(_ symbol: String) {
        let element = SlideElement(name: "Icon \(currentSlide.elements.count + 1)", frame: centeredFrame(CGSize(width: 96, height: 96)),
                                   content: .icon(IconContent(symbol: symbol)))
        var e = element
        e.lockAspectRatio = true
        insert([e], name: "Insert Icon")
    }

    func insertMedia(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { NSSound.beep(); return }
        let asset = AVURLAsset(url: url)
        let isVideo = !asset.tracks(withMediaType: .video).isEmpty
        var posterData: Data?
        var size = CGSize(width: 480, height: 270)
        if isVideo {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) {
                posterData = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                let s = min(1, 560 / CGFloat(cg.width), 315 / CGFloat(cg.height))
                size = CGSize(width: CGFloat(cg.width) * s, height: CGFloat(cg.height) * s)
            }
        } else {
            size = CGSize(width: 64, height: 64)
        }
        var mediaID = "", posterID: String?
        change("Insert Media") { p in
            mediaID = p.addMedia(data, filename: url.lastPathComponent)
            if let posterData { posterID = p.addMedia(posterData, filename: "poster.jpg") }
        }
        var content = MediaContent(kind: isVideo ? .video : .audio, mediaID: mediaID, posterID: posterID)
        content.autoplay = !isVideo
        var element = SlideElement(name: url.deletingPathExtension().lastPathComponent, frame: centeredFrame(size), content: .media(content))
        element.lockAspectRatio = true
        insert([element], name: "Insert Media")
    }

    func insertWordArt(_ preset: WordArtPreset) {
        var box = SlideElement.textBox("Your text here", frame: centeredFrame(CGSize(width: 560, height: 100)), size: 60,
                                       role: .heading, alignment: .center)
        box.name = "WordArt \(currentSlide.elements.count + 1)"
        box.text?.updateRuns { preset.apply(&$0) }
        if var body = box.text { body.wrap = true; box.text = body }
        PresentationController.fitHeight(&box, theme: theme)
        insert([box], name: "Insert WordArt", editText: true)
    }

    func insertSmartArt(_ kind: SmartArtKind, items: [String]) {
        let group = SmartArtBuilder.build(kind, items: items, in: centeredFrame(CGSize(width: 720, height: 340)))
        replaceEmptyBodyPlaceholder(with: group, name: "Insert SmartArt")
    }

    func insertDateTime(_ text: String) {
        if let editor = textEditor { editor.insertText(text); return }
        insertTextBox(text: text)
    }

    func insertSymbol(_ text: String) {
        if let editor = textEditor { editor.insertText(text); return }
        insertTextBox(text: text)
    }

    // MARK: - Deleting and duplicating

    func deleteSelection() {
        if let child = selectedChild {
            changeSlide("Delete") { slide in
                for i in slide.elements.indices {
                    if case .group(var g) = slide.elements[i].content, g.children.contains(where: { $0.id == child }) {
                        g.children.removeAll { $0.id == child }
                        if g.children.count == 1 {
                            slide.elements[i] = g.children[0]
                        } else {
                            slide.elements[i].content = .group(g)
                            slide.elements[i].frame = g.children.map(\.frame).reduce(CGRect.null) { $0.union($1) }
                        }
                    }
                }
            }
            selectedChild = nil
            return
        }
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        changeSlide("Delete") { slide in
            slide.elements.removeAll { ids.contains($0.id) }
            slide.animations.removeAll { ids.contains($0.elementID) }
        }
        selection = []
    }

    func duplicateSelection() {
        let elements = selectedElements
        guard !elements.isEmpty else { duplicateSlides(); return }
        let copies = elements.map { e -> SlideElement in
            var copy = e.duplicated()
            copy.offset(by: CGSize(width: 18, height: 18))
            copy.placeholder = nil
            return copy
        }
        insert(copies, name: "Duplicate")
    }

    // MARK: - Moving and sizing

    func nudge(dx: CGFloat, dy: CGFloat) {
        let ids = selection
        changeElements(ids, "Move") { e in
            guard !e.locked else { return }
            e.offset(by: CGSize(width: dx, height: dy))
        }
    }

    func setFrame(_ id: UUID, _ frame: CGRect, name: String = "Size and Position") {
        let theme = self.theme
        changeElements([id], name) { e in
            e.setFrame(frame)
            PresentationController.fitHeight(&e, theme: theme)
        }
    }

    func setRotation(_ degrees: Double) {
        changeTargets("Rotate") { $0.rotation = degrees.truncatingRemainder(dividingBy: 360) }
    }

    func rotate(by degrees: Double) {
        changeTargets("Rotate") { e in
            var r = (e.rotation + degrees).truncatingRemainder(dividingBy: 360)
            if r < 0 { r += 360 }
            e.rotation = r
        }
    }

    func flip(horizontal: Bool) {
        changeTargets(horizontal ? "Flip Horizontal" : "Flip Vertical") { e in
            if horizontal { e.flipH.toggle() } else { e.flipV.toggle() }
        }
    }

    // MARK: - Arrange

    func arrange(_ order: ArrangeOrder) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        let name: String
        switch order {
        case .front: name = "Bring to Front"
        case .forward: name = "Bring Forward"
        case .backward: name = "Send Backward"
        case .back: name = "Send to Back"
        }
        changeSlide(name) { slide in
            var elements = slide.elements
            switch order {
            case .front:
                let moving = elements.filter { ids.contains($0.id) }
                elements.removeAll { ids.contains($0.id) }
                elements += moving
            case .back:
                let moving = elements.filter { ids.contains($0.id) }
                elements.removeAll { ids.contains($0.id) }
                elements = moving + elements
            case .forward:
                for i in stride(from: elements.count - 2, through: 0, by: -1) where ids.contains(elements[i].id) && !ids.contains(elements[i + 1].id) {
                    elements.swapAt(i, i + 1)
                }
            case .backward:
                for i in 1..<max(elements.count, 1) where ids.contains(elements[i].id) && !ids.contains(elements[i - 1].id) {
                    elements.swapAt(i, i - 1)
                }
            }
            slide.elements = elements
        }
    }

    /// Aligns the selection to each other, or to the slide when one object is selected.
    func align(_ mode: AlignMode, toSlide: Bool = false) {
        let elements = selectedElements.filter { !$0.locked }
        guard !elements.isEmpty else { return }
        let useSlide = toSlide || elements.count == 1
        let bounds = useSlide ? CGRect(origin: .zero, size: slideSize)
            : elements.map { SlideRenderer.rotatedBounds($0.frame, rotation: $0.rotation) }.reduce(CGRect.null) { $0.union($1) }
        changeElements(elements.map(\.id), mode.title) { e in
            let b = SlideRenderer.rotatedBounds(e.frame, rotation: e.rotation)
            var d = CGSize.zero
            switch mode {
            case .left: d.width = bounds.minX - b.minX
            case .center: d.width = bounds.midX - b.midX
            case .right: d.width = bounds.maxX - b.maxX
            case .top: d.height = bounds.minY - b.minY
            case .middle: d.height = bounds.midY - b.midY
            case .bottom: d.height = bounds.maxY - b.maxY
            }
            e.offset(by: d)
        }
    }

    func distribute(horizontally: Bool) {
        let elements = selectedElements.filter { !$0.locked }
        guard elements.count >= 3 else {
            if elements.count >= 1 { align(horizontally ? .center : .middle, toSlide: true) }
            return
        }
        let sorted = elements.sorted { horizontally ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
        let first = sorted.first!.frame, last = sorted.last!.frame
        let total = sorted.reduce(0) { $0 + (horizontally ? $1.frame.width : $1.frame.height) }
        let span = horizontally ? last.maxX - first.minX : last.maxY - first.minY
        let gap = (span - total) / CGFloat(sorted.count - 1)
        var position = horizontally ? first.minX : first.minY
        var targets: [UUID: CGFloat] = [:]
        for e in sorted {
            targets[e.id] = position
            position += (horizontally ? e.frame.width : e.frame.height) + gap
        }
        changeElements(sorted.map(\.id), horizontally ? "Distribute Horizontally" : "Distribute Vertically") { e in
            guard let t = targets[e.id] else { return }
            e.offset(by: horizontally ? CGSize(width: t - e.frame.minX, height: 0) : CGSize(width: 0, height: t - e.frame.minY))
        }
    }

    func group() {
        let ids = selection
        guard ids.count >= 2 else { return }
        let members = currentSlide.elements.filter { ids.contains($0.id) }
        let frame = members.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        var group = SlideElement(name: "Group \(currentSlide.elements.count + 1)", frame: frame,
                                 content: .group(GroupContent(children: members.map { var m = $0; m.placeholder = nil; return m })))
        group.lockAspectRatio = false
        let set = Set(ids)
        changeSlide("Group") { slide in
            let firstIndex = slide.elements.firstIndex { set.contains($0.id) } ?? slide.elements.count
            slide.elements.removeAll { set.contains($0.id) }
            slide.elements.insert(group, at: min(firstIndex, slide.elements.count))
            // Animations of members move to the group.
            for i in slide.animations.indices where set.contains(slide.animations[i].elementID) { slide.animations[i].elementID = group.id }
        }
        select([group.id])
    }

    func ungroup() {
        let groups = selectedElements.filter(\.isGroup)
        guard !groups.isEmpty else { return }
        var newSelection: [UUID] = []
        changeSlide("Ungroup") { slide in
            for g in groups {
                guard let i = slide.index(of: g.id), case .group(let content) = g.content else { continue }
                var children = content.children
                // Bake the group's rotation into its children.
                if g.rotation != 0 {
                    let c = CGPoint(x: g.frame.midX, y: g.frame.midY)
                    let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(g.rotation * .pi / 180)).translatedBy(x: -c.x, y: -c.y)
                    for j in children.indices {
                        let center = CGPoint(x: children[j].frame.midX, y: children[j].frame.midY).applying(t)
                        children[j].offset(by: CGSize(width: center.x - children[j].frame.midX, height: center.y - children[j].frame.midY))
                        children[j].rotation = (children[j].rotation + g.rotation).truncatingRemainder(dividingBy: 360)
                    }
                }
                slide.elements.remove(at: i)
                slide.elements.insert(contentsOf: children, at: i)
                newSelection += children.map(\.id)
                slide.animations.removeAll { $0.elementID == g.id }
            }
        }
        select(newSelection)
    }

    func toggleLock() {
        let lock = !selectedElements.allSatisfy(\.locked)
        changeElements(selection, lock ? "Lock" : "Unlock") { $0.locked = lock }
    }

    func setHidden(_ id: UUID, hidden: Bool) {
        changeElements([id], hidden ? "Hide" : "Show") { $0.hidden = hidden }
        if hidden { selection.removeAll { $0 == id } }
    }

    func rename(_ id: UUID, to name: String) {
        changeElements([id], "Rename") { $0.name = name }
    }

    /// Moves an element in the stacking order (Selection pane drag).
    func moveElement(_ id: UUID, toIndex: Int) {
        changeSlide("Reorder") { slide in
            guard let i = slide.index(of: id) else { return }
            let e = slide.elements.remove(at: i)
            slide.elements.insert(e, at: max(0, min(toIndex, slide.elements.count)))
        }
    }

    // MARK: - Shape formatting

    func setFill(_ fill: Fill) {
        changeTargets("Shape Fill") { e in
            switch e.content {
            case .shape(var s): s.fill = fill; e.content = .shape(s)
            case .group(var g):
                for i in g.children.indices { if case .shape(var s) = g.children[i].content { s.fill = fill; g.children[i].content = .shape(s) } }
                e.content = .group(g)
            case .icon(var icon):
                if let c = fill.solidColor { icon.color = c; e.content = .icon(icon) }
            case .chart(var c): c.background = fill; e.content = .chart(c)
            default: break
            }
        }
    }

    func setLine(_ change: @escaping (inout LineStyle) -> Void) {
        changeTargets("Shape Outline") { e in
            switch e.content {
            case .shape(var s): change(&s.line); e.content = .shape(s)
            case .image(var i):
                if i.line.color == nil { i.line = .solid(.theme(.dark1), width: 1) }
                change(&i.line); e.content = .image(i)
            case .line(var l): change(&l.line); e.content = .line(l)
            case .group(var g):
                for i in g.children.indices {
                    switch g.children[i].content {
                    case .shape(var s): change(&s.line); g.children[i].content = .shape(s)
                    case .line(var l): change(&l.line); g.children[i].content = .line(l)
                    default: break
                    }
                }
                e.content = .group(g)
            default: break
            }
        }
    }

    func setEffects(_ change: @escaping (inout Effects) -> Void) {
        changeTargets("Shape Effects") { e in
            switch e.content {
            case .shape(var s): change(&s.effects); e.content = .shape(s)
            case .image(var i): change(&i.effects); e.content = .image(i)
            case .line(var l): change(&l.effects); e.content = .line(l)
            default: break
            }
        }
    }

    func changeShapeKind(_ kind: ShapeKind) {
        changeTargets("Change Shape") { e in
            if case .shape(var s) = e.content {
                s.kind = kind
                s.adjustments = []
                e.content = .shape(s)
            } else if case .image(var i) = e.content {
                i.maskShape = kind == .rect ? nil : kind
                e.content = .image(i)
            }
        }
    }

    func setAdjustments(_ id: UUID, _ values: [Double]) {
        changeElements([id], "Adjust Shape") { e in
            if case .shape(var s) = e.content { s.adjustments = values; e.content = .shape(s) }
        }
    }

    /// Applies a Shape Styles preset.
    func applyShapeStyle(_ style: ShapeStylePreset) {
        changeTargets("Shape Style") { e in
            guard case .shape(var s) = e.content else { return }
            s.fill = style.fill
            s.line = style.line
            s.effects = style.effects
            s.text.defaultColor = style.textColor
            e.content = .shape(s)
        }
    }

    func setImage(_ change: @escaping (inout ImageContent) -> Void, name: String = "Format Picture") {
        changeTargets(name) { e in
            if case .image(var i) = e.content { change(&i); e.content = .image(i) }
        }
    }

    /// Resets a picture's size, crop and adjustments.
    func resetPicture(size: Bool) {
        let media = presentation.media
        changeTargets("Reset Picture") { e in
            guard case .image(var i) = e.content else { return }
            i.adjustments = ImageAdjustments()
            i.crop = CropInsets()
            i.maskShape = nil
            i.effects = .none
            e.content = .image(i)
            if size, let natural = ImageCache.size(i.mediaID, media) {
                let s = min(1, 720 / natural.width, 480 / natural.height)
                e.frame.size = CGSize(width: natural.width * s, height: natural.height * s)
                e.rotation = 0
            }
        }
    }

    func setMedia(_ change: @escaping (inout MediaContent) -> Void) {
        changeTargets("Playback") { e in
            if case .media(var m) = e.content { change(&m); e.content = .media(m) }
        }
    }

    func setAction(_ action: ElementAction?) {
        changeTargets("Action") { $0.action = action }
    }

    func setAltText(_ text: String) {
        changeTargets("Alt Text") { $0.altText = text }
    }

    // MARK: - Format painter

    func copyFormat(sticky: Bool = false) {
        guard let element = primaryElement else { return }
        formatPainter = FormatPainter(element: element, runStyle: textEditor?.currentRunStyle ?? element.text?.firstRunStyle, sticky: sticky)
    }

    func paintFormat(onto id: UUID) {
        guard let painter = formatPainter else { return }
        let source = painter.element
        changeElements([id], "Paste Formatting") { e in
            switch (e.content, source.content) {
            case (.shape(var s), .shape(let src)):
                s.fill = src.fill
                s.line = src.line
                s.effects = src.effects
                if let run = painter.runStyle {
                    s.text.updateRuns { r in
                        let link = r.link
                        r = run
                        r.link = link
                    }
                    s.text.defaultColor = src.text.defaultColor
                }
                e.content = .shape(s)
            case (.image(var i), .image(let src)):
                i.line = src.line
                i.effects = src.effects
                i.adjustments = src.adjustments
                e.content = .image(i)
            case (.line(var l), .line(let src)):
                l.line = src.line
                l.effects = src.effects
                e.content = .line(l)
            default:
                break
            }
        }
        if !painter.sticky { formatPainter = nil }
    }
}

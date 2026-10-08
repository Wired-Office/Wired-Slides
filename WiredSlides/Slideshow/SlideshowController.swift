import AppKit
import Combine
import SwiftUI

/// Pen, highlighter and laser pointer drawn over the show.
final class InkOverlay: NSView {
    enum Tool: String { case none, pen, highlighter, laser, eraser }
    var tool: Tool = .none { didSet { updateCursor(); needsDisplay = true } }
    var penColor: NSColor = .systemRed
    var laserColor: NSColor = .red
    /// Strokes per slide, in slide coordinates.
    private var strokes: [Int: [(Tool, NSColor, [CGPoint])]] = [:]
    var slideIndex = 0 { didSet { needsDisplay = true } }
    var slideSize = CGSize(width: 960, height: 540)
    private var laserPoint: CGPoint?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { tool == .none ? nil : super.hitTest(point) }

    private var fit: (scale: CGFloat, origin: CGPoint) {
        let s = min(bounds.width / slideSize.width, bounds.height / slideSize.height)
        return (s, CGPoint(x: (bounds.width - slideSize.width * s) / 2, y: (bounds.height - slideSize.height * s) / 2))
    }

    private func slidePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let f = fit
        return CGPoint(x: (p.x - f.origin.x) / f.scale, y: (p.y - f.origin.y) / f.scale)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateCursor() {
        switch tool {
        case .laser: NSCursor.hide()
        case .none: NSCursor.unhide()
        default: NSCursor.unhide(); NSCursor.crosshair.set()
        }
        if tool != .laser { laserPoint = nil }
    }

    override func mouseMoved(with event: NSEvent) {
        guard tool == .laser else { return }
        laserPoint = slidePoint(event)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = slidePoint(event)
        switch tool {
        case .pen, .highlighter:
            strokes[slideIndex, default: []].append((tool, penColor, [p]))
        case .eraser:
            erase(near: p)
        case .laser:
            laserPoint = p
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = slidePoint(event)
        switch tool {
        case .pen, .highlighter:
            if var list = strokes[slideIndex], !list.isEmpty {
                list[list.count - 1].2.append(p)
                strokes[slideIndex] = list
            }
        case .eraser: erase(near: p)
        case .laser: laserPoint = p
        case .none: break
        }
        needsDisplay = true
    }

    private func erase(near p: CGPoint) {
        strokes[slideIndex]?.removeAll { stroke in stroke.2.contains { hypot($0.x - p.x, $0.y - p.y) < 12 } }
    }

    func clearSlide() {
        strokes[slideIndex] = []
        needsDisplay = true
    }

    var hasInk: Bool { !(strokes[slideIndex] ?? []).isEmpty }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let f = fit
        ctx.translateBy(x: f.origin.x, y: f.origin.y)
        ctx.scaleBy(x: f.scale, y: f.scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (tool, color, points) in strokes[slideIndex] ?? [] {
            ctx.setStrokeColor((tool == .highlighter ? NSColor.systemYellow.withAlphaComponent(0.4) : color).cgColor)
            ctx.setLineWidth(tool == .highlighter ? 18 : 3)
            ctx.addLines(between: points.count == 1 ? [points[0], points[0]] : points)
            ctx.strokePath()
        }
        if let p = laserPoint, tool == .laser {
            ctx.setShadow(offset: .zero, blur: 12, color: laserColor.cgColor)
            ctx.setFillColor(laserColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
        }
    }
}

/// The slide show view: the stage, ink, black/white screens and input.
final class SlideshowView: NSView {
    let stage: SlideStage
    let ink = InkOverlay()
    weak var show: SlideshowController?
    private let blank = CALayer()
    private let endLabel = NSTextField(labelWithString: "End of slide show, click to exit.")

    init(presentation: Presentation) {
        stage = SlideStage(presentation: presentation)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        for v in [stage, ink] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        ink.slideSize = presentation.slideSize
        endLabel.textColor = NSColor(white: 0.85, alpha: 1)
        endLabel.font = .systemFont(ofSize: 16)
        endLabel.isHidden = true
        endLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(endLabel)
        NSLayoutConstraint.activate([endLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20), endLabel.centerXAnchor.constraint(equalTo: centerXAnchor)])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    enum Blank { case none, black, white, end }

    func setBlank(_ mode: Blank) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blank.removeFromSuperlayer()
        endLabel.isHidden = mode != .end
        if mode != .none {
            blank.frame = bounds
            blank.backgroundColor = mode == .white ? NSColor.white.cgColor : NSColor.black.cgColor
            layer?.addSublayer(blank)
            blank.zPosition = 10
        }
        CATransaction.commit()
        endLabel.layer?.zPosition = 20
    }

    override func keyDown(with event: NSEvent) {
        if show?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 1, let show { show.handleClick(at: convert(event.locationInWindow, from: nil), in: self) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let show else { return }
        NSMenu.popUpContextMenu(show.contextMenu(), with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 3, event.phase != .changed || !event.hasPreciseScrollingDeltas else { return }
        if event.scrollingDeltaY < 0 { show?.next() } else { show?.previous() }
    }
}

/// Runs a slide show: windows on the chosen display, navigation, timings and the presenter view.
final class SlideshowController: NSObject, ObservableObject, NSWindowDelegate {
    private static var running: [SlideshowController] = []

    let presentation: Presentation
    weak var editor: PresentationController?
    private var window: NSWindow?
    private var presenterWindow: NSWindow?
    let view: SlideshowView
    /// Order of slides shown.
    let order: [Int]
    @Published private(set) var position = 0
    @Published private(set) var blank: SlideshowView.Blank = .none
    @Published var startDate = Date()
    @Published var slideStart = Date()
    @Published var paused = false
    private var pausedAt: Date?
    private var advanceTimer: Timer?
    private var typedNumber = ""
    private let rehearse: Bool
    private var rehearsal: [UUID: Double] = [:]
    private let windowed: Bool
    private var ended = false

    var currentIndex: Int { order[min(position, order.count - 1)] }
    var nextIndex: Int? { position + 1 < order.count ? order[position + 1] : (presentation.showSettings.loopUntilEscape ? order.first : nil) }

    init(presentation: Presentation, editor: PresentationController?, startingAt start: Int, rehearse: Bool, windowed: Bool) {
        self.presentation = presentation
        self.editor = editor
        self.rehearse = rehearse
        self.windowed = windowed
        var order = presentation.visibleSlideIndices
        if !order.contains(start) { order.append(start); order.sort() }
        if order.isEmpty { order = [0] }
        self.order = order
        view = SlideshowView(presentation: presentation)
        super.init()
        view.show = self
        view.stage.animationsEnabled = !presentation.showSettings.showWithoutAnimation
        view.stage.onIdle = { [weak self] in self?.scheduleAutoAdvance() }
        view.ink.penColor = presentation.showSettings.penColor.nsColor
        view.ink.laserColor = presentation.showSettings.laserColor.nsColor
        position = order.firstIndex(of: start) ?? 0
    }

    // MARK: - Starting and ending

    static func start(_ presentation: Presentation, editor: PresentationController?, from index: Int, presenter: Bool, rehearse: Bool = false, windowed: Bool = false) {
        let show = SlideshowController(presentation: presentation, editor: editor, startingAt: index, rehearse: rehearse, windowed: windowed)
        running.append(show)
        show.open(presenter: presenter)
    }

    private func open(presenter: Bool) {
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens[0]
        // With two displays, the audience sees the other one.
        let audience = screens.count > 1 ? (screens.first { $0 != main } ?? main) : main
        if windowed {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Reading View"
            w.titlebarAppearsTransparent = true
            w.contentView = view
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.backgroundColor = .black
            window = w
        } else {
            let w = KeyableWindow(contentRect: audience.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: audience)
            w.setFrame(audience.frame, display: true)
            w.level = .mainMenu + 1
            w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
            w.backgroundColor = .black
            w.contentView = view
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
            if audience == main || screens.count == 1 { NSApp.presentationOptions = [.hideDock, .hideMenuBar] }
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(view)
        view.layoutSubtreeIfNeeded()
        startDate = Date()
        slideStart = Date()
        view.stage.show(currentIndex, built: false)
        view.ink.slideIndex = currentIndex
        if presenter && !windowed { openPresenter(on: screens.count > 1 ? main : nil) }
        scheduleAutoAdvance()
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func openPresenter(on screen: NSScreen?) {
        let host = NSHostingController(rootView: PresenterView(show: self))
        let frame = screen?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1100, height: 700)
        let w = KeyableWindow(contentRect: frame, styleMask: screen == nil ? [.titled, .closable, .resizable, .miniaturizable] : [.titled, .resizable, .closable],
                              backing: .buffered, defer: false)
        w.title = "Presenter View"
        w.contentViewController = host
        w.setFrame(frame, display: true)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.forwarder = { [weak self] event in self?.handleKey(event) ?? false }
        presenterWindow = w
        w.makeKeyAndOrderFront(nil)
        if screen != nil { w.toggleFullScreen(nil) } else { window?.orderFront(nil) }
    }

    func end() {
        guard !ended else { return }
        ended = true
        advanceTimer?.invalidate()
        NSApp.presentationOptions = []
        NSCursor.unhide()
        if rehearse { offerTimings() }
        presenterWindow?.delegate = nil
        presenterWindow?.close()
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        if let editor, order.indices.contains(position) { editor.setCurrentSlide(currentIndex) }
        editor?.document?.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        Self.running.removeAll { $0 === self }
    }

    func windowWillClose(_ notification: Notification) { end() }

    private func offerTimings() {
        recordRehearsal()
        guard let editor, !rehearsal.isEmpty else { return }
        let total = rehearsal.values.reduce(0, +)
        let alert = NSAlert()
        alert.messageText = "The total time for the slide show was \(Self.format(total))."
        alert.informativeText = "Do you want to keep the new slide timings?"
        alert.addButton(withTitle: "Keep Timings")
        alert.addButton(withTitle: "Don't Keep")
        if alert.runModal() == .alertFirstButtonReturn {
            let timings = rehearsal
            editor.change("Rehearse Timings") { p in
                for i in p.slides.indices {
                    if let t = timings[p.slides[i].id] { p.slides[i].transition.advanceAfter = (t * 10).rounded() / 10 }
                }
                p.showSettings.useTimings = true
            }
        }
    }

    private func recordRehearsal() {
        guard rehearse, presentation.slides.indices.contains(currentIndex) else { return }
        let id = presentation.slides[currentIndex].id
        rehearsal[id, default: 0] += Date().timeIntervalSince(slideStart)
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Navigation

    func next() {
        if blank != .none {
            if blank == .end { end(); return }
            setBlank(.none)
            return
        }
        if view.stage.isAnimating {
            view.stage.finishAnimations()
            return
        }
        if view.stage.hasMoreSteps {
            view.stage.runStep()
            objectWillChange.send()
            return
        }
        goTo(position + 1)
    }

    func previous() {
        if blank != .none, blank != .end { setBlank(.none); return }
        if blank == .end { setBlank(.none); return }
        guard position > 0 else { return }
        recordRehearsal()
        position -= 1
        slideStart = Date()
        view.stage.show(currentIndex, built: true)
        view.ink.slideIndex = currentIndex
        scheduleAutoAdvance()
    }

    func goTo(_ newPosition: Int, animated: Bool = true) {
        advanceTimer?.invalidate()
        if newPosition >= order.count {
            if presentation.showSettings.loopUntilEscape {
                goTo(0)
            } else if AppSettings.shared.endWithBlackSlide && !windowed {
                recordRehearsal()
                setBlank(.end)
            } else {
                end()
            }
            return
        }
        guard newPosition >= 0 else { return }
        recordRehearsal()
        position = newPosition
        slideStart = Date()
        view.ink.slideIndex = currentIndex
        if animated { view.stage.transition(to: currentIndex) } else { view.stage.show(currentIndex, built: false) }
    }

    func goToSlide(index: Int) {
        guard let p = order.firstIndex(of: index) ?? (presentation.slides.indices.contains(index) ? nil : nil) else {
            // Hidden slides can still be shown by number.
            if presentation.slides.indices.contains(index) {
                recordRehearsal()
                slideStart = Date()
                view.stage.transition(to: index)
            }
            return
        }
        goTo(p)
    }

    func setBlank(_ mode: SlideshowView.Blank) {
        blank = mode
        view.setBlank(mode)
    }

    private func scheduleAutoAdvance() {
        advanceTimer?.invalidate()
        guard !rehearse, presentation.showSettings.useTimings, !paused,
              presentation.slides.indices.contains(currentIndex),
              let after = presentation.slides[currentIndex].transition.advanceAfter else { return }
        let elapsed = Date().timeIntervalSince(slideStart)
        let remaining = max(after - elapsed, 0.05)
        advanceTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            guard let self, self.blank == .none else { return }
            // Run remaining builds, then move on.
            if self.view.stage.hasMoreSteps {
                self.view.stage.runStep()
            } else {
                self.goTo(self.position + 1)
            }
        }
    }

    func togglePause() {
        paused.toggle()
        if paused { pausedAt = Date(); advanceTimer?.invalidate() } else {
            if let pausedAt { startDate += Date().timeIntervalSince(pausedAt); slideStart += Date().timeIntervalSince(pausedAt) }
            pausedAt = nil
            scheduleAutoAdvance()
        }
    }

    // MARK: - Input

    func handleClick(at point: CGPoint, in view: SlideshowView) {
        if blank == .end { end(); return }
        guard presentation.slides.indices.contains(currentIndex) else { return }
        let slide = presentation.slides[currentIndex]
        let p = view.stage.slidePoint(point)
        // Media plays on click.
        if let media = view.stage.mediaElement(at: point) {
            view.stage.toggleMedia(media)
            return
        }
        // Actions and hyperlinks.
        if let e = slide.elements.reversed().first(where: { ($0.action != nil || !($0.text?.linkTargets.isEmpty ?? true)) && CanvasGeometry.contains($0, p, tolerance: 2) }) {
            if let action = e.action {
                perform(action)
                return
            }
            if let link = e.text?.linkTargets.first, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        guard slide.transition.advanceOnClick || view.stage.hasMoreSteps else { return }
        next()
    }

    func perform(_ action: ElementAction) {
        switch action {
        case .url(let s): if let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .slide(let id): if let i = presentation.slideIndex(id) { goToSlide(index: i) }
        case .nextSlide: goTo(position + 1)
        case .previousSlide: previous()
        case .firstSlide: goTo(0)
        case .lastSlide: goTo(order.count - 1)
        case .endShow: end()
        }
    }

    /// Returns true when the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let command = event.modifierFlags.contains(.command)
        if command {
            switch chars {
            case "p": view.ink.tool = view.ink.tool == .pen ? .none : .pen; return true
            case "a": view.ink.tool = .none; return true
            case "l": view.ink.tool = view.ink.tool == .laser ? .none : .laser; return true
            case "e": view.ink.tool = .eraser; return true
            case ".": end(); return true
            default: return false
            }
        }
        if let digit = Int(chars), chars.count == 1 {
            typedNumber += String(digit)
            return true
        }
        switch event.specialKey {
        case .rightArrow?, .downArrow?, .pageDown?:
            next()
        case .leftArrow?, .upArrow?, .pageUp?, .backspace?, .delete?:
            previous()
        case .home?:
            goTo(0)
        case .end?:
            goTo(order.count - 1)
        case .carriageReturn?, .enter?:
            if let n = Int(typedNumber), n >= 1 { goToSlide(index: n - 1) } else { next() }
            typedNumber = ""
        default:
            if event.keyCode == 53 { // Escape
                if view.ink.tool != .none { view.ink.tool = .none } else { end() }
                return true
            }
            switch chars {
            case " ", "n": next()
            case "p": previous()
            case "b", ".": setBlank(blank == .black ? .none : .black)
            case "w", ",": setBlank(blank == .white ? .none : .white)
            case "e": view.ink.clearSlide()
            case "s": togglePause()
            case "l": view.ink.tool = view.ink.tool == .laser ? .none : .laser
            case "h": view.ink.tool = view.ink.tool == .highlighter ? .none : .highlighter
            case "-": end()
            default: typedNumber = ""; return false
            }
        }
        objectWillChange.send()
        return true
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.add("Next", symbol: "chevron.right") { [weak self] in self?.next() }
        menu.add("Previous", symbol: "chevron.left") { [weak self] in self?.previous() }
        let go = NSMenu(title: "Go to Slide")
        for i in presentation.slides.indices {
            let title = presentation.slides[i].title
            go.add("\(i + 1)  \(title.isEmpty ? "Slide \(i + 1)" : title)", checked: i == currentIndex) { [weak self] in self?.goToSlide(index: i) }
        }
        menu.addSubmenu(go)
        menu.addItem(.separator())
        menu.add("Laser Pointer", symbol: "light.beacon.max", checked: view.ink.tool == .laser) { [weak self] in self?.view.ink.tool = .laser }
        menu.add("Pen", symbol: "pencil.tip", checked: view.ink.tool == .pen) { [weak self] in self?.view.ink.tool = .pen }
        menu.add("Highlighter", symbol: "highlighter", checked: view.ink.tool == .highlighter) { [weak self] in self?.view.ink.tool = .highlighter }
        menu.add("Eraser", symbol: "eraser", checked: view.ink.tool == .eraser) { [weak self] in self?.view.ink.tool = .eraser }
        menu.add("Erase All Ink on Slide", symbol: "trash") { [weak self] in self?.view.ink.clearSlide() }
        menu.add("Arrow", symbol: "cursorarrow", checked: view.ink.tool == .none) { [weak self] in self?.view.ink.tool = .none }
        menu.addItem(.separator())
        menu.add("Black Screen", symbol: "rectangle.fill") { [weak self] in self?.setBlank(.black) }
        menu.add("White Screen", symbol: "rectangle") { [weak self] in self?.setBlank(.white) }
        menu.add(paused ? "Resume" : "Pause", symbol: paused ? "play" : "pause") { [weak self] in self?.togglePause() }
        menu.addItem(.separator())
        menu.add("End Show", symbol: "xmark") { [weak self] in self?.end() }
        return menu
    }
}

/// A borderless window that can become key and forwards keys it doesn't handle.
final class KeyableWindow: NSWindow {
    var forwarder: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if forwarder?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Notes, next slide and timers for the presenter.
struct PresenterView: View {
    @ObservedObject var show: SlideshowController
    @State private var notesSize: Double = 18
    @State private var now = Date()
    @State private var showingAll = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let p = show.presentation
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Label(SlideshowController.format(now.timeIntervalSince(show.startDate)), systemImage: "timer").monospacedDigit()
                Button { show.togglePause() } label: { Image(systemName: show.paused ? "play.fill" : "pause.fill") }.buttonStyle(.borderless)
                Button { show.startDate = Date(); show.slideStart = Date() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless)
                Text("This slide: \(SlideshowController.format(now.timeIntervalSince(show.slideStart)))").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text(now, style: .time).monospacedDigit()
                Button("End Slide Show") { show.end() }.keyboardShortcut(.cancelAction)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(Color.black.opacity(0.35))
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    slideImage(show.currentIndex, width: 640)
                        .overlay(alignment: .topTrailing) {
                            if show.blank != .none { Text(show.blank == .black ? "Black screen" : show.blank == .white ? "White screen" : "End").padding(6).background(.ultraThinMaterial) }
                        }
                    HStack(spacing: 14) {
                        Button { show.previous() } label: { Image(systemName: "chevron.left.circle.fill").font(.system(size: 26)) }.buttonStyle(.borderless)
                        Text("Slide \(show.currentIndex + 1) of \(p.slides.count)").font(.system(size: 15)).monospacedDigit()
                        Button { show.next() } label: { Image(systemName: "chevron.right.circle.fill").font(.system(size: 26)) }.buttonStyle(.borderless)
                        Divider().frame(height: 22)
                        Button { show.view.ink.tool = show.view.ink.tool == .pen ? .none : .pen } label: { Image(systemName: "pencil.tip") }.help("Pen (⌘P)")
                        Button { show.view.ink.tool = show.view.ink.tool == .laser ? .none : .laser } label: { Image(systemName: "light.beacon.max") }.help("Laser Pointer (⌘L)")
                        Button { show.setBlank(show.blank == .black ? .none : .black) } label: { Image(systemName: "rectangle.fill") }.help("Black Screen (B)")
                        Button { showingAll.toggle() } label: { Image(systemName: "square.grid.3x2") }.help("See All Slides")
                            .popover(isPresented: $showingAll) { allSlides }
                    }
                    .buttonStyle(.borderless)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    if let next = show.nextIndex {
                        slideImage(next, width: 340)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Color.black).frame(width: 340, height: 340 * p.slideSize.height / p.slideSize.width)
                            .overlay(Text("End of slide show").foregroundStyle(.secondary))
                    }
                    HStack {
                        Text("Notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { notesSize = max(10, notesSize - 2) } label: { Image(systemName: "textformat.size.smaller") }.buttonStyle(.borderless)
                        Button { notesSize = min(48, notesSize + 2) } label: { Image(systemName: "textformat.size.larger") }.buttonStyle(.borderless)
                    }
                    ScrollView {
                        Text(p.slides[show.currentIndex].notes.isEmpty ? "No notes for this slide." : p.slides[show.currentIndex].notes)
                            .font(.system(size: notesSize))
                            .foregroundStyle(p.slides[show.currentIndex].notes.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(minWidth: 300)
            }
            .padding(20)
        }
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        .environment(\.colorScheme, .dark)
        .onReceive(timer) { now = $0 }
        .frame(minWidth: 900, minHeight: 560)
    }

    private func slideImage(_ index: Int, width: CGFloat) -> some View {
        let p = show.presentation
        return Image(nsImage: ThumbnailCache.shared.thumbnail(p.slides[index], number: index + 1, presentation: p, width: width))
            .resizable()
            .frame(width: width, height: width * p.slideSize.height / p.slideSize.width)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var allSlides: some View {
        let p = show.presentation
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(p.slides.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        slideImage(i, width: 170)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(i == show.currentIndex ? Theme.accentColor : .clear, lineWidth: 3))
                            .opacity(p.slides[i].hidden ? 0.5 : 1)
                        Text("\(i + 1)").font(.caption).monospacedDigit()
                    }
                    .onTapGesture { show.goToSlide(index: i); showingAll = false }
                }
            }
            .padding(14)
        }
        .frame(width: 600, height: 420)
    }
}

/// Plays the current slide's transition and animations in a panel over the editor.
enum PreviewPlayer {
    private static var panel: NSPanel?

    static func preview(_ controller: PresentationController, transitionOnly: Bool) {
        controller.commitTextEditing()
        guard let window = controller.document?.windowControllers.first?.window,
              let canvas = (window.contentViewController as? PresentationViewController)?.canvasContainer else { return }
        panel?.close()
        let frameInWindow = canvas.convert(canvas.bounds, to: nil)
        let screenFrame = window.convertToScreen(frameInWindow)
        let p = NSPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.level = .floating
        let presentation = controller.presentation
        let view = SlideshowView(presentation: presentation)
        view.layer?.backgroundColor = Theme.canvasBackground.cgColor
        p.contentView = view
        p.orderFront(nil)
        panel = p
        let index = controller.currentSlideIndex
        view.layoutSubtreeIfNeeded()
        // Start from the previous slide so the transition has something to leave.
        view.stage.show(max(index - 1, 0), built: true)
        if index == 0 { view.stage.show(0, built: true) }
        let finishSteps: () -> Void = {
            guard !transitionOnly else { close(after: 0.4); return }
            func run() {
                if view.stage.runStep() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + view.stage.plan.duration(of: view.stage.nextStep - 1) + 0.25) { run() }
                } else {
                    close(after: 0.6)
                }
            }
            run()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if index > 0 || presentation.slides[index].transition.kind != .none {
                view.stage.transition(to: index) { finishSteps() }
            } else {
                view.stage.show(index, built: false)
                finishSteps()
            }
        }
    }

    private static func close(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            panel?.close()
            panel = nil
        }
    }
}

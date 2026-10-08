import AppKit
import Combine

/// Scrolls and zooms the slide canvas. Fits the slide to the window unless zoomed.
final class CanvasContainerView: NSView {
    let controller: PresentationController
    let scrollView = CanvasScrollView()
    let canvas: SlideCanvasView
    private var cancellables = Set<AnyCancellable>()

    init(controller: PresentationController) {
        self.controller = controller
        canvas = SlideCanvasView(controller: controller)
        super.init(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.canvasBackground
        scrollView.borderType = .noBorder
        scrollView.documentView = canvas
        scrollView.container = self
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        controller.$zoom.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateSize(keepCenter: true) }.store(in: &cancellables)
        controller.$fitToWindow.receive(on: RunLoop.main).sink { [weak self] fit in if fit { self?.fit() } }.store(in: &cancellables)
        controller.$revision.receive(on: RunLoop.main).sink { [weak self] _ in self?.canvas.refresh() }.store(in: &cancellables)
        controller.$currentSlideIndex.receive(on: RunLoop.main).sink { [weak self] _ in self?.canvas.refresh() }.store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        if controller.fitToWindow { fit() } else { updateSize(keepCenter: false) }
    }

    /// Zooms so the whole slide is visible.
    func fit() {
        let visible = scrollView.contentSize
        let size = controller.slideSize
        guard visible.width > 10, visible.height > 10, size.width > 0 else { return }
        let margin = SlideCanvasView.margin
        let z = min((visible.width - margin * 2) / size.width, (visible.height - margin * 2) / size.height)
        let zoom = Double(max(0.05, z))
        if abs(controller.zoom - zoom) > 0.0005 { controller.zoom = zoom }
        updateSize(keepCenter: false)
    }

    func updateSize(keepCenter: Bool) {
        let visible = scrollView.contentSize
        let content = canvas.contentSize
        let center = CGPoint(x: scrollView.contentView.bounds.midX / max(canvas.bounds.width, 1),
                             y: scrollView.contentView.bounds.midY / max(canvas.bounds.height, 1))
        let size = CGSize(width: max(visible.width, content.width), height: max(visible.height, content.height))
        if canvas.frame.size != size { canvas.setFrameSize(size) }
        canvas.refresh()
        if keepCenter {
            let target = CGPoint(x: center.x * size.width - visible.width / 2, y: center.y * size.height - visible.height / 2)
            canvas.scroll(target)
        }
    }

    /// Scrolling past the edge of a fitted slide changes slides, like PowerPoint.
    private var scrollAccumulator: CGFloat = 0

    func handleScroll(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            controller.fitToWindow = false
            let factor = 1 + Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04)
            controller.zoom = max(0.1, min(4, controller.zoom * factor))
            return true
        }
        guard controller.fitToWindow, controller.editingElement == nil else { return false }
        if event.phase == .began || event.phase == .mayBegin { scrollAccumulator = 0 }
        scrollAccumulator += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
        if abs(scrollAccumulator) > 60 {
            if scrollAccumulator < 0 { controller.nextSlide() } else { controller.previousSlide() }
            scrollAccumulator = 0
        }
        return true
    }
}

final class CanvasScrollView: NSScrollView {
    weak var container: CanvasContainerView?

    override func scrollWheel(with event: NSEvent) {
        if container?.handleScroll(event) == true { return }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        container?.canvas.magnify(with: event)
    }
}

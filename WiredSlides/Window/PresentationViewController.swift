import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Lays out the ribbon, slide navigator, canvas, notes, side pane and status bar,
/// and handles menu commands for the presentation.
final class PresentationViewController: NSViewController, NSMenuItemValidation, NSSplitViewDelegate, SheetPresenting {
    let controller: PresentationController
    let ribbonModel = RibbonModel()
    private(set) var canvasContainer: CanvasContainerView!
    private var navigator: SlideNavigatorView!
    private var notesPane: NotesPaneView!
    private var ribbonHost: NSHostingView<RibbonView>!
    private var statusHost: NSHostingView<StatusBarView>!
    private var sideHost: NSHostingView<SidePaneView>!
    private var mainSplit: NSSplitView!
    private var centerSplit: NSSplitView!
    private var alternateHost: NSView?
    private var ribbonHeight: NSLayoutConstraint!
    private var cancellables = Set<AnyCancellable>()
    private var navigatorWidth: CGFloat = 200
    private var sidePaneWidth: CGFloat = 320

    init(controller: PresentationController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        ribbonHost = NSHostingView(rootView: RibbonView(model: ribbonModel, controller: controller))
        canvasContainer = CanvasContainerView(controller: controller)
        navigator = SlideNavigatorView(controller: controller)
        notesPane = NotesPaneView(controller: controller)
        statusHost = NSHostingView(rootView: StatusBarView(controller: controller, onStartShow: { [weak self] in
            guard let self else { return }
            self.startSlideShow(from: self.controller.currentSlideIndex, presenter: self.controller.presentation.showSettings.usePresenterView, rehearse: false)
        }, onReadingView: { [weak self] in self?.readingView(nil) }))
        sideHost = NSHostingView(rootView: SidePaneView(controller: controller))

        centerSplit = NSSplitView()
        centerSplit.isVertical = false
        centerSplit.dividerStyle = .thin
        centerSplit.delegate = self
        centerSplit.addArrangedSubview(canvasContainer)
        centerSplit.addArrangedSubview(notesPane)
        centerSplit.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        centerSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        mainSplit = NSSplitView()
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        mainSplit.delegate = self
        mainSplit.addArrangedSubview(navigator)
        mainSplit.addArrangedSubview(centerSplit)
        mainSplit.addArrangedSubview(sideHost)
        mainSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        mainSplit.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        mainSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        let ribbonDivider = NSBox()
        ribbonDivider.boxType = .separator
        for v in [ribbonHost, ribbonDivider, mainSplit, statusHost] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        ribbonHeight = ribbonHost.heightAnchor.constraint(equalToConstant: ribbonModel.height)
        NSLayoutConstraint.activate([
            ribbonHost.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            ribbonHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            ribbonHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ribbonHeight,
            ribbonDivider.topAnchor.constraint(equalTo: ribbonHost.bottomAnchor),
            ribbonDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            ribbonDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainSplit.topAnchor.constraint(equalTo: ribbonDivider.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusHost.topAnchor.constraint(equalTo: mainSplit.bottomAnchor),
            statusHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusHost.heightAnchor.constraint(equalToConstant: 26),
        ])
        view = root

        controller.presenter = self
        ribbonModel.onCollapseChange = { [weak self] _ in self?.ribbonHeight.constant = self?.ribbonModel.height ?? 0 }
        controller.$sidePane.receive(on: RunLoop.main).sink { [weak self] _ in self?.updatePanes() }.store(in: &cancellables)
        controller.$viewMode.receive(on: RunLoop.main).sink { [weak self] mode in self?.applyViewMode(mode) }.store(in: &cancellables)
        controller.$selection.receive(on: RunLoop.main).sink { [weak self] _ in self?.selectionChanged() }.store(in: &cancellables)
        ribbonModel.$tab.receive(on: RunLoop.main).sink { [weak self] tab in
            self?.canvasContainer.canvas.showsAnimationBadges = tab == .animations
            self?.canvasContainer.canvas.needsDisplay = true
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: AppSettings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(addSectionRequested), name: .wsAddSection, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(readingViewRequested(_:)), name: .wsReadingView, object: nil)
        updatePanes()
    }

    private var didInitialLayout = false

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didInitialLayout, centerSplit.bounds.height > 200 else { return }
        didInitialLayout = true
        mainSplit.setPosition(navigatorWidth, ofDividerAt: 0)
        if !notesPane.isHidden { centerSplit.setPosition(centerSplit.bounds.height - 110, ofDividerAt: 0) }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        mainSplit.setPosition(navigatorWidth, ofDividerAt: 0)
        updatePanes()
        view.window?.makeFirstResponder(canvasContainer.canvas)
    }

    @objc private func settingsChanged() { updatePanes() }

    @objc private func addSectionRequested() { navigator.addSection() }

    @objc private func readingViewRequested(_ note: Notification) {
        if (note.object as? PresentationController) === controller { readingView(nil) }
    }

    private func selectionChanged() {
        // Jump to the matching contextual tab when an object is first selected.
        guard let e = controller.primaryElement else { return }
        if ribbonModel.tab.isContextual {
            switch e.content {
            case .table where ![.tableDesign, .tableLayout].contains(ribbonModel.tab): ribbonModel.tab = .tableDesign
            case .chart where ![.chartDesign, .shapeFormat].contains(ribbonModel.tab): ribbonModel.tab = .chartDesign
            case .image where ![.pictureFormat, .shapeFormat].contains(ribbonModel.tab): ribbonModel.tab = .pictureFormat
            default: break
            }
        }
    }

    private func updatePanes() {
        guard mainSplit != nil else { return }
        let showSide = controller.sidePane != nil
        if sideHost.isHidden == showSide {
            sideHost.isHidden = !showSide
            mainSplit.adjustSubviews()
            if showSide { mainSplit.setPosition(mainSplit.bounds.width - sidePaneWidth, ofDividerAt: 1) }
        }
        let showNotes = AppSettings.shared.showNotesPane && controller.viewMode == .normal
        if notesPane.isHidden == showNotes {
            notesPane.isHidden = !showNotes
            centerSplit.adjustSubviews()
            if showNotes { centerSplit.setPosition(centerSplit.bounds.height - 110, ofDividerAt: 0) }
        }
    }

    private func applyViewMode(_ mode: ViewMode) {
        guard mainSplit != nil else { return }
        controller.commitTextEditing()
        alternateHost?.removeFromSuperview()
        alternateHost = nil
        switch mode {
        case .normal:
            navigator.isHidden = false
            centerSplit.isHidden = false
            mainSplit.adjustSubviews()
            mainSplit.setPosition(navigatorWidth, ofDividerAt: 0)
        case .outline:
            // Outline replaces the thumbnails; the slide stays visible.
            let host = NSHostingView(rootView: OutlineView(controller: controller))
            navigator.isHidden = true
            centerSplit.isHidden = false
            mainSplit.insertArrangedSubview(host, at: 0)
            alternateHost = host
            mainSplit.adjustSubviews()
            mainSplit.setPosition(360, ofDividerAt: 0)
        case .sorter, .notesPage:
            let host: NSView = mode == .sorter ? NSHostingView(rootView: SlideSorterView(controller: controller)) : NSHostingView(rootView: NotesPageView(controller: controller))
            navigator.isHidden = true
            centerSplit.isHidden = true
            mainSplit.insertArrangedSubview(host, at: 0)
            alternateHost = host
            mainSplit.adjustSubviews()
        }
        updatePanes()
    }

    // MARK: - Split view

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === mainSplit && dividerIndex == 0 { return 120 }
        if splitView === centerSplit { return 160 }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === mainSplit && dividerIndex == 0 { return alternateHost != nil && controller.viewMode == .outline ? 600 : 360 }
        if splitView === mainSplit && dividerIndex == 1 { return splitView.bounds.width - 260 }
        if splitView === centerSplit { return splitView.bounds.height - 40 }
        return proposedMaximumPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let split = notification.object as? NSSplitView, split === mainSplit else { return }
        if !navigator.isHidden, navigator.frame.width > 100 { navigatorWidth = navigator.frame.width }
        if !sideHost.isHidden, sideHost.frame.width > 200 { sidePaneWidth = sideHost.frame.width }
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)), #selector(pasteAsPicture(_:)), #selector(pasteAsText(_:)):
            return controller.canPaste
        case #selector(delete(_:)), #selector(cut(_:)), #selector(copy(_:)):
            return true
        case #selector(group(_:)):
            return controller.selection.count > 1
        case #selector(ungroup(_:)):
            return controller.selectedElements.contains(where: \.isGroup)
        case #selector(toggleBold(_:)):
            item.state = controller.currentRunStyle.bold == true ? .on : .off
        case #selector(toggleItalic(_:)):
            item.state = controller.currentRunStyle.italic == true ? .on : .off
        case #selector(toggleUnderline(_:)):
            item.state = controller.currentRunStyle.underline ? .on : .off
        case #selector(toggleRibbon(_:)):
            item.title = ribbonModel.isCollapsed ? "Show Ribbon" : "Collapse Ribbon"
        case #selector(toggleNotes(_:)):
            item.state = AppSettings.shared.showNotesPane ? .on : .off
        case #selector(toggleGridlines(_:)):
            item.state = controller.showGridlines ? .on : .off
        case #selector(toggleGuides(_:)):
            item.state = controller.showGuides ? .on : .off
        case #selector(setViewMode(_:)):
            item.state = (item.representedObject as? String) == controller.viewMode.rawValue ? .on : .off
        case #selector(showSidePane(_:)):
            item.state = (item.representedObject as? String) == controller.sidePane?.rawValue ? .on : .off
        case #selector(hideSlide(_:)):
            item.title = controller.currentSlide.hidden ? "Show Slide" : "Hide Slide"
        case #selector(pasteAnimation(_:)):
            return !AnimationPainter.pending.isEmpty && !controller.selection.isEmpty
        case #selector(alignObjects(_:)), #selector(distributeHorizontally(_:)), #selector(distributeVertically(_:)),
             #selector(bringToFront(_:)), #selector(sendToBack(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
             #selector(rotateRight(_:)), #selector(rotateLeft(_:)), #selector(flipHorizontal(_:)), #selector(flipVertical(_:)), #selector(lockObjects(_:)):
            return !controller.selection.isEmpty
        default:
            break
        }
        return true
    }

    // MARK: - Edit menu

    @objc func cut(_ sender: Any?) { controller.copySelection(cut: true) }
    @objc func copy(_ sender: Any?) { controller.copySelection() }
    @objc func paste(_ sender: Any?) { controller.paste() }
    @objc func pasteAsPicture(_ sender: Any?) { controller.pasteAsPicture() }
    @objc func pasteAsText(_ sender: Any?) { controller.pasteAsText() }
    @objc func delete(_ sender: Any?) {
        if controller.selection.isEmpty { controller.deleteSlides() } else { controller.deleteSelection() }
    }
    @objc override func selectAll(_ sender: Any?) { controller.selectAllElements() }
    @objc func duplicate(_ sender: Any?) { controller.duplicateSelection() }
    @objc func copyFormat(_ sender: Any?) { controller.copyFormat() }
    @objc func pasteFormat(_ sender: Any?) {
        for id in controller.selection { controller.paintFormat(onto: id) }
    }
    @objc func pasteAnimation(_ sender: Any?) { AnimationPainter.paste(controller) }
    @objc func find(_ sender: Any?) { presentFindReplace(replace: false) }
    @objc func replace(_ sender: Any?) { presentFindReplace(replace: true) }
    @objc func findNextMatch(_ sender: Any?) {
        if !controller.findNext(FindModel.shared.options) { NSSound.beep() }
    }
    @objc func findPreviousMatch(_ sender: Any?) {
        if !controller.findNext(FindModel.shared.options, backwards: true) { NSSound.beep() }
    }

    // MARK: - Slides

    @objc func newSlide(_ sender: Any?) { controller.addSlide() }
    @objc func newSlideWithLayout(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let layout = LayoutKind(rawValue: raw) { controller.addSlide(layout: layout) }
    }
    @objc func duplicateSlide(_ sender: Any?) { controller.duplicateSlides() }
    @objc func deleteSlide(_ sender: Any?) { controller.deleteSlides() }
    @objc func hideSlide(_ sender: Any?) { controller.toggleHideSlides() }
    @objc func resetSlide(_ sender: Any?) { controller.resetSlides() }
    @objc func setLayout(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let layout = LayoutKind(rawValue: raw) { controller.setLayout(layout) }
    }
    @objc func moveSlideUp(_ sender: Any?) { controller.moveSlideUp() }
    @objc func moveSlideDown(_ sender: Any?) { controller.moveSlideDown() }
    @objc func nextSlide(_ sender: Any?) { controller.nextSlide() }
    @objc func previousSlide(_ sender: Any?) { controller.previousSlide() }
    @objc func addSection(_ sender: Any?) { navigator.addSection() }

    // MARK: - Insert

    @objc func insertTextBox(_ sender: Any?) { controller.pendingInsert = .textBox }
    @objc func insertShape(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let kind = ShapeKind(rawValue: raw) { controller.pendingInsert = .shape(kind) }
    }
    @objc func insertLine(_ sender: Any?) { controller.pendingInsert = .line(.straight, arrow: false) }
    @objc func insertArrow(_ sender: Any?) { controller.pendingInsert = .line(.straight, arrow: true) }
    @objc func insertPicture(_ sender: Any?) { insertPicturesFromFile() }
    @objc func insertMedia(_ sender: Any?) { insertMediaFromFile() }
    @objc func insertTableDialog(_ sender: Any?) { presentInsertTable() }
    @objc func insertChart(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let kind = ChartKind(rawValue: raw) { controller.insertChart(kind) }
    }
    @objc func insertIconDialog(_ sender: Any?) { presentInsertIcon() }
    @objc func insertSmartArtDialog(_ sender: Any?) { presentSmartArt() }
    @objc func insertHyperlink(_ sender: Any?) { presentHyperlink() }
    @objc func insertComment(_ sender: Any?) {
        controller.sidePane = .comments
        NotificationCenter.default.post(name: .wsNewComment, object: nil)
    }
    @objc func headerFooter(_ sender: Any?) { presentHeaderFooter() }
    @objc func insertSlideNumber(_ sender: Any?) {
        if controller.textEditor != nil { controller.textEditor?.insertText("‹#›"); return }
        var hf = controller.presentation.headerFooter
        hf.showSlideNumber = true
        controller.setHeaderFooter(hf)
    }
    @objc func insertDate(_ sender: Any?) { controller.insertDateTime(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)) }

    // MARK: - Format

    @objc func toggleBold(_ sender: Any?) { controller.toggleBold() }
    @objc func toggleItalic(_ sender: Any?) { controller.toggleItalic() }
    @objc func toggleUnderline(_ sender: Any?) { controller.toggleUnderline() }
    @objc func toggleStrikethrough(_ sender: Any?) { controller.toggleStrikethrough() }
    @objc func increaseFontSize(_ sender: Any?) { controller.growFont(true) }
    @objc func decreaseFontSize(_ sender: Any?) { controller.growFont(false) }
    @objc func superscriptText(_ sender: Any?) { controller.setBaseline(1) }
    @objc func subscriptText(_ sender: Any?) { controller.setBaseline(-1) }
    @objc func clearFormatting(_ sender: Any?) { controller.clearFormatting() }
    @objc func alignTextLeft(_ sender: Any?) { controller.setAlignment(.left) }
    @objc func alignTextCenter(_ sender: Any?) { controller.setAlignment(.center) }
    @objc func alignTextRight(_ sender: Any?) { controller.setAlignment(.right) }
    @objc func alignTextJustify(_ sender: Any?) { controller.setAlignment(.justify) }
    @objc func toggleBullets(_ sender: Any?) { controller.toggleBullets() }
    @objc func toggleNumbering(_ sender: Any?) { controller.toggleNumbering() }
    @objc func increaseIndent(_ sender: Any?) { controller.changeIndent(1) }
    @objc func decreaseIndent(_ sender: Any?) { controller.changeIndent(-1) }
    @objc func formatPane(_ sender: Any?) { controller.sidePane = .format }

    // MARK: - Arrange

    @objc func group(_ sender: Any?) { controller.group() }
    @objc func ungroup(_ sender: Any?) { controller.ungroup() }
    @objc func bringToFront(_ sender: Any?) { controller.arrange(.front) }
    @objc func sendToBack(_ sender: Any?) { controller.arrange(.back) }
    @objc func bringForward(_ sender: Any?) { controller.arrange(.forward) }
    @objc func sendBackward(_ sender: Any?) { controller.arrange(.backward) }
    @objc func alignObjects(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = AlignMode(rawValue: raw) { controller.align(mode) }
    }
    @objc func distributeHorizontally(_ sender: Any?) { controller.distribute(horizontally: true) }
    @objc func distributeVertically(_ sender: Any?) { controller.distribute(horizontally: false) }
    @objc func rotateRight(_ sender: Any?) { controller.rotate(by: 90) }
    @objc func rotateLeft(_ sender: Any?) { controller.rotate(by: -90) }
    @objc func flipHorizontal(_ sender: Any?) { controller.flip(horizontal: true) }
    @objc func flipVertical(_ sender: Any?) { controller.flip(horizontal: false) }
    @objc func lockObjects(_ sender: Any?) { controller.toggleLock() }

    // MARK: - View

    @objc func zoomIn(_ sender: Any?) { controller.fitToWindow = false; controller.zoom = min(4, controller.zoom * 1.25) }
    @objc func zoomOut(_ sender: Any?) { controller.fitToWindow = false; controller.zoom = max(0.1, controller.zoom / 1.25) }
    @objc func actualSize(_ sender: Any?) { controller.fitToWindow = false; controller.zoom = 1 }
    @objc func fitToWindow(_ sender: Any?) { controller.fitToWindow = true }
    @objc func toggleRibbon(_ sender: Any?) { ribbonModel.isCollapsed.toggle() }
    @objc func toggleNotes(_ sender: Any?) { AppSettings.shared.showNotesPane.toggle() }
    @objc func toggleGridlines(_ sender: Any?) { controller.showGridlines.toggle() }
    @objc func toggleGuides(_ sender: Any?) { controller.showGuides.toggle() }
    @objc func setViewMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = ViewMode(rawValue: raw) { controller.viewMode = mode }
    }
    @objc func showSidePane(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pane = SidePane(rawValue: raw) else { return }
        controller.sidePane = controller.sidePane == pane ? nil : pane
    }
    @objc func showRibbonTab(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let tab = RibbonModel.Tab(rawValue: raw) {
            ribbonModel.tab = tab
            ribbonModel.isCollapsed = false
        }
    }

    // MARK: - Slide show

    @objc func playFromBeginning(_ sender: Any?) { startSlideShow(from: 0, presenter: controller.presentation.showSettings.usePresenterView, rehearse: false) }
    @objc func playFromCurrent(_ sender: Any?) { startSlideShow(from: controller.currentSlideIndex, presenter: controller.presentation.showSettings.usePresenterView, rehearse: false) }
    @objc func playWithPresenter(_ sender: Any?) { startSlideShow(from: controller.currentSlideIndex, presenter: true, rehearse: false) }
    @objc func rehearseTimings(_ sender: Any?) { startSlideShow(from: 0, presenter: false, rehearse: true) }
    @objc func readingView(_ sender: Any?) {
        controller.commitTextEditing()
        SlideshowController.start(controller.presentation, editor: controller, from: controller.currentSlideIndex, presenter: false, windowed: true)
    }
    @objc func setUpShow(_ sender: Any?) { presentSetUpShow() }
    @objc func previewAnimations(_ sender: Any?) { PreviewPlayer.preview(controller, transitionOnly: false) }

    func startSlideShow(from index: Int, presenter: Bool, rehearse: Bool) {
        controller.commitTextEditing()
        SlideshowController.start(controller.presentation, editor: controller, from: index, presenter: presenter, rehearse: rehearse)
    }

    // MARK: - SheetPresenting

    private func sheet<V: View>(_ content: V, size: CGSize? = nil) {
        let host = NSHostingController(rootView: content.environment(\.dismissSheet, DismissAction { [weak self] in self?.dismissSheets() }))
        if let size { host.preferredContentSize = size }
        presentAsSheet(host)
    }

    private func dismissSheets() {
        for vc in presentedViewControllers ?? [] { dismiss(vc) }
    }

    func presentInsertTable() { sheet(InsertTableSheet(controller: controller)) }

    func presentChartEditor(_ elementID: UUID) {
        guard let e = controller.currentSlide.element(elementID), case .chart(let chart) = e.content else { return }
        sheet(ChartDataSheet(controller: controller, elementID: elementID, chart: chart))
    }

    func presentHyperlink() { sheet(HyperlinkSheet(controller: controller)) }
    func presentFindReplace(replace: Bool) {
        if let text = controller.textEditor?.selectedText, !text.isEmpty { FindModel.shared.options.text = text }
        sheet(FindReplaceSheet(controller: controller, showReplace: replace))
    }
    func presentHeaderFooter() { sheet(HeaderFooterSheet(controller: controller)) }
    func presentSlideSize() { sheet(SlideSizeSheet(controller: controller)) }
    func presentInsertIcon() { sheet(IconPickerSheet(controller: controller), size: CGSize(width: 620, height: 520)) }
    func presentSmartArt() { sheet(SmartArtSheet(controller: controller)) }
    func presentAction() { sheet(ActionSheet(controller: controller)) }
    func presentSetUpShow() { sheet(SetUpShowSheet(controller: controller)) }
    func presentSpelling() { sheet(SpellingSheet(controller: controller), size: CGSize(width: 520, height: 380)) }

    func insertPicturesFromFile() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            if self.controller.primaryElement?.isImage == true, panel.urls.count == 1, let data = try? Data(contentsOf: panel.urls[0]) {
                // With a picture selected, Insert ▸ Picture adds another one; Change Picture replaces.
                self.controller.insertPicture(data, filename: panel.urls[0].lastPathComponent)
                return
            }
            self.controller.insertFiles(panel.urls, at: nil)
        }
    }

    func insertMediaFromFile() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.controller.insertMedia(url)
        }
    }
}

/// Lets SwiftUI sheets close themselves without a presentation-mode binding.
struct DismissAction {
    let action: () -> Void
    init(_ action: @escaping () -> Void = {}) { self.action = action }
    func callAsFunction() { action() }
}

private struct DismissSheetKey: EnvironmentKey {
    static let defaultValue = DismissAction()
}

extension EnvironmentValues {
    var dismissSheet: DismissAction {
        get { self[DismissSheetKey.self] }
        set { self[DismissSheetKey.self] = newValue }
    }
}

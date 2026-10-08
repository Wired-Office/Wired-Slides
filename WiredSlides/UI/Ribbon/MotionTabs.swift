import AppKit
import SwiftUI

/// A numeric field with stepper, committing on change.
struct NumberField: View {
    let label: String
    let value: Double
    var range: ClosedRange<Double> = 0...999
    var step: Double = 0.25
    var unit = ""
    var width: CGFloat = 56
    let onChange: (Double) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty { Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5).monospacedDigit())
                .frame(width: width)
                .onSubmit(commit)
            Stepper("", value: Binding(get: { value }, set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }), in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, v in text = format(v) }
    }

    private func format(_ v: Double) -> String { (v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)) + unit }

    private func commit() {
        let digits = text.replacingOccurrences(of: unit, with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if let v = Double(digits) { onChange(min(max(v, range.lowerBound), range.upperBound)) } else { text = format(value) }
    }
}

struct TransitionsTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let t = controller.currentSlide.transition
        HStack(spacing: 0) {
            CaptionedGroup(title: "Preview") {
                RibbonLargeButton(title: "Preview", symbol: "play.circle", help: "Preview the transition") {
                    PreviewPlayer.preview(controller, transitionOnly: true)
                }
            }
            CaptionedGroup(title: "Transition to This Slide") {
                RibbonGallery(items: TransitionKind.allCases) { kind in
                    GalleryTile(isSelected: t.kind == kind, help: kind.title) {
                        controller.setTransition({ $0.kind = kind; if $0.duration <= 0 { $0.duration = 0.7 } }, name: "Transition")
                        if kind != .none { PreviewPlayer.preview(controller, transitionOnly: true) }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: kind.symbol).font(.system(size: 18)).frame(height: 24)
                                .foregroundStyle(kind == .none ? Color.secondary : Theme.accentColor)
                            Text(kind.title).font(.system(size: 9.5)).lineLimit(1)
                        }
                        .frame(width: 62, height: 48)
                    }
                }
                RibbonLargeButton(title: "Effect Options", symbol: "arrow.up.and.down.and.arrow.left.and.right", help: "Direction",
                                  isEnabled: t.kind.hasDirection, menu: {
                    let menu = NSMenu()
                    for d in MotionDirection.allCases {
                        menu.add(d.title, symbol: d.symbol, checked: t.direction == d) { controller.setTransition({ $0.direction = d }, name: "Effect Options") }
                    }
                    return menu
                })
            }
            CaptionedGroup(title: "Timing", showsDivider: false) {
                VStack(alignment: .leading, spacing: 6) {
                    NumberField(label: "Duration:", value: t.duration, range: 0.1...10, step: 0.25, unit: "s", width: 52) { v in
                        controller.setTransition({ $0.duration = v }, name: "Duration")
                    }
                    Button { controller.applyTransitionToAll() } label: { Label("Apply To All", systemImage: "square.stack.3d.up") }
                        .buttonStyle(.borderless).font(.system(size: 11.5))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Advance Slide").font(.system(size: 11)).foregroundStyle(.secondary)
                    Toggle("On Mouse Click", isOn: Binding(get: { t.advanceOnClick }, set: { v in controller.setTransition({ $0.advanceOnClick = v }, name: "Advance") }))
                        .toggleStyle(.checkbox).font(.system(size: 11.5))
                    HStack(spacing: 4) {
                        Toggle("After:", isOn: Binding(get: { t.advanceAfter != nil }, set: { v in controller.setTransition({ $0.advanceAfter = v ? 5 : nil }, name: "Advance") }))
                            .toggleStyle(.checkbox).font(.system(size: 11.5))
                        NumberField(label: "", value: t.advanceAfter ?? 0, range: 0...3600, step: 1, unit: "s", width: 46) { v in
                            controller.setTransition({ $0.advanceAfter = v }, name: "Advance")
                        }
                        .disabled(t.advanceAfter == nil)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
}

struct AnimationsTab: View {
    @ObservedObject var controller: PresentationController

    private func color(_ category: AnimationCategory) -> Color {
        switch category {
        case .entrance: .green
        case .emphasis: .yellow
        case .exit: .red
        case .motionPath: .blue
        }
    }

    var body: some View {
        let selected = controller.selectionAnimations
        let first = selected.first
        let hasSelection = !controller.selection.isEmpty
        HStack(spacing: 0) {
            CaptionedGroup(title: "Preview") {
                RibbonLargeButton(title: "Preview", symbol: "play.circle", help: "Preview the slide's animations") {
                    PreviewPlayer.preview(controller, transitionOnly: false)
                }
            }
            CaptionedGroup(title: "Animation") {
                RibbonGallery(items: AnimationEffect.allCases) { effect in
                    GalleryTile(isSelected: first?.effect == effect, help: "\(effect.category.title): \(effect.title)") {
                        controller.addAnimation(effect, replacing: true)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: effect.symbol).font(.system(size: 17)).frame(height: 22)
                                .foregroundStyle(color(effect.category))
                            Text(effect.title).font(.system(size: 9.5)).lineLimit(1)
                        }
                        .frame(width: 58, height: 46)
                    }
                    .disabled(!hasSelection)
                }
                RibbonLargeButton(title: "Effect Options", symbol: "arrow.up.and.down.and.arrow.left.and.right", help: "Direction",
                                  isEnabled: first?.effect.hasDirection == true, menu: {
                    let menu = NSMenu()
                    for d in MotionDirection.allCases {
                        menu.add(d.title, symbol: d.symbol, checked: first?.direction == d) { controller.updateSelectedAnimations { $0.direction = d } }
                    }
                    return menu
                })
            }
            CaptionedGroup(title: "Advanced Animation") {
                RibbonLargeButton(title: "Add Animation", symbol: "plus.diamond", help: "Add another effect to the selection", isEnabled: hasSelection, menu: {
                    let menu = NSMenu()
                    for category in AnimationCategory.allCases {
                        menu.addSection(category.title)
                        for effect in AnimationEffect.effects(in: category) {
                            menu.add(effect.title, symbol: effect.symbol) { controller.addAnimation(effect, replacing: false) }
                        }
                    }
                    return menu
                })
                RibbonLargeButton(title: "Animation Pane", symbol: "list.bullet.rectangle.portrait", help: "Show every animation on the slide",
                                  isOn: controller.sidePane == .animations) {
                    controller.sidePane = controller.sidePane == .animations ? nil : .animations
                }
                RibbonColumn {
                    RibbonCompactButton(title: "Remove", symbol: "xmark.diamond", help: "Remove the selection's animations", isEnabled: !selected.isEmpty) {
                        if let id = controller.selectedAnimation { controller.removeAnimation(id) } else { controller.removeAnimations(for: controller.selection) }
                    }
                    RibbonCompactButton(title: "Animation Painter", symbol: "paintbrush", help: "Copy these animations to other objects", isEnabled: !selected.isEmpty) {
                        AnimationPainter.copy(controller)
                    }
                }
            }
            CaptionedGroup(title: "Timing", showsDivider: false) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text("Start:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { first?.trigger ?? .onClick }, set: { v in controller.updateSelectedAnimations { $0.trigger = v } })) {
                            ForEach(AnimationTrigger.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 130)
                    }
                    NumberField(label: "Duration:", value: first?.duration ?? 0.5, range: 0...60, step: 0.25, unit: "s", width: 50) { v in
                        controller.updateSelectedAnimations { $0.duration = v }
                    }
                    NumberField(label: "Delay:", value: first?.delay ?? 0, range: 0...60, step: 0.25, unit: "s", width: 50) { v in
                        controller.updateSelectedAnimations { $0.delay = v }
                    }
                }
                .disabled(first == nil)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reorder Animation").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { if let a = first { controller.moveAnimation(a.id, by: -1) } } label: { Label("Move Earlier", systemImage: "arrow.up") }
                        .buttonStyle(.borderless).font(.system(size: 11.5))
                    Button { if let a = first { controller.moveAnimation(a.id, by: 1) } } label: { Label("Move Later", systemImage: "arrow.down") }
                        .buttonStyle(.borderless).font(.system(size: 11.5))
                }
                .disabled(first == nil)
                .padding(.leading, 10)
            }
        }
    }
}

/// Copies the animations of the selection onto the next selected objects.
enum AnimationPainter {
    static func copy(_ controller: PresentationController) {
        let source = controller.selectionAnimations
        guard !source.isEmpty else { return }
        controller.flash("Select the objects to receive the animation, then choose Paste Animation from the Edit menu")
        pending = source
    }

    static var pending: [SlideAnimation] = []

    static func paste(_ controller: PresentationController) {
        guard !pending.isEmpty else { return }
        let ids = controller.selection
        controller.changeSlide("Paste Animation") { slide in
            slide.animations.removeAll { ids.contains($0.elementID) }
            for id in ids {
                for template in pending {
                    var a = template
                    a.id = UUID()
                    a.elementID = id
                    slide.animations.append(a)
                }
            }
        }
    }
}

struct SlideShowTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let settings = controller.presentation.showSettings
        HStack(spacing: 0) {
            CaptionedGroup(title: "Start Slide Show") {
                RibbonLargeButton(title: "From Beginning", symbol: "play.rectangle.fill", help: "Start the slide show from the first slide (⇧⌘↩)") {
                    controller.presenter?.startSlideShow(from: 0, presenter: settings.usePresenterView, rehearse: false)
                }
                RibbonLargeButton(title: "From Current Slide", symbol: "play.rectangle", help: "Start from this slide (⌥⌘↩)") {
                    controller.presenter?.startSlideShow(from: controller.currentSlideIndex, presenter: settings.usePresenterView, rehearse: false)
                }
                RibbonLargeButton(title: "Presenter View", symbol: "rectangle.split.2x1", help: "Present with notes, next slide and timer") {
                    controller.presenter?.startSlideShow(from: controller.currentSlideIndex, presenter: true, rehearse: false)
                }
            }
            CaptionedGroup(title: "Set Up") {
                RibbonLargeButton(title: "Set Up Slide Show", symbol: "gearshape", help: "Loop, timings, presenter view") {
                    controller.presenter?.presentSetUpShow()
                }
                RibbonLargeButton(title: "Hide Slide", symbol: "eye.slash", help: "Skip this slide in the slide show",
                                  isOn: controller.currentSlide.hidden) { controller.toggleHideSlides() }
                RibbonLargeButton(title: "Rehearse Timings", symbol: "stopwatch", help: "Record how long you spend on each slide") {
                    controller.presenter?.startSlideShow(from: 0, presenter: false, rehearse: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    toggle("Use Timings", settings.useTimings) { s, v in s.useTimings = v }
                    toggle("Loop until Esc", settings.loopUntilEscape) { s, v in s.loopUntilEscape = v }
                    toggle("Play Animations", !settings.showWithoutAnimation) { s, v in s.showWithoutAnimation = !v }
                }
                .padding(.leading, 8)
            }
            CaptionedGroup(title: "Monitors", showsDivider: false) {
                VStack(alignment: .leading, spacing: 4) {
                    toggle("Use Presenter View", settings.usePresenterView) { s, v in s.usePresenterView = v }
                    Text(NSScreen.screens.count > 1 ? "\(NSScreen.screens.count) displays: show on external display" : "One display: presenter view opens in a window")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                }
            }
        }
    }

    private func toggle(_ title: String, _ value: Bool, _ set: @escaping (inout SlideShowSettings, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { v in
            var s = controller.presentation.showSettings
            set(&s, v)
            controller.setShowSettings(s)
        }))
        .toggleStyle(.checkbox)
        .font(.system(size: 11.5))
    }
}

struct ReviewTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        HStack(spacing: 0) {
            CaptionedGroup(title: "Proofing") {
                RibbonLargeButton(title: "Spelling", symbol: "textformat.abc.dottedunderline", help: "Check spelling on every slide") {
                    controller.presenter?.presentSpelling()
                }
                RibbonLargeButton(title: "Word Count", symbol: "number.square", help: "Words and characters in the presentation") {
                    WordCount.show(controller)
                }
            }
            CaptionedGroup(title: "Accessibility") {
                RibbonLargeButton(title: "Check Accessibility", symbol: "accessibility", help: "Find missing alt text and slide titles") {
                    AccessibilityChecker.show(controller)
                }
                RibbonLargeButton(title: "Alt Text", symbol: "text.below.photo", help: "Describe the selected object", isEnabled: controller.primaryElement != nil) {
                    AltTextPrompt.show(controller)
                }
            }
            CaptionedGroup(title: "Comments", showsDivider: false) {
                RibbonLargeButton(title: "New Comment", symbol: "text.bubble", help: "Comment on the slide or selection") {
                    controller.sidePane = .comments
                    NotificationCenter.default.post(name: .wsNewComment, object: nil)
                }
                RibbonColumn {
                    RibbonCompactButton(title: "Previous", symbol: "chevron.up", help: "Previous comment") { controller.goToComment(forward: false) }
                    RibbonCompactButton(title: "Next", symbol: "chevron.down", help: "Next comment") { controller.goToComment(forward: true) }
                    RibbonMenuButton(symbol: "trash", help: "Delete Comments", label: "Delete") {
                        let menu = NSMenu()
                        menu.add("Delete All Comments on This Slide") { controller.deleteAllComments(onAllSlides: false) }
                        menu.add("Delete All Comments in This Presentation") { controller.deleteAllComments(onAllSlides: true) }
                        return menu
                    }
                }
                RibbonLargeButton(title: "Show Comments", symbol: "sidebar.right", help: "Comments pane", isOn: controller.sidePane == .comments) {
                    controller.sidePane = controller.sidePane == .comments ? nil : .comments
                }
            }
        }
    }
}

struct ViewTab: View {
    @ObservedObject var controller: PresentationController
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            CaptionedGroup(title: "Presentation Views") {
                ForEach(ViewMode.allCases) { mode in
                    RibbonLargeButton(title: mode.title, symbol: mode.symbol, help: mode.title, isOn: controller.viewMode == mode) {
                        controller.viewMode = mode
                    }
                }
                RibbonLargeButton(title: "Reading View", symbol: "book", help: "Play the presentation in this window") {
                    NotificationCenter.default.post(name: .wsReadingView, object: controller)
                }
            }
            CaptionedGroup(title: "Show") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Gridlines", isOn: $controller.showGridlines).toggleStyle(.checkbox)
                    Toggle("Guides", isOn: $controller.showGuides).toggleStyle(.checkbox)
                    Toggle("Notes", isOn: $settings.showNotesPane).toggleStyle(.checkbox)
                }
                .font(.system(size: 11.5))
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Snap to Grid", isOn: $settings.snapToGrid).toggleStyle(.checkbox)
                    Toggle("Smart Guides", isOn: $settings.smartGuides).toggleStyle(.checkbox)
                }
                .font(.system(size: 11.5))
                .padding(.leading, 8)
            }
            CaptionedGroup(title: "Zoom") {
                RibbonLargeButton(title: "Zoom", symbol: "plus.magnifyingglass", help: "Zoom level", menu: {
                    let menu = NSMenu()
                    for level in [0.33, 0.5, 0.66, 1, 1.5, 2, 3, 4] {
                        menu.add("\(Int(level * 100))%", checked: abs(controller.zoom - level) < 0.01) {
                            controller.fitToWindow = false
                            controller.zoom = level
                        }
                    }
                    return menu
                })
                RibbonLargeButton(title: "Fit to Window", symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", help: "Fit the slide to the window",
                                  isOn: controller.fitToWindow) { controller.fitToWindow = true }
            }
            CaptionedGroup(title: "Panes", showsDivider: false) {
                ForEach([SidePane.format, .animations, .selection, .comments]) { pane in
                    RibbonLargeButton(title: pane.title, symbol: paneSymbol(pane), help: pane.title, isOn: controller.sidePane == pane) {
                        controller.sidePane = controller.sidePane == pane ? nil : pane
                    }
                }
            }
        }
    }

    private func paneSymbol(_ pane: SidePane) -> String {
        switch pane {
        case .format: "paintbrush"
        case .animations: "sparkles"
        case .selection: "list.bullet.rectangle"
        case .comments: "text.bubble"
        case .designer: "lightbulb"
        }
    }
}

extension Notification.Name {
    static let wsReadingView = Notification.Name("WSReadingView")
}

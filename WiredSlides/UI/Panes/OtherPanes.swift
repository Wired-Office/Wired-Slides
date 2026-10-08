import AppKit
import SwiftUI

// MARK: - Animation pane

struct AnimationPane: View {
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
        let animations = controller.currentAnimations
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { PreviewPlayer.preview(controller, transitionOnly: false) } label: { Label("Play All", systemImage: "play.fill") }
                Spacer()
                Button { if let id = controller.selectedAnimation { controller.moveAnimation(id, by: -1) } } label: { Image(systemName: "arrow.up") }
                    .disabled(controller.selectedAnimation == nil).help("Move Earlier")
                Button { if let id = controller.selectedAnimation { controller.moveAnimation(id, by: 1) } } label: { Image(systemName: "arrow.down") }
                    .disabled(controller.selectedAnimation == nil).help("Move Later")
            }
            .buttonStyle(.borderless)
            .padding(10)
            Divider()
            if animations.isEmpty {
                Text("Select an object on the slide, then choose an effect on the Animations tab.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
                Spacer()
            } else {
                List(selection: Binding(get: { controller.selectedAnimation }, set: { id in
                    controller.selectedAnimation = id
                    if let id, let a = animations.first(where: { $0.id == id }) { controller.select([a.elementID]) }
                })) {
                    ForEach(Array(animations.enumerated()), id: \.element.id) { index, a in
                        let step = animations[...index].filter { $0.trigger == .onClick }.count
                        HStack(spacing: 8) {
                            Text(a.trigger == .onClick ? "\(step)" : "").font(.system(size: 11, weight: .semibold).monospacedDigit()).frame(width: 16)
                            Image(systemName: a.trigger.symbol).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
                            Image(systemName: a.effect.symbol).foregroundStyle(color(a.effect.category)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(controller.currentSlide.element(a.elementID)?.name ?? "Object").font(.system(size: 12)).lineLimit(1)
                                Text("\(a.effect.category.title): \(a.effect.title) · \(String(format: "%.2gs", a.duration))\(a.delay > 0 ? " after \(String(format: "%.2gs", a.delay))" : "")")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TimelineBar(start: a.delay, duration: a.duration, color: color(a.effect.category)).frame(width: 50, height: 6)
                        }
                        .tag(a.id)
                        .contextMenu {
                            ForEach(AnimationTrigger.allCases) { t in Button(t.title) { controller.updateAnimation(a.id) { $0.trigger = t } } }
                            Divider()
                            Button("Remove") { controller.removeAnimation(a.id) }
                        }
                    }
                }
                .listStyle(.inset)
                if let id = controller.selectedAnimation, let a = animations.first(where: { $0.id == id }) {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Effect Options").font(.system(size: 12, weight: .semibold))
                        Picker("Effect", selection: Binding(get: { a.effect }, set: { v in controller.updateAnimation(id) { $0.effect = v } })) {
                            ForEach(AnimationEffect.effects(in: a.effect.category)) { Text($0.title).tag($0) }
                        }
                        Picker("Start", selection: Binding(get: { a.trigger }, set: { v in controller.updateAnimation(id) { $0.trigger = v } })) {
                            ForEach(AnimationTrigger.allCases) { Text($0.title).tag($0) }
                        }
                        if a.effect.hasDirection {
                            Picker("Direction", selection: Binding(get: { a.direction }, set: { v in controller.updateAnimation(id) { $0.direction = v } })) {
                                ForEach(MotionDirection.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        NumberField(label: "Duration", value: a.duration, range: 0...60, step: 0.25, unit: "s", width: 50) { v in controller.updateAnimation(id) { $0.duration = v } }
                        NumberField(label: "Delay", value: a.delay, range: 0...60, step: 0.25, unit: "s", width: 50) { v in controller.updateAnimation(id) { $0.delay = v } }
                        NumberField(label: "Repeat", value: Double(a.repeatCount), range: 1...20, step: 1, width: 40) { v in controller.updateAnimation(id) { $0.repeatCount = Int(v) } }
                        if a.effect.category == .motionPath || a.effect == .spin || a.effect == .growShrink {
                            PaneSlider(label: "Amount", value: a.amount, range: 0.25...3, format: { String(format: "%.2g×", $0) }) { v in controller.updateAnimation(id) { $0.amount = v } }
                        }
                    }
                    .font(.system(size: 11.5))
                    .padding(12)
                }
            }
        }
    }
}

private struct TimelineBar: View {
    let start: Double
    let duration: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let total = max(start + duration, 2)
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.8))
                .frame(width: max(geo.size.width * duration / total, 3))
                .offset(x: geo.size.width * start / total)
        }
    }
}

// MARK: - Selection pane

struct SelectionPane: View {
    @ObservedObject var controller: PresentationController
    @State private var renaming: UUID?
    @State private var name = ""

    var body: some View {
        let elements = Array(controller.currentSlide.elements.reversed())
        VStack(spacing: 0) {
            HStack {
                Button("Show All") {
                    let hidden = controller.currentSlide.elements.filter(\.hidden).map(\.id)
                    for id in hidden { controller.setHidden(id, hidden: false) }
                }
                Button("Hide All") {
                    for e in controller.currentSlide.elements where !e.hidden { controller.setHidden(e.id, hidden: true) }
                }
                Spacer()
                Button { controller.arrange(.forward) } label: { Image(systemName: "chevron.up") }.help("Bring Forward")
                Button { controller.arrange(.backward) } label: { Image(systemName: "chevron.down") }.help("Send Backward")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5))
            .padding(10)
            Divider()
            List(selection: Binding(get: { Set(controller.selection) }, set: { ids in
                controller.select(elements.map(\.id).filter { ids.contains($0) })
            })) {
                ForEach(elements) { e in
                    HStack(spacing: 8) {
                        Image(systemName: e.symbol).frame(width: 18).foregroundStyle(.secondary)
                        if renaming == e.id {
                            TextField("", text: $name).onSubmit {
                                controller.rename(e.id, to: name)
                                renaming = nil
                            }
                        } else {
                            Text(e.name).lineLimit(1).opacity(e.hidden ? 0.45 : 1)
                                .onTapGesture(count: 2) { renaming = e.id; name = e.name }
                        }
                        Spacer()
                        if e.locked {
                            Button { controller.select([e.id]); controller.toggleLock() } label: { Image(systemName: "lock.fill") }.buttonStyle(.borderless)
                        }
                        Button { controller.setHidden(e.id, hidden: !e.hidden) } label: { Image(systemName: e.hidden ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                            .help(e.hidden ? "Show" : "Hide")
                    }
                    .tag(e.id)
                }
                .onMove { from, to in
                    // The list is top-most first; convert to stacking order.
                    guard let source = from.first else { return }
                    let id = elements[source].id
                    let count = elements.count
                    let destination = count - (to > source ? to - 1 : to) - 1
                    controller.moveElement(id, toIndex: destination)
                }
            }
            .listStyle(.inset)
            Text("Double-click a name to rename it. Drag to change the order.").font(.system(size: 10.5)).foregroundStyle(.secondary).padding(8)
        }
    }
}

// MARK: - Comments

struct CommentsPane: View {
    @ObservedObject var controller: PresentationController
    @State private var draft = ""
    @State private var replies: [UUID: String] = [:]
    @State private var position: CGPoint?
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if controller.currentSlide.comments.isEmpty {
                        Text("No comments on this slide.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(controller.currentSlide.comments) { comment in
                        commentCard(comment)
                    }
                }
                .padding(12)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                TextField("Start a conversation", text: $draft, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($composing)
                HStack {
                    Button { controller.goToComment(forward: false) } label: { Image(systemName: "chevron.up") }.help("Previous Comment")
                    Button { controller.goToComment(forward: true) } label: { Image(systemName: "chevron.down") }.help("Next Comment")
                    Spacer()
                    Button("Post") {
                        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        controller.addComment(draft, at: position)
                        draft = ""
                        position = nil
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wsNewComment)) { note in
            position = (note.object as? NSValue)?.pointValue
            composing = true
        }
    }

    private func commentCard(_ comment: SlideComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(Theme.accentColor)
                Text(comment.author).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(comment.date, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                Menu {
                    Button(comment.resolved ? "Reopen" : "Resolve") { controller.resolveComment(comment.id, resolved: !comment.resolved) }
                    Button("Delete", role: .destructive) { controller.deleteComment(comment.id) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Text(comment.text).font(.system(size: 12)).textSelection(.enabled).strikethrough(comment.resolved)
            ForEach(comment.replies) { reply in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.author).font(.system(size: 11, weight: .semibold))
                    Text(reply.text).font(.system(size: 11.5))
                }
                .padding(.leading, 14)
            }
            if !comment.resolved {
                HStack {
                    TextField("Reply", text: Binding(get: { replies[comment.id] ?? "" }, set: { replies[comment.id] = $0 }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11.5))
                        .onSubmit {
                            let text = replies[comment.id] ?? ""
                            guard !text.isEmpty else { return }
                            controller.replyToComment(comment.id, text: text)
                            replies[comment.id] = ""
                        }
                }
            } else {
                Text("Resolved").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .opacity(comment.resolved ? 0.7 : 1)
    }
}

// MARK: - Design Ideas

/// Suggests layouts for the current content and lets you tune theme colors.
struct DesignerPane: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Layouts for this slide").font(.system(size: 12, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(suggestedLayouts, id: \.self) { layout in
                        Button { controller.setLayout(layout) } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: preview(layout)).resizable()
                                    .aspectRatio(controller.slideSize.width / controller.slideSize.height, contentMode: .fit)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(controller.currentSlide.layout == layout ? Theme.accentColor : Color.primary.opacity(0.15),
                                                                                           lineWidth: controller.currentSlide.layout == layout ? 2.5 : 0.5))
                                Text(layout.title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                Text("Theme Colors").font(.system(size: 12, weight: .semibold))
                ForEach(ThemeSlot.allCases) { slot in
                    PaneRow(label: slot.title) {
                        PaintColorWell(colors: controller.theme.colors, color: .rgb(controller.theme.colors[slot])) { picked in
                            guard let picked else { return }
                            var colors = controller.theme.colors
                            colors[slot] = picked.resolve(controller.theme.colors).withAlpha(1)
                            controller.applyColors(colors)
                        }
                    }
                }
                Divider()
                Text("Theme Fonts").font(.system(size: 12, weight: .semibold))
                PaneRow(label: "Headings") {
                    FontFamilyPicker(family: controller.theme.headingFont) { f in controller.applyFonts(FontPair(name: "Custom", heading: f, body: controller.theme.bodyFont)) }
                        .frame(width: 160)
                }
                PaneRow(label: "Body") {
                    FontFamilyPicker(family: controller.theme.bodyFont) { f in controller.applyFonts(FontPair(name: "Custom", heading: controller.theme.headingFont, body: f)) }
                        .frame(width: 160)
                }
            }
            .padding(14)
        }
    }

    private var suggestedLayouts: [LayoutKind] {
        let slide = controller.currentSlide
        let pictures = slide.elements.filter(\.isImage).count
        if controller.currentSlideIndex == 0 { return [.title, .sectionHeader, .bigNumber, .quote] }
        if pictures > 0 { return [.pictureCaption, .contentCaption, .twoContent, .titleOnly] }
        return [.titleContent, .twoContent, .comparison, .contentCaption, .sectionHeader, .quote, .bigNumber, .titleOnly]
    }

    /// The current slide's content shown in another layout.
    private func preview(_ layout: LayoutKind) -> NSImage {
        var slide = controller.currentSlide
        LayoutBuilder.apply(layout, to: &slide, theme: controller.theme, size: controller.slideSize)
        return ThumbnailCache.shared.thumbnail(slide, number: controller.currentSlideIndex + 1, presentation: controller.presentation, width: 120)
    }
}

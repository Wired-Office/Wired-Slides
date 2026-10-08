import AppKit
import SwiftUI

/// The task pane on the right of the window.
struct SidePaneView: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(controller.sidePane?.title ?? "").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { controller.sidePane = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            Divider()
            Group {
                switch controller.sidePane {
                case .format: FormatPane(controller: controller)
                case .animations: AnimationPane(controller: controller)
                case .selection: SelectionPane(controller: controller)
                case .comments: CommentsPane(controller: controller)
                case .designer: DesignerPane(controller: controller)
                case nil: Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: Theme.paneBackground))
        .frame(minWidth: 260)
    }
}

/// A swatch that opens the theme color palette.
struct PaintColorWell: View {
    let colors: ThemeColors
    let color: PaintColor?
    var kind: ThemeColorPalette.Kind = .fill
    let onChange: (PaintColor?) -> Void
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.map { Color(nsColor: $0.resolve(colors).nsColor) } ?? Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .overlay { if color == nil { Image(systemName: "nosign").font(.system(size: 10)).foregroundStyle(.secondary) } }
                    .frame(width: 34, height: 18)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showing) {
            ThemeColorPalette(kind: kind, colors: colors, onPick: { picked in
                showing = false
                onChange(picked)
            }, onMore: {
                showing = false
                ColorPanelBridge.shared.show(initial: color?.resolve(colors).nsColor) { onChange(.rgb(RGBColor($0))) }
            })
        }
    }
}

/// A collapsible section with a title.
struct PaneSection<Content: View>: View {
    let title: String
    @State var expanded = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.leading, 15)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A labeled row in a pane.
struct PaneRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content()
        }
    }
}

/// A slider with its value.
struct PaneSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Text(format(value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range).controlSize(.small)
        }
    }
}

// MARK: - Fill editor

enum FillKind: String, CaseIterable, Identifiable {
    case none = "No Fill", solid = "Solid Fill", gradient = "Gradient Fill", picture = "Picture Fill", pattern = "Pattern Fill"
    var id: String { rawValue }

    init(_ fill: Fill?) {
        switch fill {
        case .none?, nil: self = .none
        case .solid?: self = .solid
        case .gradient?: self = .gradient
        case .image?: self = .picture
        case .pattern?: self = .pattern
        }
    }
}

struct FillEditor: View {
    let colors: ThemeColors
    let fill: Fill
    var allowNone = true
    let onChange: (Fill) -> Void
    var onPickPicture: (() -> Void)?

    var body: some View {
        let kind = FillKind(fill)
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { kind }, set: { new in onChange(defaultFill(new)) })) {
                ForEach(FillKind.allCases.filter { allowNone || $0 != .none }) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            switch fill {
            case .none:
                EmptyView()
            case .solid(let c):
                PaneRow(label: "Color") { PaintColorWell(colors: colors, color: c) { onChange($0.map { .solid($0) } ?? .none) } }
                PaneSlider(label: "Transparency", value: 1 - c.alpha, range: 0...1) { v in onChange(.solid(c.withAlpha(1 - v, colors: colors))) }
            case .gradient(var g):
                PaneRow(label: "Type") {
                    Picker("", selection: Binding(get: { g.kind }, set: { g.kind = $0; onChange(.gradient(g)) })) {
                        Text("Linear").tag(GradientFill.Kind.linear)
                        Text("Radial").tag(GradientFill.Kind.radial)
                    }
                    .labelsHidden().frame(width: 110)
                }
                if g.kind == .linear {
                    PaneSlider(label: "Angle", value: g.angle, range: 0...359, format: { "\(Int($0))°" }) { v in g.angle = v.rounded(); onChange(.gradient(g)) }
                }
                ForEach(g.stops.indices, id: \.self) { i in
                    HStack {
                        Text("Stop \(i + 1)").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        PaintColorWell(colors: colors, color: g.stops[i].color) { c in if let c { g.stops[i].color = c; onChange(.gradient(g)) } }
                        Slider(value: Binding(get: { g.stops[i].position }, set: { g.stops[i].position = $0; onChange(.gradient(g)) }), in: 0...1).controlSize(.small)
                        if g.stops.count > 2 {
                            Button { g.stops.remove(at: i); onChange(.gradient(g)) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                Button { g.stops.append(GradientStop(color: .theme(.accent2), position: 1)); onChange(.gradient(g)) } label: { Label("Add Stop", systemImage: "plus") }
                    .buttonStyle(.borderless).font(.system(size: 11.5))
            case .image(var f):
                Button("Choose Picture…") { onPickPicture?() }
                PaneRow(label: "Mode") {
                    Picker("", selection: Binding(get: { f.mode }, set: { f.mode = $0; onChange(.image(f)) })) {
                        Text("Stretch").tag(ImageFill.Mode.stretch)
                        Text("Fill").tag(ImageFill.Mode.fit)
                        Text("Tile").tag(ImageFill.Mode.tile)
                    }
                    .labelsHidden().frame(width: 110)
                }
                PaneSlider(label: "Transparency", value: f.transparency, range: 0...1) { v in f.transparency = v; onChange(.image(f)) }
            case .pattern(var p):
                PaneRow(label: "Pattern") {
                    Picker("", selection: Binding(get: { p.kind }, set: { p.kind = $0; onChange(.pattern(p)) })) {
                        ForEach(PatternKind.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                }
                PaneRow(label: "Foreground") { PaintColorWell(colors: colors, color: p.foreground) { if let c = $0 { p.foreground = c; onChange(.pattern(p)) } } }
                PaneRow(label: "Background") { PaintColorWell(colors: colors, color: p.background) { if let c = $0 { p.background = c; onChange(.pattern(p)) } } }
            }
        }
    }

    private func defaultFill(_ kind: FillKind) -> Fill {
        switch kind {
        case .none: return .none
        case .solid: return .solid(fill.solidColor ?? .theme(.accent1))
        case .gradient: return .gradient(.twoTone(.theme(.accent1, shade: 0.3, alpha: 1), .theme(.accent1, shade: -0.25, alpha: 1)))
        case .picture:
            onPickPicture?()
            return fill
        case .pattern: return .pattern(PatternFill(kind: .diagonalUp, foreground: .theme(.accent1), background: .theme(.light1)))
        }
    }
}

// MARK: - Format pane

struct FormatPane: View {
    @ObservedObject var controller: PresentationController
    @State private var tab = 0

    var body: some View {
        if let e = controller.primaryElement {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Image(systemName: "paintbrush.pointed").tag(0).help("Fill & Line")
                    Image(systemName: "sparkles").tag(1).help("Effects")
                    Image(systemName: "arrow.up.left.and.arrow.down.right").tag(2).help("Size & Properties")
                    if e.isImage { Image(systemName: "photo").tag(3).help("Picture") }
                    if e.text != nil || e.isTable { Image(systemName: "textformat").tag(4).help("Text Box") }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(e.name).font(.system(size: 11)).foregroundStyle(.secondary)
                        switch tab {
                        case 0: fillAndLine(e)
                        case 1: effects(e)
                        case 2: sizeAndPosition(e)
                        case 3: picture(e)
                        default: textBox(e)
                        }
                    }
                    .padding(14)
                }
            }
        } else {
            ScrollView { BackgroundFormat(controller: controller).padding(14) }
        }
    }

    @ViewBuilder
    private func fillAndLine(_ e: SlideElement) -> some View {
        let colors = controller.theme.colors
        if e.shape != nil || e.isChart || e.isGroup {
            PaneSection(title: "Fill") {
                FillEditor(colors: colors, fill: controller.primaryFill ?? .none, onChange: { controller.setFill($0) }, onPickPicture: { pickFillPicture() })
            }
        }
        if let line = controller.primaryLineStyle {
            PaneSection(title: "Line") {
                Picker("", selection: Binding(get: { line.color == nil ? 0 : 1 }, set: { v in controller.setLine { $0.color = v == 0 ? nil : ($0.color ?? .theme(.accent1)) } })) {
                    Text("No Line").tag(0)
                    Text("Solid Line").tag(1)
                }
                .labelsHidden()
                if line.color != nil {
                    PaneRow(label: "Color") { PaintColorWell(colors: colors, color: line.color, kind: .line) { c in controller.setLine { $0.color = c } } }
                    PaneSlider(label: "Width", value: line.width, range: 0.25...24, format: { String(format: "%.2f pt", $0) }) { v in controller.setLine { $0.width = (v * 4).rounded() / 4 } }
                    PaneRow(label: "Dash type") {
                        Picker("", selection: Binding(get: { line.dash }, set: { v in controller.setLine { $0.dash = v } })) {
                            ForEach(DashStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().frame(width: 130)
                    }
                    if e.isLine {
                        PaneRow(label: "Begin arrow") {
                            Picker("", selection: Binding(get: { line.head }, set: { v in controller.setLine { $0.head = v } })) {
                                ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                        }
                        PaneRow(label: "End arrow") {
                            Picker("", selection: Binding(get: { line.tail }, set: { v in controller.setLine { $0.tail = v } })) {
                                ForEach(ArrowHead.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                        }
                        if case .line(let l) = e.content {
                            PaneRow(label: "Connector") {
                                Picker("", selection: Binding(get: { l.kind }, set: { v in
                                    controller.changeTargets("Connector Type") { el in if case .line(var c) = el.content { c.kind = v; el.content = .line(c) } }
                                })) {
                                    ForEach(ConnectorKind.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden().frame(width: 130)
                            }
                        }
                    }
                    Toggle("Round caps", isOn: Binding(get: { line.roundCaps }, set: { v in controller.setLine { $0.roundCaps = v } }))
                        .toggleStyle(.checkbox).font(.system(size: 11.5))
                }
            }
        }
        if case .icon(let icon) = e.content {
            PaneSection(title: "Icon") {
                PaneRow(label: "Color") {
                    PaintColorWell(colors: colors, color: icon.color) { c in if let c { controller.setFill(.solid(c)) } }
                }
            }
        }
    }

    @ViewBuilder
    private func effects(_ e: SlideElement) -> some View {
        let fx = controller.primaryEffects ?? Effects()
        let colors = controller.theme.colors
        PaneSection(title: "Shadow") {
            Toggle("Shadow", isOn: Binding(get: { fx.shadow != nil }, set: { v in controller.setEffects { $0.shadow = v ? .outer : nil } }))
                .toggleStyle(.checkbox)
            if let s = fx.shadow {
                PaneRow(label: "Color") {
                    PaintColorWell(colors: colors, color: .rgb(s.color)) { c in if let c { controller.setEffects { $0.shadow?.color = c.resolve(colors).withAlpha(1) } } }
                }
                PaneSlider(label: "Transparency", value: 1 - s.opacity, range: 0...1) { v in controller.setEffects { $0.shadow?.opacity = 1 - v } }
                PaneSlider(label: "Blur", value: s.blur, range: 0...60, format: { "\(Int($0)) pt" }) { v in controller.setEffects { $0.shadow?.blur = v.rounded() } }
                PaneSlider(label: "Distance", value: s.distance, range: 0...60, format: { "\(Int($0)) pt" }) { v in controller.setEffects { $0.shadow?.distance = v.rounded() } }
                PaneSlider(label: "Angle", value: s.angle, range: 0...359, format: { "\(Int($0))°" }) { v in controller.setEffects { $0.shadow?.angle = v.rounded() } }
            }
        }
        PaneSection(title: "Glow") {
            Toggle("Glow", isOn: Binding(get: { fx.glow != nil }, set: { v in controller.setEffects { $0.glow = v ? GlowEffect() : nil } }))
                .toggleStyle(.checkbox)
            if let g = fx.glow {
                PaneRow(label: "Color") { PaintColorWell(colors: colors, color: g.color) { c in if let c { controller.setEffects { $0.glow?.color = c } } } }
                PaneSlider(label: "Size", value: g.radius, range: 1...40, format: { "\(Int($0)) pt" }) { v in controller.setEffects { $0.glow?.radius = v.rounded() } }
            }
        }
        PaneSection(title: "Reflection") {
            Toggle("Reflection", isOn: Binding(get: { fx.reflection != nil }, set: { v in controller.setEffects { $0.reflection = v ? ReflectionEffect() : nil } }))
                .toggleStyle(.checkbox)
            if let r = fx.reflection {
                PaneSlider(label: "Transparency", value: 1 - r.opacity, range: 0...1) { v in controller.setEffects { $0.reflection?.opacity = 1 - v } }
                PaneSlider(label: "Size", value: r.size, range: 0.05...1) { v in controller.setEffects { $0.reflection?.size = v } }
                PaneSlider(label: "Distance", value: r.distance, range: 0...40, format: { "\(Int($0)) pt" }) { v in controller.setEffects { $0.reflection?.distance = v.rounded() } }
            }
        }
    }

    @ViewBuilder
    private func sizeAndPosition(_ e: SlideElement) -> some View {
        PaneSection(title: "Size") {
            NumberField(label: "Height", value: Double(e.frame.height), range: 0...5000, step: 1, unit: " pt", width: 70) { v in
                var f = e.frame
                if e.lockAspectRatio, f.height > 0 { f.size.width = CGFloat(v) * f.width / f.height }
                f.size.height = CGFloat(v)
                controller.setFrame(e.id, f)
            }
            NumberField(label: "Width", value: Double(e.frame.width), range: 0...5000, step: 1, unit: " pt", width: 70) { v in
                var f = e.frame
                if e.lockAspectRatio, f.width > 0 { f.size.height = CGFloat(v) * f.height / f.width }
                f.size.width = CGFloat(v)
                controller.setFrame(e.id, f)
            }
            NumberField(label: "Rotation", value: e.rotation, range: -360...360, step: 15, unit: "°", width: 60) { controller.setRotation($0) }
            Toggle("Lock aspect ratio", isOn: Binding(get: { e.lockAspectRatio }, set: { v in controller.changeTargets("Lock Aspect Ratio") { $0.lockAspectRatio = v } }))
                .toggleStyle(.checkbox).font(.system(size: 11.5))
        }
        PaneSection(title: "Position") {
            NumberField(label: "Horizontal", value: Double(e.frame.minX), range: -5000...5000, step: 1, unit: " pt", width: 70) { v in
                var f = e.frame; f.origin.x = CGFloat(v); controller.setFrame(e.id, f, name: "Position")
            }
            NumberField(label: "Vertical", value: Double(e.frame.minY), range: -5000...5000, step: 1, unit: " pt", width: 70) { v in
                var f = e.frame; f.origin.y = CGFloat(v); controller.setFrame(e.id, f, name: "Position")
            }
        }
        PaneSection(title: "Properties") {
            Toggle("Locked (can't be moved or selected on the slide)", isOn: Binding(get: { e.locked }, set: { _ in controller.toggleLock() }))
                .toggleStyle(.checkbox).font(.system(size: 11.5))
            Text("Alt Text").font(.system(size: 11.5)).foregroundStyle(.secondary)
            AltTextField(text: e.altText) { controller.setAltText($0) }
        }
    }

    @ViewBuilder
    private func picture(_ e: SlideElement) -> some View {
        if case .image(let image) = e.content {
            let a = image.adjustments
            PaneSection(title: "Picture Corrections") {
                PaneSlider(label: "Brightness", value: a.brightness, range: -1...1) { v in controller.setImage({ $0.adjustments.brightness = v }, name: "Brightness") }
                PaneSlider(label: "Contrast", value: a.contrast, range: -1...1) { v in controller.setImage({ $0.adjustments.contrast = v }, name: "Contrast") }
            }
            PaneSection(title: "Picture Color") {
                PaneSlider(label: "Saturation", value: a.saturation, range: 0...2) { v in controller.setImage({ $0.adjustments.saturation = v }, name: "Saturation") }
                Toggle("Sepia", isOn: Binding(get: { a.sepia }, set: { v in controller.setImage({ $0.adjustments.sepia = v }, name: "Sepia") })).toggleStyle(.checkbox)
            }
            PaneSection(title: "Picture Transparency") {
                PaneSlider(label: "Transparency", value: a.transparency, range: 0...1) { v in controller.setImage({ $0.adjustments.transparency = v }, name: "Transparency") }
            }
            PaneSection(title: "Crop") {
                PaneSlider(label: "Left", value: image.crop.left, range: 0...0.9) { v in controller.setImage({ $0.crop.left = v }, name: "Crop") }
                PaneSlider(label: "Right", value: image.crop.right, range: 0...0.9) { v in controller.setImage({ $0.crop.right = v }, name: "Crop") }
                PaneSlider(label: "Top", value: image.crop.top, range: 0...0.9) { v in controller.setImage({ $0.crop.top = v }, name: "Crop") }
                PaneSlider(label: "Bottom", value: image.crop.bottom, range: 0...0.9) { v in controller.setImage({ $0.crop.bottom = v }, name: "Crop") }
                PaneRow(label: "Shape") {
                    Picker("", selection: Binding(get: { image.maskShape ?? .rect }, set: { controller.changeShapeKind($0) })) {
                        ForEach([ShapeKind.rect, .roundRect, .ellipse, .triangle, .diamond, .hexagon, .star5, .heart, .teardrop]) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                }
            }
        }
    }

    @ViewBuilder
    private func textBox(_ e: SlideElement) -> some View {
        if let body = controller.currentTextBody {
            PaneSection(title: "Text Box") {
                PaneRow(label: "Vertical alignment") {
                    Picker("", selection: Binding(get: { body.anchor }, set: { controller.setVerticalAnchor($0) })) {
                        Text("Top").tag(VerticalAnchor.top)
                        Text("Middle").tag(VerticalAnchor.middle)
                        Text("Bottom").tag(VerticalAnchor.bottom)
                    }
                    .labelsHidden().frame(width: 100)
                }
                PaneRow(label: "Text direction") {
                    Picker("", selection: Binding(get: { body.direction }, set: { controller.setTextDirection($0) })) {
                        Text("Horizontal").tag(TextDirection.horizontal)
                        Text("Rotate 90°").tag(TextDirection.rotated90)
                        Text("Rotate 270°").tag(TextDirection.rotated270)
                    }
                    .labelsHidden().frame(width: 110)
                }
                Picker("Autofit", selection: Binding(get: { body.autofit }, set: { controller.setAutofit($0) })) {
                    ForEach(AutoFit.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 11.5))
                Toggle("Wrap text in shape", isOn: Binding(get: { body.wrap }, set: { controller.setWrap($0) })).toggleStyle(.checkbox).font(.system(size: 11.5))
                NumberField(label: "Columns", value: Double(body.columns), range: 1...6, step: 1, width: 40) { controller.setColumns(Int($0)) }
            }
            PaneSection(title: "Margins") {
                NumberField(label: "Left", value: body.insets.left, range: 0...200, step: 1, unit: " pt", width: 60) { v in controller.setTextBox("Margins") { $0.insets.left = v } }
                NumberField(label: "Right", value: body.insets.right, range: 0...200, step: 1, unit: " pt", width: 60) { v in controller.setTextBox("Margins") { $0.insets.right = v } }
                NumberField(label: "Top", value: body.insets.top, range: 0...200, step: 1, unit: " pt", width: 60) { v in controller.setTextBox("Margins") { $0.insets.top = v } }
                NumberField(label: "Bottom", value: body.insets.bottom, range: 0...200, step: 1, unit: " pt", width: 60) { v in controller.setTextBox("Margins") { $0.insets.bottom = v } }
            }
        }
    }

    private func pickFillPicture() {
        guard let window = controller.document?.windowControllers.first?.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            var id = ""
            controller.change("Picture Fill") { p in id = p.addMedia(data, filename: url.lastPathComponent) }
            controller.setFill(.image(ImageFill(mediaID: id)))
        }
    }
}

private struct AltTextField: View {
    let text: String
    let onCommit: (String) -> Void
    @State private var value = ""

    var body: some View {
        TextField("Describe this object", text: $value, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            .onAppear { value = text }
            .onChange(of: text) { _, t in value = t }
            .onSubmit { onCommit(value) }
    }
}

/// Format Background (no selection).
struct BackgroundFormat: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let slide = controller.currentSlide
        let fill = SlideRenderer.background(for: slide, theme: controller.theme)
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.system(size: 13, weight: .semibold))
            FillEditor(colors: controller.theme.colors, fill: fill, allowNone: false, onChange: { controller.setBackground($0, applyToAll: false) },
                       onPickPicture: { pickPicture() })
            Toggle("Hide background graphics", isOn: Binding(get: { slide.hideBackgroundGraphics }, set: { controller.setHideBackgroundGraphics($0) }))
                .toggleStyle(.checkbox).font(.system(size: 11.5))
            HStack {
                Button("Apply to All") { controller.setBackground(fill, applyToAll: true) }
                Button("Reset Background") { controller.setBackground(nil, applyToAll: false) }
            }
            .controlSize(.small)
            Divider()
            Text("Select an object on the slide to format it.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func pickPicture() {
        guard let window = controller.document?.windowControllers.first?.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            var id = ""
            controller.change("Picture Background") { p in id = p.addMedia(data, filename: url.lastPathComponent) }
            controller.setBackground(.image(ImageFill(mediaID: id, mode: .fit)), applyToAll: false)
        }
    }
}

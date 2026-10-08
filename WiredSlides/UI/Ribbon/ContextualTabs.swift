import AppKit
import SwiftUI

/// Height and width fields for the selection.
struct SizeGroup: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        if let e = controller.primaryElement {
            CaptionedGroup(title: "Size", showsDivider: false) {
                VStack(alignment: .leading, spacing: 5) {
                    NumberField(label: "Height:", value: Double(e.frame.height), range: 1...5000, step: 1, unit: " pt", width: 64) { v in
                        var f = e.frame
                        if e.lockAspectRatio, f.height > 0 { f.size.width = CGFloat(v) * f.width / f.height }
                        f.size.height = CGFloat(v)
                        controller.setFrame(e.id, f)
                    }
                    NumberField(label: "Width:", value: Double(e.frame.width), range: 1...5000, step: 1, unit: " pt", width: 64) { v in
                        var f = e.frame
                        if e.lockAspectRatio, f.width > 0 { f.size.height = CGFloat(v) * f.height / f.width }
                        f.size.width = CGFloat(v)
                        controller.setFrame(e.id, f)
                    }
                    Toggle("Lock aspect ratio", isOn: Binding(get: { e.lockAspectRatio }, set: { v in controller.changeTargets("Lock Aspect Ratio") { $0.lockAspectRatio = v } }))
                        .toggleStyle(.checkbox).font(.system(size: 11))
                }
            }
        }
    }
}

struct ArrangeGroup: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        CaptionedGroup(title: "Arrange") {
            RibbonColumn {
                RibbonCompactButton(title: "Bring Forward", symbol: "square.2.layers.3d.top.filled") { controller.arrange(.forward) }
                RibbonCompactButton(title: "Send Backward", symbol: "square.2.layers.3d.bottom.filled") { controller.arrange(.backward) }
                RibbonCompactButton(title: "Selection Pane", symbol: "list.bullet.rectangle") { controller.sidePane = .selection }
            }
            RibbonColumn {
                RibbonMenuButton(symbol: "align.horizontal.left", help: "Align", label: "Align") { RibbonMenus.align(controller) }
                RibbonMenuButton(symbol: "square.on.square.dashed", help: "Group", label: "Group") {
                    let menu = NSMenu()
                    menu.add("Group", enabled: controller.selection.count > 1) { controller.group() }
                    menu.add("Ungroup", enabled: controller.selectedElements.contains(where: \.isGroup)) { controller.ungroup() }
                    return menu
                }
                RibbonMenuButton(symbol: "rotate.right", help: "Rotate", label: "Rotate") { RibbonMenus.rotate(controller) }
            }
        }
    }
}

struct ShapeFormatTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let _ = controller.textSelectionRevision
        let colors = controller.theme.colors
        let run = controller.currentRunStyle
        HStack(spacing: 0) {
            CaptionedGroup(title: "Insert Shapes") {
                RibbonLargeButton(title: "Shapes", symbol: "square.on.circle", help: "Draw a shape", menu: { RibbonMenus.shapes(controller) })
                RibbonColumn {
                    RibbonMenuButton(symbol: "pencil.and.outline", help: "Change Shape", label: "Edit Shape") { RibbonMenus.changeShape(controller) }
                    RibbonCompactButton(title: "Text Box", symbol: "character.textbox") { controller.pendingInsert = .textBox }
                }
            }
            CaptionedGroup(title: "Shape Styles") {
                let presets = Array(ShapeStylePreset.presets().prefix(14))
                LazyHGrid(rows: [GridItem(.fixed(26)), GridItem(.fixed(26))], spacing: 3) {
                    ForEach(presets) { preset in
                        GalleryTile(help: "Apply style") { controller.applyShapeStyle(preset) } label: {
                            Image(nsImage: ShapeStyleMenu.preview(preset, colors: colors)).resizable().frame(width: 48, height: 18)
                        }
                    }
                }
                .frame(height: 62)
                RibbonMenuButton(symbol: "ellipsis", help: "More Styles") { ShapeStyleMenu.menu(controller) }
                RibbonColumn {
                    ColorSplitButton(symbol: "paintbrush.pointed", help: "Shape Fill", kind: .fill, colors: colors,
                                     current: controller.primaryFill?.solidColor ?? .theme(.accent1)) { c in controller.setFill(c.map { .solid($0) } ?? .none) }
                    HStack(spacing: 0) {
                        ColorSplitButton(symbol: "square.dashed", help: "Shape Outline", kind: .line, colors: colors,
                                         current: controller.primaryLineStyle?.color ?? .theme(.accent1)) { c in controller.setLine { $0.color = c } }
                        RibbonMenuButton(symbol: "line.3.horizontal", help: "Weight, Dashes and Arrows") { RibbonMenus.outline(controller) }
                    }
                    RibbonMenuButton(symbol: "sparkles", help: "Shape Effects", label: "Effects") { RibbonMenus.effects(controller) }
                }
            }
            CaptionedGroup(title: "WordArt Styles") {
                RibbonColumn {
                    ColorSplitButton(symbol: "a.square.fill", help: "Text Fill", kind: .text, colors: colors, current: run.color ?? .theme(.dark1)) { controller.setTextColor($0) }
                    ColorSplitButton(symbol: "a.square", help: "Text Outline", kind: .line, colors: colors, current: run.outlineColor ?? .theme(.accent1)) {
                        controller.setTextOutline($0, width: max(run.outlineWidth, 1))
                    }
                    RibbonMenuButton(symbol: "wand.and.stars", help: "Text Effects", label: "Text Effects") {
                        let menu = NSMenu()
                        menu.add("Shadow", checked: run.shadow) { controller.toggleShadow() }
                        menu.addSection("WordArt Styles")
                        for preset in WordArtPreset.all {
                            let item = menu.add("") { controller.applyRunStyle("WordArt Style") { preset.apply(&$0) } }
                            item.attributedTitle = WordArtPreview.attributed(preset, theme: controller.theme)
                        }
                        return menu
                    }
                }
            }
            CaptionedGroup(title: "Accessibility") {
                RibbonLargeButton(title: "Alt Text", symbol: "text.below.photo", help: "Describe this object for screen readers") { AltTextPrompt.show(controller) }
            }
            ArrangeGroup(controller: controller)
            SizeGroup(controller: controller)
        }
    }
}

struct PictureFormatTab: View {
    @ObservedObject var controller: PresentationController

    private var image: ImageContent? {
        if case .image(let i) = controller.primaryElement?.content { return i }
        return nil
    }

    var body: some View {
        let adj = image?.adjustments ?? ImageAdjustments()
        HStack(spacing: 0) {
            CaptionedGroup(title: "Adjust") {
                RibbonLargeButton(title: "Remove Background", symbol: "person.crop.rectangle", help: "Remove the background (subject lift)", isEnabled: image != nil) {
                    BackgroundRemover.run(controller)
                }
                RibbonLargeButton(title: "Corrections", symbol: "sun.max", help: "Brightness and contrast", isEnabled: image != nil, menu: {
                    let menu = NSMenu()
                    for b in [-0.4, -0.2, 0, 0.2, 0.4] {
                        for c in [-0.4, 0, 0.4] {
                            menu.add("Brightness \(Int(b * 100))%  Contrast \(Int(c * 100))%", checked: adj.brightness == b && adj.contrast == c) {
                                controller.setImage({ $0.adjustments.brightness = b; $0.adjustments.contrast = c }, name: "Corrections")
                            }
                        }
                    }
                    return menu
                })
                RibbonLargeButton(title: "Color", symbol: "paintpalette", help: "Saturation and recolor", isEnabled: image != nil, menu: {
                    let menu = NSMenu()
                    for s in [0.0, 0.33, 0.66, 1, 1.5, 2] {
                        menu.add("Saturation \(Int(s * 100))%", checked: adj.saturation == s && !adj.sepia) {
                            controller.setImage({ $0.adjustments.saturation = s; $0.adjustments.sepia = false }, name: "Color")
                        }
                    }
                    menu.addItem(.separator())
                    menu.add("Grayscale", checked: adj.saturation == 0) { controller.setImage({ $0.adjustments.saturation = 0 }, name: "Color") }
                    menu.add("Sepia", checked: adj.sepia) { controller.setImage({ $0.adjustments.sepia.toggle() }, name: "Color") }
                    return menu
                })
                RibbonLargeButton(title: "Transparency", symbol: "square.dashed.inset.filled", help: "Picture transparency", isEnabled: image != nil, menu: {
                    let menu = NSMenu()
                    for t in [0.0, 0.15, 0.3, 0.5, 0.65, 0.8] {
                        menu.add("\(Int(t * 100))%", checked: abs(adj.transparency - t) < 0.01) { controller.setImage({ $0.adjustments.transparency = t }, name: "Transparency") }
                    }
                    return menu
                })
                RibbonColumn {
                    RibbonCompactButton(title: "Change Picture", symbol: "photo") { ChangePicture.run(controller) }
                    RibbonCompactButton(title: "Reset Picture", symbol: "arrow.counterclockwise") { controller.resetPicture(size: false) }
                    RibbonCompactButton(title: "Reset Size", symbol: "arrow.up.left.and.arrow.down.right") { controller.resetPicture(size: true) }
                }
            }
            CaptionedGroup(title: "Picture Styles") {
                let styles = PictureStyle.all
                LazyHGrid(rows: [GridItem(.fixed(28)), GridItem(.fixed(28))], spacing: 3) {
                    ForEach(styles) { style in
                        GalleryTile(help: style.name) { controller.setImage({ style.apply(&$0) }, name: "Picture Style") } label: {
                            Image(systemName: style.symbol).font(.system(size: 15)).frame(width: 34, height: 20)
                        }
                    }
                }
                .frame(height: 64)
                RibbonColumn {
                    ColorSplitButton(symbol: "square.dashed", help: "Picture Border", kind: .line, colors: controller.theme.colors,
                                     current: image?.line.color ?? .theme(.dark1)) { c in controller.setLine { $0.color = c; if $0.width <= 0 { $0.width = 1 } } }
                    RibbonMenuButton(symbol: "sparkles", help: "Picture Effects", label: "Effects") { RibbonMenus.effects(controller) }
                    RibbonMenuButton(symbol: "crop", help: "Crop", label: "Crop") { CropMenu.menu(controller) }
                }
            }
            ArrangeGroup(controller: controller)
            SizeGroup(controller: controller)
        }
    }
}

/// Picture Styles presets.
struct PictureStyle: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let apply: (inout ImageContent) -> Void

    static let all: [PictureStyle] = [
        PictureStyle(id: "plain", name: "Simple", symbol: "photo") { $0.line = .none; $0.effects = .none; $0.maskShape = nil },
        PictureStyle(id: "frame", name: "Simple Frame, White", symbol: "photo.artframe") {
            $0.line = .solid(.white, width: 8); $0.effects = Effects(shadow: .soft); $0.maskShape = nil
        },
        PictureStyle(id: "black", name: "Simple Frame, Black", symbol: "rectangle.inset.filled") { $0.line = .solid(.black, width: 6); $0.effects = .none; $0.maskShape = nil },
        PictureStyle(id: "shadow", name: "Drop Shadow Rectangle", symbol: "square.filled.on.square") { $0.line = .none; $0.effects = Effects(shadow: .soft); $0.maskShape = nil },
        PictureStyle(id: "rounded", name: "Rounded Rectangle", symbol: "app") { $0.line = .none; $0.maskShape = .roundRect; $0.effects = Effects(shadow: .soft) },
        PictureStyle(id: "oval", name: "Soft Edge Oval", symbol: "circle") { $0.line = .none; $0.maskShape = .ellipse; $0.effects = .none },
        PictureStyle(id: "reflected", name: "Reflected Rounded Rectangle", symbol: "square.bottomhalf.filled") {
            $0.line = .none; $0.maskShape = .roundRect; $0.effects = Effects(reflection: ReflectionEffect(opacity: 0.4, size: 0.4, distance: 2))
        },
        PictureStyle(id: "glow", name: "Glow", symbol: "sun.max.circle") { $0.line = .none; $0.effects = Effects(glow: GlowEffect(color: .theme(.accent1, shade: 0, alpha: 0.6), radius: 12)) },
        PictureStyle(id: "hexagon", name: "Hexagon", symbol: "hexagon") { $0.maskShape = .hexagon; $0.line = .none },
        PictureStyle(id: "thick", name: "Thick Matte, Accent", symbol: "square.inset.filled") { $0.line = .solid(.theme(.accent1), width: 10); $0.maskShape = nil },
    ]
}

enum CropMenu {
    static func menu(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        let shapes = NSMenu(title: "Crop to Shape")
        for kind in [ShapeKind.rect, .roundRect, .ellipse, .triangle, .diamond, .pentagon, .hexagon, .octagon, .star5, .heart, .teardrop, .cloud, .snip1Rect] {
            let item = shapes.add(kind.title) { controller.changeShapeKind(kind) }
            item.image = ShapeIcons.image(kind)
        }
        menu.addSubmenu(shapes)
        let ratio = NSMenu(title: "Aspect Ratio")
        for (name, value) in [("1:1", 1.0), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9), ("3:4", 0.75), ("2:3", 2.0 / 3), ("9:16", 9.0 / 16)] {
            ratio.add(name) { cropToAspect(controller, value) }
        }
        menu.addSubmenu(ratio)
        menu.addItem(.separator())
        menu.add("Crop Edges…", symbol: "crop") { controller.sidePane = .format }
        menu.add("Remove Crop", symbol: "arrow.counterclockwise") { controller.setImage({ $0.crop = CropInsets() }, name: "Crop") }
        return menu
    }

    /// Crops the picture to an aspect ratio, centered, keeping its width.
    static func cropToAspect(_ controller: PresentationController, _ aspect: Double) {
        guard let e = controller.primaryElement, case .image(var image) = e.content,
              let natural = ImageCache.size(image.mediaID, controller.presentation.media) else { return }
        let imageAspect = Double(natural.width / max(natural.height, 1))
        image.crop = CropInsets()
        if imageAspect > aspect {
            let excess = 1 - aspect / imageAspect
            image.crop.left = excess / 2; image.crop.right = excess / 2
        } else {
            let excess = 1 - imageAspect / aspect
            image.crop.top = excess / 2; image.crop.bottom = excess / 2
        }
        var frame = e.frame
        frame.size.height = frame.width / CGFloat(aspect)
        let id = e.id
        controller.changeElements([id], "Crop") { el in
            el.content = .image(image)
            el.frame = frame
        }
    }
}

struct TableDesignTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let style = controller.selectedTable?.table.style ?? TableStyleOptions()
        let colors = controller.theme.colors
        HStack(spacing: 0) {
            CaptionedGroup(title: "Table Style Options") {
                VStack(alignment: .leading, spacing: 3) {
                    option("Header Row", style.headerRow) { $0.headerRow = $1 }
                    option("Total Row", style.totalRow) { $0.totalRow = $1 }
                    option("Banded Rows", style.bandedRows) { $0.bandedRows = $1 }
                }
                VStack(alignment: .leading, spacing: 3) {
                    option("First Column", style.firstColumn) { $0.firstColumn = $1 }
                    option("Last Column", style.lastColumn) { $0.lastColumn = $1 }
                    option("Banded Columns", style.bandedColumns) { $0.bandedColumns = $1 }
                }
                .padding(.leading, 6)
            }
            CaptionedGroup(title: "Table Styles") {
                let slots: [ThemeSlot] = [.dark1, .accent1, .accent2, .accent3, .accent4, .accent5, .accent6]
                LazyHGrid(rows: [GridItem(.fixed(20)), GridItem(.fixed(20)), GridItem(.fixed(20))], spacing: 3) {
                    ForEach(0..<3) { intensity in
                        ForEach(slots) { slot in
                            GalleryTile(isSelected: style.color == .theme(slot) && style.intensity == intensity, help: "\(["Medium", "Light", "Dark"][intensity]) – \(slot.title)") {
                                controller.setTableStyle { $0.color = .theme(slot); $0.intensity = intensity; $0.borderColor = nil }
                            } label: {
                                TableStyleSwatch(color: colors[slot], intensity: intensity).frame(width: 30, height: 14)
                            }
                        }
                    }
                }
                .frame(height: 70)
                RibbonColumn {
                    ColorSplitButton(symbol: "paintbrush.pointed", help: "Shading", kind: .fill, colors: colors, current: .theme(.accent1, shade: 0.6, alpha: 1)) {
                        controller.setCellFill($0.map { .solid($0) })
                    }
                    ColorSplitButton(symbol: "square.dashed", help: "Borders", kind: .line, colors: colors, current: style.borderColor ?? .theme(.dark1)) { c in
                        controller.setTableStyle { $0.borderColor = c }
                    }
                    RibbonMenuButton(symbol: "line.3.horizontal", help: "Border Weight", label: "Weight") {
                        let menu = NSMenu()
                        for w in [0.5, 1, 1.5, 2.25, 3] {
                            menu.add("\(w.formatted()) pt", checked: style.borderWidth == w) { controller.setTableStyle { $0.borderWidth = w; if $0.borderColor == nil { $0.borderColor = .theme(.dark1) } } }
                        }
                        return menu
                    }
                }
            }
            CaptionedGroup(title: "WordArt Styles", showsDivider: false) {
                RibbonColumn {
                    ColorSplitButton(symbol: "a.square.fill", help: "Text Fill", kind: .text, colors: colors, current: controller.currentRunStyle.color ?? .theme(.dark1)) {
                        controller.setTextColor($0)
                    }
                    RibbonCompactButton(title: "Bold", symbol: "bold", isOn: controller.currentRunStyle.bold == true) { controller.toggleBold() }
                }
            }
        }
    }

    private func option(_ title: String, _ value: Bool, _ set: @escaping (inout TableStyleOptions, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { v in controller.setTableStyle { set(&$0, v) } }))
            .toggleStyle(.checkbox).font(.system(size: 11.5))
    }
}

private struct TableStyleSwatch: View {
    let color: RGBColor
    let intensity: Int
    var body: some View {
        let base = Color(nsColor: color.nsColor)
        VStack(spacing: 1) {
            Rectangle().fill(intensity == 1 ? Color.clear : base).frame(height: 4)
                .overlay(alignment: .bottom) { if intensity == 1 { Rectangle().fill(base).frame(height: 1) } }
            Rectangle().fill(Color(nsColor: color.shaded(intensity == 2 ? -0.15 : 0.75).nsColor)).frame(height: 4)
            Rectangle().fill(Color(nsColor: (intensity == 2 ? color : color.shaded(0.88)).nsColor)).frame(height: 4)
        }
        .border(Color.primary.opacity(0.15), width: 0.5)
    }
}

struct TableLayoutTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let _ = controller.textSelectionRevision
        let paragraph = controller.currentParagraphStyle
        HStack(spacing: 0) {
            CaptionedGroup(title: "Rows & Columns") {
                RibbonLargeButton(title: "Delete", symbol: "trash", help: "Delete rows, columns or the table", menu: {
                    let menu = NSMenu()
                    menu.add("Delete Columns") { controller.deleteTableColumns() }
                    menu.add("Delete Rows") { controller.deleteTableRows() }
                    menu.add("Delete Table") { controller.deleteSelection() }
                    return menu
                })
                RibbonColumn {
                    RibbonCompactButton(title: "Insert Above", symbol: "arrow.up.to.line") { controller.insertTableRow(below: false) }
                    RibbonCompactButton(title: "Insert Below", symbol: "arrow.down.to.line") { controller.insertTableRow(below: true) }
                }
                RibbonColumn {
                    RibbonCompactButton(title: "Insert Left", symbol: "arrow.left.to.line") { controller.insertTableColumn(right: false) }
                    RibbonCompactButton(title: "Insert Right", symbol: "arrow.right.to.line") { controller.insertTableColumn(right: true) }
                }
            }
            CaptionedGroup(title: "Merge") {
                RibbonLargeButton(title: "Merge Cells", symbol: "rectangle.compress.vertical", help: "Merge the selected cells",
                                  isEnabled: controller.cellSelection.map { !$0.isSingle } ?? false) { controller.mergeCells() }
                RibbonLargeButton(title: "Split Cells", symbol: "rectangle.split.2x1", help: "Unmerge the selected cells") { controller.splitCells() }
            }
            CaptionedGroup(title: "Cell Size") {
                RibbonColumn {
                    RibbonCompactButton(title: "Distribute Rows", symbol: "distribute.vertical.fill") { controller.distributeTable(rows: true) }
                    RibbonCompactButton(title: "Distribute Columns", symbol: "distribute.horizontal.fill") { controller.distributeTable(rows: false) }
                }
            }
            CaptionedGroup(title: "Alignment") {
                VStack(spacing: 4) {
                    HStack(spacing: 1) {
                        RibbonIconButton(symbol: "text.alignleft", help: "Align Left", isOn: paragraph.alignment == .left) { controller.setAlignment(.left) }
                        RibbonIconButton(symbol: "text.aligncenter", help: "Center", isOn: paragraph.alignment == .center) { controller.setAlignment(.center) }
                        RibbonIconButton(symbol: "text.alignright", help: "Align Right", isOn: paragraph.alignment == .right) { controller.setAlignment(.right) }
                    }
                    HStack(spacing: 1) {
                        RibbonIconButton(symbol: "align.vertical.top", help: "Align Top", isOn: controller.currentTextBody?.anchor == .top) { controller.setVerticalAnchor(.top) }
                        RibbonIconButton(symbol: "align.vertical.center", help: "Center Vertically", isOn: controller.currentTextBody?.anchor == .middle) { controller.setVerticalAnchor(.middle) }
                        RibbonIconButton(symbol: "align.vertical.bottom", help: "Align Bottom", isOn: controller.currentTextBody?.anchor == .bottom) { controller.setVerticalAnchor(.bottom) }
                    }
                }
            }
            ArrangeGroup(controller: controller)
            SizeGroup(controller: controller)
        }
    }
}

struct ChartDesignTab: View {
    @ObservedObject var controller: PresentationController

    private var chart: ChartContent? {
        if case .chart(let c) = controller.primaryElement?.content { return c }
        return nil
    }

    var body: some View {
        let c = chart
        HStack(spacing: 0) {
            CaptionedGroup(title: "Type") {
                RibbonGallery(items: ChartKind.allCases, height: 58) { kind in
                    GalleryTile(isSelected: c?.kind == kind, help: kind.title) { controller.setSelectedChart { $0.kind = kind } } label: {
                        VStack(spacing: 2) {
                            Image(systemName: kind.symbol).font(.system(size: 17))
                            Text(kind.title).font(.system(size: 9)).lineLimit(1)
                        }
                        .frame(width: 64, height: 44)
                    }
                }
            }
            CaptionedGroup(title: "Data") {
                RibbonLargeButton(title: "Edit Data", symbol: "tablecells", help: "Edit the chart's numbers") {
                    if let id = controller.primaryElement?.id { controller.presenter?.presentChartEditor(id) }
                }
                RibbonLargeButton(title: "Switch Row/Column", symbol: "arrow.left.arrow.right.square", help: "Swap series and categories") {
                    controller.setSelectedChart { chart in
                        let categories = chart.series.map(\.name)
                        let series = chart.categories.indices.map { i in
                            ChartSeries(name: chart.categories[i], values: chart.series.map { i < $0.values.count ? $0.values[i] : 0 })
                        }
                        chart.categories = categories
                        chart.series = series
                    }
                }
            }
            CaptionedGroup(title: "Chart Elements", showsDivider: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Chart Title", isOn: Binding(get: { c?.title != nil }, set: { v in controller.setSelectedChart { $0.title = v ? "Chart Title" : nil } }))
                    Toggle("Data Labels", isOn: Binding(get: { c?.showDataLabels ?? false }, set: { v in controller.setSelectedChart { $0.showDataLabels = v } }))
                    Toggle("Gridlines", isOn: Binding(get: { c?.showGridlines ?? false }, set: { v in controller.setSelectedChart { $0.showGridlines = v } }))
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Legend:", selection: Binding(get: { c?.legend ?? .bottom }, set: { v in controller.setSelectedChart { $0.legend = v } })) {
                        ForEach(LegendPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .controlSize(.small).frame(width: 150)
                    NumberField(label: "Font size:", value: c?.fontSize ?? 12, range: 6...48, step: 1, unit: " pt", width: 50) { v in
                        controller.setSelectedChart { $0.fontSize = v }
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}

struct PlaybackTab: View {
    @ObservedObject var controller: PresentationController

    private var media: MediaContent? {
        if case .media(let m) = controller.primaryElement?.content { return m }
        return nil
    }

    var body: some View {
        let m = media
        HStack(spacing: 0) {
            CaptionedGroup(title: "Preview") {
                RibbonLargeButton(title: "Play", symbol: "play.fill", help: "Play the media") { MediaPreview.play(controller) }
            }
            CaptionedGroup(title: "Options", showsDivider: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Start Automatically", isOn: Binding(get: { m?.autoplay ?? false }, set: { v in controller.setMedia { $0.autoplay = v } }))
                    Toggle("Loop until Stopped", isOn: Binding(get: { m?.loop ?? false }, set: { v in controller.setMedia { $0.loop = v } }))
                    Toggle("Hide While Not Playing", isOn: Binding(get: { m?.hideWhenNotPlaying ?? false }, set: { v in controller.setMedia { $0.hideWhenNotPlaying = v } }))
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                VStack(alignment: .leading) {
                    Text("Volume").font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { m?.volume ?? 1 }, set: { v in controller.setMedia { $0.volume = v } }), in: 0...1).frame(width: 120).controlSize(.small)
                }
                .padding(.leading, 8)
            }
        }
    }
}

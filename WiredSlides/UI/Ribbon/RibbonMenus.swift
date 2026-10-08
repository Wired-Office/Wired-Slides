import AppKit
import SwiftUI

/// Small pictures of shapes and layouts for menus and galleries.
enum ShapeIcons {
    private static var cache: [String: NSImage] = [:]

    static func image(_ kind: ShapeKind, size: CGFloat = 18) -> NSImage {
        let key = "\(kind.rawValue)|\(size)"
        if let image = cache[key] { return image }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let r = rect.insetBy(dx: 1.5, dy: 1.5)
            let geo = ShapeGeometry.make(kind, in: r, adjustments: kind.isCallout ? [0.25, 1.25] : kind.defaultAdjustments)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(geo.path)
            ctx.drawPath(using: .eoFillStroke)
            for accent in geo.accents { ctx.addPath(accent.path); ctx.strokePath() }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    static func line(_ kind: ConnectorKind, arrow: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let a = CGPoint(x: 2, y: rect.height - 3), b = CGPoint(x: rect.width - 2, y: 3)
            let p = CGMutablePath()
            p.move(to: a)
            switch kind {
            case .straight: p.addLine(to: b)
            case .elbow: p.addLine(to: CGPoint(x: rect.midX, y: a.y)); p.addLine(to: CGPoint(x: rect.midX, y: b.y)); p.addLine(to: b)
            case .curved: p.addCurve(to: b, control1: CGPoint(x: rect.midX, y: a.y), control2: CGPoint(x: rect.midX, y: b.y))
            }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.2)
            ctx.addPath(p)
            ctx.strokePath()
            if arrow { Paint.arrowhead(.triangle, tip: b, from: kind == .straight ? a : CGPoint(x: rect.midX, y: b.y), width: 1, color: NSColor.black.cgColor, in: ctx) }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A miniature of a layout's placeholders.
    static func layout(_ layout: LayoutKind, theme: PresentationTheme, width: CGFloat = 96) -> NSImage {
        let slide = LayoutBuilder.makeSlide(layout, theme: theme, size: CGSize(width: 960, height: 540))
        var presentation = Presentation(theme: theme, slides: [slide])
        presentation.slideSize = CGSize(width: 960, height: 540)
        var options = SlideDrawOptions()
        options.element.editorChrome = true
        options.drawFooters = false
        return SlideRenderer.image(slide, number: 1, presentation: presentation, pixelWidth: width * 2, options: options)
    }
}

/// Menus shared by several ribbon tabs and the menu bar.
enum RibbonMenus {
    static func shapes(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        menu.addSection("Lines")
        for (kind, arrow, title) in [(ConnectorKind.straight, false, "Line"), (.straight, true, "Arrow"), (.elbow, true, "Elbow Connector"), (.curved, true, "Curved Connector")] {
            let item = menu.add(title) { controller.pendingInsert = .line(kind, arrow: arrow) }
            item.image = ShapeIcons.line(kind, arrow: arrow)
        }
        for category in ShapeKind.Category.allCases {
            let sub = NSMenu(title: category.rawValue)
            for kind in ShapeKind.kinds(in: category) {
                let item = sub.add(kind.title) { controller.pendingInsert = .shape(kind) }
                item.image = ShapeIcons.image(kind)
            }
            menu.addSubmenu(sub)
        }
        menu.addItem(.separator())
        menu.add("Text Box", symbol: "character.textbox") { controller.pendingInsert = .textBox }
        menu.add("Vertical Text Box", symbol: "text.aligncenter") { controller.pendingInsert = .verticalTextBox }
        return menu
    }

    static func changeShape(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        for category in ShapeKind.Category.allCases {
            let sub = NSMenu(title: category.rawValue)
            for kind in ShapeKind.kinds(in: category) {
                let item = sub.add(kind.title) { controller.changeShapeKind(kind) }
                item.image = ShapeIcons.image(kind)
            }
            menu.addSubmenu(sub)
        }
        return menu
    }

    static func arrange(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        menu.addSection("Order Objects")
        menu.add("Bring to Front", symbol: "square.3.layers.3d.top.filled") { controller.arrange(.front) }
        menu.add("Send to Back", symbol: "square.3.layers.3d.bottom.filled") { controller.arrange(.back) }
        menu.add("Bring Forward", symbol: "square.2.layers.3d.top.filled") { controller.arrange(.forward) }
        menu.add("Send Backward", symbol: "square.2.layers.3d.bottom.filled") { controller.arrange(.backward) }
        menu.addSection("Group Objects")
        menu.add("Group", symbol: "square.on.square.dashed", enabled: controller.selection.count > 1) { controller.group() }
        menu.add("Ungroup", symbol: "square.on.square", enabled: controller.selectedElements.contains(where: \.isGroup)) { controller.ungroup() }
        menu.addSection("Position Objects")
        menu.addSubmenu(align(controller), title: "Align")
        menu.addSubmenu(rotate(controller), title: "Rotate")
        menu.addItem(.separator())
        menu.add("Selection Pane…", symbol: "list.bullet.rectangle") { controller.sidePane = .selection }
        return menu
    }

    static func align(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu(title: "Align")
        for mode in AlignMode.allCases { menu.add(mode.title, symbol: mode.symbol) { controller.align(mode) } }
        menu.addItem(.separator())
        menu.add("Distribute Horizontally", symbol: "distribute.horizontal.center") { controller.distribute(horizontally: true) }
        menu.add("Distribute Vertically", symbol: "distribute.vertical.center") { controller.distribute(horizontally: false) }
        menu.addItem(.separator())
        menu.add("Align to Slide", symbol: "rectangle.center.inset.filled") {
            for mode in [AlignMode.center, .middle] { controller.align(mode, toSlide: true) }
        }
        return menu
    }

    static func rotate(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu(title: "Rotate")
        menu.add("Rotate Right 90°", symbol: "rotate.right") { controller.rotate(by: 90) }
        menu.add("Rotate Left 90°", symbol: "rotate.left") { controller.rotate(by: -90) }
        menu.add("Flip Vertical", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down") { controller.flip(horizontal: false) }
        menu.add("Flip Horizontal", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") { controller.flip(horizontal: true) }
        menu.add("Reset Rotation", symbol: "arrow.counterclockwise") { controller.setRotation(0) }
        return menu
    }

    static func effects(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        let shadow = NSMenu(title: "Shadow")
        shadow.add("No Shadow") { controller.setEffects { $0.shadow = nil } }
        shadow.add("Offset: Bottom Right") { controller.setEffects { $0.shadow = ShadowEffect(opacity: 0.4, blur: 4, distance: 4, angle: 45) } }
        shadow.add("Offset: Bottom") { controller.setEffects { $0.shadow = ShadowEffect(opacity: 0.4, blur: 4, distance: 4, angle: 90) } }
        shadow.add("Offset: Center") { controller.setEffects { $0.shadow = ShadowEffect(opacity: 0.4, blur: 8, distance: 0, angle: 90) } }
        shadow.add("Soft") { controller.setEffects { $0.shadow = .soft } }
        shadow.add("Perspective") { controller.setEffects { $0.shadow = ShadowEffect(opacity: 0.3, blur: 14, distance: 14, angle: 60) } }
        menu.addSubmenu(shadow)
        let glow = NSMenu(title: "Glow")
        glow.add("No Glow") { controller.setEffects { $0.glow = nil } }
        for slot in [ThemeSlot.accent1, .accent2, .accent3, .accent4, .accent5, .accent6] {
            for radius in [5.0, 10, 18] {
                let item = glow.add("\(slot.title), \(Int(radius)) pt") { controller.setEffects { $0.glow = GlowEffect(color: .theme(slot, shade: 0, alpha: 0.6), radius: radius) } }
                item.image = swatch(controller.theme.colors[slot])
            }
        }
        menu.addSubmenu(glow)
        let reflection = NSMenu(title: "Reflection")
        reflection.add("No Reflection") { controller.setEffects { $0.reflection = nil } }
        reflection.add("Tight Reflection") { controller.setEffects { $0.reflection = ReflectionEffect(opacity: 0.5, size: 0.33, distance: 1) } }
        reflection.add("Half Reflection") { controller.setEffects { $0.reflection = ReflectionEffect(opacity: 0.45, size: 0.5, distance: 2) } }
        reflection.add("Full Reflection") { controller.setEffects { $0.reflection = ReflectionEffect(opacity: 0.4, size: 1, distance: 4) } }
        menu.addSubmenu(reflection)
        menu.addItem(.separator())
        menu.add("Remove All Effects", symbol: "xmark") { controller.setEffects { $0 = .none } }
        menu.add("Effect Options…", symbol: "slider.horizontal.3") { controller.sidePane = .format }
        return menu
    }

    static func swatch(_ color: RGBColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            color.nsColor.setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).stroke()
            return true
        }
    }

    static func layouts(_ controller: PresentationController, action: @escaping (LayoutKind) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addSection(controller.theme.name)
        for layout in LayoutKind.allCases {
            let item = menu.add(layout.title, checked: controller.currentSlide.layout == layout) { action(layout) }
            item.image = ShapeIcons.layout(layout, theme: controller.theme, width: 64)
        }
        return menu
    }

    static func newSlide(_ controller: PresentationController) -> NSMenu {
        let menu = layouts(controller) { controller.addSlide(layout: $0) }
        menu.addItem(.separator())
        menu.add("Duplicate Selected Slides", symbol: "plus.rectangle.on.rectangle") { controller.duplicateSlides() }
        menu.add("Slides from Outline…", symbol: "list.bullet.indent") { SlidesFromOutline.run(controller) }
        menu.add("Reuse Slides…", symbol: "arrow.triangle.2.circlepath") { ReuseSlides.run(controller) }
        return menu
    }

    static func lineWeights(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu(title: "Weight")
        for w in [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6] {
            menu.add("\(w.formatted()) pt", checked: controller.primaryLineStyle?.width == w) { controller.setLine { $0.width = w; if $0.color == nil { $0.color = .theme(.accent1) } } }
        }
        return menu
    }

    static func dashes(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu(title: "Dashes")
        for dash in DashStyle.allCases {
            menu.add(dash.title, checked: controller.primaryLineStyle?.dash == dash) { controller.setLine { $0.dash = dash } }
        }
        return menu
    }

    static func arrows(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu(title: "Arrows")
        for head in ArrowHead.allCases {
            menu.add("Start: \(head.title)", checked: controller.primaryLineStyle?.head == head) { controller.setLine { $0.head = head } }
        }
        menu.addItem(.separator())
        for tail in ArrowHead.allCases {
            menu.add("End: \(tail.title)", checked: controller.primaryLineStyle?.tail == tail) { controller.setLine { $0.tail = tail } }
        }
        return menu
    }

    static func outline(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        menu.addSubmenu(lineWeights(controller))
        menu.addSubmenu(dashes(controller))
        menu.addSubmenu(arrows(controller))
        return menu
    }

    static func wordArt(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        for preset in WordArtPreset.all {
            let item = menu.add("") { controller.insertWordArt(preset) }
            item.attributedTitle = WordArtPreview.attributed(preset, theme: controller.theme)
        }
        return menu
    }
}

enum WordArtPreview {
    static func attributed(_ preset: WordArtPreset, theme: PresentationTheme) -> NSAttributedString {
        var run = RunStyle()
        preset.apply(&run)
        run.size = 22
        var body = TextBody()
        body.fontRole = .heading
        body.paragraphs = [Paragraph(runs: [TextRun(text: "Aa WordArt", style: run)])]
        return TextLayout.attributedString(body, TextLayout.Context(theme: theme))
    }
}

extension PresentationController {
    var primaryLineStyle: LineStyle? {
        switch primaryElement?.content {
        case .shape(let s): s.line
        case .line(let l): l.line
        case .image(let i): i.line
        default: nil
        }
    }

    var primaryFill: Fill? {
        switch primaryElement?.content {
        case .shape(let s): s.fill
        case .chart(let c): c.background
        default: nil
        }
    }

    var primaryEffects: Effects? {
        switch primaryElement?.content {
        case .shape(let s): s.effects
        case .line(let l): l.effects
        case .image(let i): i.effects
        default: nil
        }
    }
}

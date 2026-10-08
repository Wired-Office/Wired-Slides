import AppKit
import SwiftUI

struct InsertTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        HStack(spacing: 0) {
            CaptionedGroup(title: "Slides") {
                RibbonLargeButton(title: "New Slide", symbol: "plus.rectangle", help: "New Slide (⇧⌘N)", menu: { RibbonMenus.newSlide(controller) }) {
                    controller.addSlide()
                }
            }
            CaptionedGroup(title: "Tables") {
                RibbonLargeButton(title: "Table", symbol: "tablecells", help: "Insert a table", menu: {
                    let menu = NSMenu()
                    for (r, c) in [(2, 2), (3, 3), (4, 3), (4, 4), (5, 4), (6, 5), (8, 6)] {
                        menu.add("\(c) × \(r) Table", symbol: "tablecells") { controller.insertTable(rows: r, columns: c) }
                    }
                    menu.addItem(.separator())
                    menu.add("Insert Table…", symbol: "tablecells.badge.ellipsis") { controller.presenter?.presentInsertTable() }
                    return menu
                })
            }
            CaptionedGroup(title: "Images") {
                RibbonLargeButton(title: "Pictures", symbol: "photo.on.rectangle", help: "Insert pictures from a file") {
                    controller.presenter?.insertPicturesFromFile()
                }
                RibbonLargeButton(title: "Photo Album", symbol: "photo.stack", help: "Create one slide per picture") {
                    PhotoAlbum.run(controller)
                }
            }
            CaptionedGroup(title: "Illustrations") {
                RibbonLargeButton(title: "Shapes", symbol: "square.on.circle", help: "Draw a shape", menu: { RibbonMenus.shapes(controller) })
                RibbonLargeButton(title: "Icons", symbol: "star.square.on.square", help: "Insert an icon") { controller.presenter?.presentInsertIcon() }
                RibbonLargeButton(title: "SmartArt", symbol: "square.grid.3x1.below.line.grid.1x2", help: "Insert a SmartArt graphic") {
                    controller.presenter?.presentSmartArt()
                }
                RibbonLargeButton(title: "Chart", symbol: "chart.bar", help: "Insert a chart", menu: {
                    let menu = NSMenu()
                    for kind in ChartKind.allCases { menu.add(kind.title, symbol: kind.symbol) { controller.insertChart(kind) } }
                    return menu
                })
            }
            CaptionedGroup(title: "Links") {
                RibbonLargeButton(title: "Link", symbol: "link", help: "Insert a hyperlink (⌘K)") { controller.presenter?.presentHyperlink() }
                RibbonLargeButton(title: "Action", symbol: "cursorarrow.click.2", help: "What happens when the object is clicked in a slide show",
                                  isEnabled: !controller.selection.isEmpty) { controller.presenter?.presentAction() }
            }
            CaptionedGroup(title: "Comments") {
                RibbonLargeButton(title: "Comment", symbol: "text.bubble", help: "New Comment") {
                    controller.sidePane = .comments
                    NotificationCenter.default.post(name: .wsNewComment, object: nil)
                }
            }
            CaptionedGroup(title: "Text") {
                RibbonLargeButton(title: "Text Box", symbol: "character.textbox", help: "Draw a text box", menu: {
                    let menu = NSMenu()
                    menu.add("Draw Horizontal Text Box", symbol: "character.textbox") { controller.pendingInsert = .textBox }
                    menu.add("Draw Vertical Text Box", symbol: "text.aligncenter") { controller.pendingInsert = .verticalTextBox }
                    menu.add("Insert Text Box", symbol: "plus") { controller.insertTextBox() }
                    return menu
                }) { controller.pendingInsert = .textBox }
                RibbonLargeButton(title: "Header & Footer", symbol: "rectangle.topthird.inset.filled", help: "Date, slide number and footer") {
                    controller.presenter?.presentHeaderFooter()
                }
                RibbonLargeButton(title: "WordArt", symbol: "a.square", help: "Insert decorative text", menu: { RibbonMenus.wordArt(controller) })
                RibbonColumn {
                    RibbonMenuButton(symbol: "calendar", help: "Date & Time", label: "Date & Time") {
                        let menu = NSMenu()
                        let now = Date()
                        for (date, time) in [(DateFormatter.Style.short, DateFormatter.Style.none), (.medium, .none), (.long, .none), (.full, .none), (.short, .short), (.none, .short)] {
                            let text = DateFormatter.localizedString(from: now, dateStyle: date, timeStyle: time)
                            menu.add(text) { controller.insertDateTime(text) }
                        }
                        return menu
                    }
                    RibbonCompactButton(title: "Slide Number", symbol: "number", help: "Show slide numbers",
                                        isOn: controller.presentation.headerFooter.showSlideNumber) {
                        var hf = controller.presentation.headerFooter
                        hf.showSlideNumber.toggle()
                        controller.setHeaderFooter(hf)
                    }
                }
            }
            CaptionedGroup(title: "Symbols") {
                RibbonLargeButton(title: "Symbol", symbol: "command.square", help: "Insert a symbol or emoji", menu: {
                    let menu = NSMenu()
                    for s in ["©", "®", "™", "°", "±", "×", "÷", "≈", "≠", "≤", "≥", "∞", "π", "Σ", "√", "€", "£", "¥", "→", "←", "↑", "↓", "✓", "✗", "★", "•", "…", "—"] {
                        menu.add(s) { controller.insertSymbol(s) }
                    }
                    menu.addItem(.separator())
                    menu.add("Emoji & Symbols…", symbol: "face.smiling") { NSApp.orderFrontCharacterPalette(nil) }
                    return menu
                })
                RibbonLargeButton(title: "Equation", symbol: "x.squareroot", help: "Insert an equation as text", menu: {
                    let menu = NSMenu()
                    for eq in ["E = mc²", "a² + b² = c²", "x = (−b ± √(b² − 4ac)) / 2a", "A = πr²", "∑ᵢ xᵢ", "∫₀¹ f(x) dx", "e^(iπ) + 1 = 0"] {
                        menu.add(eq) {
                            controller.insertTextBox(text: eq)
                            controller.commitTextEditing()
                        }
                    }
                    return menu
                })
            }
            CaptionedGroup(title: "Media", showsDivider: false) {
                RibbonLargeButton(title: "Video", symbol: "film", help: "Insert a video from a file") { controller.presenter?.insertMediaFromFile() }
                RibbonLargeButton(title: "Audio", symbol: "speaker.wave.2", help: "Insert audio from a file") { controller.presenter?.insertMediaFromFile() }
            }
        }
    }
}

struct DesignTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        HStack(spacing: 0) {
            CaptionedGroup(title: "Themes") {
                RibbonGallery(items: ThemeLibrary.all) { theme in
                    GalleryTile(isSelected: controller.theme.id == theme.id, help: theme.name) {
                        controller.applyTheme(theme)
                    } label: {
                        Image(nsImage: ThemePreviews.image(theme, width: 80))
                            .resizable()
                            .frame(width: 80, height: 45)
                            .border(Color.primary.opacity(0.15), width: 0.5)
                    }
                }
            }
            CaptionedGroup(title: "Variants") {
                let theme = ThemeLibrary.all.first { $0.id == controller.theme.id } ?? controller.theme
                let variants = [theme.colors] + theme.variants
                HStack(spacing: 4) {
                    ForEach(variants.indices, id: \.self) { i in
                        GalleryTile(isSelected: controller.theme.colors == variants[i], help: "Variant \(i + 1)") {
                            controller.applyColors(variants[i])
                        } label: {
                            VariantSwatch(colors: variants[i]).frame(width: 52, height: 40)
                        }
                    }
                }
                RibbonColumn {
                    RibbonMenuButton(symbol: "paintpalette", help: "Theme Colors", label: "Colors") {
                        let menu = NSMenu()
                        for scheme in ColorSchemes.all {
                            let item = menu.add(scheme.name, checked: controller.theme.colors == scheme.colors) { controller.applyColors(scheme.colors) }
                            item.image = ThemePreviews.colorStrip(scheme.colors)
                        }
                        menu.addItem(.separator())
                        menu.add("Customize Colors…", symbol: "slider.horizontal.3") { controller.sidePane = .designer }
                        return menu
                    }
                    RibbonMenuButton(symbol: "textformat", help: "Theme Fonts", label: "Fonts") {
                        let menu = NSMenu()
                        for pair in FontPair.all {
                            let item = menu.add(pair.name, checked: controller.theme.headingFont == pair.heading && controller.theme.bodyFont == pair.body) {
                                controller.applyFonts(pair)
                            }
                            let title = NSMutableAttributedString(string: pair.heading, attributes: [.font: FontResolver.font(family: pair.heading, size: 14, bold: false, italic: false)])
                            title.append(NSAttributedString(string: "  /  " + pair.body, attributes: [.font: FontResolver.font(family: pair.body, size: 11, bold: false, italic: false), .foregroundColor: NSColor.secondaryLabelColor]))
                            item.attributedTitle = title
                        }
                        menu.addItem(.separator())
                        menu.add("Replace Fonts…", symbol: "arrow.left.arrow.right") { ReplaceFonts.run(controller) }
                        return menu
                    }
                    RibbonMenuButton(symbol: "rectangle.fill", help: "Background Styles", label: "Background") {
                        let menu = NSMenu()
                        let fills: [(String, Fill)] = [
                            ("Light 1", .solid(.theme(.light1))), ("Light 2", .solid(.theme(.light2))),
                            ("Dark 1", .solid(.theme(.dark1))), ("Dark 2", .solid(.theme(.dark2))),
                            ("Light Gradient", .gradient(.twoTone(.theme(.light1), .theme(.light2)))),
                            ("Accent Gradient", .gradient(.twoTone(.theme(.accent1, shade: 0.6, alpha: 1), .theme(.accent1, shade: -0.1, alpha: 1), angle: 45))),
                            ("Dark Gradient", .gradient(.twoTone(.theme(.dark2), .theme(.dark1)))),
                        ]
                        for (name, fill) in fills {
                            let item = menu.add(name) { controller.setBackground(fill, applyToAll: true) }
                            item.image = ThemePreviews.fillSwatch(fill, colors: controller.theme.colors)
                        }
                        menu.addItem(.separator())
                        menu.add("Reset Slide Background", symbol: "arrow.counterclockwise") { controller.setBackground(nil, applyToAll: false) }
                        menu.add("Format Background…", symbol: "paintbrush") {
                            controller.sidePane = .format
                            NotificationCenter.default.post(name: .wsShowBackgroundFormat, object: nil)
                        }
                        return menu
                    }
                }
            }
            CaptionedGroup(title: "Customize", showsDivider: false) {
                RibbonLargeButton(title: "Slide Size", symbol: "aspectratio", help: "Slide size and orientation", menu: {
                    let menu = NSMenu()
                    menu.add("Standard (4:3)", checked: abs(controller.slideSize.width / controller.slideSize.height - 4.0 / 3) < 0.01) {
                        controller.setSlideSize(CGSize(width: 720, height: 540), scaleContent: true)
                    }
                    menu.add("Widescreen (16:9)", checked: abs(controller.slideSize.width / controller.slideSize.height - 16.0 / 9) < 0.01) {
                        controller.setSlideSize(CGSize(width: 960, height: 540), scaleContent: true)
                    }
                    menu.addItem(.separator())
                    menu.add("Custom Slide Size…", symbol: "slider.horizontal.3") { controller.presenter?.presentSlideSize() }
                    return menu
                })
                RibbonLargeButton(title: "Format Background", symbol: "paintbrush", help: "Fill, gradient, picture or pattern background") {
                    controller.sidePane = .format
                    NotificationCenter.default.post(name: .wsShowBackgroundFormat, object: nil)
                }
                RibbonLargeButton(title: "Design Ideas", symbol: "lightbulb", help: "Theme colors, fonts and layout suggestions",
                                  isOn: controller.sidePane == .designer) {
                    controller.sidePane = controller.sidePane == .designer ? nil : .designer
                }
            }
        }
    }
}

struct VariantSwatch: View {
    let colors: ThemeColors
    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: colors.light1.nsColor))
            HStack(spacing: 0) {
                ForEach(0..<4) { i in Rectangle().fill(Color(nsColor: colors.accents[i].nsColor)) }
            }
            .frame(height: 10)
        }
        .overlay(alignment: .topLeading) {
            Text("Aa").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(nsColor: colors.dark1.nsColor)).padding(4)
        }
        .border(Color.primary.opacity(0.15), width: 0.5)
    }
}

/// Theme thumbnails rendered from a real title slide.
enum ThemePreviews {
    private static var cache: [String: NSImage] = [:]

    static func image(_ theme: PresentationTheme, width: CGFloat, layout: LayoutKind = .title, title: String? = nil) -> NSImage {
        let key = "\(theme.id)|\(theme.colors.hashValue)|\(width)|\(layout.rawValue)|\(title ?? "")"
        if let image = cache[key] { return image }
        var slide = LayoutBuilder.makeSlide(layout, theme: theme, size: CGSize(width: 960, height: 540))
        for i in slide.elements.indices {
            if slide.elements[i].placeholder?.isTitle == true { slide.elements[i].text?.setPlainText(title ?? theme.name) }
            if slide.elements[i].placeholder == .subtitle { slide.elements[i].text?.setPlainText("Presentation subtitle") }
            if slide.elements[i].placeholder == .body {
                slide.elements[i].text?.setPlainText("First point\nSecond point\nThird point")
            }
        }
        let presentation = Presentation(theme: theme, slides: [slide])
        let image = SlideRenderer.image(slide, number: 1, presentation: presentation, pixelWidth: width * 2)
        cache[key] = image
        return image
    }

    static func colorStrip(_ colors: ThemeColors) -> NSImage {
        NSImage(size: NSSize(width: 96, height: 14), flipped: false) { r in
            let all = [colors.dark1, colors.light1, colors.dark2, colors.light2] + colors.accents
            let w = r.width / CGFloat(all.count)
            for (i, c) in all.enumerated() {
                c.nsColor.setFill()
                CGRect(x: CGFloat(i) * w, y: 0, width: w, height: r.height).fill()
            }
            NSColor.black.withAlphaComponent(0.2).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    static func fillSwatch(_ fill: Fill, colors: ThemeColors) -> NSImage {
        NSImage(size: NSSize(width: 40, height: 22), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let env = RenderEnvironment(theme: PresentationTheme(id: "s", name: "s", colors: colors, headingFont: "", bodyFont: ""), media: [:], slideSize: r.size)
            Paint.fill(CGPath(rect: r, transform: nil), with: fill, bounds: r, in: ctx, env: env)
            NSColor.black.withAlphaComponent(0.2).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}

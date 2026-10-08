import AppKit
import SwiftUI

struct HomeTab: View {
    @ObservedObject var controller: PresentationController

    var body: some View {
        let _ = controller.textSelectionRevision
        let run = controller.currentRunStyle
        let paragraph = controller.currentParagraphStyle
        let colors = controller.theme.colors
        HStack(spacing: 0) {
            CaptionedGroup(title: "Clipboard") {
                RibbonLargeButton(title: "Paste", symbol: "doc.on.clipboard", help: "Paste (⌘V)", isEnabled: controller.canPaste, menu: {
                    let menu = NSMenu()
                    menu.add("Paste", symbol: "doc.on.clipboard") { controller.paste() }
                    menu.add("Paste as Picture", symbol: "photo") { controller.pasteAsPicture() }
                    menu.add("Keep Text Only", symbol: "textformat") { controller.pasteAsText() }
                    return menu
                }) { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                RibbonColumn {
                    RibbonCompactButton(title: "Cut", symbol: "scissors", help: "Cut (⌘X)") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    RibbonCompactButton(title: "Copy", symbol: "doc.on.doc", help: "Copy (⌘C)") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    RibbonCompactButton(title: "Format", symbol: "paintbrush", help: "Format Painter: copy formatting from the selection (⇧⌘C)",
                                        isOn: controller.formatPainter != nil) {
                        if controller.formatPainter != nil { controller.formatPainter = nil } else { controller.copyFormat() }
                    }
                }
            }
            CaptionedGroup(title: "Slides") {
                RibbonLargeButton(title: "New Slide", symbol: "plus.rectangle", help: "New Slide (⇧⌘N)", menu: { RibbonMenus.newSlide(controller) }) {
                    controller.addSlide()
                }
                RibbonColumn {
                    RibbonMenuButton(symbol: "rectangle.3.group", help: "Layout", label: "Layout") {
                        RibbonMenus.layouts(controller) { controller.setLayout($0) }
                    }
                    RibbonCompactButton(title: "Reset", symbol: "arrow.counterclockwise", help: "Reset placeholders to their layout positions and formatting") {
                        controller.resetSlides()
                    }
                    RibbonMenuButton(symbol: "rectangle.split.1x2", help: "Section", label: "Section") {
                        let menu = NSMenu()
                        menu.add("Add Section", symbol: "plus") { NotificationCenter.default.post(name: .wsAddSection, object: nil) }
                        menu.add("Remove All Sections", symbol: "xmark.circle", enabled: !controller.presentation.sections.isEmpty) { controller.removeAllSections() }
                        return menu
                    }
                }
            }
            CaptionedGroup(title: "Font") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        FontFamilyPicker(family: controller.currentFontFamily) { controller.setFontFamily($0) }
                            .frame(width: 150)
                        FontSizeField(size: CGFloat(controller.currentFontSize)) { controller.setFontSize(Double($0)) }
                            .frame(width: 58)
                        RibbonIconButton(symbol: "textformat.size.larger", help: "Increase Font Size (⇧⌘>)") { controller.growFont(true) }
                        RibbonIconButton(symbol: "textformat.size.smaller", help: "Decrease Font Size (⇧⌘<)") { controller.growFont(false) }
                        RibbonIconButton(symbol: "eraser", help: "Clear All Formatting") { controller.clearFormatting() }
                    }
                    HStack(spacing: 1) {
                        RibbonIconButton(symbol: "bold", help: "Bold (⌘B)", isOn: run.bold == true) { controller.toggleBold() }
                        RibbonIconButton(symbol: "italic", help: "Italic (⌘I)", isOn: run.italic == true) { controller.toggleItalic() }
                        RibbonIconButton(symbol: "underline", help: "Underline (⌘U)", isOn: run.underline) { controller.toggleUnderline() }
                        RibbonIconButton(symbol: "strikethrough", help: "Strikethrough", isOn: run.strikethrough) { controller.toggleStrikethrough() }
                        RibbonIconButton(symbol: "shadow", help: "Text Shadow", isOn: run.shadow) { controller.toggleShadow() }
                        RibbonMenuButton(symbol: "character", help: "Character Spacing") {
                            let menu = NSMenu()
                            for (title, value) in [("Very Tight", -3.0), ("Tight", -1.5), ("Normal", 0), ("Loose", 3), ("Very Loose", 6)] {
                                menu.add(title, checked: run.characterSpacing == value) { controller.setCharacterSpacing(value) }
                            }
                            return menu
                        }
                        RibbonMenuButton(symbol: "textformat", help: "Change Case") {
                            let menu = NSMenu()
                            for mode in TextCase.allCases { menu.add(mode.title) { controller.changeCase(mode) } }
                            menu.addItem(.separator())
                            menu.add("Superscript", checked: run.baseline > 0) { controller.setBaseline(1) }
                            menu.add("Subscript", checked: run.baseline < 0) { controller.setBaseline(-1) }
                            menu.add("Small Caps", checked: run.smallCaps) { let on = !run.smallCaps; controller.applyRunStyle("Small Caps") { $0.smallCaps = on } }
                            menu.add("All Caps", checked: run.allCaps) { let on = !run.allCaps; controller.applyRunStyle("All Caps") { $0.allCaps = on } }
                            return menu
                        }
                        ColorSplitButton(symbol: "character", help: "Font Color", kind: .text, colors: colors,
                                         current: run.color ?? .rgb(RGBColor(hex: 0xD32F2F))) { controller.setTextColor($0) }
                        ColorSplitButton(symbol: "highlighter", help: "Text Highlight Color", kind: .fill, colors: colors,
                                         current: run.highlight.map { .rgb($0) } ?? .rgb(RGBColor(hex: 0xFFF176))) { controller.setHighlight($0?.resolve(colors)) }
                    }
                }
            }
            CaptionedGroup(title: "Paragraph") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 1) {
                        RibbonSplitButton(symbol: "list.bullet", help: "Bullets", isOn: { if case .symbol = paragraph.bullet { return true }; return false }(),
                                          action: { controller.toggleBullets() }) {
                            let menu = NSMenu()
                            menu.add("None") { controller.applyParagraphStyle("Bullets") { $0.bullet = .none } }
                            for symbol in Bullet.standardSymbols { menu.add("\(symbol)   Bullet") { controller.toggleBullets(symbol) } }
                            return menu
                        }
                        RibbonSplitButton(symbol: "list.number", help: "Numbering", isOn: { if case .numbered = paragraph.bullet { return true }; return false }(),
                                          action: { controller.toggleNumbering() }) {
                            let menu = NSMenu()
                            menu.add("None") { controller.applyParagraphStyle("Numbering") { $0.bullet = .none } }
                            for scheme in NumberingScheme.allCases { menu.add(scheme.title) { controller.toggleNumbering(scheme) } }
                            return menu
                        }
                        RibbonIconButton(symbol: "decrease.indent", help: "Decrease List Level (⇧Tab)") { controller.changeIndent(-1) }
                        RibbonIconButton(symbol: "increase.indent", help: "Increase List Level (Tab)") { controller.changeIndent(1) }
                        RibbonMenuButton(symbol: "arrow.up.and.down.text.horizontal", help: "Line Spacing") {
                            let menu = NSMenu()
                            for value in [0.8, 0.9, 1.0, 1.15, 1.5, 2.0, 2.5, 3.0] {
                                menu.add(value.formatted(), checked: abs(paragraph.lineSpacing - value) < 0.01) { controller.setLineSpacing(value) }
                            }
                            menu.addItem(.separator())
                            menu.add("Add 12 pt Before", checked: paragraph.spaceBefore >= 12) {
                                controller.setParagraphSpacing(before: paragraph.spaceBefore >= 12 ? 0 : 12, after: nil)
                            }
                            menu.add("Add 12 pt After", checked: paragraph.spaceAfter >= 12) {
                                controller.setParagraphSpacing(before: nil, after: paragraph.spaceAfter >= 12 ? 0 : 12)
                            }
                            return menu
                        }
                        RibbonMenuButton(symbol: "text.word.spacing", help: "Columns") {
                            let menu = NSMenu()
                            for n in 1...3 { menu.add(n == 1 ? "One Column" : "\(n) Columns", checked: controller.currentTextBody?.columns == n) { controller.setColumns(n) } }
                            return menu
                        }
                    }
                    HStack(spacing: 1) {
                        RibbonIconButton(symbol: "text.alignleft", help: "Align Left (⌘L)", isOn: paragraph.alignment == .left) { controller.setAlignment(.left) }
                        RibbonIconButton(symbol: "text.aligncenter", help: "Center (⌘E)", isOn: paragraph.alignment == .center) { controller.setAlignment(.center) }
                        RibbonIconButton(symbol: "text.alignright", help: "Align Right (⌘R)", isOn: paragraph.alignment == .right) { controller.setAlignment(.right) }
                        RibbonIconButton(symbol: "text.justify", help: "Justify (⌘J)", isOn: paragraph.alignment == .justify) { controller.setAlignment(.justify) }
                        RibbonMenuButton(symbol: "text.rotate.forward", help: "Text Direction") {
                            let menu = NSMenu()
                            menu.add("Horizontal", checked: controller.currentTextBody?.direction == .horizontal) { controller.setTextDirection(.horizontal) }
                            menu.add("Rotate all text 90°", checked: controller.currentTextBody?.direction == .rotated90) { controller.setTextDirection(.rotated90) }
                            menu.add("Rotate all text 270°", checked: controller.currentTextBody?.direction == .rotated270) { controller.setTextDirection(.rotated270) }
                            return menu
                        }
                        RibbonMenuButton(symbol: "align.vertical.center", help: "Align Text") {
                            let menu = NSMenu()
                            menu.add("Top", symbol: "align.vertical.top", checked: controller.currentTextBody?.anchor == .top) { controller.setVerticalAnchor(.top) }
                            menu.add("Middle", symbol: "align.vertical.center", checked: controller.currentTextBody?.anchor == .middle) { controller.setVerticalAnchor(.middle) }
                            menu.add("Bottom", symbol: "align.vertical.bottom", checked: controller.currentTextBody?.anchor == .bottom) { controller.setVerticalAnchor(.bottom) }
                            return menu
                        }
                        RibbonMenuButton(symbol: "square.grid.3x1.below.line.grid.1x2", help: "Convert to SmartArt") {
                            let menu = NSMenu()
                            for kind in SmartArtKind.allCases {
                                menu.add(kind.title, symbol: kind.symbol) { SmartArtConversion.convertSelection(controller, to: kind) }
                            }
                            return menu
                        }
                    }
                }
            }
            CaptionedGroup(title: "Drawing") {
                RibbonLargeButton(title: "Shapes", symbol: "square.on.circle", help: "Draw a shape", menu: { RibbonMenus.shapes(controller) })
                RibbonLargeButton(title: "Arrange", symbol: "square.3.layers.3d", help: "Order, group and position objects",
                                  isEnabled: !controller.selection.isEmpty, menu: { RibbonMenus.arrange(controller) })
                RibbonLargeButton(title: "Quick Styles", symbol: "swatchpalette", help: "Shape Styles", isEnabled: controller.primaryElement?.shape != nil,
                                  menu: { ShapeStyleMenu.menu(controller) })
                RibbonColumn {
                    ColorSplitButton(symbol: "paintbrush.pointed", help: "Shape Fill", kind: .fill, colors: colors,
                                     current: controller.primaryFill?.solidColor ?? .theme(.accent1)) { c in controller.setFill(c.map { .solid($0) } ?? .none) }
                    ColorSplitButton(symbol: "square.dashed", help: "Shape Outline", kind: .line, colors: colors,
                                     current: controller.primaryLineStyle?.color ?? .theme(.accent1)) { c in controller.setLine { $0.color = c } }
                    RibbonMenuButton(symbol: "sparkles", help: "Shape Effects") { RibbonMenus.effects(controller) }
                }
            }
            CaptionedGroup(title: "Editing", showsDivider: false) {
                RibbonColumn {
                    RibbonCompactButton(title: "Find", symbol: "magnifyingglass", help: "Find (⌘F)") { controller.presenter?.presentFindReplace(replace: false) }
                    RibbonCompactButton(title: "Replace", symbol: "arrow.left.arrow.right", help: "Replace (⇧⌘H)") { controller.presenter?.presentFindReplace(replace: true) }
                    RibbonMenuButton(symbol: "cursorarrow", help: "Select", label: "Select") {
                        let menu = NSMenu()
                        menu.add("Select All", symbol: "checkmark.rectangle") { controller.selectAllElements() }
                        menu.add("Selection Pane…", symbol: "list.bullet.rectangle") { controller.sidePane = .selection }
                        return menu
                    }
                }
            }
        }
    }
}

enum ShapeStyleMenu {
    static func menu(_ controller: PresentationController) -> NSMenu {
        let menu = NSMenu()
        let presets = ShapeStylePreset.presets()
        let titles = ["Colored Outline", "Colored Fill", "Light 1 Fill", "Intense Effect"]
        for (group, title) in titles.enumerated() {
            menu.addSection(title)
            for preset in presets[(group * 7)..<(group * 7 + 7)] {
                let item = menu.add("") { controller.applyShapeStyle(preset) }
                item.image = preview(preset, colors: controller.theme.colors)
                item.title = ""
            }
        }
        return menu
    }

    static func preview(_ preset: ShapeStylePreset, colors: ThemeColors) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 22), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let env = RenderEnvironment(theme: PresentationTheme(id: "p", name: "p", colors: colors, headingFont: "Helvetica", bodyFont: "Helvetica"),
                                        media: [:], slideSize: r.size)
            let rect = r.insetBy(dx: 3, dy: 3)
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            Paint.fill(path, with: preset.fill, bounds: rect, in: ctx, env: env)
            Paint.stroke(path, with: preset.line, in: ctx, env: env)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: preset.textColor.resolve(colors).nsColor]
            ("Abc" as NSString).draw(at: CGPoint(x: rect.midX - 9, y: rect.minY + 2), withAttributes: attrs)
            return true
        }
    }
}

extension Notification.Name {
    static let wsAddSection = Notification.Name("WSAddSection")
}

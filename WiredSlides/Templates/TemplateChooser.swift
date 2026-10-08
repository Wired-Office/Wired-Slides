import AppKit
import SwiftUI

final class TemplateChooserWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TemplateChooserWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "New Presentation"
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }
        window.contentViewController = NSHostingController(rootView: TemplateChooserView(
            onCreate: { [weak self] template in
                self?.close()
                (NSDocumentController.shared as? SlidesDocumentController)?.newDocument(from: template)
            },
            onOpen: { [weak self] url in
                self?.close()
                if let url {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error { NSApp.presentError(error) }
                    }
                } else {
                    NSDocumentController.shared.openDocument(nil)
                }
            },
            onCancel: { [weak self] in self?.close() }
        ))
        window.setContentSize(NSSize(width: 900, height: 600))
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }
}

struct TemplateChooserView: View {
    let onCreate: (PresentationTemplate) -> Void
    let onOpen: (URL?) -> Void
    let onCancel: () -> Void

    @State private var selection: PresentationTemplate = TemplateLibrary.blank(ThemeLibrary.default)
    @State private var variant = 0
    private let recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Color(nsColor: Theme.barBackground))
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Themes", TemplateLibrary.themes)
                        section("Templates", TemplateLibrary.content)
                    }
                    .padding(26)
                }
                Divider()
                HStack(spacing: 12) {
                    Button("Open…") { onOpen(nil) }
                    if !selection.theme.variants.isEmpty && selection.id.hasPrefix("theme-") {
                        Text("Variant").font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach(0...selection.theme.variants.count, id: \.self) { i in
                            let colors = i == 0 ? selection.theme.colors : selection.theme.variants[i - 1]
                            VariantSwatch(colors: colors)
                                .frame(width: 34, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(variant == i ? Theme.accentColor : .clear, lineWidth: 2))
                                .onTapGesture { variant = i }
                        }
                    }
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                    Button("Create") { create(selection) }.keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
            .background(Color(nsColor: Theme.canvasBackground))
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private func create(_ template: PresentationTemplate) {
        guard variant > 0, template.id.hasPrefix("theme-"), template.theme.variants.indices.contains(variant - 1) else { onCreate(template); return }
        var theme = template.theme
        theme.colors = theme.variants[variant - 1]
        onCreate(PresentationTemplate(id: template.id, name: template.name, subtitle: template.subtitle, theme: theme) { Presentation(theme: theme) })
    }

    private func section(_ title: String, _ templates: [PresentationTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20)], spacing: 20) {
                ForEach(templates) { template in
                    TemplateCard(template: template, isSelected: template == selection, variant: template == selection ? variant : 0)
                        .onTapGesture(count: 2) { create(template) }
                        .onTapGesture {
                            if selection != template { variant = 0 }
                            selection = template
                        }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wired Slides").font(.system(size: 15, weight: .semibold))
                    Text("Choose a theme").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                if recents.isEmpty {
                    Text("No recent presentations").font(.callout).foregroundStyle(.tertiary)
                } else {
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url) { onOpen(url) }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

private struct TemplateCard: View {
    let template: PresentationTemplate
    let isSelected: Bool
    var variant = 0
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: 180)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.15), radius: hovering ? 6 : 3, y: hovering ? 3 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accentColor : .clear, lineWidth: 3)
                        .padding(-5)
                )
                .scaleEffect(hovering ? 1.02 : 1)
            VStack(spacing: 1) {
                Text(template.name).font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text(template.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var preview: NSImage {
        if template.id.hasPrefix("theme-") {
            var theme = template.theme
            if variant > 0, theme.variants.indices.contains(variant - 1) { theme.colors = theme.variants[variant - 1] }
            return ThemePreviews.image(theme, width: 180)
        }
        return TemplateThumbnails.image(for: template)
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}

/// Renders the first slide of content templates.
enum TemplateThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(for template: PresentationTemplate) -> NSImage {
        if let cached = cache[template.id] { return cached }
        let p = template.build()
        let image = SlideRenderer.image(p.slides[0], number: 1, presentation: p, pixelWidth: 360)
        cache[template.id] = image
        return image
    }
}

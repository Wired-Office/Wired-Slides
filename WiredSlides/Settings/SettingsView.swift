import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: .shared))
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show the theme chooser when Wired Slides opens", isOn: $settings.showTemplateChooserOnLaunch)
                Toggle("Save changes automatically (AutoSave)", isOn: $settings.autoSave)
                TextField("Author name", text: $settings.authorName)
                Picker("Theme for new presentations", selection: $settings.defaultThemeID) {
                    ForEach(ThemeLibrary.all) { Text($0.name).tag($0.id) }
                }
            }
            Section("Editing") {
                Toggle("Smart guides when moving objects", isOn: $settings.smartGuides)
                Toggle("Snap objects to grid", isOn: $settings.snapToGrid)
                Stepper("Grid spacing: \(Int(settings.gridSpacing)) pt", value: $settings.gridSpacing, in: 4...72, step: 2)
            }
            Section("View") {
                Toggle("Show notes under the slide", isOn: $settings.showNotesPane)
            }
            Section("Slide Show") {
                Toggle("End with a black slide", isOn: $settings.endWithBlackSlide)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class ShortcutsWindowController: NSWindowController {
    static let shared = ShortcutsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ShortcutsView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ShortcutsView: View {
    private let groups: [(String, [(String, String)])] = [
        ("Editing", [("⇧⌘N", "New slide"), ("⌘D", "Duplicate object or slide"), ("⌘G / ⇧⌘G", "Group / ungroup"), ("⌘B ⌘I ⌘U", "Bold, italic, underline"),
                     ("⇧⌘> / ⇧⌘<", "Bigger / smaller text"), ("⌘L ⌘E ⌘R ⌘J", "Align left, center, right, justify"), ("Tab / ⇧Tab", "Demote / promote a bullet; next table cell"),
                     ("Arrows", "Nudge (⇧ larger, ⌥ finer)"), ("⇧ while dragging", "Keep proportions or straight lines"), ("⌥ while dragging", "Copy the object; resize from center"),
                     ("⌘ while dragging", "Turn off smart guides"), ("Return", "Edit the selected object's text"), ("Esc", "Stop editing / deselect"),
                     ("⌥⌘C / ⌥⌘V", "Copy / paste formatting"), ("⌘K", "Hyperlink")]),
        ("Slide Show", [("⇧⌘↩", "Play from the beginning"), ("⌥⌘↩", "Play from the current slide"), ("→ ↓ Space N", "Next animation or slide"),
                        ("← ↑ Delete P", "Previous slide"), ("Number + Return", "Go to slide"), ("B / W", "Black / white screen"), ("⌘P / ⌘L / H", "Pen / laser / highlighter"),
                        ("E", "Erase ink on the slide"), ("S", "Pause timings"), ("Esc", "End the show")]),
        ("View", [("⌘= / ⌘-", "Zoom in / out"), ("⌘0", "Actual size"), ("⌥⌘0", "Fit slide to window"), ("⌥⌘R", "Collapse the ribbon"),
                  ("⌃⌘1…8", "Show a ribbon tab")]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.0) { group in
                    Text(group.0).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        ForEach(group.1, id: \.0) { row in
                            GridRow {
                                Text(row.0).font(.system(size: 12, design: .monospaced)).frame(width: 150, alignment: .leading)
                                Text(row.1).font(.system(size: 12.5))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

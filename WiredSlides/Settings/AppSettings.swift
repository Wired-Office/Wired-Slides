import AppKit
import Combine

/// User preferences, persisted in UserDefaults. Observable from SwiftUI and
/// broadcast to open presentations via `AppSettings.didChange`.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let didChange = Notification.Name("WSAppSettingsDidChange")

    private enum Key: String {
        case showTemplateChooserOnLaunch, defaultThemeID, authorName, autoSave
        case snapToGrid, gridSpacing, smartGuides, showNotesPane, showRuler
        case presenterView, endWithBlackSlide, laserColor
    }

    private let defaults: UserDefaults

    @Published var showTemplateChooserOnLaunch: Bool { didSet { store(showTemplateChooserOnLaunch, .showTemplateChooserOnLaunch) } }
    @Published var defaultThemeID: String { didSet { store(defaultThemeID, .defaultThemeID) } }
    @Published var authorName: String { didSet { store(authorName, .authorName) } }
    @Published var autoSave: Bool { didSet { store(autoSave, .autoSave) } }
    /// Snap moved and resized objects to an invisible grid.
    @Published var snapToGrid: Bool { didSet { store(snapToGrid, .snapToGrid) } }
    @Published var gridSpacing: Double { didSet { store(gridSpacing, .gridSpacing) } }
    /// Show alignment guides to other objects and the slide while dragging.
    @Published var smartGuides: Bool { didSet { store(smartGuides, .smartGuides) } }
    @Published var showNotesPane: Bool { didSet { store(showNotesPane, .showNotesPane) } }
    @Published var showRuler: Bool { didSet { store(showRuler, .showRuler) } }
    /// End slide shows on a black "End of slide show" screen.
    @Published var endWithBlackSlide: Bool { didSet { store(endWithBlackSlide, .endWithBlackSlide) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showTemplateChooserOnLaunch.rawValue: true,
            Key.defaultThemeID.rawValue: "wired",
            Key.authorName.rawValue: NSFullUserName(),
            Key.autoSave.rawValue: true,
            Key.snapToGrid.rawValue: false,
            Key.gridSpacing.rawValue: 12.0,
            Key.smartGuides.rawValue: true,
            Key.showNotesPane.rawValue: true,
            Key.showRuler.rawValue: false,
            Key.endWithBlackSlide.rawValue: true,
        ])
        showTemplateChooserOnLaunch = defaults.bool(forKey: Key.showTemplateChooserOnLaunch.rawValue)
        defaultThemeID = defaults.string(forKey: Key.defaultThemeID.rawValue) ?? "wired"
        authorName = defaults.string(forKey: Key.authorName.rawValue) ?? ""
        autoSave = defaults.bool(forKey: Key.autoSave.rawValue)
        snapToGrid = defaults.bool(forKey: Key.snapToGrid.rawValue)
        let spacing = defaults.double(forKey: Key.gridSpacing.rawValue)
        gridSpacing = spacing > 0 ? spacing : 12
        smartGuides = defaults.bool(forKey: Key.smartGuides.rawValue)
        showNotesPane = defaults.bool(forKey: Key.showNotesPane.rawValue)
        showRuler = defaults.bool(forKey: Key.showRuler.rawValue)
        endWithBlackSlide = defaults.bool(forKey: Key.endWithBlackSlide.rawValue)
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

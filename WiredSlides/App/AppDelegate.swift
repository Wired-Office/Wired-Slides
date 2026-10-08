import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recentDocumentsMenu = RecentDocumentsMenuController()

    /// True when the app is hosting unit tests: stay in the background and open no windows.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests {
            NSApp.setActivationPolicy(.prohibited)
            UserDefaults.standard.setVolatileDomain(["ApplePersistenceIgnoreState": true], forName: UserDefaults.argumentDomain)
        }
        NSApp.mainMenu = MainMenuBuilder.build(recentDocumentsDelegate: recentDocumentsMenu)
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if Self.isRunningTests { return false }
        #if DEBUG
        if DebugAutomation.runIfRequested() { return false }
        #endif
        guard AppSettings.shared.showTemplateChooserOnLaunch else { return true }
        TemplateChooserWindowController.shared.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Actions

    @objc func showTemplateChooser(_ sender: Any?) {
        TemplateChooserWindowController.shared.show()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        ShortcutsWindowController.shared.show()
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "Presentations for macOS.\n\(ThemeLibrary.all.count) themes · \(ShapeKind.allCases.count) shapes · \(AnimationEffect.allCases.count) animations · \(TransitionKind.allCases.count - 1) transitions",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Wired Slides", .credits: credits])
    }
}

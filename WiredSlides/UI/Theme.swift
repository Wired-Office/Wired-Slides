import AppKit
import SwiftUI

/// Wired Slides' visual identity: an orange accent over neutral chrome.
enum Theme {
    private static func dynamic(light: NSColor, dark: NSColor, name: String) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let accent = dynamic(
        light: NSColor(srgbRed: 0.886, green: 0.420, blue: 0.071, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.29, alpha: 1),
        name: "WSAccent"
    )

    /// Selection outlines and handles on the canvas.
    static let selection = dynamic(
        light: NSColor(srgbRed: 0.886, green: 0.420, blue: 0.071, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.58, blue: 0.24, alpha: 1),
        name: "WSSelection"
    )

    /// Smart guides.
    static let guide = NSColor(srgbRed: 0.93, green: 0.18, blue: 0.45, alpha: 1)

    static let barBackground = dynamic(
        light: NSColor(srgbRed: 0.974, green: 0.972, blue: 0.970, alpha: 1),
        dark: NSColor(srgbRed: 0.172, green: 0.168, blue: 0.165, alpha: 1),
        name: "WSBarBackground"
    )

    /// The area around the slide.
    static let canvasBackground = dynamic(
        light: NSColor(srgbRed: 0.905, green: 0.902, blue: 0.898, alpha: 1),
        dark: NSColor(srgbRed: 0.118, green: 0.115, blue: 0.113, alpha: 1),
        name: "WSCanvasBackground"
    )

    static let paneBackground = dynamic(
        light: NSColor(srgbRed: 0.955, green: 0.953, blue: 0.950, alpha: 1),
        dark: NSColor(srgbRed: 0.150, green: 0.147, blue: 0.145, alpha: 1),
        name: "WSPaneBackground"
    )

    static let separator = dynamic(
        light: NSColor(white: 0, alpha: 0.12),
        dark: NSColor(white: 1, alpha: 0.10),
        name: "WSSeparator"
    )

    static var accentColor: Color { Color(nsColor: accent) }

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

#!/usr/bin/env swift
// Renders the Wired Slides app icon: an Icon Composer AppIcon.icon (macOS 26+,
// with light and dark appearances) and the asset catalog's AppIcon.appiconset
// (light only), which older macOS falls back to.
// Usage: swift Scripts/generate-icon.swift [resources-directory]
//
// Design (matches LBrowser, Wired Paper and Wired Grid): a white squircle, a
// dot-matrix presentation screen on its stand — a title, bullet lines and a
// small bar chart on the slide — and a single orange dot.
// A dark variant (charcoal squircle, light ink) is used in Dark Mode, and also
// written as an image set (AppIconDark) that the app shows in the Dock in Dark Mode.

import AppKit

let resources = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "WiredSlides/Resources")
let appIconSet = resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let iconBundle = resources.appendingPathComponent("AppIcon.icon")

struct Palette { let tile: CGColor; let border: CGColor; let ink: (r: CGFloat, g: CGFloat, b: CGFloat); let accent: CGColor }

let light = Palette(tile: CGColor(gray: 0.996, alpha: 1), border: CGColor(gray: 0, alpha: 0.10),
                    ink: (0.039, 0.039, 0.043), accent: CGColor(srgbRed: 0.961, green: 0.478, blue: 0.106, alpha: 1))
let dark = Palette(tile: CGColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1), border: CGColor(gray: 1, alpha: 0.14),
                   ink: (0.945, 0.945, 0.953), accent: CGColor(srgbRed: 1.0, green: 0.584, blue: 0.231, alpha: 1))

/// Ink density (0…1) for the dot at lattice column `c` of `columns`, row `r` of `rows`.
func density(_ c: Int, _ r: Int, _ columns: Int, _ rows: Int) -> Double {
    let x = Double(c) / Double(columns - 1), y = Double(r) / Double(rows - 1)
    // Light falls from the top left, like LBrowser's cloud.
    let light = 0.5 - 0.3 * y - 0.2 * x
    let screenBottom = 13
    let center = columns / 2
    if r == 0 { return 0.85 + light * 0.3 }                                    // the screen's roller
    if r <= screenBottom {
        if c == 0 || c == columns - 1 { return 0 }
        if c == 1 || c == columns - 2 || r == screenBottom { return 0.62 + light * 0.5 }   // slide edge
        if r == 3, c >= 4, c <= 12 { return 0.85 + light * 0.3 }               // title
        // Bullets with ragged lines.
        let lineEnds: [Int: Int] = [6: 11, 8: 13, 10: 10]
        if let end = lineEnds[r] {
            if c == 4 { return 0.7 + light * 0.4 }
            if c >= 6, c <= end { return 0.45 + light * 0.4 }
        }
        // A bar chart on the right.
        let bars: [Int: Int] = [16: 8, 18: 6, 20: 4]
        for (column, top) in bars where (c == column || c == column + 1) && r >= top && r <= 11 {
            return 0.6 + light * 0.4
        }
        return 0.02 + light * 0.12                                             // the slide
    }
    // The stand: a short pole, then two legs splaying out.
    let step = r - screenBottom
    if step <= 2 { return c == center || c == center - 1 ? 0.6 + light * 0.4 : 0 }
    let spread = step - 2
    if c == center - 1 - spread || c == center + spread { return 0.6 + light * 0.4 }
    return 0
}

/// The tile, in the 1024-point icon canvas.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)

enum Part { case matrix, dot }

/// Draws `part` in 1024-point canvas coordinates.
func drawArtwork(in ctx: CGContext, palette: Palette, part: Part) {
    switch part {
    case .matrix:
        // The dot matrix: square dots sized and shaded by density, on an exact lattice.
        let columns = 26, rows = 18
        let pitch = 22.0
        let width = pitch * Double(columns - 1), height = pitch * Double(rows - 1)
        let originX = (1024 - width) / 2, top = 1024 - (1024 - height) / 2 - 40
        for r in 0..<rows {
            for c in 0..<columns {
                let h = density(c, r, columns, rows)
                guard h > 0 else { continue }
                let s = pitch * 0.66 * (0.25 + 0.75 * h)
                ctx.setFillColor(CGColor(srgbRed: palette.ink.r, green: palette.ink.g, blue: palette.ink.b, alpha: 0.2 + 0.8 * h))
                ctx.fill(CGRect(x: originX + Double(c) * pitch - s / 2, y: top - Double(r) * pitch - s / 2, width: s, height: s))
            }
        }
    case .dot:
        ctx.setFillColor(palette.accent)
        ctx.fillEllipse(in: CGRect(x: 690, y: 700, width: 80, height: 80))
    }
}

/// The classic icon: the artwork on a squircle tile with transparent margins.
func drawIcon(in ctx: CGContext, size: CGFloat, palette: Palette) {
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(tile)
    ctx.setFillColor(palette.tile)
    ctx.fillPath()
    ctx.addPath(tile)
    ctx.setStrokeColor(palette.border)
    ctx.setLineWidth(4)
    ctx.strokePath()

    drawArtwork(in: ctx, palette: palette, part: .matrix)
    drawArtwork(in: ctx, palette: palette, part: .dot)
}

/// One Icon Composer layer: the system draws the tile, so the tile fills the whole canvas.
func drawLayer(in ctx: CGContext, palette: Palette, part: Part) {
    ctx.scaleBy(x: 1024 / tileRect.width, y: 1024 / tileRect.height)
    ctx.translateBy(x: -tileRect.minX, y: -tileRect.minY)
    drawArtwork(in: ctx, palette: palette, part: part)
}

func renderPNG(pixels: Int, draw: (CGContext) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

func srgb(_ color: CGColor) -> String {
    let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
    return "extended-srgb:" + c.map { String(format: "%.5f", $0) }.joined(separator: ",")
}

// The asset catalog icon (light only; the catalog can't give a Mac app icon a dark appearance).
struct Entry { let size: Int; let scale: Int }
let entries = [16, 32, 128, 256, 512].flatMap { [Entry(size: $0, scale: 1), Entry(size: $0, scale: 2)] }

try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    let pixels = entry.size * entry.scale
    try renderPNG(pixels: pixels) { drawIcon(in: $0, size: CGFloat(pixels), palette: light) }
        .write(to: appIconSet.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.size)x\(entry.size)"])
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], to: appIconSet.appendingPathComponent("Contents.json"))

// The dark icon as a plain image, for switching the Dock icon at run time
// (AppIconAppearance); macOS ignores dark appearances in an .appiconset.
let darkImageSet = resources.appendingPathComponent("Assets.xcassets/AppIconDark.imageset")
try FileManager.default.createDirectory(at: darkImageSet, withIntermediateDirectories: true)
var darkImages: [[String: String]] = []
for scale in [1, 2] {
    let name = "icon_dark_512x512\(scale == 2 ? "@2x" : "").png"
    let pixels = 512 * scale
    try renderPNG(pixels: pixels) { drawIcon(in: $0, size: CGFloat(pixels), palette: dark) }
        .write(to: darkImageSet.appendingPathComponent(name))
    darkImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x"])
}
try writeJSON(["images": darkImages, "info": ["author": "xcode", "version": 1]], to: darkImageSet.appendingPathComponent("Contents.json"))

// The Icon Composer icon: a tile fill and two flat layers, each recolored for Dark Mode.
let assets = iconBundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: iconBundle)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
var layers: [[String: Any]] = []
for (part, name) in [(Part.dot, "dot"), (Part.matrix, "matrix")] {
    try renderPNG(pixels: 1024) { drawLayer(in: $0, palette: light, part: part) }
        .write(to: assets.appendingPathComponent("\(name).png"))
    // Each layer is one color at varying opacity, so a solid fill recolors it and keeps the shading.
    let color = { (palette: Palette) in
        part == .dot ? palette.accent : CGColor(srgbRed: palette.ink.r, green: palette.ink.g, blue: palette.ink.b, alpha: 1)
    }
    layers.append([
        "name": name,
        "image-name": "\(name).png",
        "fill-specializations": [
            ["value": ["solid": srgb(color(light))]],
            ["appearance": "dark", "value": ["solid": srgb(color(dark))]],
        ],
        "glass": false,
    ])
}
try writeJSON([
    "fill-specializations": [
        ["value": ["solid": srgb(light.tile)]],
        ["appearance": "dark", "value": ["solid": srgb(dark.tile)]],
    ],
    "groups": [[
        "layers": layers,
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": false, "value": 0.5],
        "specular": false,
    ]],
    "supported-platforms": ["squares": ["macOS"]],
], to: iconBundle.appendingPathComponent("icon.json"))

print("Wrote \(entries.count) icon images to \(appIconSet.path) and light/dark layers to \(iconBundle.path)")

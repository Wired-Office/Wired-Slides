# Wired Slides

A presentation app with a familiar PowerPoint workflow for **macOS, Windows and Linux**. The companion to [Wired Paper](https://github.com/Wired-Office/Wired-Paper) and [Wired Grid](https://github.com/Wired-Office/Wired-Grid).

- **macOS:** a native app written in Swift, with AppKit for the slide canvas and slide show and SwiftUI for the surrounding interface. No third-party dependencies.
- **Windows and Linux:** a desktop app built with [Tauri](https://tauri.app) (Rust plus a web-based editor) in [`cross-platform/`](cross-platform/).

Both read and write the same **`.wslides`** files (and PowerPoint **`.pptx`**), so presentations move freely between computers.

## Download

Get the latest version from [Releases](https://github.com/999david7/Wired-Slides/releases/latest):

| Platform | File |
| --- | --- |
| macOS 15+ (Apple silicon and Intel) | `Wired-Slides-<version>.dmg` |
| Windows 10/11 (x64) | `Wired-Slides-<version>-windows-x64-setup.exe` |
| Linux (x86_64), any distribution | `Wired-Slides-<version>-linux-x86_64.AppImage` |
| Debian, Ubuntu, Mint… | `Wired-Slides-<version>-linux-amd64.deb` |

The builds aren't signed by Apple or Microsoft yet, so on first launch macOS asks you to confirm (right-click ▸ Open), and Windows SmartScreen asks you to confirm (More info ▸ Run anyway). For the AppImage, make the file executable (`chmod +x`) and run it.

## Building the Mac app

Open `WiredSlides.xcodeproj` in Xcode (26 or later) and run the **WiredSlides** scheme. It requires macOS 15 or later.

From the command line:

```bash
xcodebuild -project WiredSlides.xcodeproj -scheme WiredSlides build
xcodebuild -project WiredSlides.xcodeproj -scheme WiredSlides test
```

The project uses file-system-synchronized groups, so new source files placed under `WiredSlides/` are picked up automatically. Regenerate the app icon (the light/dark `AppIcon.icon` for macOS 26+ and the light `AppIcon.appiconset` fallback for macOS 15) with `swift Scripts/generate-icon.swift`. Build the `.dmg` with `Scripts/make-dmg.sh`.

## Building the Windows and Linux app

Needs Node.js 20+ and Rust (stable). On Linux, also install the WebKitGTK development packages ([Tauri prerequisites](https://tauri.app/start/prerequisites/)).

```bash
cd cross-platform
npm install
npm test            # file format tests, including files saved by the Mac app
npm run tauri dev   # run the desktop app
npm run dev         # or just the editor, in a browser at http://localhost:1420
npm run tauri build # installers in src-tauri/target/release/bundle
```

Release installers are built by GitHub Actions ([`windows-linux.yml`](.github/workflows/windows-linux.yml)): create the release, then run the workflow with the release tag and it attaches the `.exe`, `.AppImage` and `.deb`.

### What the Windows and Linux app does

It is a TypeScript port of the Mac app's model, renderer and editor, and keeps presentations in exactly the Mac app's JSON shape, so files round-trip untouched. It has the same ribbon (Home, Insert, Design, Transitions, Animations, Slide Show, Review, View, plus Shape Format, Picture Format, Table Design and Chart Design), the 11 layouts, 12 themes with variants, 70+ preset shapes with adjustment handles, text with bullets, numbering, levels and autofit, pictures, tables, charts, icons, SmartArt, WordArt, video and audio, groups, smart guides, the Format, Animation, Selection and Comments panes, Normal, Outline, Slide Sorter, Notes Page and Reading views, 15 transitions (including Morph) and 32 animations, and a full-screen slide show with Presenter View, pen, highlighter, laser pointer and Rehearse Timings. It opens and saves `.wslides` and `.pptx`, prints slides, handouts, notes and outlines (and PDF through the system's print-to-PDF printer), exports PNG/JPEG images and an RTF outline, and shows update notifications when a new release is out. Shortcuts use Ctrl where the Mac uses ⌘.

Differences from the Mac app: Mac-only fonts (Helvetica Neue, Avenir Next, Gill Sans…) are drawn with the closest installed fonts; icons are redrawn line icons standing in for SF Symbols; there is no MP4 movie export or Remove Background.

## Features

- **Slides.** Eleven layouts (Title, Title and Content, Section Header, Two Content, Comparison, Title Only, Blank, Content with Caption, Picture with Caption, Quote, Big Number) with placeholders, Reset, sections, hide/duplicate/reorder by dragging, copy and paste slides between presentations, Reuse Slides, Slides from Outline and Photo Album.
- **Views.** Normal (thumbnails, slide, notes), Outline, Slide Sorter, Notes Page and Reading View; zoom, fit to window, gridlines, guides, light and dark mode.
- **Objects.** 70+ preset shapes with yellow adjustment handles, text boxes, lines and elbow/curved connectors with arrowheads, pictures, tables, charts, icons, SmartArt, WordArt, video and audio, groups. Move, resize, rotate, flip, nudge, smart guides and snapping, align and distribute, order, lock, Selection pane, Format Painter, Alt Text.
- **Formatting.** Theme-aware fills (solid, gradient, picture, pattern), outlines, shadow, glow and reflection; Shape Styles; picture crop, crop to shape and aspect ratio, corrections, color, transparency, picture styles, Remove Background (Vision).
- **Text.** Fonts, sizes, bold/italic/underline/strikethrough, superscript/subscript, caps, character spacing, color, highlight, outline and shadow; bullets and numbering with list levels, alignment, line and paragraph spacing, columns, text direction, vertical alignment, margins and autofit (shrink on overflow, resize shape to fit); hyperlinks; Find & Replace, spelling, Replace Fonts.
- **Tables and charts.** Table styles and style options, merging, inserting/deleting rows and columns, column resizing, cell shading and borders; column, bar (clustered and stacked), line, area, pie, doughnut and scatter charts with a data editor.
- **Design.** 12 themes with color variants, color schemes, font pairs, background styles, Format Background, slide size, header and footer (date, slide number, footer), Design Ideas.
- **Motion.** 15 transitions including Morph, Push, Cube, Flip, Shape and Dissolve; 32 entrance, emphasis, exit and motion-path animations with On Click / With Previous / After Previous, duration, delay and repeat, the Animation pane, Animation Painter and preview.
- **Slide show.** Full screen on a second display with Presenter View (notes, next slide, timers, slide grid), pen, highlighter, laser pointer and eraser, black/white screen, jump to a slide by number, action buttons, media playback, automatic timings, loop, and Rehearse Timings.
- **Review.** Comments with replies and resolve, accessibility checker, word count.
- **Files.** `.wslides` (native), PowerPoint `.pptx` open and save; export to PDF (slides, handouts, notes pages, outline), PNG/JPEG images, MP4 movie and RTF outline; printing with handouts and notes pages.

## Architecture

```
WiredSlides/
  Model/        Colors (theme colors), styles, text, shapes, elements, slides, themes, layouts, transitions and animations
  Engine/       PresentationController (the model + selection + every command, all undoable), clipboard, presets, tools
  Canvas/       SlideCanvasView (drawing and interaction), in-place text editing, geometry, container
    Rendering/  Shape geometry, TextKit layout with bullets, paint, element/table/chart/slide renderers
  Navigator/    Slide thumbnails, slide sorter, outline, notes pane and notes pages
  Slideshow/    Build plans, the Core Animation stage (effects and transitions), the show and presenter view
  Persistence/  .wslides, .pptx (reader and writer), ZIP
  Window/       Window controller and the presentation view controller (layout, menu actions, dialogs)
  UI/           Ribbon and its tabs, side panes, dialogs, status bar, theme
  Print/        Printing, PDF, movie and outline export
  Templates/    Themes, templates and the chooser
WiredSlidesTests/ File round-trips, build plans, text conversion and editing commands
```

### Key decisions

- **One model, value-typed.** `Presentation` is a struct; every edit goes through `PresentationController.change(_:_:)`, which snapshots it for undo. Drags update live and become one undo step when they end.
- **One renderer.** Slides are drawn by the same Core Graphics code in the editor, thumbnails, slide show layers, printing, PDF and PPTX fallbacks, so they always match.
- **Theme colors stay references.** Colors can point at theme slots (with tints and shades), so changing the theme or variant recolors the whole deck, like PowerPoint.
- **Text edits through TextKit.** An `NSTextView` with the renderer's own layout manager sits over the slide while editing, so bullets, numbering and autofit look the same during and after editing.

## Known limitations

- Animations aren't saved to `.pptx`; charts, icons and media are exported to `.pptx` as pictures.
- No slide master editing (themes provide the master look), equations are plain text, and there is no co-authoring.

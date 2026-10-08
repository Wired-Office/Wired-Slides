import AppKit

/// Builds the application's main menu in code (no nib required).
///
/// Items are nil-targeted so they travel the responder chain:
/// canvas (or text editor) → presentation view controller → window → window controller →
/// document → app delegate → document controller.
enum MainMenuBuilder {
    typealias VC = PresentationViewController

    static func build(recentDocumentsDelegate: NSMenuDelegate) -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        main.addItem(submenuItem(appMenu()))
        main.addItem(submenuItem(fileMenu(recentDocumentsDelegate: recentDocumentsDelegate)))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(viewMenu()))
        main.addItem(submenuItem(insertMenu()))
        main.addItem(submenuItem(formatMenu()))
        main.addItem(submenuItem(arrangeMenu()))
        main.addItem(submenuItem(slideshowMenu()))
        let window = windowMenu()
        main.addItem(submenuItem(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        help.addItem(item("Keyboard Shortcuts", #selector(AppDelegate.showKeyboardShortcuts(_:)), "/"))
        main.addItem(submenuItem(help))
        NSApp.helpMenu = help
        return main
    }

    // MARK: - Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Wired Slides")
        menu.addItem(item("About Wired Slides", #selector(AppDelegate.showAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        menu.addItem(submenuItem(services))
        menu.addItem(.separator())
        menu.addItem(item("Hide Wired Slides", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Wired Slides", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentDocumentsDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Presentation", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("New from Theme…", #selector(AppDelegate.showTemplateChooser(_:)), "n", [.command, .option]))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = recentDocumentsDelegate
        menu.addItem(submenuItem(recent))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:))))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert To", #selector(NSDocument.browseVersions(_:))))
        menu.addItem(.separator())
        let export = NSMenu(title: "Export To")
        export.addItem(item("PDF…", #selector(SlidesDocument.exportPDF(_:)), "e", [.command, .option]))
        export.addItem(item("PowerPoint (.pptx)…", #selector(SlidesDocument.exportPowerPoint(_:))))
        export.addItem(item("Images…", #selector(SlidesDocument.exportImages(_:))))
        export.addItem(item("Movie…", #selector(SlidesDocument.exportMovie(_:))))
        export.addItem(item("Outline (RTF)…", #selector(SlidesDocument.exportOutline(_:))))
        menu.addItem(submenuItem(export))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        let special = NSMenu(title: "Paste Special")
        special.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .shift, .option]))
        special.addItem(item("Paste as Picture", #selector(VC.pasteAsPicture(_:))))
        special.addItem(item("Keep Text Only", #selector(VC.pasteAsText(_:))))
        menu.addItem(submenuItem(special))
        menu.addItem(item("Copy Formatting", #selector(VC.copyFormat(_:)), "c", [.command, .option]))
        menu.addItem(item("Paste Formatting", #selector(VC.pasteFormat(_:)), "v", [.command, .option]))
        menu.addItem(item("Paste Animation", #selector(VC.pasteAnimation(_:))))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Duplicate", #selector(VC.duplicate(_:)), "d"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        let find = NSMenu(title: "Find")
        find.addItem(item("Find…", #selector(VC.find(_:)), "f"))
        find.addItem(item("Replace…", #selector(VC.replace(_:)), "h", [.command, .shift]))
        find.addItem(item("Find Next", #selector(VC.findNextMatch(_:)), "g"))
        find.addItem(item("Find Previous", #selector(VC.findPreviousMatch(_:)), "g", [.command, .shift]))
        menu.addItem(submenuItem(find))
        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        menu.addItem(submenuItem(spelling))
        let substitutions = NSMenu(title: "Substitutions")
        substitutions.addItem(item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))))
        substitutions.addItem(item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:))))
        substitutions.addItem(item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))))
        menu.addItem(submenuItem(substitutions))
        let transformations = NSMenu(title: "Transformations")
        transformations.addItem(item("Make Upper Case", #selector(NSResponder.uppercaseWord(_:))))
        transformations.addItem(item("Make Lower Case", #selector(NSResponder.lowercaseWord(_:))))
        transformations.addItem(item("Capitalize", #selector(NSResponder.capitalizeWord(_:))))
        menu.addItem(submenuItem(transformations))
        let speech = NSMenu(title: "Speech")
        speech.addItem(item("Start Speaking", #selector(NSTextView.startSpeaking(_:))))
        speech.addItem(item("Stop Speaking", #selector(NSTextView.stopSpeaking(_:))))
        menu.addItem(submenuItem(speech))
        menu.addItem(.separator())
        menu.addItem(item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        for mode in ViewMode.allCases {
            let entry = item(mode.title, #selector(VC.setViewMode(_:)))
            entry.representedObject = mode.rawValue
            menu.addItem(entry)
        }
        menu.addItem(item("Reading View", #selector(VC.readingView(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(VC.zoomIn(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(VC.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(VC.actualSize(_:)), "0"))
        menu.addItem(item("Fit Slide to Window", #selector(VC.fitToWindow(_:)), "0", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Notes", #selector(VC.toggleNotes(_:))))
        menu.addItem(item("Gridlines", #selector(VC.toggleGridlines(_:)), "'"))
        menu.addItem(item("Guides", #selector(VC.toggleGuides(_:)), ";", [.command, .option]))
        menu.addItem(item("Collapse Ribbon", #selector(VC.toggleRibbon(_:)), "r", [.command, .option]))
        let panes = NSMenu(title: "Panes")
        for pane in SidePane.allCases {
            let entry = item(pane.title, #selector(VC.showSidePane(_:)))
            entry.representedObject = pane.rawValue
            panes.addItem(entry)
        }
        menu.addItem(submenuItem(panes))
        let tabs = NSMenu(title: "Ribbon Tab")
        for (index, tab) in RibbonModel.Tab.standard.enumerated() {
            let entry = item(tab.title, #selector(VC.showRibbonTab(_:)), "\(index + 1)", [.command, .control])
            entry.representedObject = tab.rawValue
            tabs.addItem(entry)
        }
        menu.addItem(submenuItem(tabs))
        menu.addItem(.separator())
        menu.addItem(item("Next Slide", #selector(VC.nextSlide(_:)), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), [.command, .option]))
        menu.addItem(item("Previous Slide", #selector(VC.previousSlide(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func insertMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert")
        menu.addItem(item("New Slide", #selector(VC.newSlide(_:)), "n", [.command, .shift]))
        let layouts = NSMenu(title: "New Slide with Layout")
        for layout in LayoutKind.allCases {
            let entry = item(layout.title, #selector(VC.newSlideWithLayout(_:)))
            entry.representedObject = layout.rawValue
            layouts.addItem(entry)
        }
        menu.addItem(submenuItem(layouts))
        menu.addItem(item("Duplicate Slide", #selector(VC.duplicateSlide(_:)), "d", [.command, .shift]))
        menu.addItem(item("Section", #selector(VC.addSection(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Text Box", #selector(VC.insertTextBox(_:)), "t", [.command, .control]))
        let shapes = NSMenu(title: "Shape")
        for category in ShapeKind.Category.allCases {
            let sub = NSMenu(title: category.rawValue)
            for kind in ShapeKind.kinds(in: category) {
                let entry = item(kind.title, #selector(VC.insertShape(_:)))
                entry.representedObject = kind.rawValue
                entry.image = ShapeIcons.image(kind)
                sub.addItem(entry)
            }
            shapes.addItem(submenuItem(sub))
        }
        menu.addItem(submenuItem(shapes))
        menu.addItem(item("Line", #selector(VC.insertLine(_:))))
        menu.addItem(item("Arrow", #selector(VC.insertArrow(_:))))
        menu.addItem(item("Table…", #selector(VC.insertTableDialog(_:))))
        let charts = NSMenu(title: "Chart")
        for kind in ChartKind.allCases {
            let entry = item(kind.title, #selector(VC.insertChart(_:)))
            entry.representedObject = kind.rawValue
            entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            charts.addItem(entry)
        }
        menu.addItem(submenuItem(charts))
        menu.addItem(item("SmartArt…", #selector(VC.insertSmartArtDialog(_:))))
        menu.addItem(item("Icon…", #selector(VC.insertIconDialog(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Picture…", #selector(VC.insertPicture(_:)), "i", [.command, .shift]))
        menu.addItem(item("Video or Audio…", #selector(VC.insertMedia(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hyperlink…", #selector(VC.insertHyperlink(_:)), "k"))
        menu.addItem(item("Comment", #selector(VC.insertComment(_:)), "m", [.command, .option]))
        menu.addItem(item("Header & Footer…", #selector(VC.headerFooter(_:))))
        menu.addItem(item("Slide Number", #selector(VC.insertSlideNumber(_:))))
        menu.addItem(item("Date", #selector(VC.insertDate(_:))))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        let font = NSMenu(title: "Font")
        font.addItem(item("Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t"))
        font.addItem(item("Bold", #selector(VC.toggleBold(_:)), "b"))
        font.addItem(item("Italic", #selector(VC.toggleItalic(_:)), "i"))
        font.addItem(item("Underline", #selector(VC.toggleUnderline(_:)), "u"))
        font.addItem(item("Strikethrough", #selector(VC.toggleStrikethrough(_:)), "x", [.command, .shift]))
        font.addItem(.separator())
        font.addItem(item("Bigger", #selector(VC.increaseFontSize(_:)), ">", [.command, .shift]))
        font.addItem(item("Smaller", #selector(VC.decreaseFontSize(_:)), "<", [.command, .shift]))
        font.addItem(.separator())
        font.addItem(item("Superscript", #selector(VC.superscriptText(_:)), "=", [.command, .control]))
        font.addItem(item("Subscript", #selector(VC.subscriptText(_:)), "-", [.command, .control]))
        font.addItem(item("Show Colors", #selector(NSApplication.orderFrontColorPanel(_:)), "c", [.command, .shift]))
        menu.addItem(submenuItem(font))
        let text = NSMenu(title: "Text")
        text.addItem(item("Align Left", #selector(VC.alignTextLeft(_:)), "l"))
        text.addItem(item("Center", #selector(VC.alignTextCenter(_:)), "e"))
        text.addItem(item("Align Right", #selector(VC.alignTextRight(_:)), "r"))
        text.addItem(item("Justify", #selector(VC.alignTextJustify(_:)), "j"))
        text.addItem(.separator())
        text.addItem(item("Bullets", #selector(VC.toggleBullets(_:)), "8", [.command, .shift]))
        text.addItem(item("Numbering", #selector(VC.toggleNumbering(_:)), "7", [.command, .shift]))
        text.addItem(item("Increase List Level", #selector(VC.increaseIndent(_:)), "]"))
        text.addItem(item("Decrease List Level", #selector(VC.decreaseIndent(_:)), "["))
        menu.addItem(submenuItem(text))
        menu.addItem(item("Clear Formatting", #selector(VC.clearFormatting(_:)), " ", [.command, .control, .option]))
        menu.addItem(.separator())
        let layouts = NSMenu(title: "Slide Layout")
        for layout in LayoutKind.allCases {
            let entry = item(layout.title, #selector(VC.setLayout(_:)))
            entry.representedObject = layout.rawValue
            layouts.addItem(entry)
        }
        menu.addItem(submenuItem(layouts))
        menu.addItem(item("Reset Slide", #selector(VC.resetSlide(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Format Pane…", #selector(VC.formatPane(_:)), "1"))
        return menu
    }

    private static func arrangeMenu() -> NSMenu {
        let menu = NSMenu(title: "Arrange")
        menu.addItem(item("Bring to Front", #selector(VC.bringToFront(_:)), "f", [.command, .shift, .option]))
        menu.addItem(item("Bring Forward", #selector(VC.bringForward(_:)), "f", [.command, .option]))
        menu.addItem(item("Send Backward", #selector(VC.sendBackward(_:)), "b", [.command, .option]))
        menu.addItem(item("Send to Back", #selector(VC.sendToBack(_:)), "b", [.command, .shift, .option]))
        menu.addItem(.separator())
        let align = NSMenu(title: "Align Objects")
        for mode in AlignMode.allCases {
            let entry = item(mode.title, #selector(VC.alignObjects(_:)))
            entry.representedObject = mode.rawValue
            entry.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            align.addItem(entry)
        }
        menu.addItem(submenuItem(align))
        let distribute = NSMenu(title: "Distribute Objects")
        distribute.addItem(item("Horizontally", #selector(VC.distributeHorizontally(_:))))
        distribute.addItem(item("Vertically", #selector(VC.distributeVertically(_:))))
        menu.addItem(submenuItem(distribute))
        menu.addItem(.separator())
        menu.addItem(item("Rotate Right 90°", #selector(VC.rotateRight(_:))))
        menu.addItem(item("Rotate Left 90°", #selector(VC.rotateLeft(_:))))
        menu.addItem(item("Flip Horizontally", #selector(VC.flipHorizontal(_:))))
        menu.addItem(item("Flip Vertically", #selector(VC.flipVertical(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Group", #selector(VC.group(_:)), "g"))
        menu.addItem(item("Ungroup", #selector(VC.ungroup(_:)), "g", [.command, .shift]))
        menu.addItem(item("Lock", #selector(VC.lockObjects(_:)), "l", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Move Slide Up", #selector(VC.moveSlideUp(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.command, .shift]))
        menu.addItem(item("Move Slide Down", #selector(VC.moveSlideDown(_:)), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), [.command, .shift]))
        return menu
    }

    private static func slideshowMenu() -> NSMenu {
        let menu = NSMenu(title: "Slide Show")
        menu.addItem(item("Play from Beginning", #selector(VC.playFromBeginning(_:)), "\r", [.command, .shift]))
        menu.addItem(item("Play from Current Slide", #selector(VC.playFromCurrent(_:)), "\r", [.command, .option]))
        menu.addItem(item("Presenter View", #selector(VC.playWithPresenter(_:))))
        menu.addItem(item("Reading View", #selector(VC.readingView(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Preview Animations", #selector(VC.previewAnimations(_:))))
        menu.addItem(item("Rehearse Timings", #selector(VC.rehearseTimings(_:))))
        menu.addItem(item("Set Up Slide Show…", #selector(VC.setUpShow(_:))))
        menu.addItem(item("Hide Slide", #selector(VC.hideSlide(_:))))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: - Helpers

    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

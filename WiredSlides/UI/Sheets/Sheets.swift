import AppKit
import SwiftUI

/// The standard frame of a dialog: title, content, and buttons.
struct SheetFrame<Content: View>: View {
    let title: String
    var okTitle = "OK"
    var okEnabled = true
    let onOK: () -> Void
    @Environment(\.dismissSheet) private var dismiss
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(okTitle) { onOK(); dismiss() }.keyboardShortcut(.defaultAction).disabled(!okEnabled)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}

struct InsertTableSheet: View {
    let controller: PresentationController
    @State private var rows = 3
    @State private var columns = 4
    @State private var hover: (Int, Int)?

    var body: some View {
        SheetFrame(title: "Insert Table", onOK: { controller.insertTable(rows: rows, columns: columns) }) {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 2) {
                    ForEach(0..<8) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<10) { c in
                                Rectangle()
                                    .fill(r < rows && c < columns ? Theme.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
                                    .frame(width: 16, height: 16)
                                    .onTapGesture { rows = r + 1; columns = c + 1 }
                            }
                        }
                    }
                }
                Form {
                    Stepper("Columns: \(columns)", value: $columns, in: 1...30)
                    Stepper("Rows: \(rows)", value: $rows, in: 1...60)
                }
                .frame(width: 160)
            }
        }
    }
}

struct ChartDataSheet: View {
    let controller: PresentationController
    let elementID: UUID
    @State var chart: ChartContent
    @Environment(\.dismissSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chart Data").font(.system(size: 15, weight: .semibold))
            HStack {
                Picker("Type", selection: $chart.kind) {
                    ForEach(ChartKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .frame(width: 240)
                TextField("Title", text: Binding(get: { chart.title ?? "" }, set: { chart.title = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 110)
                        ForEach(chart.series.indices, id: \.self) { s in
                            HStack(spacing: 2) {
                                TextField("Series", text: $chart.series[s].name).textFieldStyle(.roundedBorder).frame(width: 96)
                                if chart.series.count > 1 {
                                    Button { chart.series.remove(at: s) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                }
                            }
                        }
                        Button { addSeries() } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless).help("Add Series")
                    }
                    ForEach(chart.categories.indices, id: \.self) { i in
                        GridRow {
                            HStack(spacing: 2) {
                                if chart.categories.count > 1 {
                                    Button { removeCategory(i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                }
                                TextField("Category", text: $chart.categories[i]).textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 110)
                            ForEach(chart.series.indices, id: \.self) { s in
                                TextField("0", value: valueBinding(s, i), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 118)
                            }
                        }
                    }
                    GridRow {
                        Button { addCategory() } label: { Label("Add Category", systemImage: "plus") }.buttonStyle(.borderless)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 220, maxHeight: 360)
            HStack {
                Toggle("Data labels", isOn: $chart.showDataLabels)
                Toggle("Gridlines", isOn: $chart.showGridlines)
                Picker("Legend", selection: $chart.legend) {
                    ForEach(LegendPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .frame(width: 160)
                Button("Paste from Clipboard") { pasteTable() }.help("Paste tab-separated data copied from a spreadsheet")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    let edited = chart
                    controller.setChart(elementID) { $0 = edited }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .toggleStyle(.checkbox)
        }
        .padding(20)
        .frame(minWidth: 620)
    }

    private func valueBinding(_ s: Int, _ i: Int) -> Binding<Double> {
        Binding(get: { i < chart.series[s].values.count ? chart.series[s].values[i] : 0 }, set: { v in
            while chart.series[s].values.count <= i { chart.series[s].values.append(0) }
            chart.series[s].values[i] = v
        })
    }

    private func addSeries() {
        chart.series.append(ChartSeries(name: "Series \(chart.series.count + 1)", values: Array(repeating: 1, count: chart.categories.count)))
    }

    private func addCategory() {
        chart.categories.append("Category \(chart.categories.count + 1)")
        for s in chart.series.indices { chart.series[s].values.append(0) }
    }

    private func removeCategory(_ i: Int) {
        chart.categories.remove(at: i)
        for s in chart.series.indices where i < chart.series[s].values.count { chart.series[s].values.remove(at: i) }
    }

    /// Reads a block of tab- or comma-separated values: header row of series names, first column of categories.
    private func pasteTable() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let rows = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.map { line in
            line.contains("\t") ? line.components(separatedBy: "\t") : line.components(separatedBy: ",")
        }
        guard rows.count >= 2, let header = rows.first, header.count >= 2 else { return }
        chart.categories = rows.dropFirst().map { $0.first ?? "" }
        chart.series = (1..<header.count).map { c in
            ChartSeries(name: header[c], values: rows.dropFirst().map { c < $0.count ? Double($0[c].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) ?? 0 : 0 })
        }
    }
}

struct HyperlinkSheet: View {
    let controller: PresentationController
    @State private var address = ""
    @State private var kind = 0
    @State private var slide = 0

    var body: some View {
        SheetFrame(title: "Insert Hyperlink", okTitle: "Insert", onOK: apply) {
            Picker("", selection: $kind) {
                Text("Web Page").tag(0)
                Text("Slide in This Presentation").tag(1)
                Text("Email Address").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch kind {
            case 1:
                Picker("Slide", selection: $slide) {
                    ForEach(controller.slides.indices, id: \.self) { i in
                        Text("\(i + 1). \(controller.slides[i].title.isEmpty ? "Slide \(i + 1)" : controller.slides[i].title)").tag(i)
                    }
                }
            case 2:
                TextField("Email address", text: $address).textFieldStyle(.roundedBorder)
            default:
                TextField("https://", text: $address).textFieldStyle(.roundedBorder)
            }
            if controller.currentLink != nil {
                Button("Remove Link") { controller.setHyperlink(nil); controller.setAction(nil) }.buttonStyle(.borderless)
            }
        }
        .onAppear { address = controller.currentLink ?? "" }
    }

    private func apply() {
        switch kind {
        case 1:
            if controller.slides.indices.contains(slide) {
                if controller.selection.isEmpty && controller.textEditor == nil {
                    var box = SlideElement.textBox("Go to slide \(slide + 1)", frame: controller.centeredFrame(CGSize(width: 220, height: 40)))
                    box.action = .slide(controller.slides[slide].id)
                    box.text?.updateRuns { $0.underline = true; $0.color = .theme(.hyperlink) }
                    controller.insert([box], name: "Insert Hyperlink")
                } else {
                    controller.setAction(.slide(controller.slides[slide].id))
                }
            }
        case 2:
            controller.setHyperlink(address.hasPrefix("mailto:") ? address : "mailto:" + address)
        default:
            var url = address.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty, !url.contains("://"), !url.hasPrefix("mailto:") { url = "https://" + url }
            controller.setHyperlink(url)
        }
    }
}

final class FindModel: ObservableObject {
    static let shared = FindModel()
    @Published var options = PresentationController.FindOptions()
}

struct FindReplaceSheet: View {
    let controller: PresentationController
    @State var showReplace: Bool
    @ObservedObject private var model = FindModel.shared
    @State private var message = ""
    @Environment(\.dismissSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(showReplace ? "Replace" : "Find").font(.system(size: 15, weight: .semibold))
            TextField("Find what", text: $model.options.text).textFieldStyle(.roundedBorder)
            if showReplace {
                TextField("Replace with", text: $model.options.replacement).textFieldStyle(.roundedBorder)
            }
            HStack {
                Toggle("Match case", isOn: $model.options.matchCase)
                Toggle("Find whole words only", isOn: $model.options.wholeWords)
            }
            .toggleStyle(.checkbox)
            Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(height: 14)
            HStack {
                if !showReplace { Button("Replace…") { showReplace = true } }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if showReplace {
                    Button("Replace") { controller.replaceCurrent(model.options) }
                    Button("Replace All") {
                        let n = controller.replaceAll(model.options)
                        message = n == 0 ? "No matches found." : "Replaced \(n) occurrence\(n == 1 ? "" : "s")."
                    }
                }
                Button("Find Next") {
                    message = controller.findNext(model.options) ? "" : "No matches found."
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct HeaderFooterSheet: View {
    let controller: PresentationController
    @State private var hf = HeaderFooter()
    @State private var fixedDate = false
    @State private var dateText = ""

    var body: some View {
        SheetFrame(title: "Header & Footer", okTitle: "Apply to All", onOK: {
            var result = hf
            result.fixedDate = fixedDate ? dateText : nil
            controller.setHeaderFooter(result)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Include on slide").font(.system(size: 12, weight: .semibold))
                Toggle("Date and time", isOn: $hf.showDate)
                if hf.showDate {
                    Picker("", selection: $fixedDate) {
                        Text("Update automatically").tag(false)
                        Text("Fixed").tag(true)
                    }
                    .pickerStyle(.radioGroup).labelsHidden().padding(.leading, 18)
                    if fixedDate { TextField("Date", text: $dateText).textFieldStyle(.roundedBorder).padding(.leading, 18) }
                }
                Toggle("Slide number", isOn: $hf.showSlideNumber)
                Toggle("Footer", isOn: $hf.showFooter)
                if hf.showFooter { TextField("Footer text", text: $hf.footerText).textFieldStyle(.roundedBorder).padding(.leading, 18) }
                Divider()
                Toggle("Don't show on title slide", isOn: $hf.hideOnTitleSlide)
            }
            .toggleStyle(.checkbox)
        }
        .onAppear {
            hf = controller.presentation.headerFooter
            fixedDate = hf.fixedDate != nil
            dateText = hf.fixedDate ?? DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        }
    }
}

struct SlideSizeSheet: View {
    let controller: PresentationController
    @State private var width: Double = 960
    @State private var height: Double = 540
    @State private var scale = true

    var body: some View {
        SheetFrame(title: "Slide Size", onOK: { controller.setSlideSize(CGSize(width: width, height: height), scaleContent: scale) }) {
            Picker("Preset", selection: Binding(get: { "\(Int(width))x\(Int(height))" }, set: { key in
                let parts = key.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { width = parts[0]; height = parts[1] }
            })) {
                ForEach(Presentation.standardSizes, id: \.name) { entry in
                    Text(entry.name).tag("\(Int(entry.size.width))x\(Int(entry.size.height))")
                }
                Text("Custom").tag("custom")
            }
            HStack {
                NumberField(label: "Width", value: width / 72, range: 1...56, step: 0.25, unit: " in", width: 70) { width = $0 * 72 }
                NumberField(label: "Height", value: height / 72, range: 1...56, step: 0.25, unit: " in", width: 70) { height = $0 * 72 }
            }
            HStack {
                Button { (width, height) = (max(width, height), min(width, height)) } label: { Label("Landscape", systemImage: "rectangle") }
                Button { (width, height) = (min(width, height), max(width, height)) } label: { Label("Portrait", systemImage: "rectangle.portrait") }
            }
            Picker("When content doesn't fit", selection: $scale) {
                Text("Ensure Fit (scale down)").tag(true)
                Text("Maximize (scale up)").tag(false)
            }
            .pickerStyle(.radioGroup)
        }
        .onAppear { width = Double(controller.slideSize.width); height = Double(controller.slideSize.height) }
    }
}

struct IconPickerSheet: View {
    let controller: PresentationController
    @State private var search = ""
    @State private var selected: String?
    @Environment(\.dismissSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insert Icons").font(.system(size: 15, weight: .semibold))
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(IconCatalog.categories, id: \.name) { category in
                        let icons = category.symbols.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || category.name.localizedCaseInsensitiveContains(search) }
                        if !icons.isEmpty {
                            Text(category.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                                ForEach(icons, id: \.self) { symbol in
                                    Image(systemName: symbol)
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(selected == symbol ? Theme.accentColor.opacity(0.25) : Color.primary.opacity(0.04)))
                                        .onTapGesture { selected = symbol }
                                        .onTapGesture(count: 2) { controller.insertIcon(symbol); dismiss() }
                                        .help(symbol)
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Insert") { if let s = selected { controller.insertIcon(s) }; dismiss() }.keyboardShortcut(.defaultAction).disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

enum IconCatalog {
    static let categories: [(name: String, symbols: [String])] = [
        ("Business", ["briefcase", "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "dollarsign.circle", "creditcard", "building.2", "cart", "bag", "banknote",
                      "target", "flag", "trophy", "rosette", "signature", "doc.text", "folder", "tray.full", "calendar", "clock"]),
        ("People", ["person", "person.2", "person.3", "person.crop.circle", "figure.walk", "figure.run", "hand.raised", "hand.thumbsup", "person.badge.plus",
                    "person.wave.2", "figure.2.and.child.holdinghands", "brain.head.profile", "heart"]),
        ("Communication", ["envelope", "phone", "message", "bubble.left.and.bubble.right", "megaphone", "antenna.radiowaves.left.and.right", "wifi",
                           "paperplane", "bell", "quote.bubble", "video", "mic"]),
        ("Technology", ["desktopcomputer", "laptopcomputer", "iphone", "server.rack", "cpu", "memorychip", "externaldrive", "network", "cloud", "lock", "key",
                        "shield", "gearshape", "wrench.and.screwdriver", "hammer", "terminal", "qrcode", "barcode"]),
        ("Arrows", ["arrow.right", "arrow.left", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.triangle.2.circlepath", "arrow.up.right", "arrow.left.arrow.right",
                    "chevron.right.2", "arrowshape.turn.up.right", "arrow.uturn.left", "arrow.triangle.branch"]),
        ("Nature", ["leaf", "tree", "sun.max", "moon", "cloud.sun", "cloud.rain", "snowflake", "flame", "drop", "bolt", "globe.americas", "mountain.2", "pawprint", "ladybug"]),
        ("Education", ["book", "books.vertical", "graduationcap", "pencil", "highlighter", "ruler", "function", "x.squareroot", "lightbulb", "puzzlepiece",
                       "atom", "flask", "testtube.2", "microscope"]),
        ("Travel", ["airplane", "car", "bus", "tram", "bicycle", "ferry", "map", "mappin.and.ellipse", "location", "house", "suitcase", "globe"]),
        ("Symbols", ["checkmark.circle", "xmark.circle", "exclamationmark.triangle", "questionmark.circle", "info.circle", "plus.circle", "minus.circle", "star",
                     "heart.fill", "bookmark", "tag", "sparkles", "crown", "infinity", "number", "percent"]),
        ("Media", ["play.circle", "pause.circle", "music.note", "headphones", "camera", "photo", "film", "tv", "gamecontroller", "paintpalette", "theatermasks"]),
        ("Health", ["cross.case", "pills", "stethoscope", "heart.text.square", "bandage", "syringe", "bed.double", "figure.mind.and.body"]),
    ]
}

struct SmartArtSheet: View {
    let controller: PresentationController
    @State private var kind: SmartArtKind = .process
    @State private var items = SmartArtKind.process.sampleItems.joined(separator: "\n")

    var body: some View {
        SheetFrame(title: "Choose a SmartArt Graphic", onOK: {
            controller.insertSmartArt(kind, items: items.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }) {
            HStack(alignment: .top, spacing: 16) {
                List(SmartArtKind.allCases, selection: Binding(get: { kind }, set: { if let k = $0 { kind = k; items = k.sampleItems.joined(separator: "\n") } })) { k in
                    Label(k.title, systemImage: k.symbol).tag(k)
                }
                .frame(width: 200, height: 260)
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.category).font(.system(size: 11)).foregroundStyle(.secondary)
                    Image(nsImage: SmartArtPreview.image(kind, items: items.components(separatedBy: "\n"), theme: controller.theme))
                        .resizable().aspectRatio(16 / 9, contentMode: .fit).frame(width: 300)
                        .border(Color.primary.opacity(0.15), width: 0.5)
                    Text("Items (one per line)").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextEditor(text: $items).font(.system(size: 12)).frame(height: 90).border(Color.primary.opacity(0.15), width: 0.5)
                }
            }
        }
    }
}

enum SmartArtPreview {
    static func image(_ kind: SmartArtKind, items: [String], theme: PresentationTheme) -> NSImage {
        let group = SmartArtBuilder.build(kind, items: items.filter { !$0.isEmpty }, in: CGRect(x: 60, y: 60, width: 840, height: 420))
        var slide = Slide(layout: .blank)
        slide.elements = [group]
        let p = Presentation(theme: theme, slides: [slide])
        return SlideRenderer.image(slide, number: 1, presentation: p, pixelWidth: 600)
    }
}

struct ActionSheet: View {
    let controller: PresentationController
    @State private var choice = 0
    @State private var url = ""
    @State private var slide = 0

    var body: some View {
        SheetFrame(title: "Action Settings", onOK: apply) {
            Text("When the object is clicked in a slide show:").font(.system(size: 12))
            Picker("", selection: $choice) {
                Text("None").tag(0)
                Text("Next Slide").tag(1)
                Text("Previous Slide").tag(2)
                Text("First Slide").tag(3)
                Text("Last Slide").tag(4)
                Text("End Show").tag(5)
                Text("Slide…").tag(6)
                Text("URL…").tag(7)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            if choice == 6 {
                Picker("Slide", selection: $slide) {
                    ForEach(controller.slides.indices, id: \.self) { i in Text("\(i + 1). \(controller.slides[i].title)").tag(i) }
                }
            }
            if choice == 7 { TextField("https://", text: $url).textFieldStyle(.roundedBorder) }
        }
        .onAppear {
            switch controller.primaryElement?.action {
            case .nextSlide?: choice = 1
            case .previousSlide?: choice = 2
            case .firstSlide?: choice = 3
            case .lastSlide?: choice = 4
            case .endShow?: choice = 5
            case .slide(let id)?: choice = 6; slide = controller.presentation.slideIndex(id) ?? 0
            case .url(let u)?: choice = 7; url = u
            default: choice = 0
            }
        }
    }

    private func apply() {
        let action: ElementAction?
        switch choice {
        case 1: action = .nextSlide
        case 2: action = .previousSlide
        case 3: action = .firstSlide
        case 4: action = .lastSlide
        case 5: action = .endShow
        case 6: action = controller.slides.indices.contains(slide) ? .slide(controller.slides[slide].id) : nil
        case 7: action = url.isEmpty ? nil : .url(url.contains("://") ? url : "https://" + url)
        default: action = nil
        }
        controller.setAction(action)
    }
}

struct SetUpShowSheet: View {
    let controller: PresentationController
    @State private var settings = SlideShowSettings()
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        SheetFrame(title: "Set Up Slide Show", onOK: { controller.setShowSettings(settings) }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Show options").font(.system(size: 12, weight: .semibold))
                Toggle("Loop continuously until Esc", isOn: $settings.loopUntilEscape)
                Toggle("Show without animation", isOn: $settings.showWithoutAnimation)
                Toggle("End with a black slide", isOn: $app.endWithBlackSlide)
                Text("Advance slides").font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                Picker("", selection: $settings.useTimings) {
                    Text("Manually").tag(false)
                    Text("Using timings, if present").tag(true)
                }
                .pickerStyle(.radioGroup).labelsHidden()
                Text("Monitors").font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                Toggle("Use Presenter View", isOn: $settings.usePresenterView)
                HStack {
                    Text("Pen color")
                    ColorPicker("", selection: Binding(get: { Color(nsColor: settings.penColor.nsColor) }, set: { settings.penColor = RGBColor(NSColor($0)) }))
                        .labelsHidden()
                    Text("Laser pointer color").padding(.leading, 12)
                    ColorPicker("", selection: Binding(get: { Color(nsColor: settings.laserColor.nsColor) }, set: { settings.laserColor = RGBColor(NSColor($0)) }))
                        .labelsHidden()
                }
            }
            .toggleStyle(.checkbox)
        }
        .onAppear { settings = controller.presentation.showSettings }
    }
}

/// Walks through misspelled words on every slide.
struct SpellingSheet: View {
    let controller: PresentationController
    @State private var issues: [(slide: Int, element: UUID, word: String, guesses: [String])] = []
    @State private var index = 0
    @State private var ignored: Set<String> = []
    @Environment(\.dismissSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spelling").font(.system(size: 15, weight: .semibold))
            if issues.isEmpty || index >= issues.count {
                Text(issues.isEmpty ? "The spelling check is complete. No errors found." : "The spelling check is complete.")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else {
                let issue = issues[index]
                Text("Not in dictionary (slide \(issue.slide + 1)):").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(issue.word).font(.system(size: 18, weight: .semibold)).foregroundStyle(.red)
                Text("Suggestions").font(.system(size: 12)).foregroundStyle(.secondary)
                List(issue.guesses, id: \.self) { guess in
                    Button(guess) { change(issue, to: guess) }.buttonStyle(.plain)
                }
                .frame(height: 140)
                HStack {
                    Button("Ignore") { index += 1; focus() }
                    Button("Ignore All") { ignored.insert(issue.word); advance() }
                    Button("Learn") {
                        NSSpellChecker.shared.learnWord(issue.word)
                        ignored.insert(issue.word)
                        advance()
                    }
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Change") { if let g = issue.guesses.first { change(issue, to: g) } }.keyboardShortcut(.defaultAction).disabled(issue.guesses.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
        .onAppear { scan(); focus() }
    }

    private func scan() {
        let checker = NSSpellChecker.shared
        var found: [(Int, UUID, String, [String])] = []
        for (s, slide) in controller.slides.enumerated() {
            for e in slide.elements {
                for text in e.allText {
                    var start = 0
                    let ns = text as NSString
                    while start < ns.length {
                        let range = checker.checkSpelling(of: text, startingAt: start)
                        guard range.location != NSNotFound, range.length > 0 else { break }
                        let word = ns.substring(with: range)
                        let guesses = checker.guesses(forWordRange: range, in: text, language: nil, inSpellDocumentWithTag: 0) ?? []
                        found.append((s, e.id, word, Array(guesses.prefix(8))))
                        start = NSMaxRange(range)
                    }
                }
            }
        }
        issues = found
    }

    private func advance() {
        index += 1
        while index < issues.count, ignored.contains(issues[index].word) { index += 1 }
        focus()
    }

    private func focus() {
        guard index < issues.count else { return }
        controller.setCurrentSlide(issues[index].slide)
        controller.select([issues[index].element])
    }

    private func change(_ issue: (slide: Int, element: UUID, word: String, guesses: [String]), to replacement: String) {
        var options = PresentationController.FindOptions()
        options.text = issue.word
        options.replacement = replacement
        options.matchCase = true
        options.wholeWords = true
        controller.setCurrentSlide(issue.slide)
        controller.select([issue.element])
        controller.changeElements([issue.element], "Spelling") { e in
            var done = false
            PresentationController.replaceText(in: &e) { text in
                guard !done, let r = text.range(of: issue.word) else { return text }
                done = true
                return text.replacingCharacters(in: r, with: replacement)
            }
        }
        advance()
    }
}

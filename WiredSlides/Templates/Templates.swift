import AppKit

/// A starting point in the template chooser.
struct PresentationTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let theme: PresentationTheme
    let build: () -> Presentation

    static func == (a: PresentationTemplate, b: PresentationTemplate) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Builds slides tersely.
private struct DeckBuilder {
    var presentation: Presentation
    var theme: PresentationTheme { presentation.theme }
    var size: CGSize { presentation.slideSize }

    init(_ theme: PresentationTheme) {
        presentation = Presentation(theme: theme)
        presentation.slides = []
    }

    @discardableResult
    mutating func slide(_ layout: LayoutKind, title: String? = nil, body: [String] = [], body2: [String] = [], subtitle: String? = nil,
                        notes: String = "", transition: TransitionKind = .none, extra: [SlideElement] = []) -> Int {
        var slide = LayoutBuilder.makeSlide(layout, theme: theme, size: size)
        var bodies = [body, body2]
        for i in slide.elements.indices {
            guard let role = slide.elements[i].placeholder, var text = slide.elements[i].text else { continue }
            switch role {
            case .title, .centeredTitle:
                if let title { text.setPlainText(title) }
            case .subtitle:
                if let subtitle { text.setPlainText(subtitle) }
            case .body:
                guard !bodies.isEmpty else { continue }
                let lines = bodies.removeFirst()
                guard !lines.isEmpty else { continue }
                let style = text.paragraphs.first?.style ?? .plain
                let run = text.paragraphs.first?.runs.first?.style ?? .plain
                text.paragraphs = lines.map { line in
                    var s = style
                    let level = line.prefix { $0 == "\t" }.count
                    s.level = level
                    return Paragraph(String(line.dropFirst(level)), style: s, run: run)
                }
            default:
                break
            }
            slide.elements[i].text = text
        }
        slide.elements += extra
        slide.notes = notes
        slide.transition.kind = transition
        presentation.slides.append(slide)
        return presentation.slides.count - 1
    }

    mutating func animate(_ slide: Int, _ effect: AnimationEffect, elementNamed name: String? = nil, trigger: AnimationTrigger = .onClick) {
        let elements = presentation.slides[slide].elements.filter { name == nil ? $0.placeholder == .body : $0.name == name }
        for (i, e) in elements.enumerated() {
            presentation.slides[slide].animations.append(SlideAnimation(elementID: e.id, effect: effect, trigger: i == 0 ? trigger : .afterPrevious))
        }
    }
}

enum TemplateLibrary {
    static func blank(_ theme: PresentationTheme) -> PresentationTemplate {
        PresentationTemplate(id: "theme-" + theme.id, name: theme.name, subtitle: "Theme", theme: theme) {
            Presentation(theme: theme)
        }
    }

    static let pitchDeck = PresentationTemplate(id: "pitch", name: "Pitch Deck", subtitle: "Problem, solution, market, ask", theme: ThemeLibrary.midnight) {
        var b = DeckBuilder(ThemeLibrary.midnight)
        b.slide(.title, title: "Company Name", subtitle: "The one-line description of what you do", notes: "Introduce yourself and the company in one breath.", transition: .fade)
        let problem = b.slide(.titleContent, title: "The Problem", body: ["Who has the problem", "How they solve it today", "Why that isn't good enough"], transition: .push)
        b.animate(problem, .floatIn)
        b.slide(.titleContent, title: "Our Solution", body: ["What the product does", "The moment it clicks for customers", "Why now"], transition: .push)
        let chart = SlideElement(name: "Market Chart", frame: CGRect(x: 120, y: 140, width: 720, height: 340), content: .chart(ChartContent(
            kind: .column, title: "Market size ($B)", categories: ["2024", "2025", "2026", "2027"],
            series: [ChartSeries(name: "Market", values: [4.2, 5.9, 8.1, 11.4])], legend: .none, showDataLabels: true)))
        b.slide(.titleOnly, title: "Market Opportunity", transition: .push, extra: [chart])
        b.slide(.bigNumber, title: "3×", body: ["faster than the leading alternative"], transition: .zoom)
        b.slide(.twoContent, title: "Business Model", body: ["Pricing", "\tPer seat, billed annually", "\tFree tier for teams under 5"],
                body2: ["Go-to-market", "\tBottom-up adoption", "\tSales-assisted expansion"], transition: .push)
        b.slide(.sectionHeader, title: "The Ask", body: ["Raising $2M to reach 1,000 customers"], transition: .fadeThroughBlack)
        return b.presentation
    }

    static let projectStatus = PresentationTemplate(id: "status", name: "Project Status", subtitle: "Weekly or monthly update", theme: ThemeLibrary.clean) {
        var b = DeckBuilder(ThemeLibrary.clean)
        b.slide(.title, title: "Project Status Update", subtitle: DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
        b.slide(.titleContent, title: "Summary", body: ["Overall status: On track", "Key milestone reached this period", "One risk needs attention"])
        var table = TableContent.make(rows: 5, columns: 4, width: 840)
        let data = [["Workstream", "Owner", "Status", "Due"], ["Design", "Alex", "Done", "Mar 1"], ["Build", "Sam", "In progress", "Apr 15"],
                    ["Testing", "Jordan", "Not started", "May 1"], ["Launch", "Riley", "Not started", "May 20"]]
        for r in 0..<5 { for c in 0..<4 { table.rows[r][c].text = TableContent.cellBody(data[r][c]) } }
        b.slide(.titleOnly, title: "Milestones", extra: [SlideElement(name: "Milestones", frame: CGRect(x: 60, y: 150, width: 840, height: 185), content: .table(table))])
        b.slide(.twoContent, title: "Risks & Next Steps", body: ["Risks", "\tVendor delay could push testing", "\tTwo open hires"],
                body2: ["Next steps", "\tConfirm vendor dates", "\tStart test planning"])
        return b.presentation
    }

    static let lesson = PresentationTemplate(id: "lesson", name: "Lesson", subtitle: "Objectives, content and a quiz", theme: ThemeLibrary.pastel) {
        var b = DeckBuilder(ThemeLibrary.pastel)
        b.slide(.title, title: "Lesson Title", subtitle: "Course · Unit 1")
        let objectives = b.slide(.titleContent, title: "Today's Objectives", body: ["Understand the key idea", "Practice with examples", "Check understanding"])
        b.animate(objectives, .fadeIn)
        let cycle = SmartArtBuilder.build(.cycle, items: ["Learn", "Practice", "Reflect", "Apply"], in: CGRect(x: 230, y: 140, width: 500, height: 360))
        b.slide(.titleOnly, title: "How We'll Learn", extra: [cycle])
        b.slide(.quote, title: "\u{201C}Tell me and I forget. Teach me and I remember. Involve me and I learn.\u{201D}", body: ["— Attributed to Benjamin Franklin"])
        b.slide(.titleContent, title: "Quick Quiz", body: ["Question 1?", "Question 2?", "Question 3?"])
        return b.presentation
    }

    static let quarterlyReview = PresentationTemplate(id: "quarterly", name: "Quarterly Review", subtitle: "Results, charts and outlook", theme: ThemeLibrary.wired) {
        var b = DeckBuilder(ThemeLibrary.wired)
        b.slide(.title, title: "Q3 Business Review", subtitle: "Results and outlook", transition: .morph)
        let revenue = SlideElement(name: "Revenue", frame: CGRect(x: 60, y: 140, width: 520, height: 340), content: .chart(ChartContent(
            kind: .lineMarkers, title: "Revenue ($M)", categories: ["Q4", "Q1", "Q2", "Q3"],
            series: [ChartSeries(name: "2026", values: [12.1, 13.4, 14.8, 16.2]), ChartSeries(name: "Plan", values: [12, 13, 14, 15])])))
        let mix = SlideElement(name: "Mix", frame: CGRect(x: 600, y: 160, width: 300, height: 300), content: .chart(ChartContent(
            kind: .doughnut, title: "Revenue mix", categories: ["Product", "Services", "Other"], series: [ChartSeries(name: "Mix", values: [62, 30, 8])], legend: .bottom, showDataLabels: true)))
        b.slide(.titleOnly, title: "Revenue", transition: .fade, extra: [revenue, mix])
        b.slide(.bigNumber, title: "+18%", body: ["year-over-year growth"], transition: .zoom)
        b.slide(.twoContent, title: "Highlights & Lowlights", body: ["Highlights", "\tRecord quarter for new customers", "\tChurn down 2 points"],
                body2: ["Lowlights", "\tHiring behind plan", "\tEMEA pipeline soft"])
        b.slide(.sectionHeader, title: "Outlook", body: ["What we expect next quarter"])
        return b.presentation
    }

    static let photoStory = PresentationTemplate(id: "photo", name: "Photo Story", subtitle: "Big pictures with captions", theme: ThemeLibrary.graphite) {
        var b = DeckBuilder(ThemeLibrary.graphite)
        b.slide(.title, title: "A Photo Story", subtitle: "Add your pictures", transition: .fade)
        for i in 1...3 { b.slide(.pictureCaption, title: "Chapter \(i)", body: ["A sentence about this picture."], transition: .fade) }
        return b.presentation
    }

    static var themes: [PresentationTemplate] { ThemeLibrary.all.map(blank) }
    static let content: [PresentationTemplate] = [pitchDeck, quarterlyReview, projectStatus, lesson, photoStory]
}

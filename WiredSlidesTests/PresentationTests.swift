import XCTest
@testable import WiredSlides

final class PresentationTests: XCTestCase {
    private func sample() -> Presentation {
        TemplateLibrary.quarterlyReview.build()
    }

    func testNativeRoundTrip() throws {
        var p = sample()
        let id = p.addMedia(Data([0x89, 0x50, 0x4E, 0x47]), filename: "x.png")
        p.slides[0].elements.append(SlideElement(name: "Pic", frame: CGRect(x: 1, y: 2, width: 3, height: 4), content: .image(ImageContent(mediaID: id))))
        p.slides[1].notes = "Speaker notes"
        let data = try WSlidesFormat.write(p)
        let back = try WSlidesFormat.read(data)
        XCTAssertEqual(back.slides, p.slides)
        XCTAssertEqual(back.theme, p.theme)
        XCTAssertEqual(back.media[id]?.data, p.media[id]?.data)
    }

    func testPowerPointRoundTripKeepsText() throws {
        let p = sample()
        let back = try PPTXReader.read(try PPTXWriter.write(p))
        XCTAssertEqual(back.slides.count, p.slides.count)
        XCTAssertEqual(back.slideSize, p.slideSize)
        XCTAssertEqual(back.slides.map(\.title), p.slides.map(\.title))
        XCTAssertEqual(back.theme.colors.accent1.hexString, p.theme.colors.accent1.hexString)
    }

    func testBuildPlanSteps() {
        var slide = Slide(layout: .blank)
        let a = SlideElement.shape(.rect, frame: .zero), b = SlideElement.shape(.ellipse, frame: .zero)
        slide.elements = [a, b]
        slide.animations = [SlideAnimation(elementID: a.id, effect: .fadeIn, trigger: .withPrevious),
                            SlideAnimation(elementID: b.id, effect: .flyIn, trigger: .onClick),
                            SlideAnimation(elementID: a.id, effect: .fadeOut, trigger: .afterPrevious)]
        let plan = SlideBuildPlan(slide)
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].count, 1)
        XCTAssertEqual(plan.steps[1][1].start, plan.steps[1][0].end, accuracy: 0.0001)
        XCTAssertEqual(plan.initiallyHidden, [a.id, b.id])
    }

    func testTextKitConversionRoundTrip() {
        var body = TextBody("First\nSecond", size: 24)
        body.paragraphs[1].style.bullet = .numbered(.arabicPeriod, start: 1)
        body.paragraphs[0].runs[0].style.bold = true
        body.paragraphs[0].runs[0].style.color = .theme(.accent2)
        let ctx = TextLayout.Context(theme: ThemeLibrary.wired)
        let back = TextLayout.textBody(from: TextLayout.attributedString(body, ctx), base: body, ctx)
        XCTAssertEqual(back.paragraphs, body.paragraphs)
    }

    func testUndoRestoresSlides() {
        let doc = SlidesDocument()
        let c = doc.controller
        let count = c.slides.count
        c.addSlide()
        c.insertShape(.star5)
        XCTAssertEqual(c.slides.count, count + 1)
        doc.undoManager?.undo()
        doc.undoManager?.undo()
        XCTAssertEqual(c.slides.count, count)
    }

    func testGroupAndUngroup() {
        let doc = SlidesDocument()
        let c = doc.controller
        c.setLayout(.blank)
        c.insertShape(.rect, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        c.insertShape(.ellipse, frame: CGRect(x: 20, y: 20, width: 10, height: 10))
        c.selectAllElements()
        c.group()
        XCTAssertEqual(c.currentSlide.elements.count, 1)
        XCTAssertEqual(c.currentSlide.elements[0].frame, CGRect(x: 0, y: 0, width: 30, height: 30))
        c.ungroup()
        XCTAssertEqual(c.currentSlide.elements.count, 2)
    }

    func testReplaceAll() {
        let doc = SlidesDocument()
        let c = doc.controller
        c.load(TemplateLibrary.pitchDeck.build())
        var options = PresentationController.FindOptions()
        options.text = "Problem"
        options.replacement = "Pain"
        XCTAssertGreaterThan(c.replaceAll(options), 0)
        XCTAssertTrue(c.slides.contains { $0.title == "The Pain" })
    }
}

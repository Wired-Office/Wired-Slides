import AppKit

/// Writes PowerPoint (.pptx) files: slides, layouts, theme, text, shapes, pictures,
/// lines, tables, groups, notes, transitions and hyperlinks. Charts, icons and
/// media posters become pictures; animations are not exported.
enum PPTXWriter {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"
    static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static var namespaces: String { "xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\"" }
    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    static func emu(_ points: CGFloat) -> Int { Int((points * 12700).rounded()) }
    static func emu(_ points: Double) -> Int { Int((points * 12700).rounded()) }

    static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters.
                if ch.value < 0x20 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// Relationships of one part.
    final class Rels {
        private(set) var items: [(id: String, type: String, target: String, external: Bool)] = []
        func add(_ type: String, _ target: String, external: Bool = false) -> String {
            if let existing = items.first(where: { $0.type == type && $0.target == target }) { return existing.id }
            let id = "rId\(items.count + 1)"
            items.append((id, type, target, external))
            return id
        }
        var xml: String {
            var s = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            for item in items {
                s += "<Relationship Id=\"\(item.id)\" Type=\"\(relBase)/\(item.type)\" Target=\"\(esc(item.target))\"\(item.external ? " TargetMode=\"External\"" : "")/>"
            }
            return s + "</Relationships>"
        }
    }

    /// Shared state while writing.
    final class Context {
        let presentation: Presentation
        var mediaFiles: [String: String] = [:]   // media id or render key → ppt/media file name
        var entries: [(path: String, data: Data)] = []
        var mediaCounter = 0
        var contentTypes: Set<String> = []
        init(_ p: Presentation) { presentation = p }

        func addMedia(_ data: Data, ext: String, key: String) -> String {
            if let existing = mediaFiles[key] { return existing }
            mediaCounter += 1
            let name = "image\(mediaCounter).\(ext)"
            entries.append(("ppt/media/\(name)", data))
            mediaFiles[key] = name
            contentTypes.insert(ext)
            return name
        }
    }

    static func write(_ presentation: Presentation) throws -> Data {
        let ctx = Context(presentation)
        let p = presentation
        let hasNotes = p.slides.contains { !$0.notes.isEmpty }
        let layouts = LayoutKind.allCases

        // Theme.
        ctx.entries.append(("ppt/theme/theme1.xml", Data(themeXML(p.theme, name: p.theme.name).utf8)))
        if hasNotes { ctx.entries.append(("ppt/theme/theme2.xml", Data(themeXML(p.theme, name: "Notes").utf8))) }

        // Master.
        let masterRels = Rels()
        var layoutIDs = ""
        for (i, _) in layouts.enumerated() {
            let rid = masterRels.add("slideLayout", "../slideLayouts/slideLayout\(i + 1).xml")
            layoutIDs += "<p:sldLayoutId id=\"\(2147483649 + i)\" r:id=\"\(rid)\"/>"
        }
        _ = masterRels.add("theme", "../theme/theme1.xml")
        let masterShapes = shapesXML(SlideRenderer.decorations(for: Slide(layout: .blank), theme: p.theme, size: p.slideSize), ctx: ctx, rels: masterRels, slideIndex: nil, firstID: 10)
        let master = header + "<p:sldMaster \(namespaces)><p:cSld>\(backgroundXML(p.theme.background, ctx: ctx, rels: masterRels))<p:spTree>\(groupHeader)"
            + placeholderShape(.title, id: 2, rect: LayoutBuilder.scaled(CGRect(x: 60, y: 30, width: 840, height: 96), to: p.slideSize), idx: nil)
            + placeholderShape(.body, id: 3, rect: LayoutBuilder.scaled(CGRect(x: 60, y: 140, width: 840, height: 350), to: p.slideSize), idx: 1)
            + masterShapes + "</p:spTree></p:cSld>"
            + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
            + "<p:sldLayoutIdLst>\(layoutIDs)</p:sldLayoutIdLst>" + textStylesXML(p.theme) + "</p:sldMaster>"
        ctx.entries.append(("ppt/slideMasters/slideMaster1.xml", Data(master.utf8)))

        // Layouts.
        for (i, layout) in layouts.enumerated() {
            let rels = Rels()
            _ = rels.add("slideMaster", "../slideMasters/slideMaster1.xml")
            var sample = LayoutBuilder.makeSlide(layout, theme: p.theme, size: p.slideSize)
            var bodyIndex = 0
            var shapes = ""
            for (n, e) in sample.elements.enumerated() {
                guard let role = e.placeholder else { continue }
                var idx: Int?
                if !role.isTitle { bodyIndex += 1; idx = bodyIndex }
                shapes += placeholderShape(role, id: n + 2, rect: e.frame, idx: idx, prompt: e.text?.prompt)
            }
            var background = ""
            var showMaster = ""
            if layout.isTitleStyle {
                sample.hideBackgroundGraphics = false
                showMaster = " showMasterSp=\"0\""
                background = backgroundXML(p.theme.titleBackground ?? p.theme.background, ctx: ctx, rels: rels)
                shapes = shapesXML(SlideRenderer.decorations(for: sample, theme: p.theme, size: p.slideSize), ctx: ctx, rels: rels, slideIndex: nil, firstID: 20) + shapes
            }
            let xml = header + "<p:sldLayout \(namespaces) type=\"\(layout.ooxmlType)\" preserve=\"1\"\(showMaster)><p:cSld name=\"\(esc(layout.title))\">\(background)<p:spTree>\(groupHeader)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
            ctx.entries.append(("ppt/slideLayouts/slideLayout\(i + 1).xml", Data(xml.utf8)))
            ctx.entries.append(("ppt/slideLayouts/_rels/slideLayout\(i + 1).xml.rels", Data(rels.xml.utf8)))
        }
        ctx.entries.append(("ppt/slideMasters/_rels/slideMaster1.xml.rels", Data(masterRels.xml.utf8)))

        // Notes master.
        if hasNotes {
            let rels = Rels()
            _ = rels.add("theme", "../theme/theme2.xml")
            let xml = header + "<p:notesMaster \(namespaces)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg><p:spTree>\(groupHeader)"
                + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\" idx=\"2\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"1143000\"/><a:ext cx=\"5486400\" cy=\"3086100\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln w=\"12700\"><a:solidFill><a:prstClr val=\"black\"/></a:solidFill></a:ln></p:spPr></p:sp>"
                + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" sz=\"quarter\" idx=\"3\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"4400550\"/><a:ext cx=\"5486400\" cy=\"3600450\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\"/><a:lstStyle/><a:p><a:pPr lvl=\"0\"/><a:r><a:rPr lang=\"en-US\"/><a:t>Click to edit Master text styles</a:t></a:r></a:p></p:txBody></p:sp>"
                + "</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/></p:notesMaster>"
            ctx.entries.append(("ppt/notesMasters/notesMaster1.xml", Data(xml.utf8)))
            ctx.entries.append(("ppt/notesMasters/_rels/notesMaster1.xml.rels", Data(rels.xml.utf8)))
        }

        // Slides.
        for (i, slide) in p.slides.enumerated() {
            let rels = Rels()
            let layoutIndex = (layouts.firstIndex(of: slide.layout) ?? 6) + 1
            _ = rels.add("slideLayout", "../slideLayouts/slideLayout\(layoutIndex).xml")
            var bodyIndex = 0
            var nextID = 2
            var shapes = ""
            for e in slide.elements {
                var idx: Int?
                if let role = e.placeholder, !role.isTitle { bodyIndex += 1; idx = bodyIndex }
                shapes += elementXML(e, ctx: ctx, rels: rels, slideIndex: i, id: &nextID, placeholderIndex: idx)
            }
            shapes += shapesXML(SlideRenderer.footers(for: slide, number: i + 1, presentation: p), ctx: ctx, rels: rels, slideIndex: i, firstID: 900)
            let background = slide.background.map { backgroundXML($0, ctx: ctx, rels: rels) } ?? ""
            let attributes = (slide.hidden ? " show=\"0\"" : "") + (slide.hideBackgroundGraphics ? " showMasterSp=\"0\"" : "")
            var xml = header + "<p:sld \(namespaces)\(attributes)><p:cSld>\(background)<p:spTree>\(groupHeader)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
            xml += transitionXML(slide.transition)
            xml += "</p:sld>"
            if !slide.notes.isEmpty {
                let notesRels = Rels()
                _ = notesRels.add("notesMaster", "../notesMasters/notesMaster1.xml")
                _ = notesRels.add("slide", "../slides/slide\(i + 1).xml")
                _ = rels.add("notesSlide", "../notesSlides/notesSlide\(i + 1).xml")
                let paragraphs = slide.notes.components(separatedBy: "\n").map {
                    "<a:p><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(esc($0))</a:t></a:r></a:p>"
                }.joined()
                let notes = header + "<p:notes \(namespaces)><p:cSld><p:spTree>\(groupHeader)"
                    + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>"
                    + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>"
                    + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
                ctx.entries.append(("ppt/notesSlides/notesSlide\(i + 1).xml", Data(notes.utf8)))
                ctx.entries.append(("ppt/notesSlides/_rels/notesSlide\(i + 1).xml.rels", Data(notesRels.xml.utf8)))
            }
            ctx.entries.append(("ppt/slides/slide\(i + 1).xml", Data(xml.utf8)))
            ctx.entries.append(("ppt/slides/_rels/slide\(i + 1).xml.rels", Data(rels.xml.utf8)))
        }

        // Presentation part.
        let presRels = Rels()
        let masterRID = presRels.add("slideMaster", "slideMasters/slideMaster1.xml")
        var slideIDs = ""
        for i in p.slides.indices {
            let rid = presRels.add("slide", "slides/slide\(i + 1).xml")
            slideIDs += "<p:sldId id=\"\(256 + i)\" r:id=\"\(rid)\"/>"
        }
        var notesMasterList = ""
        if hasNotes {
            let rid = presRels.add("notesMaster", "notesMasters/notesMaster1.xml")
            notesMasterList = "<p:notesMasterIdLst><p:notesMasterId r:id=\"\(rid)\"/></p:notesMasterIdLst>"
        }
        _ = presRels.add("presProps", "presProps.xml")
        _ = presRels.add("viewProps", "viewProps.xml")
        _ = presRels.add("theme", "theme/theme1.xml")
        _ = presRels.add("tableStyles", "tableStyles.xml")
        var sections = ""
        if !p.sections.isEmpty {
            sections = "<p:extLst><p:ext uri=\"{521415D9-36F7-43E2-AB2F-B90AF26B5E84}\"><p14:sectionLst xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\">"
            for (n, section) in p.sections.enumerated() {
                let start = p.slideIndex(section.firstSlideID) ?? 0
                let end = n + 1 < p.sections.count ? (p.slideIndex(p.sections[n + 1].firstSlideID) ?? p.slides.count) : p.slides.count
                let ids = (start..<max(start, end)).map { "<p14:sldId id=\"\(256 + $0)\"/>" }.joined()
                sections += "<p14:section name=\"\(esc(section.name))\" id=\"{\(section.id.uuidString)}\"><p14:sldIdLst>\(ids)</p14:sldIdLst></p14:section>"
            }
            sections += "</p14:sectionLst></p:ext></p:extLst>"
        }
        let presentationXML = header + "<p:presentation \(namespaces) saveSubsetFonts=\"1\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"\(masterRID)\"/></p:sldMasterIdLst>\(notesMasterList)<p:sldIdLst>\(slideIDs)</p:sldIdLst>"
            + "<p:sldSz cx=\"\(emu(p.slideSize.width))\" cy=\"\(emu(p.slideSize.height))\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>\(sections)</p:presentation>"
        ctx.entries.append(("ppt/presentation.xml", Data(presentationXML.utf8)))
        ctx.entries.append(("ppt/_rels/presentation.xml.rels", Data(presRels.xml.utf8)))
        var showPr = ""
        if p.showSettings.loopUntilEscape { showPr = "<p:showPr loop=\"1\" showNarration=\"1\"><p:present/><p:sldAll/><p:penClr><a:prstClr val=\"red\"/></p:penClr></p:showPr>" }
        ctx.entries.append(("ppt/presProps.xml", Data((header + "<p:presentationPr \(namespaces)>\(showPr)</p:presentationPr>").utf8)))
        ctx.entries.append(("ppt/viewProps.xml", Data((header + "<p:viewPr \(namespaces)><p:normalViewPr><p:restoredLeft sz=\"15620\"/><p:restoredTop sz=\"94660\"/></p:normalViewPr><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>").utf8)))
        ctx.entries.append(("ppt/tableStyles.xml", Data((header + "<a:tblStyleLst xmlns:a=\"\(nsA)\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>").utf8)))

        // Document properties.
        let date = ISO8601DateFormatter().string(from: Date())
        let created = ISO8601DateFormatter().string(from: p.created)
        let core = header + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
            + "<dc:title>\(esc(p.title))</dc:title><dc:creator>\(esc(p.author))</dc:creator><cp:lastModifiedBy>\(esc(p.author))</cp:lastModifiedBy>"
            + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(created)</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(date)</dcterms:modified></cp:coreProperties>"
        let app = header + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>Wired Slides</Application><Slides>\(p.slides.count)</Slides><PresentationFormat>Custom</PresentationFormat></Properties>"
        ctx.entries.append(("docProps/core.xml", Data(core.utf8)))
        ctx.entries.append(("docProps/app.xml", Data(app.utf8)))
        let rootRels = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"\(relBase)/officeDocument\" Target=\"ppt/presentation.xml\"/>"
            + "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"
            + "<Relationship Id=\"rId3\" Type=\"\(relBase)/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>"
        ctx.entries.append(("_rels/.rels", Data(rootRels.utf8)))

        // Content types go first.
        var types = header + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        let mimeTypes = ["png": "image/png", "jpeg": "image/jpeg", "jpg": "image/jpeg", "gif": "image/gif", "tiff": "image/tiff", "tif": "image/tiff", "bmp": "image/bmp"]
        for ext in ctx.contentTypes.sorted() { types += "<Default Extension=\"\(ext)\" ContentType=\"\(mimeTypes[ext] ?? "application/octet-stream")\"/>" }
        let ppt = "application/vnd.openxmlformats-officedocument.presentationml"
        types += "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(ppt).presentation.main+xml\"/>"
        types += "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"\(ppt).slideMaster+xml\"/>"
        for i in layouts.indices { types += "<Override PartName=\"/ppt/slideLayouts/slideLayout\(i + 1).xml\" ContentType=\"\(ppt).slideLayout+xml\"/>" }
        for (i, slide) in p.slides.enumerated() {
            types += "<Override PartName=\"/ppt/slides/slide\(i + 1).xml\" ContentType=\"\(ppt).slide+xml\"/>"
            if !slide.notes.isEmpty { types += "<Override PartName=\"/ppt/notesSlides/notesSlide\(i + 1).xml\" ContentType=\"\(ppt).notesSlide+xml\"/>" }
        }
        types += "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        if hasNotes {
            types += "<Override PartName=\"/ppt/theme/theme2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
            types += "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"\(ppt).notesMaster+xml\"/>"
        }
        types += "<Override PartName=\"/ppt/presProps.xml\" ContentType=\"\(ppt).presProps+xml\"/><Override PartName=\"/ppt/viewProps.xml\" ContentType=\"\(ppt).viewProps+xml\"/>"
        types += "<Override PartName=\"/ppt/tableStyles.xml\" ContentType=\"\(ppt).tableStyles+xml\"/>"
        types += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        types += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/></Types>"
        return ZipArchive.write([("[Content_Types].xml", Data(types.utf8))] + ctx.entries)
    }

    static let groupHeader = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    // MARK: Theme

    static func themeXML(_ theme: PresentationTheme, name: String) -> String {
        let c = theme.colors
        func clr(_ tag: String, _ color: RGBColor) -> String { "<a:\(tag)><a:srgbClr val=\"\(color.hexString)\"/></a:\(tag)>" }
        let scheme = clr("dk1", c.dark1) + clr("lt1", c.light1) + clr("dk2", c.dark2) + clr("lt2", c.light2)
            + clr("accent1", c.accent1) + clr("accent2", c.accent2) + clr("accent3", c.accent3) + clr("accent4", c.accent4)
            + clr("accent5", c.accent5) + clr("accent6", c.accent6) + clr("hlink", c.hyperlink) + clr("folHlink", c.followedHyperlink)
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"6350\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln>"
        let fmt = "<a:fmtScheme name=\"Office\"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst><a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme>"
        return header + "<a:theme xmlns:a=\"\(nsA)\" name=\"\(esc(name))\"><a:themeElements><a:clrScheme name=\"\(esc(name))\">\(scheme)</a:clrScheme>"
            + "<a:fontScheme name=\"\(esc(name))\"><a:majorFont><a:latin typeface=\"\(esc(theme.headingFont))\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont>"
            + "<a:minorFont><a:latin typeface=\"\(esc(theme.bodyFont))\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + fmt + "</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }

    static func textStylesXML(_ theme: PresentationTheme) -> String {
        func level(_ n: Int, size: Double, bullet: Bool) -> String {
            let marL = bullet ? emu(Double(n) * 28 + 24) : 0
            let bu = bullet ? "<a:buFont typeface=\"Arial\"/><a:buChar char=\"\(esc(theme.bulletSymbol))\"/>" : "<a:buNone/>"
            return "<a:lvl\(n + 1)pPr marL=\"\(marL)\" indent=\"\(bullet ? -emu(24.0) : 0)\" algn=\"l\">\(bu)<a:defRPr sz=\"\(Int(size * 100))\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl\(n + 1)pPr>"
        }
        let title = "<p:titleStyle><a:lvl1pPr algn=\"l\"><a:buNone/><a:defRPr sz=\"\(Int(theme.titleSize * 100))\"\(theme.titleBold ? " b=\"1\"" : "")><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mj-lt\"/></a:defRPr></a:lvl1pPr></p:titleStyle>"
        let body = "<p:bodyStyle>" + (0..<5).map { level($0, size: max(theme.bodySize - Double($0) * 2, 12), bullet: true) }.joined() + "</p:bodyStyle>"
        let other = "<p:otherStyle>" + level(0, size: 18, bullet: false) + "</p:otherStyle>"
        return "<p:txStyles>\(title)\(body)\(other)</p:txStyles>"
    }

    // MARK: Colors and fills

    static func colorXML(_ color: PaintColor) -> String {
        switch color {
        case .rgb(let c):
            let alpha = c.a < 1 ? "<a:alpha val=\"\(Int(c.a * 100_000))\"/>" : ""
            return alpha.isEmpty ? "<a:srgbClr val=\"\(c.hexString)\"/>" : "<a:srgbClr val=\"\(c.hexString)\">\(alpha)</a:srgbClr>"
        case .theme(let slot, let shade, let alpha):
            let name: String
            switch slot {
            case .dark1: name = "tx1"
            case .light1: name = "bg1"
            case .dark2: name = "tx2"
            case .light2: name = "bg2"
            default: name = slot.ooxmlName
            }
            var mods = ""
            if shade > 0 { mods += "<a:lumMod val=\"\(Int((1 - shade) * 100_000))\"/><a:lumOff val=\"\(Int(shade * 100_000))\"/>" }
            if shade < 0 { mods += "<a:lumMod val=\"\(Int((1 + shade) * 100_000))\"/>" }
            if alpha < 1 { mods += "<a:alpha val=\"\(Int(alpha * 100_000))\"/>" }
            return mods.isEmpty ? "<a:schemeClr val=\"\(name)\"/>" : "<a:schemeClr val=\"\(name)\">\(mods)</a:schemeClr>"
        }
    }

    static func fillXML(_ fill: Fill, ctx: Context, rels: Rels) -> String {
        switch fill {
        case .none:
            return "<a:noFill/>"
        case .solid(let c):
            return "<a:solidFill>\(colorXML(c))</a:solidFill>"
        case .gradient(let g):
            let stops = g.stops.map { "<a:gs pos=\"\(Int($0.position * 100_000))\">\(colorXML($0.color))</a:gs>" }.joined()
            let shade = g.kind == .linear
                ? "<a:lin ang=\"\(Int(g.angle.truncatingRemainder(dividingBy: 360) * 60_000))\" scaled=\"0\"/>"
                : "<a:path path=\"circle\"><a:fillToRect l=\"50000\" t=\"50000\" r=\"50000\" b=\"50000\"/></a:path>"
            return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst>\(shade)</a:gradFill>"
        case .image(let image):
            guard let file = mediaFile(image.mediaID, ctx: ctx) else { return "<a:noFill/>" }
            let rid = rels.add("image", "../media/\(file)")
            let mode = image.mode == .tile ? "<a:tile tx=\"0\" ty=\"0\" sx=\"100000\" sy=\"100000\" flip=\"none\" algn=\"tl\"/>" : "<a:stretch><a:fillRect/></a:stretch>"
            let alpha = image.transparency > 0 ? "<a:alphaModFix amt=\"\(Int((1 - image.transparency) * 100_000))\"/>" : ""
            return "<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(rid)\">\(alpha)</a:blip>\(mode)</a:blipFill>"
        case .pattern(let pattern):
            let preset: String
            switch pattern.kind {
            case .horizontal: preset = "ltHorz"
            case .vertical: preset = "ltVert"
            case .diagonalUp: preset = "ltUpDiag"
            case .diagonalDown: preset = "ltDnDiag"
            case .grid: preset = "smGrid"
            case .dots: preset = "pct10"
            case .checker: preset = "smCheck"
            }
            return "<a:pattFill prst=\"\(preset)\"><a:fgClr>\(colorXML(pattern.foreground))</a:fgClr><a:bgClr>\(colorXML(pattern.background))</a:bgClr></a:pattFill>"
        }
    }

    static func backgroundXML(_ fill: Fill, ctx: Context, rels: Rels) -> String {
        "<p:bg><p:bgPr>\(fillXML(fill, ctx: ctx, rels: rels))<a:effectLst/></p:bgPr></p:bg>"
    }

    static func lineXML(_ line: LineStyle) -> String {
        guard let color = line.color, line.width > 0 else { return "<a:ln><a:noFill/></a:ln>" }
        var s = "<a:ln w=\"\(emu(line.width))\"\(line.roundCaps ? " cap=\"rnd\"" : "")><a:solidFill>\(colorXML(color))</a:solidFill>"
        if line.dash != .solid { s += "<a:prstDash val=\"\(line.dash.ooxml)\"/>" }
        s += "<a:round/>"
        if line.head != .none { s += "<a:headEnd type=\"\(line.head.ooxml)\"/>" }
        if line.tail != .none { s += "<a:tailEnd type=\"\(line.tail.ooxml)\"/>" }
        return s + "</a:ln>"
    }

    static func effectsXML(_ fx: Effects) -> String {
        guard !fx.isEmpty else { return "" }
        var s = "<a:effectLst>"
        if let glow = fx.glow { s += "<a:glow rad=\"\(emu(glow.radius))\">\(colorXML(glow.color))</a:glow>" }
        if let shadow = fx.shadow {
            s += "<a:outerShdw blurRad=\"\(emu(shadow.blur))\" dist=\"\(emu(shadow.distance))\" dir=\"\(Int(shadow.angle * 60_000))\" algn=\"ctr\" rotWithShape=\"0\">"
                + "<a:srgbClr val=\"\(shadow.color.hexString)\"><a:alpha val=\"\(Int(shadow.opacity * 100_000))\"/></a:srgbClr></a:outerShdw>"
        }
        if let r = fx.reflection {
            s += "<a:reflection blurRad=\"6350\" stA=\"\(Int(r.opacity * 100_000))\" endPos=\"\(Int(r.size * 100_000))\" dist=\"\(emu(r.distance))\" dir=\"5400000\" sy=\"-100000\" algn=\"bl\" rotWithShape=\"0\"/>"
        }
        return s + "</a:effectLst>"
    }

    static func xfrmXML(_ e: SlideElement, tag: String = "a:xfrm", children: Bool = false) -> String {
        var attrs = ""
        if e.rotation != 0 { attrs += " rot=\"\(Int(e.rotation.truncatingRemainder(dividingBy: 360) * 60_000))\"" }
        if e.flipH { attrs += " flipH=\"1\"" }
        if e.flipV { attrs += " flipV=\"1\"" }
        let off = "<a:off x=\"\(emu(e.frame.minX))\" y=\"\(emu(e.frame.minY))\"/><a:ext cx=\"\(emu(e.frame.width))\" cy=\"\(emu(e.frame.height))\"/>"
        let child = children ? "<a:chOff x=\"\(emu(e.frame.minX))\" y=\"\(emu(e.frame.minY))\"/><a:chExt cx=\"\(emu(e.frame.width))\" cy=\"\(emu(e.frame.height))\"/>" : ""
        return "<\(tag)\(attrs)>\(off)\(child)</\(tag)>"
    }

    // MARK: Text

    static func textBodyXML(_ body: TextBody, ctx: Context, rels: Rels, tag: String = "p:txBody", isTitle: Bool = false) -> String {
        let anchor = body.anchor == .top ? "t" : body.anchor == .middle ? "ctr" : "b"
        var attrs = " wrap=\"\(body.wrap ? "square" : "none")\" lIns=\"\(emu(body.insets.left))\" tIns=\"\(emu(body.insets.top))\" rIns=\"\(emu(body.insets.right))\" bIns=\"\(emu(body.insets.bottom))\" anchor=\"\(anchor)\" rtlCol=\"0\""
        if body.columns > 1 { attrs += " numCol=\"\(body.columns)\" spcCol=\"\(emu(14.0))\"" }
        if body.direction == .rotated90 { attrs += " vert=\"vert\"" } else if body.direction == .rotated270 { attrs += " vert=\"vert270\"" }
        let fit: String
        switch body.autofit {
        case .none: fit = "<a:noAutofit/>"
        case .shrink: fit = "<a:normAutofit/>"
        case .resizeShape: fit = "<a:spAutoFit/>"
        }
        var s = "<\(tag)><a:bodyPr\(attrs)>\(fit)</a:bodyPr><a:lstStyle/>"
        for paragraph in body.paragraphs {
            s += paragraphXML(paragraph, body: body, ctx: ctx, rels: rels)
        }
        return s + "</\(tag)>"
    }

    static func paragraphXML(_ paragraph: Paragraph, body: TextBody, ctx: Context, rels: Rels) -> String {
        let st = paragraph.style
        let algn: String
        switch st.alignment {
        case .left: algn = "l"
        case .center: algn = "ctr"
        case .right: algn = "r"
        case .justify: algn = "just"
        }
        let hasBullet = !st.bullet.isNone
        let unit = max(body.defaultSize / 24, 0.6)
        let marL = emu((Double(st.level) * 28 + (hasBullet ? 24 : 0)) * unit)
        var p = "<a:p><a:pPr marL=\"\(marL)\" lvl=\"\(st.level)\" indent=\"\(hasBullet ? -emu(24 * unit) : 0)\" algn=\"\(algn)\">"
        p += "<a:lnSpc><a:spcPct val=\"\(Int(st.lineSpacing * 100_000))\"/></a:lnSpc>"
        p += "<a:spcBef><a:spcPts val=\"\(Int(st.spaceBefore * 100))\"/></a:spcBef><a:spcAft><a:spcPts val=\"\(Int(st.spaceAfter * 100))\"/></a:spcAft>"
        if let bc = st.bulletColor, hasBullet { p += "<a:buClr>\(colorXML(bc))</a:buClr>" }
        switch st.bullet {
        case .none: p += "<a:buNone/>"
        case .symbol(let symbol): p += "<a:buFont typeface=\"Arial\"/><a:buChar char=\"\(esc(symbol))\"/>"
        case .numbered(let scheme, let start): p += "<a:buFont typeface=\"+mj-lt\"/><a:buAutoNum type=\"\(scheme.ooxml)\"\(start != 1 ? " startAt=\"\(start)\"" : "")/>"
        }
        p += "</a:pPr>"
        for run in paragraph.runs where !run.text.isEmpty {
            // Line breaks inside a run become <a:br/>.
            let pieces = run.text.components(separatedBy: "\u{2028}")
            for (i, piece) in pieces.enumerated() {
                if i > 0 { p += "<a:br>\(runPropertiesXML(run.style, body: body, ctx: ctx, rels: rels))</a:br>" }
                p += "<a:r>\(runPropertiesXML(run.style, body: body, ctx: ctx, rels: rels))<a:t>\(esc(piece))</a:t></a:r>"
            }
        }
        let end = paragraph.runs.last?.style ?? .plain
        p += "<a:endParaRPr lang=\"en-US\" sz=\"\(Int((end.size ?? body.defaultSize) * 100))\" dirty=\"0\"/></a:p>"
        return p
    }

    static func runPropertiesXML(_ st: RunStyle, body: TextBody, ctx: Context, rels: Rels) -> String {
        var attrs = " lang=\"en-US\" sz=\"\(Int(((st.size ?? body.defaultSize) * 100).rounded()))\""
        if st.bold == true { attrs += " b=\"1\"" } else if st.bold == false { attrs += " b=\"0\"" }
        if st.italic == true { attrs += " i=\"1\"" }
        if st.underline || st.link != nil { attrs += " u=\"sng\"" }
        if st.strikethrough { attrs += " strike=\"sngStrike\"" }
        if st.baseline != 0 { attrs += " baseline=\"\(st.baseline > 0 ? 30000 : -25000)\"" }
        if st.allCaps { attrs += " cap=\"all\"" } else if st.smallCaps { attrs += " cap=\"small\"" }
        if st.characterSpacing != 0 { attrs += " spc=\"\(Int(st.characterSpacing * 100))\"" }
        attrs += " dirty=\"0\""
        var s = "<a:rPr\(attrs)>"
        if let outline = st.outlineColor, st.outlineWidth > 0 {
            s += "<a:ln w=\"\(emu(st.outlineWidth))\"><a:solidFill>\(colorXML(outline))</a:solidFill></a:ln>"
        }
        s += "<a:solidFill>\(colorXML(st.color ?? (st.link != nil ? .theme(.hyperlink) : body.defaultColor)))</a:solidFill>"
        if st.shadow {
            s += "<a:effectLst><a:outerShdw blurRad=\"38100\" dist=\"38100\" dir=\"2700000\" algn=\"tl\"><a:srgbClr val=\"000000\"><a:alpha val=\"43137\"/></a:srgbClr></a:outerShdw></a:effectLst>"
        }
        if let highlight = st.highlight { s += "<a:highlight><a:srgbClr val=\"\(highlight.hexString)\"/></a:highlight>" }
        let typeface = st.fontFamily ?? (body.fontRole == .heading ? "+mj-lt" : "+mn-lt")
        s += "<a:latin typeface=\"\(esc(typeface))\"/>"
        if let link = st.link {
            let rid = rels.add("hyperlink", link, external: true)
            s += "<a:hlinkClick r:id=\"\(rid)\"/>"
        }
        return s + "</a:rPr>"
    }

    // MARK: Elements

    static func placeholderShape(_ role: PlaceholderRole, id: Int, rect: CGRect, idx: Int?, prompt: String? = nil) -> String {
        let idxAttr = idx.map { " idx=\"\($0)\"" } ?? ""
        let promptXML = prompt.map { "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\(esc($0))</a:t></a:r></a:p>" } ?? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>"
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(role.isTitle ? "Title" : "Placeholder") \(id)\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"\(role.ooxml)\"\(idxAttr)/></p:nvPr></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"\(emu(rect.minX))\" y=\"\(emu(rect.minY))\"/><a:ext cx=\"\(emu(rect.width))\" cy=\"\(emu(rect.height))\"/></a:xfrm></p:spPr>"
            + "<p:txBody><a:bodyPr/><a:lstStyle/>\(promptXML)</p:txBody></p:sp>"
    }

    static func shapesXML(_ elements: [SlideElement], ctx: Context, rels: Rels, slideIndex: Int?, firstID: Int) -> String {
        var id = firstID
        return elements.map { elementXML($0, ctx: ctx, rels: rels, slideIndex: slideIndex, id: &id, placeholderIndex: nil) }.joined()
    }

    static func actionXML(_ e: SlideElement, ctx: Context, rels: Rels) -> String {
        guard let action = e.action else { return "" }
        switch action {
        case .url(let url):
            return "<a:hlinkClick r:id=\"\(rels.add("hyperlink", url, external: true))\"/>"
        case .slide(let target):
            guard let index = ctx.presentation.slideIndex(target) else { return "" }
            return "<a:hlinkClick r:id=\"\(rels.add("slide", "slide\(index + 1).xml"))\" action=\"ppaction://hlinksldjump\"/>"
        case .nextSlide: return "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=nextslide\"/>"
        case .previousSlide: return "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=previousslide\"/>"
        case .firstSlide: return "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=firstslide\"/>"
        case .lastSlide: return "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=lastslide\"/>"
        case .endShow: return "<a:hlinkClick r:id=\"\" action=\"ppaction://hlinkshowjump?jump=endshow\"/>"
        }
    }

    static func cNvPr(_ e: SlideElement, id: Int, ctx: Context, rels: Rels) -> String {
        let descr = e.altText.isEmpty ? "" : " descr=\"\(esc(e.altText))\""
        let hidden = e.hidden ? " hidden=\"1\"" : ""
        let action = actionXML(e, ctx: ctx, rels: rels)
        return action.isEmpty
            ? "<p:cNvPr id=\"\(id)\" name=\"\(esc(e.name))\"\(descr)\(hidden)/>"
            : "<p:cNvPr id=\"\(id)\" name=\"\(esc(e.name))\"\(descr)\(hidden)>\(action)</p:cNvPr>"
    }

    static func mediaFile(_ mediaID: String, ctx: Context) -> String? {
        guard let item = ctx.presentation.media[mediaID] else { return nil }
        var ext = (item.filename as NSString).pathExtension.lowercased()
        var data = item.data
        if !["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp"].contains(ext) {
            // Convert anything else (HEIC, PDF, SVG, WebP…) to PNG.
            guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
            data = png
            ext = "png"
        }
        if ext == "jpg" { ext = "jpeg" }
        if ext == "tif" { ext = "tiff" }
        return ctx.addMedia(data, ext: ext, key: mediaID)
    }

    static func pictureXML(_ e: SlideElement, file: String, crop: CropInsets = CropInsets(), adjustments: ImageAdjustments = ImageAdjustments(),
                           line: LineStyle = .none, effects: Effects = .none, mask: ShapeKind? = nil, id: Int, ctx: Context, rels: Rels) -> String {
        let rid = rels.add("image", "../media/\(file)")
        var blip = ""
        if adjustments.saturation == 0 { blip += "<a:grayscl/>" }
        if adjustments.brightness != 0 || adjustments.contrast != 0 {
            blip += "<a:lum bright=\"\(Int(adjustments.brightness * 50_000))\" contrast=\"\(Int(adjustments.contrast * 100_000))\"/>"
        }
        if adjustments.transparency > 0 { blip = "<a:alphaModFix amt=\"\(Int((1 - adjustments.transparency) * 100_000))\"/>" + blip }
        let src = crop.isZero ? "" : "<a:srcRect l=\"\(Int(crop.left * 100_000))\" t=\"\(Int(crop.top * 100_000))\" r=\"\(Int(crop.right * 100_000))\" b=\"\(Int(crop.bottom * 100_000))\"/>"
        return "<p:pic><p:nvPicPr>\(cNvPr(e, id: id, ctx: ctx, rels: rels))<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"\(rid)\">\(blip)</a:blip>\(src)<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
            + "<p:spPr>\(xfrmXML(e))<a:prstGeom prst=\"\(mask?.ooxml ?? "rect")\"><a:avLst/></a:prstGeom>\(line.isVisible ? lineXML(line) : "")\(effectsXML(effects))</p:spPr></p:pic>"
    }

    /// Renders an element to a PNG picture (charts, icons).
    static func renderedPictureXML(_ e: SlideElement, id: Int, ctx: Context, rels: Rels) -> String {
        var flat = e
        flat.rotation = 0
        guard let cg = SlideRenderer.elementImage(flat, presentation: ctx.presentation, scale: 3),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return "" }
        let bounds = SlideRenderer.visualBounds(flat)
        let file = ctx.addMedia(png, ext: "png", key: "render-\(e.id)-\(e.hashValue)")
        var placed = e
        placed.frame = bounds
        placed.flipH = false
        placed.flipV = false
        return pictureXML(placed, file: file, id: id, ctx: ctx, rels: rels)
    }

    static func elementXML(_ e: SlideElement, ctx: Context, rels: Rels, slideIndex: Int?, id: inout Int, placeholderIndex: Int?) -> String {
        let myID = id
        id += 1
        switch e.content {
        case .shape(let s):
            var nvPr = "<p:nvPr/>"
            if let role = e.placeholder, role != .picture {
                nvPr = "<p:nvPr><p:ph type=\"\(role.ooxml)\"\(placeholderIndex.map { " idx=\"\($0)\"" } ?? "")/></p:nvPr>"
            }
            let isTextBox = s.fill.isNone && !s.line.isVisible && e.placeholder == nil
            var adj = ""
            if !s.adjustments.isEmpty, !s.kind.isCallout {
                let names = s.adjustments.count == 1 ? ["adj"] : (1...s.adjustments.count).map { "adj\($0)" }
                // Stars store the inner radius out of 50000; pies store angles in 60000ths of a degree.
                let factor: Double
                switch s.kind {
                case .star4, .star5, .star6, .star8, .star12, .star24: factor = 50_000
                case .pie, .chord: factor = 60_000
                default: factor = 100_000
                }
                for (name, value) in zip(names, s.adjustments) { adj += "<a:gd name=\"\(name)\" fmla=\"val \(Int(value * factor))\"/>" }
            }
            var xml = "<p:sp><p:nvSpPr>\(cNvPr(e, id: myID, ctx: ctx, rels: rels))<p:cNvSpPr\(isTextBox ? " txBox=\"1\"" : "")/>\(nvPr)</p:nvSpPr>"
            xml += "<p:spPr>\(xfrmXML(e))<a:prstGeom prst=\"\(s.kind.ooxml)\"><a:avLst>\(adj)</a:avLst></a:prstGeom>\(fillXML(s.fill, ctx: ctx, rels: rels))\(lineXML(s.line))\(effectsXML(s.effects))</p:spPr>"
            xml += textBodyXML(s.text, ctx: ctx, rels: rels)
            return xml + "</p:sp>"
        case .image(let image):
            guard let file = mediaFile(image.mediaID, ctx: ctx) else { return "" }
            return pictureXML(e, file: file, crop: image.crop, adjustments: image.adjustments, line: image.line, effects: image.effects,
                              mask: image.maskShape, id: myID, ctx: ctx, rels: rels)
        case .line(let line):
            return "<p:cxnSp><p:nvCxnSpPr>\(cNvPr(e, id: myID, ctx: ctx, rels: rels))<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(xfrmXML(e))<a:prstGeom prst=\"\(line.kind.ooxml)\"><a:avLst/></a:prstGeom>\(lineXML(line.line))\(effectsXML(line.effects))</p:spPr></p:cxnSp>"
        case .table(let table):
            return tableXML(e, table, id: myID, ctx: ctx, rels: rels)
        case .chart, .icon:
            return renderedPictureXML(e, id: myID, ctx: ctx, rels: rels)
        case .media(let media):
            if let poster = media.posterID, let file = mediaFile(poster, ctx: ctx) {
                return pictureXML(e, file: file, id: myID, ctx: ctx, rels: rels)
            }
            return renderedPictureXML(e, id: myID, ctx: ctx, rels: rels)
        case .group(let group):
            var xml = "<p:grpSp><p:nvGrpSpPr>\(cNvPr(e, id: myID, ctx: ctx, rels: rels))<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>\(xfrmXML(e, children: true))</p:grpSpPr>"
            for child in group.children { xml += elementXML(child, ctx: ctx, rels: rels, slideIndex: slideIndex, id: &id, placeholderIndex: nil) }
            return xml + "</p:grpSp>"
        }
    }

    static func tableXML(_ e: SlideElement, _ table: TableContent, id: Int, ctx: Context, rels: Rels) -> String {
        let colors = ctx.presentation.theme.colors
        let totalW = max(table.columnWidths.reduce(0, +), 1)
        var xml = "<p:graphicFrame><p:nvGraphicFramePr>\(cNvPr(e, id: id, ctx: ctx, rels: rels))<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
        xml += "<p:xfrm><a:off x=\"\(emu(e.frame.minX))\" y=\"\(emu(e.frame.minY))\"/><a:ext cx=\"\(emu(e.frame.width))\" cy=\"\(emu(e.frame.height))\"/></p:xfrm>"
        let s = table.style
        xml += "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"\(s.headerRow ? 1 : 0)\" bandRow=\"\(s.bandedRows ? 1 : 0)\" lastRow=\"\(s.totalRow ? 1 : 0)\" firstCol=\"\(s.firstColumn ? 1 : 0)\"/><a:tblGrid>"
        for w in table.columnWidths { xml += "<a:gridCol w=\"\(emu(w / totalW * Double(e.frame.width)))\"/>" }
        xml += "</a:tblGrid>"
        let borderColor = s.borderColor ?? (s.intensity == 1 ? s.color : .white)
        let border = "<a:solidFill>\(colorXML(borderColor))</a:solidFill>"
        let lineW = emu(s.borderColor != nil ? s.borderWidth : 1)
        for row in 0..<table.rowCount {
            xml += "<a:tr h=\"\(emu(table.rowHeights[row]))\">"
            for column in 0..<table.columnCount {
                let cell = table.rows[row][column]
                var attrs = ""
                if cell.columnSpan > 1 { attrs += " gridSpan=\"\(cell.columnSpan)\"" }
                if cell.rowSpan > 1 { attrs += " rowSpan=\"\(cell.rowSpan)\"" }
                if cell.isMerged {
                    // Covered cells: horizontal or vertical merge continuation.
                    let coveredHorizontally = (0..<column).contains { c in
                        let o = table.rows[row][c]; return !o.isMerged && c + o.columnSpan > column && o.rowSpan >= 1
                    }
                    attrs += coveredHorizontally ? " hMerge=\"1\"" : " vMerge=\"1\""
                }
                let look = TableRenderer.cellAppearance(table, row: row, column: column, colors: colors)
                var body = cell.text
                if let text = look.text { body.defaultColor = text }
                if look.bold { body.updateRuns { if $0.bold == nil { $0.bold = true } } }
                xml += "<a:tc\(attrs)>\(textBodyXML(body, ctx: ctx, rels: rels, tag: "a:txBody"))"
                let anchor = cell.text.anchor == .top ? "t" : cell.text.anchor == .middle ? "ctr" : "b"
                xml += "<a:tcPr marL=\"\(emu(cell.text.insets.left))\" marR=\"\(emu(cell.text.insets.right))\" marT=\"\(emu(cell.text.insets.top))\" marB=\"\(emu(cell.text.insets.bottom))\" anchor=\"\(anchor)\">"
                for side in ["lnL", "lnR", "lnT", "lnB"] { xml += "<a:\(side) w=\"\(lineW)\">\(border)</a:\(side)>" }
                if let fill = cell.fill {
                    xml += fillXML(fill, ctx: ctx, rels: rels)
                } else if let color = look.fill {
                    xml += "<a:solidFill><a:srgbClr val=\"\(color.hexString)\"/></a:solidFill>"
                } else {
                    xml += "<a:noFill/>"
                }
                xml += "</a:tcPr></a:tc>"
            }
            xml += "</a:tr>"
        }
        return xml + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
    }

    static func transitionXML(_ t: Transition) -> String {
        guard t.kind != .none || !t.advanceOnClick || t.advanceAfter != nil else { return "" }
        let speed = t.duration < 0.6 ? "fast" : t.duration < 1.2 ? "med" : "slow"
        var attrs = " spd=\"\(speed)\""
        if !t.advanceOnClick { attrs += " advClick=\"0\"" }
        if let after = t.advanceAfter { attrs += " advTm=\"\(Int(after * 1000))\"" }
        let dir = t.direction.ooxml
        let effect: String
        switch t.kind {
        case .none, .morph: effect = ""
        case .fade: effect = "<p:fade/>"
        case .fadeThroughBlack: effect = "<p:fade thruBlk=\"1\"/>"
        case .push, .flip, .cube: effect = "<p:push dir=\"\(dir)\"/>"
        case .wipe: effect = "<p:wipe dir=\"\(dir)\"/>"
        case .split: effect = "<p:split orient=\"vert\" dir=\"out\"/>"
        case .reveal, .cover: effect = "<p:cover dir=\"\(dir)\"/>"
        case .uncover: effect = "<p:pull dir=\"\(dir)\"/>"
        case .zoom: effect = "<p:zoom/>"
        case .circle: effect = "<p:circle/>"
        case .dissolve: effect = "<p:dissolve/>"
        case .blinds: effect = "<p:blinds dir=\"vert\"/>"
        }
        return "<p:transition\(attrs)>\(effect)</p:transition>"
    }
}

import AppKit

/// A light wrapper over XMLElement that matches by local name, ignoring namespace prefixes.
struct XNode {
    let element: XMLElement

    var name: String { element.localName ?? element.name ?? "" }

    var children: [XNode] { (element.children ?? []).compactMap { ($0 as? XMLElement).map(XNode.init) } }

    func child(_ name: String) -> XNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XNode] { children.filter { $0.name == name } }

    func path(_ names: String...) -> XNode? {
        var node: XNode? = self
        for n in names { node = node?.child(n) }
        return node
    }

    func attr(_ name: String) -> String? {
        for a in element.attributes ?? [] where (a.localName ?? a.name) == name { return a.stringValue }
        return nil
    }

    func int(_ name: String) -> Int? { attr(name).flatMap { Int($0) } }

    /// The `r:id` attribute (elements like `p:sldId` also have a plain `id`).
    var relationshipID: String? {
        (element.attributes ?? []).first { $0.name == "r:id" || ($0.localName == "id" && $0.uri == PPTXWriter.nsR) }?.stringValue
    }
    func double(_ name: String) -> Double? { attr(name).flatMap { Double($0) } }
    func bool(_ name: String) -> Bool? { attr(name).map { $0 == "1" || $0 == "true" } }

    var text: String { element.stringValue ?? "" }

    /// All descendants with a name, depth-first.
    func descendants(_ name: String) -> [XNode] {
        var result: [XNode] = []
        for c in children {
            if c.name == name { result.append(c) }
            result += c.descendants(name)
        }
        return result
    }

    /// Children, with `mc:AlternateContent` replaced by its fallback (or first choice).
    var resolvedChildren: [XNode] {
        children.flatMap { c -> [XNode] in
            guard c.name == "AlternateContent" else { return [c] }
            let branch = c.child("Fallback") ?? c.child("Choice")
            return branch?.resolvedChildren ?? []
        }
    }

    static func parse(_ data: Data) -> XNode? {
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]), let root = document.rootElement() else { return nil }
        return XNode(element: root)
    }
}

/// Reads PowerPoint (.pptx) files.
enum PPTXReader {
    static func pt(_ emu: Int?) -> CGFloat { CGFloat(emu ?? 0) / 12700 }
    static func pt(_ emu: String?) -> CGFloat { pt(emu.flatMap { Int($0) }) }

    /// Inherited placeholder properties from layouts and masters.
    struct PlaceholderInfo {
        var frame: CGRect?
        var anchor: VerticalAnchor?
        var size: Double?
        var bold: Bool?
        var alignment: TextAlignment?
        var color: PaintColor?
        var insets: EdgeInsetsValue?
        var bullets: Bool?
    }

    final class Reader {
        let entries: [String: Data]
        var presentation: Presentation
        var mediaByPath: [String: String] = [:]
        var colors: ThemeColors
        var headingFont = "Calibri Light"
        var bodyFont = "Calibri"
        var titleSize: Double = 44
        var bodySizes: [Double] = [28, 24, 20, 18, 18, 18, 18, 18, 18]
        var otherSize: Double = 18

        init(_ entries: [String: Data]) {
            self.entries = entries
            colors = ColorSchemes.all[1].colors
            presentation = Presentation(theme: ThemeLibrary.clean, slides: [Slide(layout: .blank)])
        }

        func xml(_ path: String) -> XNode? { entries[path].flatMap(XNode.parse) }

        /// Relationship id → absolute part path (or external URL).
        func rels(for part: String) -> [String: (target: String, type: String, external: Bool)] {
            let dir = (part as NSString).deletingLastPathComponent
            let relsPath = dir + "/_rels/" + (part as NSString).lastPathComponent + ".rels"
            guard let root = xml(relsPath) else { return [:] }
            var result: [String: (String, String, Bool)] = [:]
            for r in root.children("Relationship") {
                guard let id = r.attr("Id"), let target = r.attr("Target") else { continue }
                let external = r.attr("TargetMode") == "External"
                let type = (r.attr("Type") ?? "").components(separatedBy: "/").last ?? ""
                result[id] = (external ? target : resolve(target, from: dir), type, external)
            }
            return result
        }

        func resolve(_ target: String, from dir: String) -> String {
            if target.hasPrefix("/") { return String(target.dropFirst()) }
            var parts = dir.isEmpty ? [] : dir.components(separatedBy: "/")
            for piece in target.components(separatedBy: "/") {
                if piece == ".." { if !parts.isEmpty { parts.removeLast() } } else if piece != "." { parts.append(piece) }
            }
            return parts.joined(separator: "/")
        }

        // MARK: Colors

        func color(in node: XNode?) -> PaintColor? {
            guard let node else { return nil }
            for c in node.children {
                var base: PaintColor?
                switch c.name {
                case "srgbClr":
                    if let v = c.attr("val"), let rgb = RGBColor(hexString: v) { base = .rgb(rgb) }
                case "schemeClr":
                    if let slot = ThemeSlot.fromOOXML(c.attr("val") ?? "") { base = .theme(slot, shade: 0, alpha: 1) }
                case "sysClr":
                    if let v = c.attr("lastClr"), let rgb = RGBColor(hexString: v) { base = .rgb(rgb) }
                    else { base = .rgb(c.attr("val") == "window" ? .white : .black) }
                case "prstClr":
                    let named: [String: UInt32] = ["black": 0, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
                                                   "yellow": 0xFFFF00, "gray": 0x808080, "orange": 0xFFA500]
                    base = .rgb(RGBColor(hex: named[c.attr("val") ?? ""] ?? 0))
                case "scrgbClr":
                    base = .rgb(RGBColor(r: (c.double("r") ?? 0) / 100_000, g: (c.double("g") ?? 0) / 100_000, b: (c.double("b") ?? 0) / 100_000))
                default:
                    continue
                }
                guard var result = base else { continue }
                var shade = 0.0, alpha = 1.0
                if let lumMod = c.child("lumMod")?.double("val") {
                    let off = c.child("lumOff")?.double("val") ?? 0
                    shade = off > 0 ? off / 100_000 : lumMod / 100_000 - 1
                }
                if let tint = c.child("tint")?.double("val") { shade = 1 - tint / 100_000 }
                if let s = c.child("shade")?.double("val") { shade = s / 100_000 - 1 }
                if let a = c.child("alpha")?.double("val") { alpha = a / 100_000 }
                switch result {
                case .rgb(let rgb): result = .rgb(rgb.shaded(shade).withAlpha(alpha))
                case .theme(let slot, _, _): result = .theme(slot, shade: shade, alpha: alpha)
                }
                return result
            }
            return nil
        }

        func fill(in parent: XNode?, part: String) -> Fill? {
            guard let parent else { return nil }
            for c in parent.children {
                switch c.name {
                case "noFill": return Fill.none
                case "solidFill": return color(in: c).map { .solid($0) } ?? .none
                case "gradFill":
                    let stops = (c.child("gsLst")?.children("gs") ?? []).compactMap { gs -> GradientStop? in
                        guard let col = color(in: gs) else { return nil }
                        return GradientStop(color: col, position: (gs.double("pos") ?? 0) / 100_000)
                    }
                    guard !stops.isEmpty else { return Fill.none }
                    var g = GradientFill(stops: stops)
                    if let lin = c.child("lin") { g.angle = (lin.double("ang") ?? 5_400_000) / 60_000 } else if c.child("path") != nil { g.kind = .radial }
                    return .gradient(g)
                case "blipFill":
                    if let id = mediaID(c.child("blip"), part: part) {
                        return .image(ImageFill(mediaID: id, mode: c.child("tile") != nil ? .tile : .stretch))
                    }
                case "pattFill":
                    let fg = color(in: c.child("fgClr")) ?? .black
                    let bg = color(in: c.child("bgClr")) ?? .white
                    let prst = c.attr("prst") ?? ""
                    let kind: PatternKind = prst.contains("Horz") ? .horizontal : prst.contains("Vert") ? .vertical
                        : prst.contains("UpDiag") ? .diagonalUp : prst.contains("DnDiag") ? .diagonalDown
                        : prst.contains("Grid") || prst.contains("cross") ? .grid : prst.contains("Check") ? .checker : .dots
                    return .pattern(PatternFill(kind: kind, foreground: fg, background: bg))
                case "grpFill":
                    return nil
                default:
                    continue
                }
            }
            return nil
        }

        func mediaID(_ blip: XNode?, part: String) -> String? {
            guard let blip, let rid = blip.attr("embed") ?? blip.attr("link"), let target = rels(for: part)[rid], !target.external else { return nil }
            if let existing = mediaByPath[target.target] { return existing }
            guard let data = entries[target.target] else { return nil }
            let id = presentation.addMedia(data, filename: (target.target as NSString).lastPathComponent)
            mediaByPath[target.target] = id
            return id
        }

        func line(_ ln: XNode?) -> LineStyle? {
            guard let ln else { return nil }
            if ln.child("noFill") != nil { return LineStyle.none }
            var style = LineStyle(color: color(in: ln.child("solidFill")) ?? (ln.child("solidFill") != nil ? .black : nil))
            if style.color == nil && ln.int("w") != nil && ln.child("gradFill") == nil { return nil }
            style.width = ln.int("w").map { Double(pt($0)) } ?? 0.75
            if let dash = ln.child("prstDash")?.attr("val") { style.dash = DashStyle.fromOOXML(dash) }
            if let head = ln.child("headEnd")?.attr("type") { style.head = ArrowHead.fromOOXML(head) }
            if let tail = ln.child("tailEnd")?.attr("type") { style.tail = ArrowHead.fromOOXML(tail) }
            style.roundCaps = ln.attr("cap") == "rnd"
            return style
        }

        func effects(_ list: XNode?) -> Effects {
            var fx = Effects()
            guard let list else { return fx }
            if let s = list.child("outerShdw") {
                var shadow = ShadowEffect()
                shadow.blur = Double(pt(s.int("blurRad")))
                shadow.distance = Double(pt(s.int("dist")))
                shadow.angle = (s.double("dir") ?? 2_700_000) / 60_000
                if let c = color(in: s) {
                    shadow.color = c.resolve(colors).withAlpha(1)
                    shadow.opacity = c.alpha
                }
                fx.shadow = shadow
            }
            if let g = list.child("glow") {
                fx.glow = GlowEffect(color: color(in: g) ?? .theme(.accent1, shade: 0, alpha: 0.6), radius: Double(pt(g.int("rad"))))
            }
            if let r = list.child("reflection") {
                fx.reflection = ReflectionEffect(opacity: (r.double("stA") ?? 50_000) / 100_000, size: (r.double("endPos") ?? 40_000) / 100_000,
                                                 distance: Double(pt(r.int("dist"))))
            }
            return fx
        }

        // MARK: Theme and master

        func readTheme(_ path: String) {
            guard let theme = xml(path), let elements = theme.child("themeElements") else { return }
            if let scheme = elements.child("clrScheme") {
                func c(_ name: String, _ fallback: RGBColor) -> RGBColor {
                    color(in: scheme.child(name))?.resolve(colors) ?? fallback
                }
                colors = ThemeColors(dark1: c("dk1", .black), light1: c("lt1", .white), dark2: c("dk2", RGBColor(hex: 0x44546A)),
                                     light2: c("lt2", RGBColor(hex: 0xE7E6E6)),
                                     accents: (1...6).map { c("accent\($0)", colors.accents[$0 - 1]) },
                                     hyperlink: c("hlink", colors.hyperlink), followedHyperlink: c("folHlink", colors.followedHyperlink))
            }
            if let fonts = elements.child("fontScheme") {
                if let major = fonts.path("majorFont", "latin")?.attr("typeface"), !major.isEmpty { headingFont = major }
                if let minor = fonts.path("minorFont", "latin")?.attr("typeface"), !minor.isEmpty { bodyFont = minor }
            }
        }

        func readMasterStyles(_ master: XNode) {
            guard let styles = master.child("txStyles") else { return }
            if let sz = styles.path("titleStyle", "lvl1pPr", "defRPr")?.double("sz") { titleSize = sz / 100 }
            if let body = styles.child("bodyStyle") {
                for i in 0..<9 { if let sz = body.path("lvl\(i + 1)pPr", "defRPr")?.double("sz") { bodySizes[i] = sz / 100 } }
            }
            if let sz = styles.path("otherStyle", "lvl1pPr", "defRPr")?.double("sz") { otherSize = sz / 100 }
        }

        /// Placeholders of a layout or master, keyed by "type" and "idx:n".
        func placeholders(in root: XNode?) -> [String: PlaceholderInfo] {
            guard let tree = root?.path("cSld", "spTree") else { return [:] }
            var result: [String: PlaceholderInfo] = [:]
            for sp in tree.descendants("sp") {
                guard let ph = sp.path("nvSpPr", "nvPr", "ph") else { continue }
                var info = PlaceholderInfo()
                if let xfrm = sp.path("spPr", "xfrm"), let off = xfrm.child("off"), let ext = xfrm.child("ext") {
                    info.frame = CGRect(x: pt(off.int("x")), y: pt(off.int("y")), width: pt(ext.int("cx")), height: pt(ext.int("cy")))
                }
                if let body = sp.path("txBody", "bodyPr") {
                    info.anchor = anchor(body.attr("anchor"))
                    if body.attr("lIns") != nil { info.insets = insets(body) }
                }
                if let lvl = sp.path("txBody", "lstStyle", "lvl1pPr") {
                    if let sz = lvl.child("defRPr")?.double("sz") { info.size = sz / 100 }
                    info.bold = lvl.child("defRPr")?.bool("b")
                    info.alignment = alignment(lvl.attr("algn"))
                    info.color = color(in: lvl.path("defRPr", "solidFill"))
                    if lvl.child("buNone") != nil { info.bullets = false }
                }
                let type = ph.attr("type") ?? "body"
                if let idx = ph.attr("idx") { result["idx:\(idx)"] = info }
                if result[type] == nil { result[type] = info }
            }
            return result
        }

        func anchor(_ value: String?) -> VerticalAnchor? {
            switch value {
            case "t": .top
            case "ctr": .middle
            case "b": .bottom
            default: nil
            }
        }

        func alignment(_ value: String?) -> TextAlignment? {
            switch value {
            case "l": .left
            case "ctr": .center
            case "r": .right
            case "just", "dist": .justify
            default: nil
            }
        }

        func insets(_ body: XNode) -> EdgeInsetsValue {
            EdgeInsetsValue(top: body.attr("tIns").map { Double(pt($0)) } ?? 3.6, left: body.attr("lIns").map { Double(pt($0)) } ?? 7.2,
                            bottom: body.attr("bIns").map { Double(pt($0)) } ?? 3.6, right: body.attr("rIns").map { Double(pt($0)) } ?? 7.2)
        }

        // MARK: Text

        func textBody(_ node: XNode?, part: String, role: PlaceholderRole?, inherited: PlaceholderInfo?) -> TextBody {
            var body = TextBody()
            let isTitle = role?.isTitle == true
            body.fontRole = isTitle ? .heading : .body
            body.defaultSize = inherited?.size ?? (isTitle ? titleSize : role != nil ? bodySizes[0] : otherSize)
            if let c = inherited?.color { body.defaultColor = c }
            body.anchor = inherited?.anchor ?? (isTitle ? .middle : .top)
            if let i = inherited?.insets { body.insets = i }
            guard let node else { return body }
            if let pr = node.child("bodyPr") {
                if let a = anchor(pr.attr("anchor")) { body.anchor = a }
                if pr.attr("lIns") != nil || pr.attr("tIns") != nil { body.insets = insets(pr) }
                body.wrap = pr.attr("wrap") != "none"
                body.columns = max(1, pr.int("numCol") ?? 1)
                if pr.attr("vert") == "vert" || pr.attr("vert") == "eaVert" { body.direction = .rotated90 }
                if pr.attr("vert") == "vert270" { body.direction = .rotated270 }
                if pr.child("normAutofit") != nil { body.autofit = .shrink }
                if pr.child("spAutoFit") != nil { body.autofit = .resizeShape }
            }
            var paragraphs: [Paragraph] = []
            for p in node.children("p") {
                var style = ParagraphStyle()
                let pPr = p.child("pPr")
                style.level = pPr?.int("lvl") ?? 0
                style.alignment = alignment(pPr?.attr("algn")) ?? inherited?.alignment ?? .left
                if let pct = pPr?.path("lnSpc", "spcPct")?.double("val") { style.lineSpacing = pct / 100_000 }
                if let before = pPr?.path("spcBef", "spcPts")?.double("val") { style.spaceBefore = before / 100 }
                if let after = pPr?.path("spcAft", "spcPts")?.double("val") { style.spaceAfter = after / 100 }
                if let char = pPr?.child("buChar")?.attr("char") {
                    style.bullet = .symbol(char)
                } else if let auto = pPr?.child("buAutoNum") {
                    style.bullet = .numbered(NumberingScheme.fromOOXML(auto.attr("type") ?? ""), start: auto.int("startAt") ?? 1)
                } else if pPr?.child("buNone") == nil, role == .body, inherited?.bullets != false {
                    style.bullet = .symbol("•")
                }
                if let bc = color(in: pPr?.child("buClr")) { style.bulletColor = bc }
                let levelSize = role == .body && !isTitle ? bodySizes[min(style.level, 8)] : nil
                var runs: [TextRun] = []
                for r in p.children {
                    switch r.name {
                    case "r", "fld":
                        var rs = runStyle(r.child("rPr"), part: part, inheritedBold: inherited?.bold)
                        if rs.size == nil, let levelSize, levelSize != body.defaultSize, inherited?.size == nil { rs.size = levelSize }
                        runs.append(TextRun(text: r.child("t")?.text ?? "", style: rs))
                    case "br":
                        if let last = runs.last { runs[runs.count - 1].text = last.text + "\u{2028}" } else { runs.append(TextRun(text: "\u{2028}")) }
                    default:
                        break
                    }
                }
                if runs.isEmpty {
                    var rs = runStyle(p.child("endParaRPr"), part: part, inheritedBold: inherited?.bold)
                    rs.link = nil
                    runs = [TextRun(text: "", style: rs)]
                }
                paragraphs.append(Paragraph(runs: runs, style: style))
            }
            if !paragraphs.isEmpty { body.paragraphs = paragraphs }
            return body
        }

        func runStyle(_ rPr: XNode?, part: String, inheritedBold: Bool?) -> RunStyle {
            var s = RunStyle()
            s.bold = inheritedBold
            guard let rPr else { return s }
            if let sz = rPr.double("sz") { s.size = sz / 100 }
            if let b = rPr.bool("b") { s.bold = b }
            if let i = rPr.bool("i") { s.italic = i }
            if let u = rPr.attr("u"), u != "none" { s.underline = true }
            if let strike = rPr.attr("strike"), strike != "noStrike" { s.strikethrough = true }
            if let baseline = rPr.int("baseline"), baseline != 0 { s.baseline = baseline > 0 ? 1 : -1 }
            if rPr.attr("cap") == "all" { s.allCaps = true }
            if rPr.attr("cap") == "small" { s.smallCaps = true }
            if let spc = rPr.double("spc") { s.characterSpacing = spc / 100 }
            if let c = color(in: rPr.child("solidFill")) { s.color = c }
            if let h = color(in: rPr.child("highlight")) { s.highlight = h.resolve(colors) }
            if let face = rPr.child("latin")?.attr("typeface"), !face.hasPrefix("+") {
                s.fontFamily = face
            }
            if let ln = rPr.child("ln"), let c = color(in: ln.child("solidFill")) {
                s.outlineColor = c
                s.outlineWidth = Double(pt(ln.int("w") ?? 9525))
            }
            if rPr.path("effectLst", "outerShdw") != nil { s.shadow = true }
            if let rid = rPr.child("hlinkClick")?.attr("id"), let target = rels(for: part)[rid], target.external {
                s.link = target.target
            }
            return s
        }

        // MARK: Shapes

        func frame(_ xfrm: XNode?) -> CGRect? {
            guard let xfrm, let off = xfrm.child("off"), let ext = xfrm.child("ext") else { return nil }
            return CGRect(x: pt(off.int("x")), y: pt(off.int("y")), width: pt(ext.int("cx")), height: pt(ext.int("cy")))
        }

        func applyTransform(_ xfrm: XNode?, to e: inout SlideElement) {
            guard let xfrm else { return }
            e.rotation = (xfrm.double("rot") ?? 0) / 60_000
            e.flipH = xfrm.bool("flipH") ?? false
            e.flipV = xfrm.bool("flipV") ?? false
        }

        func action(_ cNvPr: XNode?, part: String, slidePaths: [String]) -> ElementAction? {
            guard let link = cNvPr?.child("hlinkClick") else { return nil }
            let act = link.attr("action") ?? ""
            if act.contains("nextslide") { return .nextSlide }
            if act.contains("previousslide") { return .previousSlide }
            if act.contains("firstslide") { return .firstSlide }
            if act.contains("lastslide") { return .lastSlide }
            if act.contains("endshow") { return .endShow }
            guard let rid = link.attr("id"), let target = rels(for: part)[rid] else { return nil }
            if target.external { return .url(target.target) }
            if let index = slidePaths.firstIndex(of: target.target), index < pendingSlideIDs.count { return .slide(pendingSlideIDs[index]) }
            return nil
        }

        var pendingSlideIDs: [UUID] = []
        var slidePaths: [String] = []

        func elements(in tree: XNode, part: String, inherited: (PlaceholderRole?, String?, String?) -> PlaceholderInfo?,
                      includePlaceholders: Bool = true) -> [SlideElement] {
            var result: [SlideElement] = []
            for node in tree.resolvedChildren {
                if let e = element(node, part: part, inherited: inherited, includePlaceholders: includePlaceholders) { result.append(e) }
            }
            return result
        }

        func element(_ node: XNode, part: String, inherited: (PlaceholderRole?, String?, String?) -> PlaceholderInfo?,
                     includePlaceholders: Bool) -> SlideElement? {
            switch node.name {
            case "sp":
                let nv = node.child("nvSpPr")
                let ph = nv?.path("nvPr", "ph")
                if ph != nil && !includePlaceholders { return nil }
                let role = ph.map { PlaceholderRole.fromOOXML($0.attr("type")) }
                let info = ph != nil ? inherited(role, ph?.attr("type"), ph?.attr("idx")) : nil
                let spPr = node.child("spPr")
                guard let rect = frame(spPr?.child("xfrm")) ?? info?.frame else { return nil }
                let prst = spPr?.child("prstGeom")?.attr("prst")
                let kind = prst.flatMap(ShapeKind.fromOOXML) ?? .rect
                var content = ShapeContent(kind: kind, fill: fill(in: spPr, part: part) ?? .none, line: line(spPr?.child("ln")) ?? .none)
                // Shapes styled through the theme (p:style) get theme fill and outline.
                if let style = node.child("style"), spPr.flatMap({ fill(in: $0, part: part) }) == nil {
                    if let c = color(in: style.child("fillRef")), (style.child("fillRef")?.int("idx") ?? 0) > 0 { content.fill = .solid(c) }
                    if line(spPr?.child("ln")) == nil, let c = color(in: style.child("lnRef")), (style.child("lnRef")?.int("idx") ?? 0) > 0 {
                        content.line = LineStyle(color: c.resolveShade(-0.25), width: 1)
                    }
                }
                if let gds = spPr?.path("prstGeom", "avLst")?.children("gd"), !gds.isEmpty {
                    let factor: Double
                    switch kind {
                    case .star4, .star5, .star6, .star8, .star12, .star24: factor = 50_000
                    case .pie, .chord: factor = 60_000
                    default: factor = 100_000
                    }
                    let values = gds.compactMap { $0.attr("fmla")?.components(separatedBy: " ").last.flatMap(Double.init) }.map { $0 / factor }
                    if !kind.isCallout, !values.isEmpty { content.adjustments = values }
                }
                content.effects = effects(spPr?.child("effectLst"))
                var body = textBody(node.child("txBody"), part: part, role: role, inherited: info)
                if node.child("style") != nil, let fontColor = color(in: node.path("style", "fontRef")), ph == nil { body.defaultColor = fontColor }
                if ph == nil && !content.fill.isNone && node.child("txBody") != nil && body.anchor == .top && node.path("txBody", "bodyPr")?.attr("anchor") == nil {
                    body.anchor = .middle
                }
                content.text = body
                var e = SlideElement(name: nv?.child("cNvPr")?.attr("name") ?? kind.title, frame: rect, content: .shape(content), placeholder: role)
                if role == .date || role == .footer || role == .slideNumber { e.placeholder = nil }
                e.altText = nv?.child("cNvPr")?.attr("descr") ?? ""
                e.hidden = nv?.child("cNvPr")?.bool("hidden") ?? false
                e.action = action(nv?.child("cNvPr"), part: part, slidePaths: slidePaths)
                applyTransform(spPr?.child("xfrm"), to: &e)
                return e
            case "pic":
                let nv = node.child("nvPicPr")
                let spPr = node.child("spPr")
                let ph = nv?.path("nvPr", "ph")
                if ph != nil && !includePlaceholders { return nil }
                let info = ph != nil ? inherited(.picture, ph?.attr("type"), ph?.attr("idx")) : nil
                guard let rect = frame(spPr?.child("xfrm")) ?? info?.frame,
                      let id = mediaID(node.path("blipFill", "blip"), part: part) else { return nil }
                var content = ImageContent(mediaID: id)
                if let src = node.path("blipFill", "srcRect") {
                    content.crop = CropInsets(left: (src.double("l") ?? 0) / 100_000, top: (src.double("t") ?? 0) / 100_000,
                                              right: (src.double("r") ?? 0) / 100_000, bottom: (src.double("b") ?? 0) / 100_000)
                }
                if let blip = node.path("blipFill", "blip") {
                    if blip.child("grayscl") != nil { content.adjustments.saturation = 0 }
                    if let amt = blip.child("alphaModFix")?.double("amt") { content.adjustments.transparency = 1 - amt / 100_000 }
                }
                content.line = line(spPr?.child("ln")) ?? .none
                content.effects = effects(spPr?.child("effectLst"))
                if let prst = spPr?.child("prstGeom")?.attr("prst"), prst != "rect" { content.maskShape = ShapeKind.fromOOXML(prst) }
                var e = SlideElement(name: nv?.child("cNvPr")?.attr("name") ?? "Picture", frame: rect, content: .image(content))
                e.altText = nv?.child("cNvPr")?.attr("descr") ?? ""
                e.lockAspectRatio = true
                e.action = action(nv?.child("cNvPr"), part: part, slidePaths: slidePaths)
                applyTransform(spPr?.child("xfrm"), to: &e)
                return e
            case "cxnSp":
                let spPr = node.child("spPr")
                guard let rect = frame(spPr?.child("xfrm")) else { return nil }
                let prst = spPr?.child("prstGeom")?.attr("prst") ?? "line"
                let kind: ConnectorKind = prst.hasPrefix("bent") ? .elbow : prst.hasPrefix("curved") ? .curved : .straight
                var style = line(spPr?.child("ln")) ?? LineStyle(color: .theme(.accent1), width: 1)
                if style.color == nil, let c = color(in: node.path("style", "lnRef")) { style.color = c }
                var e = SlideElement(name: node.path("nvCxnSpPr", "cNvPr")?.attr("name") ?? "Connector", frame: rect,
                                     content: .line(LineContent(kind: kind, line: style, effects: effects(spPr?.child("effectLst")))))
                applyTransform(spPr?.child("xfrm"), to: &e)
                return e
            case "grpSp":
                let xfrm = node.path("grpSpPr", "xfrm")
                guard let outer = frame(xfrm) else { return nil }
                let chOff = xfrm?.child("chOff"), chExt = xfrm?.child("chExt")
                let inner = CGRect(x: pt(chOff?.int("x")), y: pt(chOff?.int("y")), width: pt(chExt?.int("cx")), height: pt(chExt?.int("cy")))
                var children = elements(in: node, part: part, inherited: inherited, includePlaceholders: includePlaceholders)
                guard !children.isEmpty else { return nil }
                // Map child coordinates into the slide.
                let sx = inner.width > 0 ? outer.width / inner.width : 1
                let sy = inner.height > 0 ? outer.height / inner.height : 1
                for i in children.indices {
                    let f = children[i].frame
                    children[i].setFrame(CGRect(x: outer.minX + (f.minX - inner.minX) * sx, y: outer.minY + (f.minY - inner.minY) * sy,
                                                width: f.width * sx, height: f.height * sy))
                }
                var e = SlideElement(name: node.path("nvGrpSpPr", "cNvPr")?.attr("name") ?? "Group", frame: outer,
                                     content: .group(GroupContent(children: children)))
                applyTransform(xfrm, to: &e)
                return e
            case "graphicFrame":
                guard let rect = frame(node.child("xfrm")) else { return nil }
                let data = node.path("graphic", "graphicData")
                if let tbl = data?.child("tbl") {
                    return SlideElement(name: node.path("nvGraphicFramePr", "cNvPr")?.attr("name") ?? "Table", frame: rect,
                                        content: .table(table(tbl, part: part, width: rect.width)))
                }
                if let chartRef = data?.child("chart"), let rid = chartRef.attr("id"), let target = rels(for: part)[rid],
                   let chart = chart(target.target) {
                    return SlideElement(name: node.path("nvGraphicFramePr", "cNvPr")?.attr("name") ?? "Chart", frame: rect, content: .chart(chart))
                }
                return nil
            default:
                return nil
            }
        }

        func table(_ tbl: XNode, part: String, width: CGFloat) -> TableContent {
            let widths = (tbl.child("tblGrid")?.children("gridCol") ?? []).map { Double(pt($0.int("w"))) }
            var rows: [[TableCell]] = []
            var heights: [Double] = []
            for tr in tbl.children("tr") {
                heights.append(Double(pt(tr.int("h"))))
                var row: [TableCell] = []
                for tc in tr.children("tc") {
                    var body = textBody(tc.child("txBody"), part: part, role: nil, inherited: nil)
                    if let pr = tc.child("tcPr") {
                        body.anchor = anchor(pr.attr("anchor")) ?? .top
                        body.insets = EdgeInsetsValue(top: pr.attr("marT").map { Double(pt($0)) } ?? 3.6, left: pr.attr("marL").map { Double(pt($0)) } ?? 7.2,
                                                      bottom: pr.attr("marB").map { Double(pt($0)) } ?? 3.6, right: pr.attr("marR").map { Double(pt($0)) } ?? 7.2)
                    }
                    var cell = TableCell(text: body)
                    cell.fill = fill(in: tc.child("tcPr"), part: part)
                    cell.columnSpan = tc.int("gridSpan") ?? 1
                    cell.rowSpan = tc.int("rowSpan") ?? 1
                    cell.isMerged = tc.bool("hMerge") == true || tc.bool("vMerge") == true
                    row.append(cell)
                }
                while row.count < widths.count { row.append(TableCell(text: TableContent.cellBody(""))) }
                rows.append(Array(row.prefix(max(widths.count, 1))))
            }
            var table = TableContent(rows: rows, columnWidths: widths.isEmpty ? [Double(width)] : widths, rowHeights: heights)
            let props = tbl.child("tblPr")
            table.style.headerRow = props?.bool("firstRow") ?? false
            table.style.bandedRows = props?.bool("bandRow") ?? false
            table.style.totalRow = props?.bool("lastRow") ?? false
            table.style.firstColumn = props?.bool("firstCol") ?? false
            return table
        }

        func chart(_ path: String) -> ChartContent? {
            guard let space = xml(path), let chartNode = space.child("chart"), let plot = chartNode.child("plotArea") else { return nil }
            let types = ["barChart", "bar3DChart", "lineChart", "line3DChart", "pieChart", "pie3DChart", "doughnutChart", "areaChart", "scatterChart"]
            guard let typeNode = plot.children.first(where: { types.contains($0.name) }) else { return nil }
            var kind: ChartKind
            switch typeNode.name {
            case "barChart", "bar3DChart":
                let horizontal = typeNode.child("barDir")?.attr("val") == "bar"
                let stacked = (typeNode.child("grouping")?.attr("val") ?? "").contains("tacked")
                kind = horizontal ? (stacked ? .stackedBar : .bar) : (stacked ? .stackedColumn : .column)
            case "lineChart", "line3DChart": kind = .lineMarkers
            case "pieChart", "pie3DChart": kind = .pie
            case "doughnutChart": kind = .doughnut
            case "areaChart": kind = .area
            default: kind = .scatter
            }
            func values(_ node: XNode?) -> [String] {
                guard let node else { return [] }
                let cache = node.descendants("strCache").first ?? node.descendants("numCache").first
                let points = cache?.children("pt") ?? []
                let count = cache?.child("ptCount")?.int("val") ?? points.count
                var result = Array(repeating: "", count: count)
                for p in points { if let i = p.int("idx"), i < count { result[i] = p.child("v")?.text ?? "" } }
                return result
            }
            var series: [ChartSeries] = []
            var categories: [String] = []
            for (n, ser) in typeNode.children("ser").enumerated() {
                let name = values(ser.child("tx")).first ?? "Series \(n + 1)"
                let vals = values(ser.child("val") ?? ser.child("yVal")).map { Double($0) ?? 0 }
                if categories.isEmpty { categories = values(ser.child("cat") ?? ser.child("xVal")) }
                if kind == .line, ser.path("marker", "symbol")?.attr("val") == "none" { kind = .line }
                series.append(ChartSeries(name: name, values: vals))
            }
            if typeNode.name == "lineChart", typeNode.children("ser").allSatisfy({ $0.path("marker", "symbol")?.attr("val") == "none" }) { kind = .line }
            guard !series.isEmpty else { return nil }
            if categories.isEmpty { categories = (1...(series[0].values.count)).map(String.init) }
            var chart = ChartContent(kind: kind, title: nil, categories: categories, series: series)
            if let title = chartNode.child("title") {
                let text = title.descendants("t").map(\.text).joined()
                chart.title = text.isEmpty ? (series.count == 1 ? series[0].name : nil) : text
            }
            if chartNode.child("autoTitleDeleted")?.bool("val") == true { chart.title = nil }
            if let legend = chartNode.child("legend") {
                switch legend.child("legendPos")?.attr("val") {
                case "r": chart.legend = .right
                case "l": chart.legend = .left
                case "t": chart.legend = .top
                default: chart.legend = .bottom
                }
            } else {
                chart.legend = .none
            }
            return chart
        }

        // MARK: Slides

        func background(_ root: XNode?, part: String) -> Fill? {
            guard let bg = root?.path("cSld", "bg") else { return nil }
            if let pr = bg.child("bgPr") { return fill(in: pr, part: part) }
            if let ref = bg.child("bgRef"), let c = color(in: ref) { return .solid(c) }
            return nil
        }

        func run() throws -> Presentation {
            guard let pres = xml("ppt/presentation.xml") else {
                throw SlidesError.corrupt("The file isn't a PowerPoint presentation (ppt/presentation.xml is missing).")
            }
            if let size = pres.child("sldSz"), let cx = size.int("cx"), let cy = size.int("cy"), cx > 0, cy > 0 {
                presentation.slideSize = CGSize(width: pt(cx), height: pt(cy))
            }
            let presRels = rels(for: "ppt/presentation.xml")
            if let themePath = presRels.values.first(where: { $0.type == "theme" })?.target { readTheme(themePath) }
            slidePaths = (pres.child("sldIdLst")?.children("sldId") ?? []).compactMap { node in
                node.relationshipID.flatMap { presRels[$0]?.target }
            }
            pendingSlideIDs = slidePaths.map { _ in UUID() }

            var theme = ThemeLibrary.clean
            theme.id = "imported"
            theme.name = "Imported Theme"
            theme.colors = colors
            theme.headingFont = headingFont
            theme.bodyFont = bodyFont
            theme.titleSize = titleSize
            theme.bodySize = bodySizes[0]
            theme.decorations = []
            theme.titleDecorations = []
            theme.titleBackground = nil
            theme.background = .solid(.theme(.light1))
            theme.variants = []
            presentation.theme = theme

            var slides: [Slide] = []
            for (index, path) in slidePaths.enumerated() {
                guard let root = xml(path) else { continue }
                let slideRels = rels(for: path)
                let layoutPath = slideRels.values.first { $0.type == "slideLayout" }?.target
                let layoutRoot = layoutPath.flatMap(xml)
                let masterPath = layoutPath.flatMap { rels(for: $0).values.first { $0.type == "slideMaster" }?.target }
                let masterRoot = masterPath.flatMap(xml)
                if index == 0, let masterRoot { readMasterStyles(masterRoot) }
                let layoutPH = placeholders(in: layoutRoot)
                let masterPH = placeholders(in: masterRoot)
                func inherited(_ role: PlaceholderRole?, _ type: String?, _ idx: String?) -> PlaceholderInfo? {
                    let t = type ?? "body"
                    let masterKey = (t == "ctrTitle" || t == "title") ? "title" : (t == "subTitle" || t == "obj" || t == "pic") ? "body" : t
                    var info = idx.flatMap { layoutPH["idx:\($0)"] } ?? layoutPH[t] ?? (t == "ctrTitle" ? layoutPH["title"] : nil)
                    let m = masterPH[masterKey]
                    if info == nil { info = m }
                    if info?.frame == nil { info?.frame = m?.frame }
                    if info?.size == nil { info?.size = m?.size }
                    if info?.anchor == nil { info?.anchor = m?.anchor }
                    if info?.size == nil, t == "ctrTitle" || t == "title" { info?.size = titleSize }
                    return info
                }
                var slide = Slide(layout: LayoutKind.fromOOXML(layoutRoot?.attr("type")))
                slide.id = pendingSlideIDs[index]
                slide.hidden = root.attr("show") == "0"
                // Master and layout graphics become locked shapes at the back.
                var backdrop: [SlideElement] = []
                let showMaster = root.attr("showMasterSp") != "0" && layoutRoot?.attr("showMasterSp") != "0"
                if showMaster, let tree = masterRoot?.path("cSld", "spTree"), let masterPath {
                    backdrop += elements(in: tree, part: masterPath, inherited: { _, _, _ in nil }, includePlaceholders: false)
                }
                if root.attr("showMasterSp") != "0", let tree = layoutRoot?.path("cSld", "spTree"), let layoutPath {
                    backdrop += elements(in: tree, part: layoutPath, inherited: { _, _, _ in nil }, includePlaceholders: false)
                }
                for i in backdrop.indices { backdrop[i].locked = true; backdrop[i].name = "Background " + backdrop[i].name }
                if let tree = root.path("cSld", "spTree") {
                    slide.elements = backdrop + elements(in: tree, part: path, inherited: inherited)
                }
                slide.background = background(root, part: path)
                    ?? layoutPath.flatMap { background(layoutRoot, part: $0) }
                    ?? masterPath.flatMap { background(masterRoot, part: $0) }
                // Notes.
                if let notesPath = slideRels.values.first(where: { $0.type == "notesSlide" })?.target, let notes = xml(notesPath) {
                    let bodies = notes.descendants("sp").filter { $0.path("nvSpPr", "nvPr", "ph")?.attr("type") == "body" }
                    slide.notes = bodies.flatMap { $0.descendants("p") }.map { $0.descendants("t").map(\.text).joined() }.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let transition = root.descendants("transition").first {
                    slide.transition = self.transition(transition)
                }
                slides.append(slide)
            }
            if slides.isEmpty { slides = [LayoutBuilder.makeSlide(.title, theme: presentation.theme, size: presentation.slideSize)] }
            presentation.slides = slides

            // Sections.
            if let list = pres.descendants("sectionLst").first {
                for section in list.children("section") {
                    let ids = section.descendants("sldId").compactMap { $0.attr("id") }
                    let allIDs = (pres.child("sldIdLst")?.children("sldId") ?? []).compactMap { $0.attr("id") }
                    if let first = ids.first, let index = allIDs.firstIndex(of: first), index < slides.count {
                        presentation.sections.append(SlideSection(name: section.attr("name") ?? "Section", firstSlideID: slides[index].id))
                    }
                }
            }
            if let core = xml("docProps/core.xml") {
                presentation.title = core.child("title")?.text ?? ""
                presentation.author = core.child("creator")?.text ?? ""
            }
            presentation.pruneMedia()
            return presentation
        }

        func transition(_ node: XNode) -> Transition {
            var t = Transition()
            switch node.attr("spd") {
            case "fast": t.duration = 0.5
            case "slow": t.duration = 1.5
            default: t.duration = 0.75
            }
            if let dur = node.double("dur") { t.duration = dur / 1000 }
            if node.attr("advClick") == "0" { t.advanceOnClick = false }
            if let after = node.double("advTm") { t.advanceAfter = after / 1000 }
            guard let effect = node.children.first else { return t }
            switch effect.name {
            case "fade": t.kind = effect.bool("thruBlk") == true ? .fadeThroughBlack : .fade
            case "push": t.kind = .push
            case "wipe": t.kind = .wipe
            case "split": t.kind = .split
            case "cover": t.kind = .cover
            case "pull": t.kind = .uncover
            case "zoom", "newsflash": t.kind = .zoom
            case "circle", "diamond", "plus", "wedge", "wheel": t.kind = .circle
            case "dissolve", "random": t.kind = .dissolve
            case "blinds", "checker", "comb", "randomBar", "strips": t.kind = .blinds
            case "morph": t.kind = .morph
            case "flip", "gallery", "conveyor", "ferris", "flythrough", "switch", "pan": t.kind = .flip
            case "prism", "cube", "box", "rotate", "orbit", "window", "doors": t.kind = .cube
            default: t.kind = .fade
            }
            switch effect.attr("dir") {
            case "l": t.direction = .fromRight
            case "r": t.direction = .fromLeft
            case "u": t.direction = .fromBottom
            case "d": t.direction = .fromTop
            default: break
            }
            return t
        }
    }

    static func read(_ data: Data) throws -> Presentation {
        let entries: [String: Data]
        do {
            entries = try ZipArchive.read(data)
        } catch {
            throw SlidesError.corrupt("The file couldn't be opened because it isn't a valid PowerPoint presentation.")
        }
        return try Reader(entries).run()
    }
}

private extension PaintColor {
    func resolveShade(_ amount: Double) -> PaintColor {
        switch self {
        case .rgb(let c): .rgb(c.shaded(amount))
        case .theme(let slot, let shade, let alpha): .theme(slot, shade: shade + amount, alpha: alpha)
        }
    }
}

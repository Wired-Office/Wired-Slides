import type {
  ChartContent, ChartKind, EdgeInsets, Effects, ElementAction, Fill, LineStyle, PaintColor, PatternKind, PlaceholderRole, Presentation,
  RunStyle, Slide, SlideElement, TableCell, TableContent, TextAlignment, TextBody, ThemeColors, Transition, UUID, VerticalAnchor,
} from "../model/types";
import {
  NO_LINE, chartContent, element, emptyTextBody, frame, imageContent, isTitleRole, lineStyle, noEffects, numberedBullet, numberingFromOOXML,
  OUTER_SHADOW, plainParagraphStyle, plainRun, rgbHex, rgbPaint, resolve, setElementFrame, shapeContent, shaded, slotFromOOXML, symbolBullet,
  tableCellBody, themePaint, uuid, withAlpha, BLACK, WHITE, arrowFromOOXML, dashFromOOXML, paintAlpha, R, isRoundChart,
} from "../model/core";
import { COLOR_SCHEMES, isCallout, isStar, layoutFromOOXML, newTransition, placeholderFromOOXML, shapeFromOOXML } from "../model/catalog";
import { addMedia, makeSlide, newPresentation, newSlide, pruneMedia } from "../model/presentation";
import { themeById } from "../model/themes";
import { readZip, text } from "./zip";
import { FileFormatError } from "./wslides";

// MARK: XML helpers (match by local name, ignoring prefixes)

type X = Element;
const kids = (n: X | null | undefined): X[] => (n ? Array.from(n.children) : []);
const child = (n: X | null | undefined, name: string): X | null => kids(n).find((c) => c.localName === name) ?? null;
const childrenNamed = (n: X | null | undefined, name: string) => kids(n).filter((c) => c.localName === name);
const path = (n: X | null | undefined, ...names: string[]) => names.reduce<X | null>((node, name) => child(node, name), n ?? null);
const attr = (n: X | null | undefined, name: string): string | null => {
  if (!n) return null;
  if (n.hasAttribute(name)) return n.getAttribute(name);
  for (const a of Array.from(n.attributes)) if (a.localName === name) return a.value;
  return null;
};
const num = (n: X | null | undefined, name: string): number | null => { const v = attr(n, name); return v === null || v === "" || isNaN(Number(v)) ? null : Number(v); };
const bool = (n: X | null | undefined, name: string): boolean | null => { const v = attr(n, name); return v === null ? null : v === "1" || v === "true"; };
const descendants = (n: X | null | undefined, name: string): X[] => (n ? Array.from(n.getElementsByTagName("*")).filter((e) => e.localName === name) : []);
const pt = (emu: number | string | null) => (emu === null ? 0 : Number(emu) / 12700);
const relID = (n: X) => n.getAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "id") ?? n.getAttribute("r:id");

/** Children, with `mc:AlternateContent` replaced by its fallback (or first choice). */
function resolvedChildren(n: X): X[] {
  return kids(n).flatMap((c) => {
    if (c.localName !== "AlternateContent") return [c];
    const branch = child(c, "Fallback") ?? child(c, "Choice");
    return kids(branch);
  });
}

function parseXML(bytes: Uint8Array | undefined): X | null {
  if (!bytes) return null;
  const doc = new DOMParser().parseFromString(text(bytes), "application/xml");
  if (doc.getElementsByTagName("parsererror").length) return null;
  return doc.documentElement;
}

interface PlaceholderInfo {
  frame?: [number, number, number, number];
  anchor?: VerticalAnchor;
  size?: number;
  bold?: boolean | null;
  alignment?: TextAlignment;
  color?: PaintColor;
  insets?: EdgeInsets;
  bullets?: boolean;
}

interface Rel { target: string; type: string; external: boolean }

class Reader {
  presentation: Presentation;
  colors: ThemeColors = structuredClone(COLOR_SCHEMES[1][1]);
  headingFont = "Calibri Light";
  bodyFont = "Calibri";
  titleSize = 44;
  bodySizes = [28, 24, 20, 18, 18, 18, 18, 18, 18];
  otherSize = 18;
  mediaByPath = new Map<string, string>();
  slidePaths: string[] = [];
  pendingSlideIDs: UUID[] = [];
  private xmlCache = new Map<string, X | null>();
  private relsCache = new Map<string, Record<string, Rel>>();

  constructor(private entries: Record<string, Uint8Array>) {
    this.presentation = newPresentation(themeById("clean"), [newSlide("blank")]);
  }

  xml(p: string): X | null {
    if (!this.xmlCache.has(p)) this.xmlCache.set(p, parseXML(this.entries[p]));
    return this.xmlCache.get(p)!;
  }

  rels(part: string): Record<string, Rel> {
    let result = this.relsCache.get(part);
    if (result) return result;
    result = {};
    const dir = part.includes("/") ? part.slice(0, part.lastIndexOf("/")) : "";
    const root = this.xml(`${dir}/_rels/${part.slice(part.lastIndexOf("/") + 1)}.rels`);
    for (const r of childrenNamed(root, "Relationship")) {
      const id = attr(r, "Id"), target = attr(r, "Target");
      if (!id || !target) continue;
      const external = attr(r, "TargetMode") === "External";
      result[id] = { target: external ? target : this.resolve(target, dir), type: (attr(r, "Type") ?? "").split("/").pop() ?? "", external };
    }
    this.relsCache.set(part, result);
    return result;
  }

  resolve(target: string, dir: string): string {
    if (target.startsWith("/")) return target.slice(1);
    const parts = dir ? dir.split("/") : [];
    for (const piece of target.split("/")) {
      if (piece === "..") parts.pop();
      else if (piece !== ".") parts.push(piece);
    }
    return parts.join("/");
  }

  // MARK: Colors and fills

  color(node: X | null | undefined): PaintColor | null {
    for (const c of kids(node)) {
      let base: PaintColor | null = null;
      switch (c.localName) {
        case "srgbClr": { const v = attr(c, "val"); if (v && /^[0-9a-f]{6}$/i.test(v)) base = rgbPaint(rgbHex(parseInt(v, 16))); break; }
        case "schemeClr": { const slot = slotFromOOXML(attr(c, "val") ?? ""); if (slot) base = themePaint(slot); break; }
        case "sysClr": { const v = attr(c, "lastClr"); base = rgbPaint(v ? rgbHex(parseInt(v, 16)) : attr(c, "val") === "window" ? WHITE : BLACK); break; }
        case "prstClr": {
          const named: Record<string, number> = { black: 0, white: 0xffffff, red: 0xff0000, green: 0x008000, blue: 0x0000ff, yellow: 0xffff00, gray: 0x808080, orange: 0xffa500 };
          base = rgbPaint(rgbHex(named[attr(c, "val") ?? ""] ?? 0));
          break;
        }
        case "scrgbClr":
          base = rgbPaint({ r: (num(c, "r") ?? 0) / 100000, g: (num(c, "g") ?? 0) / 100000, b: (num(c, "b") ?? 0) / 100000, a: 1 });
          break;
        default: continue;
      }
      if (!base) continue;
      let shade = 0, alpha = 1;
      const lumMod = num(child(c, "lumMod"), "val");
      if (lumMod !== null) {
        const off = num(child(c, "lumOff"), "val") ?? 0;
        shade = off > 0 ? off / 100000 : lumMod / 100000 - 1;
      }
      const tint = num(child(c, "tint"), "val");
      if (tint !== null) shade = 1 - tint / 100000;
      const sh = num(child(c, "shade"), "val");
      if (sh !== null) shade = sh / 100000 - 1;
      const a = num(child(c, "alpha"), "val");
      if (a !== null) alpha = a / 100000;
      if ("rgb" in base) return rgbPaint(withAlpha(shaded(base.rgb._0, shade), alpha));
      return themePaint(base.theme._0, shade, alpha);
    }
    return null;
  }

  fill(parent: X | null | undefined, part: string): Fill | null {
    for (const c of kids(parent)) {
      switch (c.localName) {
        case "noFill": return { none: {} };
        case "solidFill": { const col = this.color(c); return col ? { solid: { _0: col } } : { none: {} }; }
        case "gradFill": {
          const stops = childrenNamed(child(c, "gsLst"), "gs").flatMap((gs) => {
            const col = this.color(gs);
            return col ? [{ color: col, position: (num(gs, "pos") ?? 0) / 100000 }] : [];
          });
          if (!stops.length) return { none: {} };
          const lin = child(c, "lin");
          return { gradient: { _0: { kind: lin || !child(c, "path") ? "linear" : "radial", stops, angle: lin ? (num(lin, "ang") ?? 5400000) / 60000 : 90 } } };
        }
        case "blipFill": {
          const id = this.mediaID(child(c, "blip"), part);
          if (id) return { image: { _0: { mediaID: id, mode: child(c, "tile") ? "tile" : "stretch", transparency: 0 } } };
          break;
        }
        case "pattFill": {
          const prst = attr(c, "prst") ?? "";
          const kind: PatternKind = /Horz/.test(prst) ? "horizontal" : /Vert/.test(prst) ? "vertical" : /UpDiag/.test(prst) ? "diagonalUp"
            : /DnDiag/.test(prst) ? "diagonalDown" : /Grid|cross/.test(prst) ? "grid" : /Check/.test(prst) ? "checker" : "dots";
          return { pattern: { _0: { kind, foreground: this.color(child(c, "fgClr")) ?? rgbPaint(BLACK), background: this.color(child(c, "bgClr")) ?? rgbPaint(WHITE) } } };
        }
        case "grpFill": return null;
      }
    }
    return null;
  }

  mediaID(blip: X | null, part: string): string | null {
    if (!blip) return null;
    const rid = attr(blip, "embed") ?? attr(blip, "link");
    const target = rid ? this.rels(part)[rid] : undefined;
    if (!target || target.external) return null;
    const existing = this.mediaByPath.get(target.target);
    if (existing) return existing;
    const data = this.entries[target.target];
    if (!data) return null;
    const id = addMedia(this.presentation, data, target.target.split("/").pop()!);
    this.mediaByPath.set(target.target, id);
    return id;
  }

  line(ln: X | null): LineStyle | null {
    if (!ln) return null;
    if (child(ln, "noFill")) return NO_LINE();
    const col = this.color(child(ln, "solidFill")) ?? (child(ln, "solidFill") ? rgbPaint(BLACK) : undefined);
    if (!col && num(ln, "w") !== null && !child(ln, "gradFill")) return null;
    const style = lineStyle(col ?? undefined, num(ln, "w") !== null ? pt(num(ln, "w")) : 0.75);
    const dash = attr(child(ln, "prstDash"), "val");
    if (dash) style.dash = dashFromOOXML(dash);
    const head = attr(child(ln, "headEnd"), "type"), tail = attr(child(ln, "tailEnd"), "type");
    if (head) style.head = arrowFromOOXML(head);
    if (tail) style.tail = arrowFromOOXML(tail);
    style.roundCaps = attr(ln, "cap") === "rnd";
    return style;
  }

  effects(list: X | null): Effects {
    const fx = noEffects();
    if (!list) return fx;
    const s = child(list, "outerShdw");
    if (s) {
      const shadow = OUTER_SHADOW();
      shadow.blur = pt(num(s, "blurRad"));
      shadow.distance = pt(num(s, "dist"));
      shadow.angle = (num(s, "dir") ?? 2700000) / 60000;
      const col = this.color(s);
      if (col) { shadow.color = withAlpha(resolve(col, this.colors), 1); shadow.opacity = paintAlpha(col); }
      fx.shadow = shadow;
    }
    const g = child(list, "glow");
    if (g) fx.glow = { color: this.color(g) ?? themePaint("accent1", 0, 0.6), radius: pt(num(g, "rad")) };
    const r = child(list, "reflection");
    if (r) fx.reflection = { opacity: (num(r, "stA") ?? 50000) / 100000, size: (num(r, "endPos") ?? 40000) / 100000, distance: pt(num(r, "dist")) };
    return fx;
  }

  // MARK: Theme and master

  readTheme(p: string) {
    const elements = child(this.xml(p), "themeElements");
    if (!elements) return;
    const scheme = child(elements, "clrScheme");
    if (scheme) {
      const c = (name: string, fallback: typeof BLACK) => { const col = this.color(child(scheme, name)); return col ? resolve(col, this.colors) : fallback; };
      const base = this.colors;
      this.colors = {
        dark1: c("dk1", BLACK), light1: c("lt1", WHITE), dark2: c("dk2", rgbHex(0x44546a)), light2: c("lt2", rgbHex(0xe7e6e6)),
        accent1: c("accent1", base.accent1), accent2: c("accent2", base.accent2), accent3: c("accent3", base.accent3),
        accent4: c("accent4", base.accent4), accent5: c("accent5", base.accent5), accent6: c("accent6", base.accent6),
        hyperlink: c("hlink", base.hyperlink), followedHyperlink: c("folHlink", base.followedHyperlink),
      };
    }
    const fonts = child(elements, "fontScheme");
    const major = attr(path(fonts, "majorFont", "latin"), "typeface"), minor = attr(path(fonts, "minorFont", "latin"), "typeface");
    if (major) this.headingFont = major;
    if (minor) this.bodyFont = minor;
  }

  readMasterStyles(master: X) {
    const styles = child(master, "txStyles");
    if (!styles) return;
    const t = num(path(styles, "titleStyle", "lvl1pPr", "defRPr"), "sz");
    if (t !== null) this.titleSize = t / 100;
    const body = child(styles, "bodyStyle");
    for (let i = 0; i < 9; i++) { const sz = num(path(body, `lvl${i + 1}pPr`, "defRPr"), "sz"); if (sz !== null) this.bodySizes[i] = sz / 100; }
    const o = num(path(styles, "otherStyle", "lvl1pPr", "defRPr"), "sz");
    if (o !== null) this.otherSize = o / 100;
  }

  placeholders(root: X | null): Record<string, PlaceholderInfo> {
    const tree = path(root, "cSld", "spTree");
    const result: Record<string, PlaceholderInfo> = {};
    for (const sp of descendants(tree, "sp")) {
      const ph = path(sp, "nvSpPr", "nvPr", "ph");
      if (!ph) continue;
      const info: PlaceholderInfo = {};
      const xfrm = path(sp, "spPr", "xfrm");
      const off = child(xfrm, "off"), ext = child(xfrm, "ext");
      if (off && ext) info.frame = [pt(num(off, "x")), pt(num(off, "y")), pt(num(ext, "cx")), pt(num(ext, "cy"))];
      const body = path(sp, "txBody", "bodyPr");
      if (body) {
        info.anchor = anchor(attr(body, "anchor")) ?? undefined;
        if (attr(body, "lIns") !== null) info.insets = insets(body);
      }
      const lvl = path(sp, "txBody", "lstStyle", "lvl1pPr");
      if (lvl) {
        const sz = num(child(lvl, "defRPr"), "sz");
        if (sz !== null) info.size = sz / 100;
        info.bold = bool(child(lvl, "defRPr"), "b");
        info.alignment = alignment(attr(lvl, "algn")) ?? undefined;
        info.color = this.color(path(lvl, "defRPr", "solidFill")) ?? undefined;
        if (child(lvl, "buNone")) info.bullets = false;
      }
      const type = attr(ph, "type") ?? "body";
      const idx = attr(ph, "idx");
      if (idx !== null) result[`idx:${idx}`] = info;
      if (!result[type]) result[type] = info;
    }
    return result;
  }

  // MARK: Text

  textBody(node: X | null, part: string, role: PlaceholderRole | null, inherited: PlaceholderInfo | null): TextBody {
    const body = emptyTextBody();
    const isTitle = isTitleRole(role ?? undefined);
    body.fontRole = isTitle ? "heading" : "body";
    body.defaultSize = inherited?.size ?? (isTitle ? this.titleSize : role ? this.bodySizes[0] : this.otherSize);
    if (inherited?.color) body.defaultColor = inherited.color;
    body.anchor = inherited?.anchor ?? (isTitle ? "middle" : "top");
    if (inherited?.insets) body.insets = inherited.insets;
    if (!node) return body;
    const pr = child(node, "bodyPr");
    if (pr) {
      const a = anchor(attr(pr, "anchor"));
      if (a) body.anchor = a;
      if (attr(pr, "lIns") !== null || attr(pr, "tIns") !== null) body.insets = insets(pr);
      body.wrap = attr(pr, "wrap") !== "none";
      body.columns = Math.max(1, Math.round(num(pr, "numCol") ?? 1));
      const vert = attr(pr, "vert");
      if (vert === "vert" || vert === "eaVert") body.direction = "rotated90";
      if (vert === "vert270") body.direction = "rotated270";
      if (child(pr, "normAutofit")) body.autofit = "shrink";
      if (child(pr, "spAutoFit")) body.autofit = "resizeShape";
    }
    const paragraphs = childrenNamed(node, "p").map((p) => {
      const style = plainParagraphStyle();
      const pPr = child(p, "pPr");
      style.level = Math.max(0, Math.min(8, Math.round(num(pPr, "lvl") ?? 0)));
      style.alignment = alignment(attr(pPr, "algn")) ?? inherited?.alignment ?? "left";
      const pct = num(path(pPr, "lnSpc", "spcPct"), "val");
      if (pct !== null) style.lineSpacing = pct / 100000;
      const before = num(path(pPr, "spcBef", "spcPts"), "val");
      if (before !== null) style.spaceBefore = before / 100;
      const after = num(path(pPr, "spcAft", "spcPts"), "val");
      if (after !== null) style.spaceAfter = after / 100;
      const char = attr(child(pPr, "buChar"), "char");
      const auto = child(pPr, "buAutoNum");
      if (char) style.bullet = symbolBullet(char);
      else if (auto) style.bullet = numberedBullet(numberingFromOOXML(attr(auto, "type") ?? ""), Math.round(num(auto, "startAt") ?? 1));
      else if (!child(pPr, "buNone") && role === "body" && inherited?.bullets !== false) style.bullet = symbolBullet("•");
      const bc = this.color(child(pPr, "buClr"));
      if (bc) style.bulletColor = bc;
      const levelSize = role === "body" ? this.bodySizes[Math.min(style.level, 8)] : null;
      const runs: { text: string; style: RunStyle }[] = [];
      for (const r of kids(p)) {
        if (r.localName === "r" || r.localName === "fld") {
          const rs = this.runStyle(child(r, "rPr"), part, inherited?.bold ?? null);
          if (rs.size === undefined && levelSize !== null && levelSize !== body.defaultSize && inherited?.size === undefined) rs.size = levelSize;
          runs.push({ text: child(r, "t")?.textContent ?? "", style: rs });
        } else if (r.localName === "br") {
          if (runs.length) runs[runs.length - 1].text += "\u2028"; else runs.push({ text: "\u2028", style: plainRun() });
        }
      }
      if (!runs.length) {
        const rs = this.runStyle(child(p, "endParaRPr"), part, inherited?.bold ?? null);
        delete rs.link;
        runs.push({ text: "", style: rs });
      }
      return { runs, style };
    });
    if (paragraphs.length) body.paragraphs = paragraphs;
    return body;
  }

  runStyle(rPr: X | null, part: string, inheritedBold: boolean | null): RunStyle {
    const s = plainRun();
    if (inheritedBold !== null) s.bold = inheritedBold;
    if (!rPr) return s;
    const sz = num(rPr, "sz");
    if (sz !== null) s.size = sz / 100;
    const b = bool(rPr, "b"), i = bool(rPr, "i");
    if (b !== null) s.bold = b;
    if (i !== null) s.italic = i;
    const u = attr(rPr, "u");
    if (u && u !== "none") s.underline = true;
    const strike = attr(rPr, "strike");
    if (strike && strike !== "noStrike") s.strikethrough = true;
    const baseline = num(rPr, "baseline");
    if (baseline) s.baseline = baseline > 0 ? 1 : -1;
    if (attr(rPr, "cap") === "all") s.allCaps = true;
    if (attr(rPr, "cap") === "small") s.smallCaps = true;
    const spc = num(rPr, "spc");
    if (spc !== null) s.characterSpacing = spc / 100;
    const col = this.color(child(rPr, "solidFill"));
    if (col) s.color = col;
    const h = this.color(child(rPr, "highlight"));
    if (h) s.highlight = resolve(h, this.colors);
    const face = attr(child(rPr, "latin"), "typeface");
    if (face && !face.startsWith("+")) s.fontFamily = face;
    const ln = child(rPr, "ln");
    const outline = this.color(child(ln, "solidFill"));
    if (ln && outline) { s.outlineColor = outline; s.outlineWidth = pt(num(ln, "w") ?? 9525); }
    if (path(rPr, "effectLst", "outerShdw")) s.shadow = true;
    const link = attr(child(rPr, "hlinkClick"), "id");
    const target = link ? this.rels(part)[link] : undefined;
    if (target?.external) s.link = target.target;
    return s;
  }

  // MARK: Shapes

  frame(xfrm: X | null): [number, number, number, number] | null {
    const off = child(xfrm, "off"), ext = child(xfrm, "ext");
    if (!off || !ext) return null;
    return [pt(num(off, "x")), pt(num(off, "y")), pt(num(ext, "cx")), pt(num(ext, "cy"))];
  }

  transform(xfrm: X | null, e: SlideElement) {
    if (!xfrm) return;
    e.rotation = (num(xfrm, "rot") ?? 0) / 60000;
    e.flipH = bool(xfrm, "flipH") ?? false;
    e.flipV = bool(xfrm, "flipV") ?? false;
  }

  action(cNvPr: X | null, part: string): ElementAction | null {
    const link = child(cNvPr, "hlinkClick");
    if (!link) return null;
    const act = attr(link, "action") ?? "";
    if (act.includes("nextslide")) return { nextSlide: {} };
    if (act.includes("previousslide")) return { previousSlide: {} };
    if (act.includes("firstslide")) return { firstSlide: {} };
    if (act.includes("lastslide")) return { lastSlide: {} };
    if (act.includes("endshow")) return { endShow: {} };
    const rid = attr(link, "id");
    const target = rid ? this.rels(part)[rid] : undefined;
    if (!target) return null;
    if (target.external) return { url: { _0: target.target } };
    const index = this.slidePaths.indexOf(target.target);
    return index >= 0 ? { slide: { _0: this.pendingSlideIDs[index] } } : null;
  }

  elements(tree: X, part: string, inherited: Inherit, includePlaceholders = true): SlideElement[] {
    return resolvedChildren(tree).flatMap((node) => { const e = this.element(node, part, inherited, includePlaceholders); return e ? [e] : []; });
  }

  element(node: X, part: string, inherited: Inherit, includePlaceholders: boolean): SlideElement | null {
    switch (node.localName) {
      case "sp": {
        const nv = child(node, "nvSpPr");
        const ph = path(nv, "nvPr", "ph");
        if (ph && !includePlaceholders) return null;
        const role = ph ? placeholderFromOOXML(attr(ph, "type")) : null;
        const info = ph ? inherited(role, attr(ph, "type"), attr(ph, "idx")) : null;
        const spPr = child(node, "spPr");
        const rect = this.frame(child(spPr, "xfrm")) ?? info?.frame;
        if (!rect) return null;
        const prst = attr(child(spPr, "prstGeom"), "prst");
        const kind = (prst && shapeFromOOXML(prst)) || "rect";
        const content = shapeContent(kind, this.fill(spPr, part) ?? { none: {} }, this.line(child(spPr, "ln")) ?? NO_LINE());
        // Shapes styled through the theme (p:style) get theme fill and outline.
        const style = child(node, "style");
        if (style && !this.fill(spPr, part)) {
          const fc = this.color(child(style, "fillRef"));
          if (fc && (num(child(style, "fillRef"), "idx") ?? 0) > 0) content.fill = { solid: { _0: fc } };
          const lc = this.color(child(style, "lnRef"));
          if (!this.line(child(spPr, "ln")) && lc && (num(child(style, "lnRef"), "idx") ?? 0) > 0) {
            content.line = lineStyle("rgb" in lc ? rgbPaint(shaded(lc.rgb._0, -0.25)) : themePaint(lc.theme._0, lc.theme.shade - 0.25, lc.theme.alpha), 1);
          }
        }
        const gds = childrenNamed(path(spPr, "prstGeom", "avLst"), "gd");
        if (gds.length) {
          const factor = isStar(kind) ? 50000 : kind === "pie" || kind === "chord" ? 60000 : 100000;
          const values = gds.map((g) => Number((attr(g, "fmla") ?? "").split(" ").pop())).filter((v) => !isNaN(v)).map((v) => v / factor);
          if (!isCallout(kind) && values.length) content.adjustments = values;
        }
        content.effects = this.effects(child(spPr, "effectLst"));
        const body = this.textBody(child(node, "txBody"), part, role, info);
        const fontColor = this.color(path(node, "style", "fontRef"));
        if (style && fontColor && !ph) body.defaultColor = fontColor;
        if (!ph && !("none" in content.fill) && child(node, "txBody") && body.anchor === "top" && attr(path(node, "txBody", "bodyPr"), "anchor") === null) body.anchor = "middle";
        content.text = body;
        const cNvPr = child(nv, "cNvPr");
        const e = element(attr(cNvPr, "name") ?? kind, frame(...rect), { shape: { _0: content } }, role ?? undefined);
        if (role === "date" || role === "footer" || role === "slideNumber") delete e.placeholder;
        this.common(e, cNvPr, part);
        this.transform(child(spPr, "xfrm"), e);
        return e;
      }
      case "pic": {
        const nv = child(node, "nvPicPr");
        const spPr = child(node, "spPr");
        const ph = path(nv, "nvPr", "ph");
        if (ph && !includePlaceholders) return null;
        const info = ph ? inherited("picture", attr(ph, "type"), attr(ph, "idx")) : null;
        const rect = this.frame(child(spPr, "xfrm")) ?? info?.frame;
        const id = this.mediaID(path(node, "blipFill", "blip"), part);
        if (!rect || !id) return null;
        const content = imageContent(id);
        const src = path(node, "blipFill", "srcRect");
        if (src) content.crop = { left: (num(src, "l") ?? 0) / 100000, top: (num(src, "t") ?? 0) / 100000, right: (num(src, "r") ?? 0) / 100000, bottom: (num(src, "b") ?? 0) / 100000 };
        const blip = path(node, "blipFill", "blip");
        if (child(blip, "grayscl")) content.adjustments.saturation = 0;
        const amt = num(child(blip, "alphaModFix"), "amt");
        if (amt !== null) content.adjustments.transparency = 1 - amt / 100000;
        content.line = this.line(child(spPr, "ln")) ?? NO_LINE();
        content.effects = this.effects(child(spPr, "effectLst"));
        const prst = attr(child(spPr, "prstGeom"), "prst");
        if (prst && prst !== "rect") { const mask = shapeFromOOXML(prst); if (mask) content.maskShape = mask; }
        const cNvPr = child(nv, "cNvPr");
        const e = element(attr(cNvPr, "name") ?? "Picture", frame(...rect), { image: { _0: content } });
        this.common(e, cNvPr, part);
        e.lockAspectRatio = true;
        this.transform(child(spPr, "xfrm"), e);
        return e;
      }
      case "cxnSp": {
        const spPr = child(node, "spPr");
        const rect = this.frame(child(spPr, "xfrm"));
        if (!rect) return null;
        const prst = attr(child(spPr, "prstGeom"), "prst") ?? "line";
        const style = this.line(child(spPr, "ln")) ?? lineStyle(themePaint("accent1"), 1);
        if (!style.color) { const c = this.color(path(node, "style", "lnRef")); if (c) style.color = c; }
        const e = element(attr(path(node, "nvCxnSpPr", "cNvPr"), "name") ?? "Connector", frame(...rect), {
          line: { _0: { kind: prst.startsWith("bent") ? "elbow" : prst.startsWith("curved") ? "curved" : "straight", line: style, effects: this.effects(child(spPr, "effectLst")) } },
        });
        this.transform(child(spPr, "xfrm"), e);
        return e;
      }
      case "grpSp": {
        const xfrm = path(node, "grpSpPr", "xfrm");
        const outer = this.frame(xfrm);
        if (!outer) return null;
        const chOff = child(xfrm, "chOff"), chExt = child(xfrm, "chExt");
        const inner = { x: pt(num(chOff, "x")), y: pt(num(chOff, "y")), w: pt(num(chExt, "cx")), h: pt(num(chExt, "cy")) };
        const children = this.elements(node, part, inherited, includePlaceholders);
        if (!children.length) return null;
        const sx = inner.w > 0 ? outer[2] / inner.w : 1, sy = inner.h > 0 ? outer[3] / inner.h : 1;
        for (const c of children) {
          const f = R(c.frame);
          setElementFrame(c, { x: outer[0] + (f.x - inner.x) * sx, y: outer[1] + (f.y - inner.y) * sy, w: f.w * sx, h: f.h * sy });
        }
        const e = element(attr(path(node, "nvGrpSpPr", "cNvPr"), "name") ?? "Group", frame(...outer), { group: { _0: { children } } });
        this.transform(xfrm, e);
        return e;
      }
      case "graphicFrame": {
        const rect = this.frame(child(node, "xfrm"));
        if (!rect) return null;
        const data = path(node, "graphic", "graphicData");
        const name = attr(path(node, "nvGraphicFramePr", "cNvPr"), "name");
        const tbl = child(data, "tbl");
        if (tbl) return element(name ?? "Table", frame(...rect), { table: { _0: this.table(tbl, part, rect[2]) } });
        const chartRef = child(data, "chart");
        const rid = chartRef ? relID(chartRef) ?? attr(chartRef, "id") : null;
        const target = rid ? this.rels(part)[rid] : undefined;
        const chart = target ? this.chart(target.target) : null;
        if (chart) return element(name ?? "Chart", frame(...rect), { chart: { _0: chart } });
        return null;
      }
    }
    return null;
  }

  common(e: SlideElement, cNvPr: X | null, part: string) {
    e.altText = attr(cNvPr, "descr") ?? "";
    e.hidden = bool(cNvPr, "hidden") ?? false;
    const action = this.action(cNvPr, part);
    if (action) e.action = action;
  }

  table(tbl: X, part: string, width: number): TableContent {
    const widths = childrenNamed(child(tbl, "tblGrid"), "gridCol").map((g) => pt(num(g, "w")));
    const rows: TableCell[][] = [];
    const heights: number[] = [];
    for (const tr of childrenNamed(tbl, "tr")) {
      heights.push(pt(num(tr, "h")));
      const row: TableCell[] = childrenNamed(tr, "tc").map((tc) => {
        const body = this.textBody(child(tc, "txBody"), part, null, null);
        const pr = child(tc, "tcPr");
        if (pr) {
          body.anchor = anchor(attr(pr, "anchor")) ?? "top";
          const m = (name: string, fallback: number) => (attr(pr, name) !== null ? pt(attr(pr, name)) : fallback);
          body.insets = { top: m("marT", 3.6), left: m("marL", 7.2), bottom: m("marB", 3.6), right: m("marR", 7.2) };
        }
        const cell: TableCell = { text: body, rowSpan: Math.round(num(tc, "rowSpan") ?? 1), columnSpan: Math.round(num(tc, "gridSpan") ?? 1), isMerged: !!(bool(tc, "hMerge") || bool(tc, "vMerge")) };
        const f = this.fill(pr, part);
        if (f) cell.fill = f;
        return cell;
      });
      while (row.length < widths.length) row.push({ text: tableCellBody(""), rowSpan: 1, columnSpan: 1, isMerged: false });
      rows.push(row.slice(0, Math.max(widths.length, 1)));
    }
    const props = child(tbl, "tblPr");
    return {
      rows, columnWidths: widths.length ? widths : [width], rowHeights: heights,
      style: {
        headerRow: bool(props, "firstRow") ?? false, totalRow: bool(props, "lastRow") ?? false, bandedRows: bool(props, "bandRow") ?? false,
        firstColumn: bool(props, "firstCol") ?? false, lastColumn: false, bandedColumns: false, color: themePaint("accent1"), intensity: 0, borderWidth: 1,
      },
    };
  }

  chart(p: string): ChartContent | null {
    const space = this.xml(p);
    const chartNode = child(space, "chart");
    const plot = child(chartNode, "plotArea");
    if (!plot) return null;
    const types = ["barChart", "bar3DChart", "lineChart", "line3DChart", "pieChart", "pie3DChart", "doughnutChart", "areaChart", "scatterChart"];
    const typeNode = kids(plot).find((c) => types.includes(c.localName));
    if (!typeNode) return null;
    let kind: ChartKind;
    switch (typeNode.localName) {
      case "barChart": case "bar3DChart": {
        const horizontal = attr(child(typeNode, "barDir"), "val") === "bar";
        const stacked = /tacked/.test(attr(child(typeNode, "grouping"), "val") ?? "");
        kind = horizontal ? (stacked ? "stackedBar" : "bar") : stacked ? "stackedColumn" : "column";
        break;
      }
      case "lineChart": case "line3DChart": kind = "lineMarkers"; break;
      case "pieChart": case "pie3DChart": kind = "pie"; break;
      case "doughnutChart": kind = "doughnut"; break;
      case "areaChart": kind = "area"; break;
      default: kind = "scatter";
    }
    const values = (node: X | null): string[] => {
      if (!node) return [];
      const cache = descendants(node, "strCache")[0] ?? descendants(node, "numCache")[0];
      const points = childrenNamed(cache, "pt");
      const count = num(child(cache, "ptCount"), "val") ?? points.length;
      const result = Array<string>(count).fill("");
      for (const p of points) { const i = num(p, "idx"); if (i !== null && i < count) result[i] = child(p, "v")?.textContent ?? ""; }
      return result;
    };
    let categories: string[] = [];
    const series = childrenNamed(typeNode, "ser").map((ser, n) => {
      const name = values(child(ser, "tx"))[0] ?? `Series ${n + 1}`;
      const vals = values(child(ser, "val") ?? child(ser, "yVal")).map((v) => Number(v) || 0);
      if (!categories.length) categories = values(child(ser, "cat") ?? child(ser, "xVal"));
      return { name, values: vals };
    });
    if (typeNode.localName === "lineChart" && childrenNamed(typeNode, "ser").every((s) => attr(path(s, "marker", "symbol"), "val") === "none")) kind = "line";
    if (!series.length) return null;
    if (!categories.length) categories = series[0].values.map((_, i) => String(i + 1));
    const chart = chartContent(kind, { categories, series });
    const title = child(chartNode, "title");
    if (title) {
      const t = descendants(title, "t").map((x) => x.textContent ?? "").join("");
      const resolved = t || (series.length === 1 ? series[0].name : "");
      if (resolved) chart.title = resolved;
    }
    if (bool(child(chartNode, "autoTitleDeleted"), "val")) delete chart.title;
    const legend = child(chartNode, "legend");
    if (legend) {
      const pos = attr(child(legend, "legendPos"), "val");
      chart.legend = pos === "r" ? "right" : pos === "l" ? "left" : pos === "t" ? "top" : "bottom";
    } else chart.legend = "none";
    if (isRoundChart(kind)) chart.series = chart.series.slice(0, 1);
    return chart;
  }

  // MARK: Slides

  background(root: X | null, part: string): Fill | null {
    const bg = path(root, "cSld", "bg");
    if (!bg) return null;
    const pr = child(bg, "bgPr");
    if (pr) return this.fill(pr, part);
    const c = this.color(child(bg, "bgRef"));
    return c ? { solid: { _0: c } } : null;
  }

  run(): Presentation {
    const pres = this.xml("ppt/presentation.xml");
    if (!pres) throw new FileFormatError("The file isn't a PowerPoint presentation (ppt/presentation.xml is missing).");
    const size = child(pres, "sldSz");
    const cx = num(size, "cx"), cy = num(size, "cy");
    if (cx && cy && cx > 0 && cy > 0) this.presentation.slideSize = [pt(cx), pt(cy)];
    const presRels = this.rels("ppt/presentation.xml");
    const themePath = Object.values(presRels).find((r) => r.type === "theme")?.target;
    if (themePath) this.readTheme(themePath);
    const slideNodes = childrenNamed(child(pres, "sldIdLst"), "sldId");
    this.slidePaths = slideNodes.map((n) => { const rid = relID(n); return rid ? presRels[rid]?.target : undefined; }).filter((x): x is string => !!x);
    this.pendingSlideIDs = this.slidePaths.map(() => uuid());

    const theme = themeById("clean");
    Object.assign(theme, {
      id: "imported", name: "Imported Theme", colors: this.colors, headingFont: this.headingFont, bodyFont: this.bodyFont,
      decorations: [], titleDecorations: [], background: { solid: { _0: themePaint("light1") } }, variants: [],
    });
    delete theme.titleBackground;
    this.presentation.theme = theme;

    const slides: Slide[] = [];
    this.slidePaths.forEach((slidePath, index) => {
      const root = this.xml(slidePath);
      if (!root) return;
      const slideRels = this.rels(slidePath);
      const layoutPath = Object.values(slideRels).find((r) => r.type === "slideLayout")?.target;
      const layoutRoot = layoutPath ? this.xml(layoutPath) : null;
      const masterPath = layoutPath ? Object.values(this.rels(layoutPath)).find((r) => r.type === "slideMaster")?.target : undefined;
      const masterRoot = masterPath ? this.xml(masterPath) : null;
      if (index === 0 && masterRoot) {
        this.readMasterStyles(masterRoot);
        theme.titleSize = this.titleSize;
        theme.bodySize = this.bodySizes[0];
      }
      const layoutPH = this.placeholders(layoutRoot), masterPH = this.placeholders(masterRoot);
      const inherited: Inherit = (_role, type, idx) => {
        const t = type ?? "body";
        const masterKey = t === "ctrTitle" || t === "title" ? "title" : t === "subTitle" || t === "obj" || t === "pic" ? "body" : t;
        let info: PlaceholderInfo | undefined = (idx !== null ? layoutPH[`idx:${idx}`] : undefined) ?? layoutPH[t] ?? (t === "ctrTitle" ? layoutPH.title : undefined);
        const m = masterPH[masterKey];
        if (!info) info = m ? { ...m } : undefined;
        if (info) {
          info = { ...info };
          info.frame ??= m?.frame;
          info.size ??= m?.size;
          info.anchor ??= m?.anchor;
          if (info.size === undefined && (t === "ctrTitle" || t === "title")) info.size = this.titleSize;
        }
        return info ?? null;
      };
      const slide = newSlide(layoutFromOOXML(attr(layoutRoot, "type")));
      slide.id = this.pendingSlideIDs[index];
      slide.hidden = attr(root, "show") === "0";
      // Master and layout graphics become locked shapes at the back.
      const backdrop: SlideElement[] = [];
      const showMaster = attr(root, "showMasterSp") !== "0" && attr(layoutRoot, "showMasterSp") !== "0";
      const masterTree = path(masterRoot, "cSld", "spTree");
      if (showMaster && masterTree && masterPath) backdrop.push(...this.elements(masterTree, masterPath, () => null, false));
      const layoutTree = path(layoutRoot, "cSld", "spTree");
      if (attr(root, "showMasterSp") !== "0" && layoutTree && layoutPath) backdrop.push(...this.elements(layoutTree, layoutPath, () => null, false));
      for (const b of backdrop) { b.locked = true; b.name = "Background " + b.name; }
      const tree = path(root, "cSld", "spTree");
      if (tree) slide.elements = [...backdrop, ...this.elements(tree, slidePath, inherited)];
      const bg = this.background(root, slidePath) ?? (layoutPath ? this.background(layoutRoot, layoutPath) : null) ?? (masterPath ? this.background(masterRoot, masterPath) : null);
      if (bg) slide.background = bg;
      const notesPath = Object.values(slideRels).find((r) => r.type === "notesSlide")?.target;
      const notes = notesPath ? this.xml(notesPath) : null;
      if (notes) {
        const bodies = descendants(notes, "sp").filter((sp) => attr(path(sp, "nvSpPr", "nvPr", "ph"), "type") === "body");
        slide.notes = bodies.flatMap((b) => descendants(b, "p")).map((p) => descendants(p, "t").map((t) => t.textContent ?? "").join("")).join("\n").trim();
      }
      const transition = descendants(root, "transition")[0];
      if (transition) slide.transition = readTransition(transition);
      slides.push(slide);
    });
    this.presentation.slides = slides.length ? slides : [makeSlide("title", theme, this.presentation.slideSize)];

    const list = descendants(pres, "sectionLst")[0];
    if (list) {
      const allIDs = slideNodes.map((n) => attr(n, "id"));
      for (const section of childrenNamed(list, "section")) {
        const first = attr(descendants(section, "sldId")[0], "id");
        const index = first ? allIDs.indexOf(first) : -1;
        if (index >= 0 && index < slides.length) this.presentation.sections.push({ id: uuid(), name: attr(section, "name") ?? "Section", firstSlideID: slides[index].id });
      }
    }
    const core = this.xml("docProps/core.xml");
    if (core) {
      this.presentation.title = child(core, "title")?.textContent ?? "";
      this.presentation.author = child(core, "creator")?.textContent ?? "";
    }
    pruneMedia(this.presentation);
    return this.presentation;
  }
}

type Inherit = (role: PlaceholderRole | null, type: string | null, idx: string | null) => PlaceholderInfo | null;

function anchor(v: string | null): VerticalAnchor | null {
  return v === "t" ? "top" : v === "ctr" ? "middle" : v === "b" ? "bottom" : null;
}

function alignment(v: string | null): TextAlignment | null {
  switch (v) {
    case "l": return "left";
    case "ctr": return "center";
    case "r": return "right";
    case "just": case "dist": return "justify";
  }
  return null;
}

function insets(body: X): EdgeInsets {
  const m = (name: string, fallback: number) => (attr(body, name) !== null ? pt(attr(body, name)) : fallback);
  return { top: m("tIns", 3.6), left: m("lIns", 7.2), bottom: m("bIns", 3.6), right: m("rIns", 7.2) };
}

function readTransition(node: X): Transition {
  const t = newTransition();
  const spd = attr(node, "spd");
  t.duration = spd === "fast" ? 0.5 : spd === "slow" ? 1.5 : 0.75;
  const dur = num(node, "dur");
  if (dur !== null) t.duration = dur / 1000;
  if (attr(node, "advClick") === "0") t.advanceOnClick = false;
  const after = num(node, "advTm");
  if (after !== null) t.advanceAfter = after / 1000;
  const effect = kids(node).find((c) => c.localName !== "sndAc" && c.localName !== "extLst");
  if (!effect) return t;
  const kinds: Record<string, Transition["kind"]> = {
    fade: "fade", push: "push", wipe: "wipe", split: "split", cover: "cover", pull: "uncover", zoom: "zoom", newsflash: "zoom",
    circle: "circle", diamond: "circle", plus: "circle", wedge: "circle", wheel: "circle", dissolve: "dissolve", random: "dissolve",
    blinds: "blinds", checker: "blinds", comb: "blinds", randomBar: "blinds", strips: "blinds", morph: "morph",
    flip: "flip", gallery: "flip", conveyor: "flip", ferris: "flip", flythrough: "flip", switch: "flip", pan: "flip",
    prism: "cube", cube: "cube", box: "cube", rotate: "cube", orbit: "cube", window: "cube", doors: "cube",
  };
  t.kind = kinds[effect.localName] ?? "fade";
  if (effect.localName === "fade" && bool(effect, "thruBlk")) t.kind = "fadeThroughBlack";
  const dir = attr(effect, "dir");
  if (dir === "l") t.direction = "fromRight";
  else if (dir === "r") t.direction = "fromLeft";
  else if (dir === "u") t.direction = "fromBottom";
  else if (dir === "d") t.direction = "fromTop";
  return t;
}

export function readPPTX(bytes: Uint8Array): Presentation {
  let entries: Record<string, Uint8Array>;
  try {
    entries = readZip(bytes);
  } catch {
    throw new FileFormatError("The file couldn't be opened because it isn't a valid PowerPoint presentation.");
  }
  return new Reader(entries).run();
}

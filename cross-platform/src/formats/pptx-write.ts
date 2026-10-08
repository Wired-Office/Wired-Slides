import type {
  Effects, Fill, LineStyle, PaintColor, PlaceholderRole, Presentation, PresentationTheme, SlideElement, TextBody, Paragraph, RunStyle, Transition,
  TableContent, CropInsets, ImageAdjustments, ShapeKind,
} from "../model/types";
import type { Rect } from "../model/core";
import {
  ARROW_OOXML, DASH_OOXML, NUMBERING_OOXML, R, SLOT_OOXML, bulletIsNone, cropZero, effectsEmpty, hexString, identityAdjustments, isNoFill, isTitleRole,
  lineVisible, noEffects, NO_LINE, zeroCrop,
} from "../model/core";
import { CONNECTOR_OOXML, DIRECTION_OOXML, LAYOUTS, LAYOUT_OOXML, LAYOUT_TITLES, PLACEHOLDER_OOXML, isCallout, isStar } from "../model/catalog";
import { makeSlide, scaledRect, slideIndex } from "../model/presentation";
import { writeZip } from "./zip";
import { cellAppearance, styledCellBody } from "../render/table";
import { slideDecorations, slideFooters } from "../render/slide";

/** Turns charts, icons and media without posters into pictures (needs a canvas, so the app supplies it). */
export type ElementRasterizer = (e: SlideElement) => { png: Uint8Array; bounds: Rect } | null;

export interface PPTXHelpers {
  rasterize?: ElementRasterizer;
  /** Converts media PowerPoint can't show (WebP, HEIC, SVG…) to PNG. */
  toPNG?: (id: string) => Uint8Array | null;
}

const nsA = "http://schemas.openxmlformats.org/drawingml/2006/main";
const nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const nsP = "http://schemas.openxmlformats.org/presentationml/2006/main";
const relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const NAMESPACES = `xmlns:a="${nsA}" xmlns:r="${nsR}" xmlns:p="${nsP}"`;
const HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const GROUP_HEADER = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
const CLR_MAP = '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>';

const emu = (points: number) => Math.round(points * 12700);
const int = (v: number) => Math.round(v);

export function esc(s: string): string {
  let out = "";
  for (const ch of s) {
    const code = ch.codePointAt(0)!;
    if (ch === "&") out += "&amp;";
    else if (ch === "<") out += "&lt;";
    else if (ch === ">") out += "&gt;";
    else if (ch === '"') out += "&quot;";
    else if (code < 0x20 && ch !== "\t" && ch !== "\n" && ch !== "\r") continue;
    else out += ch;
  }
  return out;
}

/** Relationships of one part. */
class Rels {
  items: { id: string; type: string; target: string; external: boolean }[] = [];
  add(type: string, target: string, external = false): string {
    const existing = this.items.find((i) => i.type === type && i.target === target);
    if (existing) return existing.id;
    const id = `rId${this.items.length + 1}`;
    this.items.push({ id, type, target, external });
    return id;
  }
  get xml() {
    return HEADER + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + this.items.map((i) => `<Relationship Id="${i.id}" Type="${relBase}/${i.type}" Target="${esc(i.target)}"${i.external ? ' TargetMode="External"' : ""}/>`).join("")
      + "</Relationships>";
  }
}

class Context {
  mediaFiles = new Map<string, string>();
  entries: [string, Uint8Array | string][] = [];
  mediaCounter = 0;
  contentTypes = new Set<string>();
  constructor(public p: Presentation, public helpers: PPTXHelpers) {}

  addMedia(data: Uint8Array, ext: string, key: string): string {
    const existing = this.mediaFiles.get(key);
    if (existing) return existing;
    this.mediaCounter++;
    const name = `image${this.mediaCounter}.${ext}`;
    this.entries.push([`ppt/media/${name}`, data]);
    this.mediaFiles.set(key, name);
    this.contentTypes.add(ext);
    return name;
  }
}

export function writePPTX(p: Presentation, helpers: PPTXHelpers = {}): Uint8Array {
  const ctx = new Context(p, helpers);
  const hasNotes = p.slides.some((s) => s.notes);
  ctx.entries.push(["ppt/theme/theme1.xml", themeXML(p.theme, p.theme.name)]);
  if (hasNotes) ctx.entries.push(["ppt/theme/theme2.xml", themeXML(p.theme, "Notes")]);

  // Master.
  const masterRels = new Rels();
  let layoutIDs = "";
  LAYOUTS.forEach((_, i) => { layoutIDs += `<p:sldLayoutId id="${2147483649 + i}" r:id="${masterRels.add("slideLayout", `../slideLayouts/slideLayout${i + 1}.xml`)}"/>`; });
  masterRels.add("theme", "../theme/theme1.xml");
  const blank = makeSlide("blank", p.theme, p.slideSize);
  const masterShapes = shapesXML(slideDecorations(blank, p.theme, p.slideSize), ctx, masterRels, 10);
  const titleRect = scaledRect([60, 30, 840, 96], p.slideSize), bodyRect = scaledRect([60, 140, 840, 350], p.slideSize);
  ctx.entries.push(["ppt/slideMasters/slideMaster1.xml", HEADER + `<p:sldMaster ${NAMESPACES}><p:cSld>${backgroundXML(p.theme.background, ctx, masterRels)}<p:spTree>${GROUP_HEADER}`
    + placeholderShape("title", 2, titleRect, null) + placeholderShape("body", 3, bodyRect, 1) + masterShapes + "</p:spTree></p:cSld>"
    + CLR_MAP + `<p:sldLayoutIdLst>${layoutIDs}</p:sldLayoutIdLst>` + textStylesXML(p.theme) + "</p:sldMaster>"]);

  // Layouts.
  LAYOUTS.forEach((layout, i) => {
    const rels = new Rels();
    rels.add("slideMaster", "../slideMasters/slideMaster1.xml");
    const sample = makeSlide(layout, p.theme, p.slideSize);
    let bodyIndex = 0;
    let shapes = "";
    sample.elements.forEach((e, n) => {
      if (!e.placeholder) return;
      let idx: number | null = null;
      if (!isTitleRole(e.placeholder)) idx = ++bodyIndex;
      const f = R(e.frame);
      shapes += placeholderShape(e.placeholder, n + 2, [f.x, f.y, f.w, f.h], idx, "shape" in e.content ? e.content.shape._0.text.prompt : undefined);
    });
    let background = "", showMaster = "";
    if (layout === "title" || layout === "sectionHeader") {
      showMaster = ' showMasterSp="0"';
      background = backgroundXML(p.theme.titleBackground ?? p.theme.background, ctx, rels);
      shapes = shapesXML(slideDecorations(sample, p.theme, p.slideSize), ctx, rels, 20) + shapes;
    }
    ctx.entries.push([`ppt/slideLayouts/slideLayout${i + 1}.xml`, HEADER + `<p:sldLayout ${NAMESPACES} type="${LAYOUT_OOXML[layout]}" preserve="1"${showMaster}><p:cSld name="${esc(LAYOUT_TITLES[layout])}">${background}<p:spTree>${GROUP_HEADER}${shapes}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`]);
    ctx.entries.push([`ppt/slideLayouts/_rels/slideLayout${i + 1}.xml.rels`, rels.xml]);
  });
  ctx.entries.push(["ppt/slideMasters/_rels/slideMaster1.xml.rels", masterRels.xml]);

  if (hasNotes) {
    const rels = new Rels();
    rels.add("theme", "../theme/theme2.xml");
    ctx.entries.push(["ppt/notesMasters/notesMaster1.xml", HEADER + `<p:notesMaster ${NAMESPACES}><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>${GROUP_HEADER}`
      + '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="685800" y="1143000"/><a:ext cx="5486400" cy="3086100"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>'
      + '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="685800" y="4400550"/><a:ext cx="5486400" cy="3600450"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/><a:lstStyle/><a:p><a:pPr lvl="0"/><a:r><a:rPr lang="en-US"/><a:t>Click to edit Master text styles</a:t></a:r></a:p></p:txBody></p:sp>'
      + `</p:spTree></p:cSld>${CLR_MAP}</p:notesMaster>`]);
    ctx.entries.push(["ppt/notesMasters/_rels/notesMaster1.xml.rels", rels.xml]);
  }

  // Slides.
  p.slides.forEach((slide, i) => {
    const rels = new Rels();
    rels.add("slideLayout", `../slideLayouts/slideLayout${Math.max(LAYOUTS.indexOf(slide.layout), 0) + 1}.xml`);
    let bodyIndex = 0;
    const id = { next: 2 };
    let shapes = "";
    for (const e of slide.elements) {
      let idx: number | null = null;
      if (e.placeholder && !isTitleRole(e.placeholder)) idx = ++bodyIndex;
      shapes += elementXML(e, ctx, rels, id, idx);
    }
    shapes += shapesXML(slideFooters(slide, i + 1, p), ctx, rels, 900);
    const background = slide.background ? backgroundXML(slide.background, ctx, rels) : "";
    const attrs = (slide.hidden ? ' show="0"' : "") + (slide.hideBackgroundGraphics ? ' showMasterSp="0"' : "");
    const xml = HEADER + `<p:sld ${NAMESPACES}${attrs}><p:cSld>${background}<p:spTree>${GROUP_HEADER}${shapes}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>`
      + transitionXML(slide.transition) + "</p:sld>";
    if (slide.notes) {
      const notesRels = new Rels();
      notesRels.add("notesMaster", "../notesMasters/notesMaster1.xml");
      notesRels.add("slide", `../slides/slide${i + 1}.xml`);
      rels.add("notesSlide", `../notesSlides/notesSlide${i + 1}.xml`);
      const paragraphs = slide.notes.split("\n").map((line) => `<a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>${esc(line)}</a:t></a:r></a:p>`).join("");
      ctx.entries.push([`ppt/notesSlides/notesSlide${i + 1}.xml`, HEADER + `<p:notes ${NAMESPACES}><p:cSld><p:spTree>${GROUP_HEADER}`
        + '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>'
        + `<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>${paragraphs}</p:txBody></p:sp>`
        + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"]);
      ctx.entries.push([`ppt/notesSlides/_rels/notesSlide${i + 1}.xml.rels`, notesRels.xml]);
    }
    ctx.entries.push([`ppt/slides/slide${i + 1}.xml`, xml]);
    ctx.entries.push([`ppt/slides/_rels/slide${i + 1}.xml.rels`, rels.xml]);
  });

  // Presentation part.
  const presRels = new Rels();
  const masterRID = presRels.add("slideMaster", "slideMasters/slideMaster1.xml");
  const slideIDs = p.slides.map((_, i) => `<p:sldId id="${256 + i}" r:id="${presRels.add("slide", `slides/slide${i + 1}.xml`)}"/>`).join("");
  const notesMasterList = hasNotes ? `<p:notesMasterIdLst><p:notesMasterId r:id="${presRels.add("notesMaster", "notesMasters/notesMaster1.xml")}"/></p:notesMasterIdLst>` : "";
  presRels.add("presProps", "presProps.xml");
  presRels.add("viewProps", "viewProps.xml");
  presRels.add("theme", "theme/theme1.xml");
  presRels.add("tableStyles", "tableStyles.xml");
  let sections = "";
  if (p.sections.length) {
    sections = '<p:extLst><p:ext uri="{521415D9-36F7-43E2-AB2F-B90AF26B5E84}"><p14:sectionLst xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main">';
    p.sections.forEach((section, n) => {
      const start = Math.max(slideIndex(p, section.firstSlideID), 0);
      const end = n + 1 < p.sections.length ? Math.max(slideIndex(p, p.sections[n + 1].firstSlideID), start) : p.slides.length;
      let ids = "";
      for (let s = start; s < end; s++) ids += `<p14:sldId id="${256 + s}"/>`;
      sections += `<p14:section name="${esc(section.name)}" id="{${section.id}}"><p14:sldIdLst>${ids}</p14:sldIdLst></p14:section>`;
    });
    sections += "</p14:sectionLst></p:ext></p:extLst>";
  }
  ctx.entries.push(["ppt/presentation.xml", HEADER + `<p:presentation ${NAMESPACES} saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="${masterRID}"/></p:sldMasterIdLst>${notesMasterList}<p:sldIdLst>${slideIDs}</p:sldIdLst>`
    + `<p:sldSz cx="${emu(p.slideSize[0])}" cy="${emu(p.slideSize[1])}"/><p:notesSz cx="6858000" cy="9144000"/>${sections}</p:presentation>`]);
  ctx.entries.push(["ppt/_rels/presentation.xml.rels", presRels.xml]);
  const showPr = p.showSettings.loopUntilEscape ? '<p:showPr loop="1" showNarration="1"><p:present/><p:sldAll/><p:penClr><a:prstClr val="red"/></p:penClr></p:showPr>' : "";
  ctx.entries.push(["ppt/presProps.xml", HEADER + `<p:presentationPr ${NAMESPACES}>${showPr}</p:presentationPr>`]);
  ctx.entries.push(["ppt/viewProps.xml", HEADER + `<p:viewPr ${NAMESPACES}><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>`]);
  ctx.entries.push(["ppt/tableStyles.xml", HEADER + `<a:tblStyleLst xmlns:a="${nsA}" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>`]);

  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  ctx.entries.push(["docProps/core.xml", HEADER + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    + `<dc:title>${esc(p.title)}</dc:title><dc:creator>${esc(p.author)}</dc:creator><cp:lastModifiedBy>${esc(p.author)}</cp:lastModifiedBy>`
    + `<dcterms:created xsi:type="dcterms:W3CDTF">${esc(p.created)}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}</dcterms:modified></cp:coreProperties>`]);
  ctx.entries.push(["docProps/app.xml", HEADER + `<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Wired Slides</Application><Slides>${p.slides.length}</Slides><PresentationFormat>Custom</PresentationFormat></Properties>`]);
  ctx.entries.push(["_rels/.rels", HEADER + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + `<Relationship Id="rId1" Type="${relBase}/officeDocument" Target="ppt/presentation.xml"/>`
    + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    + `<Relationship Id="rId3" Type="${relBase}/extended-properties" Target="docProps/app.xml"/></Relationships>`]);

  // Content types go first.
  const mimes: Record<string, string> = { png: "image/png", jpeg: "image/jpeg", gif: "image/gif", tiff: "image/tiff", bmp: "image/bmp" };
  const ppt = "application/vnd.openxmlformats-officedocument.presentationml";
  let types = HEADER + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>';
  for (const ext of [...ctx.contentTypes].sort()) types += `<Default Extension="${ext}" ContentType="${mimes[ext] ?? "application/octet-stream"}"/>`;
  types += `<Override PartName="/ppt/presentation.xml" ContentType="${ppt}.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="${ppt}.slideMaster+xml"/>`;
  LAYOUTS.forEach((_, i) => { types += `<Override PartName="/ppt/slideLayouts/slideLayout${i + 1}.xml" ContentType="${ppt}.slideLayout+xml"/>`; });
  p.slides.forEach((s, i) => {
    types += `<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="${ppt}.slide+xml"/>`;
    if (s.notes) types += `<Override PartName="/ppt/notesSlides/notesSlide${i + 1}.xml" ContentType="${ppt}.notesSlide+xml"/>`;
  });
  types += '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>';
  if (hasNotes) types += `<Override PartName="/ppt/theme/theme2.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="${ppt}.notesMaster+xml"/>`;
  types += `<Override PartName="/ppt/presProps.xml" ContentType="${ppt}.presProps+xml"/><Override PartName="/ppt/viewProps.xml" ContentType="${ppt}.viewProps+xml"/><Override PartName="/ppt/tableStyles.xml" ContentType="${ppt}.tableStyles+xml"/>`;
  types += '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>';
  return writeZip([["[Content_Types].xml", types], ...ctx.entries]);
}

// MARK: Theme

function themeXML(theme: PresentationTheme, name: string): string {
  const c = theme.colors;
  const clr = (tag: string, color: typeof c.dark1) => `<a:${tag}><a:srgbClr val="${hexString(color)}"/></a:${tag}>`;
  const scheme = clr("dk1", c.dark1) + clr("lt1", c.light1) + clr("dk2", c.dark2) + clr("lt2", c.light2) + clr("accent1", c.accent1) + clr("accent2", c.accent2)
    + clr("accent3", c.accent3) + clr("accent4", c.accent4) + clr("accent5", c.accent5) + clr("accent6", c.accent6) + clr("hlink", c.hyperlink) + clr("folHlink", c.followedHyperlink);
  const fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
  const line = '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>';
  const fmt = `<a:fmtScheme name="Office"><a:fillStyleLst>${fill}${fill}${fill}</a:fillStyleLst><a:lnStyleLst>${line}${line}${line}</a:lnStyleLst>`
    + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
    + `<a:bgFillStyleLst>${fill}${fill}${fill}</a:bgFillStyleLst></a:fmtScheme>`;
  return HEADER + `<a:theme xmlns:a="${nsA}" name="${esc(name)}"><a:themeElements><a:clrScheme name="${esc(name)}">${scheme}</a:clrScheme>`
    + `<a:fontScheme name="${esc(name)}"><a:majorFont><a:latin typeface="${esc(theme.headingFont)}"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>`
    + `<a:minorFont><a:latin typeface="${esc(theme.bodyFont)}"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>`
    + fmt + "</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>";
}

function textStylesXML(theme: PresentationTheme): string {
  const level = (n: number, size: number, bullet: boolean) => {
    const bu = bullet ? `<a:buFont typeface="Arial"/><a:buChar char="${esc(theme.bulletSymbol)}"/>` : "<a:buNone/>";
    return `<a:lvl${n + 1}pPr marL="${bullet ? emu(n * 28 + 24) : 0}" indent="${bullet ? -emu(24) : 0}" algn="l">${bu}<a:defRPr sz="${int(size * 100)}"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/></a:defRPr></a:lvl${n + 1}pPr>`;
  };
  const title = `<p:titleStyle><a:lvl1pPr algn="l"><a:buNone/><a:defRPr sz="${int(theme.titleSize * 100)}"${theme.titleBold ? ' b="1"' : ""}><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/></a:defRPr></a:lvl1pPr></p:titleStyle>`;
  const body = "<p:bodyStyle>" + [0, 1, 2, 3, 4].map((i) => level(i, Math.max(theme.bodySize - i * 2, 12), true)).join("") + "</p:bodyStyle>";
  return `<p:txStyles>${title}${body}<p:otherStyle>${level(0, 18, false)}</p:otherStyle></p:txStyles>`;
}

// MARK: Colors and fills

function colorXML(color: PaintColor): string {
  if ("rgb" in color) {
    const c = color.rgb._0;
    return c.a < 1 ? `<a:srgbClr val="${hexString(c)}"><a:alpha val="${int(c.a * 100000)}"/></a:srgbClr>` : `<a:srgbClr val="${hexString(c)}"/>`;
  }
  const { _0: slot, shade, alpha } = color.theme;
  const name = slot === "dark1" ? "tx1" : slot === "light1" ? "bg1" : slot === "dark2" ? "tx2" : slot === "light2" ? "bg2" : SLOT_OOXML[slot];
  let mods = "";
  if (shade > 0) mods += `<a:lumMod val="${int((1 - shade) * 100000)}"/><a:lumOff val="${int(shade * 100000)}"/>`;
  if (shade < 0) mods += `<a:lumMod val="${int((1 + shade) * 100000)}"/>`;
  if (alpha < 1) mods += `<a:alpha val="${int(alpha * 100000)}"/>`;
  return mods ? `<a:schemeClr val="${name}">${mods}</a:schemeClr>` : `<a:schemeClr val="${name}"/>`;
}

function fillXML(fill: Fill, ctx: Context, rels: Rels): string {
  if ("none" in fill) return "<a:noFill/>";
  if ("solid" in fill) return `<a:solidFill>${colorXML(fill.solid._0)}</a:solidFill>`;
  if ("gradient" in fill) {
    const g = fill.gradient._0;
    const stops = g.stops.map((s) => `<a:gs pos="${int(s.position * 100000)}">${colorXML(s.color)}</a:gs>`).join("");
    const shade = g.kind === "linear" ? `<a:lin ang="${int((g.angle % 360) * 60000)}" scaled="0"/>` : '<a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path>';
    return `<a:gradFill rotWithShape="1"><a:gsLst>${stops}</a:gsLst>${shade}</a:gradFill>`;
  }
  if ("image" in fill) {
    const image = fill.image._0;
    const file = mediaFile(image.mediaID, ctx);
    if (!file) return "<a:noFill/>";
    const rid = rels.add("image", `../media/${file}`);
    const mode = image.mode === "tile" ? '<a:tile tx="0" ty="0" sx="100000" sy="100000" flip="none" algn="tl"/>' : "<a:stretch><a:fillRect/></a:stretch>";
    const alpha = image.transparency > 0 ? `<a:alphaModFix amt="${int((1 - image.transparency) * 100000)}"/>` : "";
    return `<a:blipFill dpi="0" rotWithShape="1"><a:blip r:embed="${rid}">${alpha}</a:blip>${mode}</a:blipFill>`;
  }
  const pattern = fill.pattern._0;
  const preset = { horizontal: "ltHorz", vertical: "ltVert", diagonalUp: "ltUpDiag", diagonalDown: "ltDnDiag", grid: "smGrid", dots: "pct10", checker: "smCheck" }[pattern.kind];
  return `<a:pattFill prst="${preset}"><a:fgClr>${colorXML(pattern.foreground)}</a:fgClr><a:bgClr>${colorXML(pattern.background)}</a:bgClr></a:pattFill>`;
}

const backgroundXML = (fill: Fill, ctx: Context, rels: Rels) => `<p:bg><p:bgPr>${fillXML(fill, ctx, rels)}<a:effectLst/></p:bgPr></p:bg>`;

function lineXML(line: LineStyle): string {
  if (!line.color || line.width <= 0) return "<a:ln><a:noFill/></a:ln>";
  let s = `<a:ln w="${emu(line.width)}"${line.roundCaps ? ' cap="rnd"' : ""}><a:solidFill>${colorXML(line.color)}</a:solidFill>`;
  if (line.dash !== "solid") s += `<a:prstDash val="${DASH_OOXML[line.dash]}"/>`;
  s += "<a:round/>";
  if (line.head !== "none") s += `<a:headEnd type="${ARROW_OOXML[line.head]}"/>`;
  if (line.tail !== "none") s += `<a:tailEnd type="${ARROW_OOXML[line.tail]}"/>`;
  return s + "</a:ln>";
}

function effectsXML(fx: Effects): string {
  if (effectsEmpty(fx)) return "";
  let s = "<a:effectLst>";
  if (fx.glow) s += `<a:glow rad="${emu(fx.glow.radius)}">${colorXML(fx.glow.color)}</a:glow>`;
  if (fx.shadow) {
    const sh = fx.shadow;
    s += `<a:outerShdw blurRad="${emu(sh.blur)}" dist="${emu(sh.distance)}" dir="${int(sh.angle * 60000)}" algn="ctr" rotWithShape="0"><a:srgbClr val="${hexString(sh.color)}"><a:alpha val="${int(sh.opacity * 100000)}"/></a:srgbClr></a:outerShdw>`;
  }
  if (fx.reflection) {
    const r = fx.reflection;
    s += `<a:reflection blurRad="6350" stA="${int(r.opacity * 100000)}" endPos="${int(r.size * 100000)}" dist="${emu(r.distance)}" dir="5400000" sy="-100000" algn="bl" rotWithShape="0"/>`;
  }
  return s + "</a:effectLst>";
}

function xfrmXML(e: SlideElement, tag = "a:xfrm", children = false): string {
  const f = R(e.frame);
  let attrs = "";
  if (e.rotation) attrs += ` rot="${int((e.rotation % 360) * 60000)}"`;
  if (e.flipH) attrs += ' flipH="1"';
  if (e.flipV) attrs += ' flipV="1"';
  const off = `<a:off x="${emu(f.x)}" y="${emu(f.y)}"/><a:ext cx="${emu(f.w)}" cy="${emu(f.h)}"/>`;
  const child = children ? `<a:chOff x="${emu(f.x)}" y="${emu(f.y)}"/><a:chExt cx="${emu(f.w)}" cy="${emu(f.h)}"/>` : "";
  return `<${tag}${attrs}>${off}${child}</${tag}>`;
}

// MARK: Text

function textBodyXML(body: TextBody, _ctx: Context, rels: Rels, tag = "p:txBody"): string {
  const anchor = body.anchor === "top" ? "t" : body.anchor === "middle" ? "ctr" : "b";
  let attrs = ` wrap="${body.wrap ? "square" : "none"}" lIns="${emu(body.insets.left)}" tIns="${emu(body.insets.top)}" rIns="${emu(body.insets.right)}" bIns="${emu(body.insets.bottom)}" anchor="${anchor}" rtlCol="0"`;
  if (body.columns > 1) attrs += ` numCol="${body.columns}" spcCol="${emu(14)}"`;
  if (body.direction === "rotated90") attrs += ' vert="vert"'; else if (body.direction === "rotated270") attrs += ' vert="vert270"';
  const fit = body.autofit === "shrink" ? "<a:normAutofit/>" : body.autofit === "resizeShape" ? "<a:spAutoFit/>" : "<a:noAutofit/>";
  return `<${tag}><a:bodyPr${attrs}>${fit}</a:bodyPr><a:lstStyle/>` + body.paragraphs.map((p) => paragraphXML(p, body, rels)).join("") + `</${tag}>`;
}

function paragraphXML(paragraph: Paragraph, body: TextBody, rels: Rels): string {
  const st = paragraph.style;
  const algn = { left: "l", center: "ctr", right: "r", justify: "just" }[st.alignment];
  const hasBullet = !bulletIsNone(st.bullet);
  const unit = Math.max(body.defaultSize / 24, 0.6);
  let p = `<a:p><a:pPr marL="${emu((st.level * 28 + (hasBullet ? 24 : 0)) * unit)}" lvl="${st.level}" indent="${hasBullet ? -emu(24 * unit) : 0}" algn="${algn}">`;
  p += `<a:lnSpc><a:spcPct val="${int(st.lineSpacing * 100000)}"/></a:lnSpc><a:spcBef><a:spcPts val="${int(st.spaceBefore * 100)}"/></a:spcBef><a:spcAft><a:spcPts val="${int(st.spaceAfter * 100)}"/></a:spcAft>`;
  if (st.bulletColor && hasBullet) p += `<a:buClr>${colorXML(st.bulletColor)}</a:buClr>`;
  if ("symbol" in st.bullet) p += `<a:buFont typeface="Arial"/><a:buChar char="${esc(st.bullet.symbol._0)}"/>`;
  else if ("numbered" in st.bullet) {
    const n = st.bullet.numbered;
    p += `<a:buFont typeface="+mj-lt"/><a:buAutoNum type="${NUMBERING_OOXML[n._0]}"${n.start !== 1 ? ` startAt="${n.start}"` : ""}/>`;
  } else p += "<a:buNone/>";
  p += "</a:pPr>";
  for (const run of paragraph.runs) {
    if (!run.text) continue;
    run.text.split("\u2028").forEach((piece, i) => {
      if (i > 0) p += `<a:br>${runPropertiesXML(run.style, body, rels)}</a:br>`;
      p += `<a:r>${runPropertiesXML(run.style, body, rels)}<a:t>${esc(piece)}</a:t></a:r>`;
    });
  }
  const end = paragraph.runs[paragraph.runs.length - 1]?.style;
  return p + `<a:endParaRPr lang="en-US" sz="${int((end?.size ?? body.defaultSize) * 100)}" dirty="0"/></a:p>`;
}

function runPropertiesXML(st: RunStyle, body: TextBody, rels: Rels): string {
  let attrs = ` lang="en-US" sz="${int((st.size ?? body.defaultSize) * 100)}"`;
  if (st.bold === true) attrs += ' b="1"'; else if (st.bold === false) attrs += ' b="0"';
  if (st.italic) attrs += ' i="1"';
  if (st.underline || st.link) attrs += ' u="sng"';
  if (st.strikethrough) attrs += ' strike="sngStrike"';
  if (st.baseline) attrs += ` baseline="${st.baseline > 0 ? 30000 : -25000}"`;
  if (st.allCaps) attrs += ' cap="all"'; else if (st.smallCaps) attrs += ' cap="small"';
  if (st.characterSpacing) attrs += ` spc="${int(st.characterSpacing * 100)}"`;
  attrs += ' dirty="0"';
  let s = `<a:rPr${attrs}>`;
  if (st.outlineColor && st.outlineWidth > 0) s += `<a:ln w="${emu(st.outlineWidth)}"><a:solidFill>${colorXML(st.outlineColor)}</a:solidFill></a:ln>`;
  s += `<a:solidFill>${colorXML(st.color ?? (st.link ? { theme: { _0: "hyperlink", shade: 0, alpha: 1 } } : body.defaultColor))}</a:solidFill>`;
  if (st.shadow) s += '<a:effectLst><a:outerShdw blurRad="38100" dist="38100" dir="2700000" algn="tl"><a:srgbClr val="000000"><a:alpha val="43137"/></a:srgbClr></a:outerShdw></a:effectLst>';
  if (st.highlight) s += `<a:highlight><a:srgbClr val="${hexString(st.highlight)}"/></a:highlight>`;
  s += `<a:latin typeface="${esc(st.fontFamily ?? (body.fontRole === "heading" ? "+mj-lt" : "+mn-lt"))}"/>`;
  if (st.link) s += `<a:hlinkClick r:id="${rels.add("hyperlink", st.link, true)}"/>`;
  return s + "</a:rPr>";
}

// MARK: Elements

function placeholderShape(role: PlaceholderRole, id: number, r: [number, number, number, number], idx: number | null, prompt?: string): string {
  const promptXML = prompt ? `<a:p><a:r><a:rPr lang="en-US"/><a:t>${esc(prompt)}</a:t></a:r></a:p>` : '<a:p><a:endParaRPr lang="en-US"/></a:p>';
  return `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="${isTitleRole(role) ? "Title" : "Placeholder"} ${id}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="${PLACEHOLDER_OOXML[role]}"${idx !== null ? ` idx="${idx}"` : ""}/></p:nvPr></p:nvSpPr>`
    + `<p:spPr><a:xfrm><a:off x="${emu(r[0])}" y="${emu(r[1])}"/><a:ext cx="${emu(r[2])}" cy="${emu(r[3])}"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>${promptXML}</p:txBody></p:sp>`;
}

function shapesXML(elements: SlideElement[], ctx: Context, rels: Rels, firstID: number): string {
  const id = { next: firstID };
  return elements.map((e) => elementXML(e, ctx, rels, id, null)).join("");
}

function actionXML(e: SlideElement, ctx: Context, rels: Rels): string {
  const a = e.action;
  if (!a) return "";
  if ("url" in a) return `<a:hlinkClick r:id="${rels.add("hyperlink", a.url._0, true)}"/>`;
  if ("slide" in a) {
    const index = slideIndex(ctx.p, a.slide._0);
    return index < 0 ? "" : `<a:hlinkClick r:id="${rels.add("slide", `slide${index + 1}.xml`)}" action="ppaction://hlinksldjump"/>`;
  }
  const jump = "nextSlide" in a ? "nextslide" : "previousSlide" in a ? "previousslide" : "firstSlide" in a ? "firstslide" : "lastSlide" in a ? "lastslide" : "endshow";
  return `<a:hlinkClick r:id="" action="ppaction://hlinkshowjump?jump=${jump}"/>`;
}

function cNvPr(e: SlideElement, id: number, ctx: Context, rels: Rels): string {
  const descr = e.altText ? ` descr="${esc(e.altText)}"` : "";
  const hidden = e.hidden ? ' hidden="1"' : "";
  const action = actionXML(e, ctx, rels);
  return action ? `<p:cNvPr id="${id}" name="${esc(e.name)}"${descr}${hidden}>${action}</p:cNvPr>` : `<p:cNvPr id="${id}" name="${esc(e.name)}"${descr}${hidden}/>`;
}

function mediaFile(id: string, ctx: Context): string | null {
  const item = ctx.p.media[id];
  if (!item) return null;
  let ext = item.filename.split(".").pop()?.toLowerCase() ?? "";
  let data: Uint8Array | null = item.data;
  if (!["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp"].includes(ext)) {
    data = ctx.helpers.toPNG?.(id) ?? null;
    if (!data) return null;
    ext = "png";
  }
  if (ext === "jpg") ext = "jpeg";
  if (ext === "tif") ext = "tiff";
  return ctx.addMedia(data, ext, id);
}

function pictureXML(e: SlideElement, file: string, id: number, ctx: Context, rels: Rels, o: { crop?: CropInsets; adjustments?: ImageAdjustments; line?: LineStyle; effects?: Effects; mask?: ShapeKind } = {}): string {
  const rid = rels.add("image", `../media/${file}`);
  const adj = o.adjustments ?? identityAdjustments(), crop = o.crop ?? zeroCrop();
  let blip = "";
  if (adj.saturation === 0) blip += "<a:grayscl/>";
  if (adj.brightness || adj.contrast) blip += `<a:lum bright="${int(adj.brightness * 50000)}" contrast="${int(adj.contrast * 100000)}"/>`;
  if (adj.transparency > 0) blip = `<a:alphaModFix amt="${int((1 - adj.transparency) * 100000)}"/>` + blip;
  const src = cropZero(crop) ? "" : `<a:srcRect l="${int(crop.left * 100000)}" t="${int(crop.top * 100000)}" r="${int(crop.right * 100000)}" b="${int(crop.bottom * 100000)}"/>`;
  const line = o.line ?? NO_LINE();
  return `<p:pic><p:nvPicPr>${cNvPr(e, id, ctx, rels)}<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>`
    + `<p:blipFill><a:blip r:embed="${rid}">${blip}</a:blip>${src}<a:stretch><a:fillRect/></a:stretch></p:blipFill>`
    + `<p:spPr>${xfrmXML(e)}<a:prstGeom prst="${o.mask ?? "rect"}"><a:avLst/></a:prstGeom>${lineVisible(line) ? lineXML(line) : ""}${effectsXML(o.effects ?? noEffects())}</p:spPr></p:pic>`;
}

function renderedPictureXML(e: SlideElement, id: number, ctx: Context, rels: Rels): string {
  const flat = { ...e, rotation: 0 };
  const rendered = ctx.helpers.rasterize?.(flat);
  if (!rendered) return "";
  const file = ctx.addMedia(rendered.png, "png", `render-${e.id}-${ctx.mediaCounter}`);
  const placed: SlideElement = { ...e, frame: [[rendered.bounds.x, rendered.bounds.y], [rendered.bounds.w, rendered.bounds.h]], flipH: false, flipV: false };
  return pictureXML(placed, file, id, ctx, rels);
}

function elementXML(e: SlideElement, ctx: Context, rels: Rels, ids: { next: number }, placeholderIndex: number | null): string {
  const myID = ids.next++;
  const c = e.content;
  if ("shape" in c) {
    const s = c.shape._0;
    let nvPr = "<p:nvPr/>";
    if (e.placeholder && e.placeholder !== "picture") nvPr = `<p:nvPr><p:ph type="${PLACEHOLDER_OOXML[e.placeholder]}"${placeholderIndex !== null ? ` idx="${placeholderIndex}"` : ""}/></p:nvPr>`;
    const isTextBox = isNoFill(s.fill) && !lineVisible(s.line) && !e.placeholder;
    let adj = "";
    if (s.adjustments.length && !isCallout(s.kind)) {
      const names = s.adjustments.length === 1 ? ["adj"] : s.adjustments.map((_, i) => `adj${i + 1}`);
      // Stars store the inner radius out of 50000; pies store angles in 60000ths of a degree.
      const factor = isStar(s.kind) ? 50000 : s.kind === "pie" || s.kind === "chord" ? 60000 : 100000;
      s.adjustments.forEach((v, i) => { adj += `<a:gd name="${names[i]}" fmla="val ${int(v * factor)}"/>`; });
    }
    return `<p:sp><p:nvSpPr>${cNvPr(e, myID, ctx, rels)}<p:cNvSpPr${isTextBox ? ' txBox="1"' : ""}/>${nvPr}</p:nvSpPr>`
      + `<p:spPr>${xfrmXML(e)}<a:prstGeom prst="${s.kind}"><a:avLst>${adj}</a:avLst></a:prstGeom>${fillXML(s.fill, ctx, rels)}${lineXML(s.line)}${effectsXML(s.effects)}</p:spPr>`
      + textBodyXML(s.text, ctx, rels) + "</p:sp>";
  }
  if ("image" in c) {
    const image = c.image._0;
    const file = mediaFile(image.mediaID, ctx);
    if (!file) return "";
    return pictureXML(e, file, myID, ctx, rels, { crop: image.crop, adjustments: image.adjustments, line: image.line, effects: image.effects, mask: image.maskShape });
  }
  if ("line" in c) {
    const line = c.line._0;
    return `<p:cxnSp><p:nvCxnSpPr>${cNvPr(e, myID, ctx, rels)}<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>`
      + `<p:spPr>${xfrmXML(e)}<a:prstGeom prst="${CONNECTOR_OOXML[line.kind]}"><a:avLst/></a:prstGeom>${lineXML(line.line)}${effectsXML(line.effects)}</p:spPr></p:cxnSp>`;
  }
  if ("table" in c) return tableXML(e, c.table._0, myID, ctx, rels);
  if ("chart" in c || "icon" in c) return renderedPictureXML(e, myID, ctx, rels);
  if ("media" in c) {
    const poster = c.media._0.posterID;
    const file = poster ? mediaFile(poster, ctx) : null;
    return file ? pictureXML(e, file, myID, ctx, rels) : renderedPictureXML(e, myID, ctx, rels);
  }
  const g = c.group._0;
  let xml = `<p:grpSp><p:nvGrpSpPr>${cNvPr(e, myID, ctx, rels)}<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>${xfrmXML(e, "a:xfrm", true)}</p:grpSpPr>`;
  for (const child of g.children) xml += elementXML(child, ctx, rels, ids, null);
  return xml + "</p:grpSp>";
}

function tableXML(e: SlideElement, t: TableContent, id: number, ctx: Context, rels: Rels): string {
  const f = R(e.frame);
  const totalW = Math.max(t.columnWidths.reduce((a, b) => a + b, 0), 1);
  const s = t.style;
  let xml = `<p:graphicFrame><p:nvGraphicFramePr>${cNvPr(e, id, ctx, rels)}<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>`;
  xml += `<p:xfrm><a:off x="${emu(f.x)}" y="${emu(f.y)}"/><a:ext cx="${emu(f.w)}" cy="${emu(f.h)}"/></p:xfrm>`;
  xml += `<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="${s.headerRow ? 1 : 0}" bandRow="${s.bandedRows ? 1 : 0}" lastRow="${s.totalRow ? 1 : 0}" firstCol="${s.firstColumn ? 1 : 0}"/><a:tblGrid>`;
  for (const w of t.columnWidths) xml += `<a:gridCol w="${emu((w / totalW) * f.w)}"/>`;
  xml += "</a:tblGrid>";
  const borderColor: PaintColor = s.borderColor ?? (s.intensity === 1 ? s.color : { rgb: { _0: { r: 1, g: 1, b: 1, a: 1 } } });
  const border = `<a:solidFill>${colorXML(borderColor)}</a:solidFill>`;
  const lineW = emu(s.borderColor ? s.borderWidth : 1);
  const colors = ctx.p.theme.colors;
  t.rows.forEach((row, r) => {
    xml += `<a:tr h="${emu(t.rowHeights[r] ?? 37)}">`;
    row.forEach((cell, col) => {
      let attrs = "";
      if (cell.columnSpan > 1) attrs += ` gridSpan="${cell.columnSpan}"`;
      if (cell.rowSpan > 1) attrs += ` rowSpan="${cell.rowSpan}"`;
      if (cell.isMerged) {
        const coveredHorizontally = row.slice(0, col).some((o, c2) => !o.isMerged && c2 + o.columnSpan > col);
        attrs += coveredHorizontally ? ' hMerge="1"' : ' vMerge="1"';
      }
      const body = styledCellBody(t, r, col, colors);
      xml += `<a:tc${attrs}>${textBodyXML(body, ctx, rels, "a:txBody")}`;
      const anchor = cell.text.anchor === "top" ? "t" : cell.text.anchor === "middle" ? "ctr" : "b";
      xml += `<a:tcPr marL="${emu(cell.text.insets.left)}" marR="${emu(cell.text.insets.right)}" marT="${emu(cell.text.insets.top)}" marB="${emu(cell.text.insets.bottom)}" anchor="${anchor}">`;
      for (const side of ["lnL", "lnR", "lnT", "lnB"]) xml += `<a:${side} w="${lineW}">${border}</a:${side}>`;
      if (cell.fill) xml += fillXML(cell.fill, ctx, rels);
      else {
        const look = cellAppearance(t, r, col, colors).fill;
        xml += look ? `<a:solidFill><a:srgbClr val="${hexString(look)}"/></a:solidFill>` : "<a:noFill/>";
      }
      xml += "</a:tcPr></a:tc>";
    });
    xml += "</a:tr>";
  });
  return xml + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame>";
}

function transitionXML(t: Transition): string {
  if (t.kind === "none" && t.advanceOnClick && t.advanceAfter === undefined) return "";
  const speed = t.duration < 0.6 ? "fast" : t.duration < 1.2 ? "med" : "slow";
  let attrs = ` spd="${speed}"`;
  if (!t.advanceOnClick) attrs += ' advClick="0"';
  if (t.advanceAfter !== undefined) attrs += ` advTm="${int(t.advanceAfter * 1000)}"`;
  const dir = DIRECTION_OOXML[t.direction];
  const effects: Record<Transition["kind"], string> = {
    none: "", morph: "", fade: "<p:fade/>", fadeThroughBlack: '<p:fade thruBlk="1"/>', push: `<p:push dir="${dir}"/>`, flip: `<p:push dir="${dir}"/>`,
    cube: `<p:push dir="${dir}"/>`, wipe: `<p:wipe dir="${dir}"/>`, split: '<p:split orient="vert" dir="out"/>', reveal: `<p:cover dir="${dir}"/>`,
    cover: `<p:cover dir="${dir}"/>`, uncover: `<p:pull dir="${dir}"/>`, zoom: "<p:zoom/>", circle: "<p:circle/>", dissolve: "<p:dissolve/>", blinds: '<p:blinds dir="vert"/>',
  };
  return `<p:transition${attrs}>${effects[t.kind]}</p:transition>`;
}

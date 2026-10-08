import type {
  LayoutKind, MediaItem, PlaceholderRole, Presentation, PresentationTheme, Size, Slide, SlideElement, TextAlignment, UUID, VerticalAnchor,
} from "./types";
import {
  NO_FILL, NO_LINE, R, clone, effectsEmpty, element, elementMediaIDs, emptyTextBody, fillMediaIDs, frame, hasText, imageOf, isTitleRole,
  isoNow, noEffects, paragraph, plainParagraphStyle, plainRun, plainText, rgbHex, shapeContent, shapeOf, symbolBullet, textIsEmpty, textOf, themePaint, uuid,
} from "./core";
import { newTransition } from "./catalog";
import { themeById } from "./themes";

// MARK: Layouts

interface Spec {
  role: PlaceholderRole;
  rect: [number, number, number, number];
  prompt: string;
  size: number;
  heading: boolean;
  alignment?: TextAlignment;
  anchor?: VerticalAnchor;
  bullets?: boolean;
  bold?: boolean;
  colorShade?: number;
}

export function layoutSpecs(layout: LayoutKind, theme: PresentationTheme): Spec[] {
  const t = theme.titleSize, b = theme.bodySize;
  const title: Spec = { role: "title", rect: [60, 30, 840, 96], prompt: "Click to add title", size: t, heading: true, anchor: "middle" };
  switch (layout) {
    case "title":
      return [
        { role: "centeredTitle", rect: [120, 120, 720, 170], prompt: "Click to add title", size: t * 1.4, heading: true, alignment: "center", anchor: "bottom" },
        { role: "subtitle", rect: [120, 304, 720, 110], prompt: "Click to add subtitle", size: b, heading: false, alignment: "center", colorShade: 0.25 },
      ];
    case "titleContent":
      return [title, { role: "body", rect: [60, 140, 840, 350], prompt: "Click to add text", size: b, heading: false, bullets: true }];
    case "sectionHeader":
      return [
        { role: "title", rect: [66, 130, 828, 200], prompt: "Click to add section title", size: t * 1.4, heading: true, anchor: "bottom" },
        { role: "body", rect: [66, 340, 828, 90], prompt: "Click to add text", size: b * 0.85, heading: false, colorShade: 0.3 },
      ];
    case "twoContent":
      return [
        title,
        { role: "body", rect: [60, 140, 410, 350], prompt: "Click to add text", size: b * 0.9, heading: false, bullets: true },
        { role: "body", rect: [490, 140, 410, 350], prompt: "Click to add text", size: b * 0.9, heading: false, bullets: true },
      ];
    case "comparison":
      return [
        title,
        { role: "body", rect: [60, 136, 410, 52], prompt: "Click to add text", size: b, heading: false, anchor: "bottom", bold: true },
        { role: "body", rect: [60, 194, 410, 296], prompt: "Click to add text", size: b * 0.85, heading: false, bullets: true },
        { role: "body", rect: [490, 136, 410, 52], prompt: "Click to add text", size: b, heading: false, anchor: "bottom", bold: true },
        { role: "body", rect: [490, 194, 410, 296], prompt: "Click to add text", size: b * 0.85, heading: false, bullets: true },
      ];
    case "titleOnly":
      return [title];
    case "blank":
      return [];
    case "contentCaption":
      return [
        { role: "title", rect: [60, 40, 320, 120], prompt: "Click to add title", size: t * 0.75, heading: true, anchor: "bottom" },
        { role: "body", rect: [420, 40, 480, 450], prompt: "Click to add text", size: b, heading: false, bullets: true },
        { role: "body", rect: [60, 175, 320, 315], prompt: "Click to add text", size: b * 0.65, heading: false, colorShade: 0.2 },
      ];
    case "pictureCaption":
      return [
        { role: "title", rect: [60, 40, 320, 120], prompt: "Click to add title", size: t * 0.75, heading: true, anchor: "bottom" },
        { role: "picture", rect: [420, 40, 480, 450], prompt: "Click icon to add picture", size: b, heading: false, alignment: "center", anchor: "middle" },
        { role: "body", rect: [60, 175, 320, 315], prompt: "Click to add text", size: b * 0.65, heading: false, colorShade: 0.2 },
      ];
    case "quote":
      return [
        { role: "title", rect: [120, 110, 720, 220], prompt: "“Click to add a quote”", size: t * 0.9, heading: true, alignment: "center", anchor: "middle" },
        { role: "body", rect: [120, 350, 720, 60], prompt: "— Click to add source", size: b * 0.8, heading: false, alignment: "center", colorShade: 0.3 },
      ];
    case "bigNumber":
      return [
        { role: "title", rect: [60, 90, 840, 220], prompt: "100%", size: 120, heading: true, alignment: "center", anchor: "bottom", bold: true },
        { role: "body", rect: [60, 320, 840, 100], prompt: "Click to add text", size: b, heading: false, alignment: "center", colorShade: 0.25 },
      ];
  }
}

export function scaledRect(r: [number, number, number, number], size: Size): [number, number, number, number] {
  const sx = size[0] / 960, sy = size[1] / 540;
  return [r[0] * sx, r[1] * sy, r[2] * sx, r[3] * sy];
}

function placeholder(spec: Spec, theme: PresentationTheme, size: Size): SlideElement {
  const body = emptyTextBody();
  const run = plainRun();
  if (spec.bold || (spec.heading && theme.titleBold)) run.bold = true;
  if (spec.heading && theme.titleCaps) run.allCaps = true;
  const style = plainParagraphStyle(spec.alignment ?? "left");
  if (spec.bullets) {
    style.bullet = symbolBullet(theme.bulletSymbol);
    if (theme.bulletColor) style.bulletColor = clone(theme.bulletColor);
    style.spaceBefore = 8;
  }
  if (spec.heading) style.lineSpacing = 0.9;
  body.paragraphs = [{ runs: [{ text: "", style: run }], style }];
  body.defaultSize = spec.size;
  body.fontRole = spec.heading ? "heading" : "body";
  body.anchor = spec.anchor ?? "top";
  body.autofit = "shrink";
  body.prompt = spec.prompt;
  body.defaultColor = spec.heading ? clone(theme.titleColor) : themePaint("dark1", spec.colorShade ?? 0);
  const name = isTitleRole(spec.role) ? "Title" : spec.role === "subtitle" ? "Subtitle" : spec.role === "picture" ? "Picture Placeholder" : "Content Placeholder";
  const [x, y, w, h] = scaledRect(spec.rect, size);
  return element(name, frame(x, y, w, h), { shape: { _0: shapeContent("rect", NO_FILL, NO_LINE(), body) } }, spec.role);
}

export function newSlide(layout: LayoutKind): Slide {
  return {
    id: uuid(), layout, elements: [], notes: "", transition: newTransition(), animations: [], hidden: false, comments: [], hideBackgroundGraphics: false,
  };
}

export function makeSlide(layout: LayoutKind, theme: PresentationTheme, size: Size): Slide {
  const slide = newSlide(layout);
  const count: Partial<Record<PlaceholderRole, number>> = {};
  slide.elements = layoutSpecs(layout, theme).map((spec) => {
    const e = placeholder(spec, theme, size);
    count[spec.role] = (count[spec.role] ?? 0) + 1;
    if (count[spec.role]! > 1) e.name += ` ${count[spec.role]}`;
    return e;
  });
  return slide;
}

/** Applies a different layout, moving existing placeholder text into the new placeholders. */
export function applyLayout(layout: LayoutKind, slide: Slide, theme: PresentationTheme, size: Size) {
  const fresh = makeSlide(layout, theme, size).elements;
  const oldPlaceholders = slide.elements.filter((e) => e.placeholder);
  const others = slide.elements.filter((e) => !e.placeholder);
  const result: SlideElement[] = [];
  for (const target of fresh) {
    const wantsTitle = isTitleRole(target.placeholder);
    const i = oldPlaceholders.findIndex((e) => isTitleRole(e.placeholder) === wantsTitle && (e.placeholder === "picture") === (target.placeholder === "picture"));
    if (i >= 0) {
      const [old] = oldPlaceholders.splice(i, 1);
      const oldText = textOf(old), newText = textOf(target);
      if (oldText && !textIsEmpty(oldText) && newText) {
        newText.paragraphs = oldText.paragraphs;
      } else if (old.placeholder === "picture" && elementMediaIDs(old).length) {
        old.frame = target.frame;
        result.push(old);
        continue;
      }
      target.id = old.id;
    }
    result.push(target);
  }
  for (const leftover of oldPlaceholders) {
    if (hasText(leftover) || imageOf(leftover)) {
      delete leftover.placeholder;
      others.push(leftover);
    }
  }
  slide.layout = layout;
  slide.elements = [...result, ...others];
}

/** Restores placeholder positions and formatting of the layout (Reset). */
export function resetSlide(slide: Slide, theme: PresentationTheme, size: Size) {
  const fresh = makeSlide(slide.layout, theme, size).elements;
  const used = new Set<UUID>();
  for (const e of slide.elements) {
    if (!e.placeholder) continue;
    const match = fresh.find((f) => f.placeholder === e.placeholder && !used.has(f.id));
    if (!match) continue;
    used.add(match.id);
    e.frame = match.frame;
    e.rotation = 0;
    const text = textOf(e), freshText = textOf(match);
    if (text && freshText) {
      const pStyle = freshText.paragraphs[0]?.style ?? plainParagraphStyle();
      const rStyle = freshText.paragraphs[0]?.runs[0]?.style ?? plainRun();
      text.paragraphs = text.paragraphs.map((p) => ({
        runs: p.runs.map((r) => ({ text: r.text, style: clone(rStyle) })),
        style: { ...clone(pStyle), level: p.style.level },
      }));
      text.defaultSize = freshText.defaultSize;
      text.defaultColor = freshText.defaultColor;
      text.anchor = freshText.anchor;
      text.fontRole = freshText.fontRole;
    }
    const s = shapeOf(e);
    if (s) { s.fill = NO_FILL; s.line = NO_LINE(); s.effects = noEffects(); }
  }
}

// MARK: Presentation

export function newPresentation(theme: PresentationTheme = themeById("wired"), slides?: Slide[]): Presentation {
  const size: Size = [960, 540];
  return {
    slides: slides ?? [makeSlide("title", theme, size)],
    theme,
    slideSize: size,
    sections: [],
    headerFooter: { showDate: false, showSlideNumber: false, showFooter: false, footerText: "", hideOnTitleSlide: true },
    showSettings: { loopUntilEscape: false, showWithoutAnimation: false, useTimings: true, usePresenterView: true, penColor: rgbHex(0xe53935), laserColor: rgbHex(0xff1e1e) },
    title: "",
    author: "",
    created: isoNow(),
    media: {},
  };
}

export const slideIndex = (p: Presentation, id: UUID) => p.slides.findIndex((s) => s.id === id);
export const slideMediaIDs = (s: Slide) => [...s.elements.flatMap(elementMediaIDs), ...fillMediaIDs(s.background)];
export const themeMediaIDs = (t: PresentationTheme) => [
  ...fillMediaIDs(t.background), ...fillMediaIDs(t.titleBackground), ...t.decorations.flatMap(elementMediaIDs), ...t.titleDecorations.flatMap(elementMediaIDs),
];

/** Removes media no element uses any more. */
export function pruneMedia(p: Presentation) {
  const used = new Set([...p.slides.flatMap(slideMediaIDs), ...themeMediaIDs(p.theme)]);
  for (const id of Object.keys(p.media)) if (!used.has(id)) delete p.media[id];
}

function sameBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export function addMedia(p: Presentation, data: Uint8Array, filename: string): string {
  for (const [id, item] of Object.entries(p.media)) if (sameBytes(item.data, data)) return id;
  const ext = filename.includes(".") ? filename.split(".").pop()!.toLowerCase() : "";
  const id = uuid() + (ext ? "." + ext : "");
  p.media[id] = { filename, data } satisfies MediaItem;
  return id;
}

export function slideTitle(slide: Slide): string {
  const titled = slide.elements.find((e) => isTitleRole(e.placeholder));
  const text = (titled && textOf(titled) && plainText(textOf(titled)!)) || slide.elements.map((e) => (hasText(e) ? plainText(textOf(e)!) : "")).find((t) => t) || "";
  return text.split("\n")[0].trim();
}

/** The section containing a slide. */
export function sectionFor(p: Presentation, index: number) {
  let current = null;
  for (let i = 0; i <= index && i < p.slides.length; i++) {
    const s = p.sections.find((x) => x.firstSlideID === p.slides[i].id);
    if (s) current = s;
  }
  return current;
}

export function sectionRanges(p: Presentation) {
  const starts = p.sections.map((s) => ({ section: s, start: slideIndex(p, s.firstSlideID) })).filter((x) => x.start >= 0).sort((a, b) => a.start - b.start);
  return starts.map((x, i) => ({ section: x.section, start: x.start, end: i + 1 < starts.length ? starts[i + 1].start : p.slides.length }));
}

export const visibleSlideIndices = (p: Presentation) => p.slides.map((_, i) => i).filter((i) => !p.slides[i].hidden);

/** Text paragraphs with outline levels, as `\t`-indented lines. */
export function bodyLines(lines: string[], base = paragraph("")) {
  return lines.map((line) => {
    const level = line.length - line.replace(/^\t+/, "").length;
    const p = clone(base);
    p.runs = [{ text: line.slice(level), style: clone(base.runs[0]?.style ?? plainRun()) }];
    p.style.level = level;
    return p;
  });
}

export const hasEffects = (e: SlideElement) => { const s = shapeOf(e); return !!s && !effectsEmpty(s.effects); };
export { R };

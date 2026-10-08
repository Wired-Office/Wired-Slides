import type { PresentationTheme, RunStyle, TextBody, ParagraphStyle } from "../model/types";
import type { Rect } from "../model/core";
import { bulletIsNone, clone, cssColor, numberLabel, paragraphText, resolve, rgbPaint, setPlainText, textIsEmpty, themePaint, updateRuns } from "../model/core";
import { fontString } from "./fonts";

/**
 * Lays out and draws a TextBody on a canvas, the way the Mac app's TextKit
 * layout does: hanging indents for bullets and numbers by outline level,
 * line spacing as a multiple, paragraph spacing, alignment, shrink-on-overflow,
 * columns and rotated text.
 */

export interface TextOptions {
  showPrompt?: boolean;
  promptColor?: string;
  slideNumber?: number;
}

interface Piece {
  text: string;
  font: string;
  size: number;
  style: RunStyle;
  color: string;
  width: number;
  ascent: number;
  descent: number;
  /** Superscript/subscript shift (positive is up). */
  shift: number;
  spacing: number;
}

interface Line {
  pieces: Piece[];
  width: number;
  ascent: number;
  descent: number;
  height: number;
  /** Offset of the line's text from the paragraph's left edge. */
  indent: number;
  marker?: { label: string; font: string; color: string; x: number };
  alignment: ParagraphStyle["alignment"];
  justify: boolean;
  spaceBefore: number;
  spaceAfter: number;
  /** Line y position (top) within the layout. */
  y: number;
  baseline: number;
}

export interface TextLayoutResult {
  lines: Line[];
  height: number;
  width: number;
}

let measureCtx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D | null | undefined;
function measurer() {
  if (measureCtx === undefined) {
    measureCtx = null;
    try {
      if (typeof OffscreenCanvas !== "undefined") measureCtx = new OffscreenCanvas(4, 4).getContext("2d");
      else if (typeof document !== "undefined") measureCtx = document.createElement("canvas").getContext("2d");
    } catch {
      measureCtx = null;
    }
  }
  return measureCtx;
}

const metricsCache = new Map<string, { ascent: number; descent: number }>();
function fontMetrics(font: string, size: number) {
  let m = metricsCache.get(font);
  if (!m) {
    const ctx = measurer();
    if (ctx) {
      ctx.font = font;
      const tm = ctx.measureText("Hgjy");
      const a = tm.fontBoundingBoxAscent, d = tm.fontBoundingBoxDescent;
      m = a && d ? { ascent: a / size, descent: d / size } : { ascent: 0.93, descent: 0.25 };
      // Normalize odd fonts so line heights stay close to the Mac's.
      const total = m.ascent + m.descent;
      if (total < 1.05 || total > 1.5) m = { ascent: 0.93 * (m.ascent / total) * 1.18, descent: 0.25 * (m.descent / total) * 1.18 };
    } else {
      m = { ascent: 0.93, descent: 0.25 };
    }
    metricsCache.set(font, m);
  }
  return { ascent: m.ascent * size, descent: m.descent * size };
}

const widthCache = new Map<string, number>();
function measure(text: string, font: string, spacing: number): number {
  if (!text) return 0;
  const key = font + "\u0000" + text;
  let w = widthCache.get(key);
  if (w === undefined) {
    const ctx = measurer();
    if (ctx) { ctx.font = font; w = ctx.measureText(text).width; }
    else w = text.length * parseFloat(font.match(/([\d.]+)px/)?.[1] ?? "16") * 0.5;
    if (widthCache.size > 20000) widthCache.clear();
    widthCache.set(key, w);
  }
  return w + spacing * [...text].length;
}

export function runFont(style: RunStyle, body: TextBody, theme: PresentationTheme, scale: number) {
  const family = style.fontFamily ?? (body.fontRole === "heading" ? theme.headingFont : theme.bodyFont);
  let size = (style.size ?? body.defaultSize) * scale;
  if (style.baseline) size *= 0.66;
  size = Math.max(size, 1);
  return { family, size, font: fontString(family, size, style.bold ?? false, style.italic ?? false, style.smallCaps) };
}

export function runColor(style: RunStyle, body: TextBody, theme: PresentationTheme): string {
  if (style.link) return cssColor(resolve(style.color ?? themePaint("hyperlink"), theme.colors));
  return cssColor(resolve(style.color ?? body.defaultColor, theme.colors));
}

const indentUnit = (body: TextBody, scale: number) => Math.max((body.defaultSize * scale) / 24, 0.6);

function makePiece(text: string, style: RunStyle, body: TextBody, theme: PresentationTheme, scale: number): Piece {
  const { size, font } = runFont(style, body, theme, scale);
  const m = fontMetrics(font, size);
  const spacing = style.characterSpacing * scale;
  const full = (style.size ?? body.defaultSize) * scale;
  return {
    text, font, size, style, color: runColor(style, body, theme), width: measure(text, font, spacing),
    ascent: m.ascent, descent: m.descent, shift: style.baseline ? style.baseline * full * 0.33 : 0, spacing,
  };
}

/** Splits text into words with their trailing spaces, keeping forced line breaks as their own tokens. */
function tokens(text: string): string[] {
  return text.match(/\u2028|[^\s\u2028]+\s*|\s+/g) ?? [];
}

function layoutParagraphs(body: TextBody, theme: PresentationTheme, width: number, scale: number, slideNumber?: number): TextLayoutResult {
  const lines: Line[] = [];
  const unit = indentUnit(body, scale);
  const counters = new Map<number, number>();
  let y = 0, maxWidth = 0;
  const wrapWidth = body.wrap ? Math.max(width, 1) : Infinity;

  body.paragraphs.forEach((paragraph) => {
    const st = paragraph.style;
    const hasBullet = !bulletIsNone(st.bullet);
    const indent = (st.level * 28 + (hasBullet ? 24 : 0)) * unit;
    const markerX = st.level * 28 * unit;
    const runs = paragraph.runs.length ? paragraph.runs : [{ text: "", style: body.paragraphs[0]?.runs[0]?.style ?? ({} as RunStyle) }];

    // Numbering restarts after a shallower paragraph.
    for (const level of [...counters.keys()]) if (level > st.level) counters.delete(level);
    let label: string | undefined;
    if ("symbol" in st.bullet) label = st.bullet.symbol._0;
    else if ("numbered" in st.bullet) {
      const n = (counters.get(st.level) ?? st.bullet.numbered.start - 1) + 1;
      counters.set(st.level, n);
      label = numberLabel(st.bullet.numbered._0, n);
    } else counters.delete(st.level);

    // Build pieces, splitting runs into words.
    const pieces: Piece[] = [];
    for (const run of runs) {
      let text = run.text;
      if (run.style.allCaps) text = text.toUpperCase();
      if (slideNumber !== undefined) text = text.replace(/‹#›/g, String(slideNumber));
      if (!text) continue;
      for (const token of tokens(text)) pieces.push(makePiece(token, run.style, body, theme, scale));
    }
    const emptyPiece = makePiece("", runs[runs.length - 1].style, body, theme, scale);
    const firstStyle = runs[0].style;
    const markerFont = runFont(firstStyle, body, theme, scale).font;
    const markerColor = st.bulletColor ? cssColor(resolve(st.bulletColor, theme.colors)) : runColor(firstStyle, body, theme);
    const isEmpty = paragraphText(paragraph) === "";

    let current: Piece[] = [];
    let lineWidth = 0;
    let first = true;
    const available = wrapWidth - indent;
    const flush = (forced: boolean, last: boolean) => {
      // Trailing spaces don't count toward the width.
      let w = lineWidth;
      const tail = current[current.length - 1];
      if (tail) {
        const trimmed = tail.text.replace(/\s+$/, "");
        if (trimmed !== tail.text) w -= tail.width - measure(trimmed, tail.font, tail.spacing);
      }
      const content = current.length ? current : [emptyPiece];
      let ascent = 0, descent = 0;
      for (const p of content) { ascent = Math.max(ascent, p.ascent + Math.max(p.shift, 0)); descent = Math.max(descent, p.descent - Math.min(p.shift, 0)); }
      const natural = ascent + descent;
      const height = natural * st.lineSpacing;
      const line: Line = {
        pieces: current, width: w, ascent, descent, height, indent, alignment: st.alignment,
        justify: st.alignment === "justify" && !forced && !last,
        spaceBefore: first ? st.spaceBefore * scale : 0, spaceAfter: last ? st.spaceAfter * scale : 0, y: 0, baseline: 0,
      };
      if (first && label && (!isEmpty || pieces.length)) line.marker = { label, font: markerFont, color: markerColor, x: markerX };
      lines.push(line);
      maxWidth = Math.max(maxWidth, w + indent);
      current = [];
      lineWidth = 0;
      first = false;
    };

    for (let i = 0; i < pieces.length; i++) {
      const p = pieces[i];
      if (p.text === "\u2028") { flush(true, false); continue; }
      const trimmedWidth = measure(p.text.replace(/\s+$/, ""), p.font, p.spacing);
      if (current.length && lineWidth + trimmedWidth > available + 0.01) flush(false, false);
      if (!current.length && trimmedWidth > available && available > 0 && body.wrap) {
        // A word wider than the line breaks between characters.
        const chars = [...p.text];
        let chunk = "";
        for (const ch of chars) {
          if (chunk && measure(chunk + ch, p.font, p.spacing) > available) {
            current.push({ ...p, text: chunk, width: measure(chunk, p.font, p.spacing) });
            lineWidth = current[0].width;
            flush(false, false);
            chunk = "";
          }
          chunk += ch;
        }
        if (chunk) { current.push({ ...p, text: chunk, width: measure(chunk, p.font, p.spacing) }); lineWidth += current[current.length - 1].width; }
        continue;
      }
      current.push(p);
      lineWidth += p.width;
    }
    flush(true, true);
  });

  // Vertical positions.
  for (const line of lines) {
    y += line.spaceBefore;
    line.y = y;
    // Like TextKit's line height multiple, extra or missing space goes above the glyphs.
    line.baseline = y + line.height - line.descent;
    y += line.height + line.spaceAfter;
  }
  return { lines, height: y, width: maxWidth };
}

// MARK: Caching

const layoutCache = new WeakMap<TextBody, Map<string, TextLayoutResult>>();

export function layoutText(body: TextBody, theme: PresentationTheme, width: number, scale = 1, slideNumber?: number): TextLayoutResult {
  let map = layoutCache.get(body);
  if (!map) { map = new Map(); layoutCache.set(body, map); }
  const key = `${Math.round(width * 4)}|${scale.toFixed(4)}|${theme.headingFont}|${theme.bodyFont}|${slideNumber ?? ""}|${JSON.stringify(theme.colors)}`;
  let result = map.get(key);
  if (!result) {
    result = layoutParagraphs(body, theme, width, scale, slideNumber);
    if (map.size > 24) map.clear();
    map.set(key, result);
  }
  return result;
}

const fitCache = new WeakMap<TextBody, Map<string, number>>();

/** The shrink factor that makes the text fit its box. */
export function fittedScale(body: TextBody, w: number, h: number, theme: PresentationTheme): number {
  if (body.autofit !== "shrink" || textIsEmpty(body)) return 1;
  const width = w - body.insets.left - body.insets.right;
  const height = h - body.insets.top - body.insets.bottom;
  if (width <= 4 || height <= 4) return 1;
  let map = fitCache.get(body);
  if (!map) { map = new Map(); fitCache.set(body, map); }
  const key = `${Math.round(width * 2)}|${Math.round(height * 2)}|${theme.headingFont}|${theme.bodyFont}`;
  const cached = map.get(key);
  if (cached !== undefined) return cached;
  const columns = Math.max(1, body.columns);
  const fits = (s: number) => {
    const columnWidth = (width - 14 * (columns - 1)) / columns;
    return layoutParagraphs(body, theme, columnWidth, s).height / columns <= height + 0.5;
  };
  let result = 1;
  if (!fits(1)) {
    let lo = 0.25, hi = 1;
    if (fits(lo)) {
      for (let i = 0; i < 7; i++) {
        const mid = (lo + hi) / 2;
        if (fits(mid)) lo = mid; else hi = mid;
      }
    }
    result = lo;
  }
  map.set(key, result);
  return result;
}

/** Height needed to show all the text at a width (for "Resize shape to fit text"). */
export function requiredHeight(body: TextBody, width: number, theme: PresentationTheme): number {
  const inner = width - body.insets.left - body.insets.right;
  let measureBody = body;
  if (textIsEmpty(body)) {
    measureBody = clone(body);
    measureBody.paragraphs = measureBody.paragraphs.map((p) => ({ ...p, runs: [{ text: " ", style: p.runs[0]?.style ?? ({} as RunStyle) }] }));
  }
  const result = layoutParagraphs(measureBody, theme, inner, 1);
  return Math.ceil(result.height + body.insets.top + body.insets.bottom);
}

/** Width needed for unwrapped text. */
export function requiredWidth(body: TextBody, theme: PresentationTheme): number {
  const unwrapped = { ...body, wrap: false };
  return Math.ceil(layoutParagraphs(unwrapped, theme, 100000, 1).width + body.insets.left + body.insets.right + 2);
}

export function contentRect(body: TextBody, r: Rect): Rect {
  return {
    x: r.x + body.insets.left, y: r.y + body.insets.top,
    w: Math.max(r.w - body.insets.left - body.insets.right, 1), h: Math.max(r.h - body.insets.top - body.insets.bottom, 1),
  };
}

// MARK: Drawing

type Ctx = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

function drawLine(ctx: Ctx, line: Line, left: number, width: number, top: number) {
  const usable = width - line.indent;
  let x = left + line.indent;
  let gap = 0;
  if (line.alignment === "center") x += (usable - line.width) / 2;
  else if (line.alignment === "right") x += usable - line.width;
  else if (line.justify && line.pieces.length > 1) {
    const spaces = line.pieces.slice(0, -1).filter((p) => /\s$/.test(p.text)).length;
    if (spaces) gap = (usable - line.width) / spaces;
  }
  const baseline = top + line.baseline;
  if (line.marker) {
    // Centered and right-aligned bulleted lines carry their marker with them.
    const mx = line.alignment === "center" || line.alignment === "right" ? x - (line.indent - line.marker.x) : left + line.marker.x;
    ctx.font = line.marker.font;
    ctx.fillStyle = line.marker.color;
    ctx.fillText(line.marker.label, mx, baseline);
  }
  for (let i = 0; i < line.pieces.length; i++) {
    const p = line.pieces[i];
    const isLast = i === line.pieces.length - 1;
    const text = isLast ? p.text.replace(/\s+$/, "") : p.text;
    const w = isLast ? measure(text, p.font, p.spacing) : p.width;
    const y = baseline - p.shift;
    if (p.style.highlight) {
      ctx.fillStyle = cssColor(p.style.highlight);
      ctx.fillRect(x, baseline - p.ascent, p.width + (gap && /\s$/.test(p.text) ? gap : 0), p.ascent + p.descent);
    }
    ctx.font = p.font;
    ctx.fillStyle = p.color;
    if (p.style.shadow) {
      ctx.save();
      ctx.shadowColor = "rgba(0,0,0,0.45)";
      ctx.shadowOffsetX = p.size * 0.04;
      ctx.shadowOffsetY = p.size * 0.04;
      ctx.shadowBlur = p.size * 0.08;
    }
    const draw = (fn: (t: string, x: number, y: number) => void) => {
      if (!p.spacing) { fn(text, x, y); return; }
      let cx = x;
      for (const ch of text) { fn(ch, cx, y); cx += measure(ch, p.font, 0) + p.spacing; }
    };
    draw((t, tx, ty) => ctx.fillText(t, tx, ty));
    if (p.style.outlineColor && p.style.outlineWidth > 0) {
      ctx.lineWidth = p.style.outlineWidth;
      ctx.lineJoin = "round";
      ctx.strokeStyle = outlineColors.get(p.style) ?? p.color;
      draw((t, tx, ty) => ctx.strokeText(t, tx, ty));
    }
    if (p.style.shadow) ctx.restore();
    if (p.style.underline || p.style.link || p.style.strikethrough) {
      ctx.fillStyle = p.color;
      const thickness = Math.max(p.size / 16, 0.75);
      if (p.style.underline || p.style.link) ctx.fillRect(x, y + p.size * 0.12, w, thickness);
      if (p.style.strikethrough) ctx.fillRect(x, y - p.size * 0.3, w, thickness);
    }
    x += p.width + (gap && /\s$/.test(p.text) ? gap : 0);
  }
}

/** Outline colors resolved per draw (run styles hold theme references). */
const outlineColors = new WeakMap<RunStyle, string>();

/** Draws text into a context whose units are slide points. */
export function drawText(ctx: Ctx, source: TextBody, r: Rect, theme: PresentationTheme, options: TextOptions = {}) {
  let body = source;
  if (textIsEmpty(body)) {
    if (!options.showPrompt || !body.prompt) return;
    body = clone(source);
    setPlainText(body, source.prompt!);
    body.defaultColor = rgbPaint({ r: 0.55, g: 0.55, b: 0.55, a: 1 });
    updateRuns(body, (s) => { delete s.color; });
    body.autofit = "shrink";
    promptBodies.set(body, options.promptColor ?? "rgb(140,140,140)");
  }
  let area = r;
  let rotation = 0;
  if (body.direction !== "horizontal") {
    rotation = body.direction === "rotated90" ? Math.PI / 2 : -Math.PI / 2;
    area = { x: r.x + r.w / 2 - r.h / 2, y: r.y + r.h / 2 - r.w / 2, w: r.h, h: r.w };
  }
  const scale = fittedScale(body, area.w, area.h, theme);
  const content = contentRect(body, area);
  const columns = Math.max(1, body.columns);
  const gap = 14;
  const columnWidth = (content.w - gap * (columns - 1)) / columns;
  const layout = layoutText(body, theme, columnWidth, scale, options.slideNumber);
  const prompt = promptBodies.get(body);

  ctx.save();
  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "left";
  if (rotation) {
    ctx.translate(r.x + r.w / 2, r.y + r.h / 2);
    ctx.rotate(rotation);
    ctx.translate(-(r.x + r.w / 2), -(r.y + r.h / 2));
  }
  for (const line of layout.lines) for (const p of line.pieces) {
    if (prompt) p.color = prompt;
    if (p.style.outlineColor) outlineColors.set(p.style, cssColor(resolve(p.style.outlineColor, theme.colors)));
  }
  if (prompt) for (const line of layout.lines) if (line.marker) line.marker.color = prompt;
  if (columns === 1) {
    let top = content.y;
    if (body.anchor === "middle") top = content.y + content.h / 2 - layout.height / 2;
    else if (body.anchor === "bottom") top = content.y + content.h - layout.height;
    let left = content.x, width = content.w;
    if (!body.wrap) {
      // Unwrapped text is positioned by its alignment within the box.
      width = Math.max(layout.width, content.w);
      const alignment = body.paragraphs[0]?.style.alignment;
      if (alignment === "center") left = content.x + content.w / 2 - width / 2;
      else if (alignment === "right") left = content.x + content.w - width;
    }
    for (const line of layout.lines) drawLine(ctx, line, left, width, top);
  } else {
    let column = 0, offset = 0;
    for (const line of layout.lines) {
      if (line.y + line.height - offset > content.h + 0.5 && line.y > offset && column < columns - 1) { column++; offset = line.y; }
      drawLine(ctx, line, content.x + column * (columnWidth + gap), columnWidth, content.y - offset);
    }
  }
  ctx.restore();
}

const promptBodies = new WeakMap<TextBody, string>();

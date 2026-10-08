import type { Fill, Presentation, PresentationTheme, Slide, SlideElement, UUID } from "../model/types";
import { R, clone, frame, setElementFrame, textBoxElement, textOf, themePaint } from "../model/core";
import { isTitleStyleLayout } from "../model/catalog";
import { drawElement, type DrawOptions } from "./elements";
import { fillPath, type Ctx, type RenderEnv } from "./paint";

export interface SlideDrawOptions {
  element?: DrawOptions;
  /** Elements not to draw (the slide show draws animated ones separately). */
  skip?: Set<UUID>;
  drawBackground?: boolean;
  drawElements?: boolean;
  drawFooters?: boolean;
}

export const envOf = (p: Presentation): RenderEnv => ({ theme: p.theme, media: p.media, slideSize: p.slideSize });

export function slideBackground(slide: Slide, theme: PresentationTheme): Fill {
  return slide.background ?? (isTitleStyleLayout(slide.layout) ? theme.titleBackground ?? theme.background : theme.background);
}

const decorationCache = new WeakMap<PresentationTheme, Map<string, SlideElement[]>>();

/** Theme graphics behind a slide, laid out for 960×540 and scaled to the slide size. */
export function slideDecorations(slide: Slide, theme: PresentationTheme, size: [number, number]): SlideElement[] {
  if (slide.hideBackgroundGraphics) return [];
  const source = isTitleStyleLayout(slide.layout) ? theme.titleDecorations : theme.decorations;
  if (size[0] === 960 && size[1] === 540) return source;
  let map = decorationCache.get(theme);
  if (!map) { map = new Map(); decorationCache.set(theme, map); }
  const key = `${isTitleStyleLayout(slide.layout)}|${size[0]}x${size[1]}`;
  let result = map.get(key);
  if (!result) {
    const sx = size[0] / 960, sy = size[1] / 540;
    result = source.map((d) => {
      const e = clone(d);
      const r = R(e.frame);
      setElementFrame(e, { x: r.x * sx, y: r.y * sy, w: r.w * sx, h: r.h * sy });
      return e;
    });
    map.set(key, result);
  }
  return result;
}

/** Date, footer and slide-number text boxes from Header & Footer settings. */
export function slideFooters(slide: Slide, number: number, p: Presentation): SlideElement[] {
  const hf = p.headerFooter;
  if (hf.hideOnTitleSlide && slide.layout === "title") return [];
  const [w, h] = p.slideSize;
  const y = h - (34 * h) / 540, height = (24 * h) / 540;
  const box = (text: string, x: number, width: number, alignment: "left" | "center" | "right") => {
    const e = textBoxElement(text, frame((x * w) / 960, y, (width * w) / 960, height), { size: 11, alignment, color: themePaint("dark1", 0.45), anchor: "middle" });
    textOf(e)!.autofit = "none";
    e.name = "Footer";
    return e;
  };
  const result: SlideElement[] = [];
  if (hf.showDate) result.push(box(hf.fixedDate ?? new Date().toLocaleDateString(undefined, { dateStyle: "medium" }), 60, 220, "left"));
  if (hf.showFooter && hf.footerText) result.push(box(hf.footerText, 320, 320, "center"));
  if (hf.showSlideNumber) result.push(box(String(number), 760, 140, "right"));
  return result;
}

/** Draws a slide into a context whose units are slide points. */
export function drawSlide(ctx: Ctx, slide: Slide, number: number, p: Presentation, options: SlideDrawOptions = {}) {
  const env = envOf(p);
  const [w, h] = p.slideSize;
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, w, h);
  ctx.clip();
  if (options.drawBackground !== false) {
    ctx.fillStyle = "white";
    ctx.fillRect(0, 0, w, h);
    const bounds = new Path2D();
    bounds.rect(0, 0, w, h);
    fillPath(ctx, bounds, slideBackground(slide, p.theme), { x: 0, y: 0, w, h }, env);
    for (const d of slideDecorations(slide, p.theme, p.slideSize)) drawElement(ctx, d, env);
  }
  const elementOptions = { ...options.element, slideNumber: number };
  if (options.drawElements !== false) {
    for (const e of slide.elements) if (!options.skip?.has(e.id)) drawElement(ctx, e, env, elementOptions);
  }
  if (options.drawFooters !== false) for (const f of slideFooters(slide, number, p)) drawElement(ctx, f, env, elementOptions);
  ctx.restore();
}

/** Renders a slide to a new canvas `pixelWidth` wide. */
export function renderSlide(slide: Slide, number: number, p: Presentation, pixelWidth: number, options: SlideDrawOptions = {}): HTMLCanvasElement {
  const [w, h] = p.slideSize;
  const scale = pixelWidth / w;
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(pixelWidth));
  canvas.height = Math.max(1, Math.round(h * scale));
  const ctx = canvas.getContext("2d")!;
  ctx.scale(scale, scale);
  drawSlide(ctx, slide, number, p, options);
  return canvas;
}

export async function slidePNG(slide: Slide, number: number, p: Presentation, pixelWidth: number, type = "image/png", quality = 0.92): Promise<Uint8Array> {
  const canvas = renderSlide(slide, number, p, pixelWidth);
  const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, type, quality));
  return new Uint8Array(await (blob ?? new Blob()).arrayBuffer());
}

/** Thumbnails cached by slide content (slides are replaced, never changed in place). */
const thumbnails = new WeakMap<Slide, { key: string; canvas: HTMLCanvasElement }>();
let generation = 0;
/** Forces thumbnails to redraw (pictures finished loading). */
export function invalidateThumbnails() { generation++; }

export function thumbnail(slide: Slide, number: number, p: Presentation, pixelWidth: number): HTMLCanvasElement {
  const key = `${number}|${pixelWidth}|${generation}|${p.slideSize.join("x")}|${themeKey(p.theme)}|${JSON.stringify(p.headerFooter)}`;
  const cached = thumbnails.get(slide);
  if (cached && cached.key === key) return cached.canvas;
  const canvas = renderSlide(slide, number, p, pixelWidth);
  thumbnails.set(slide, { key, canvas });
  return canvas;
}

const themeKeys = new WeakMap<PresentationTheme, string>();
function themeKey(t: PresentationTheme) {
  let k = themeKeys.get(t);
  if (!k) { k = String(Math.random()); themeKeys.set(t, k); }
  return k;
}

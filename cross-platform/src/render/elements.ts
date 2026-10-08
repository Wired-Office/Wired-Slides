import type { ImageContent, LineContent, MediaContent, ShapeContent, SlideElement, UUID } from "../model/types";
import type { Rect } from "../model/core";
import {
  R, cssColor, effectsOf, fillRepresentative, isDark, isNoFill, lineEndpoints, lineStyle, lineVisible, maxY, midX, midY, resolve, rotatedBounds, textIsEmpty, themePaint, WHITE,
} from "../model/core";
import { resolvedAdjustments } from "../model/catalog";
import { shapeGeometry, type ShapeGeometry } from "./geometry";
import {
  adjustedPicture, applyGlow, applyShadow, arrowInset, arrowhead, clearShadow, fillPath, picture, pictureSize, strokePath, type Ctx, type RenderEnv,
} from "./paint";
import { drawText } from "./text";
import { drawSymbol } from "./symbols";
import { drawTable } from "./table";
import { drawChart } from "./chart";

export interface DrawOptions {
  /** Show placeholder prompts and outlines (the editor, not the show or thumbnails). */
  editorChrome?: boolean;
  /** The element whose text is being edited (the editor draws it instead). */
  editingTextElement?: UUID;
  editingCell?: [number, number];
  slideNumber?: number;
  drawHidden?: boolean;
}

export function drawElement(ctx: Ctx, e: SlideElement, env: RenderEnv, options: DrawOptions = {}, includeReflection = true) {
  if (e.hidden && !options.drawHidden) return;
  const r = R(e.frame);
  ctx.save();
  if (e.rotation) {
    ctx.translate(midX(r), midY(r));
    ctx.rotate((e.rotation * Math.PI) / 180);
    ctx.translate(-midX(r), -midY(r));
  }
  const fx = effectsOf(e);
  if (includeReflection && fx?.reflection) drawReflection(ctx, e, env, options);
  const c = e.content;
  if ("shape" in c) drawShape(ctx, e, c.shape._0, env, options);
  else if ("image" in c) drawImage(ctx, e, c.image._0, env);
  else if ("line" in c) drawLine(ctx, e, c.line._0, env);
  else if ("table" in c) drawTable(ctx, c.table._0, r, e.id, env, options);
  else if ("chart" in c) drawChart(ctx, c.chart._0, r, env);
  else if ("icon" in c) drawSymbol(ctx, c.icon._0.symbol, r, cssColor(resolve(c.icon._0.color, env.theme.colors)), e.flipH, e.flipV);
  else if ("media" in c) drawMedia(ctx, c.media._0, r, env);
  else if ("group" in c) {
    applyFlip(ctx, e);
    for (const child of c.group._0.children) drawElement(ctx, child, env, options);
  }
  ctx.restore();
}

function applyFlip(ctx: Ctx, e: SlideElement) {
  if (!e.flipH && !e.flipV) return;
  const r = R(e.frame);
  ctx.translate(midX(r), midY(r));
  ctx.scale(e.flipH ? -1 : 1, e.flipV ? -1 : 1);
  ctx.translate(-midX(r), -midY(r));
}

// MARK: Shapes

const geometryCache = new WeakMap<ShapeContent, { key: string; geo: ShapeGeometry }>();

export function elementGeometry(e: SlideElement, s: ShapeContent): ShapeGeometry {
  const key = JSON.stringify(e.frame);
  const cached = geometryCache.get(s);
  if (cached && cached.key === key) return cached.geo;
  const geo = shapeGeometry(s.kind, R(e.frame), resolvedAdjustments(s.kind, s.adjustments));
  geometryCache.set(s, { key, geo });
  return geo;
}

/** The text area of a shape (text boxes use their whole frame). */
export function shapeTextRect(e: SlideElement, s: ShapeContent): Rect {
  if (s.kind === "rect" || s.kind === "roundRect") return R(e.frame);
  return elementGeometry(e, s).textRect;
}

function drawShape(ctx: Ctx, e: SlideElement, s: ShapeContent, env: RenderEnv, options: DrawOptions) {
  const geo = elementGeometry(e, s);
  const r = R(e.frame);
  const hasFill = !isNoFill(s.fill);
  const textOnly = !hasFill && !lineVisible(s.line);
  const rule: CanvasFillRule = geo.evenOdd ? "evenodd" : "nonzero";

  ctx.save();
  applyFlip(ctx, e);
  if (s.effects.glow) {
    ctx.save();
    applyGlow(ctx, s.effects.glow, env);
    const color = cssColor(resolve(s.effects.glow.color, env.theme.colors));
    if (hasFill) { ctx.fillStyle = color; ctx.fill(geo.path, rule); }
    else { ctx.strokeStyle = color; ctx.lineWidth = s.effects.glow.radius; ctx.stroke(geo.path); }
    ctx.restore();
  }
  if (s.effects.shadow && !textOnly) {
    ctx.save();
    applyShadow(ctx, s.effects.shadow);
    if (hasFill) fillPath(ctx, geo.path, s.fill, r, env, 0, rule);
    else strokePath(ctx, geo.path, s.line, env);
    ctx.restore();
  }
  if (geo.union && lineVisible(s.line)) {
    // Overlapping pieces: a doubled stroke under the fill leaves only the outer edge.
    strokePath(ctx, geo.path, s.line, env, 2);
    fillPath(ctx, geo.path, hasFill ? s.fill : { solid: { _0: themePaint("light1", 0, 0) } }, r, env, 0, "nonzero");
  } else {
    fillPath(ctx, geo.path, s.fill, r, env, 0, rule);
  }
  for (const accent of geo.accents) {
    fillPath(ctx, accent.path, s.fill, r, env, accent.shade);
    strokePath(ctx, accent.path, s.line, env);
  }
  if (!geo.union) strokePath(ctx, geo.path, s.line, env);
  for (const detail of geo.details) {
    const line = s.line.color ? s.line : lineStyle(themePaint("dark1", 0, 0.6), Math.max(1, r.w / 60));
    strokePath(ctx, detail, line, env);
  }
  ctx.restore();

  // Text never mirrors; a vertical flip turns it upside down like PowerPoint.
  if (options.editingTextElement === e.id) return;
  const emptyPlaceholder = !!e.placeholder && textIsEmpty(s.text);
  if (emptyPlaceholder && options.editorChrome) { drawPlaceholderChrome(ctx, e, s, env); return; }
  if (textIsEmpty(s.text)) return;
  ctx.save();
  if (e.flipV) {
    ctx.translate(midX(r), midY(r));
    ctx.rotate(Math.PI);
    ctx.translate(-midX(r), -midY(r));
  }
  if (textOnly && s.effects.shadow) applyShadow(ctx, s.effects.shadow);
  drawText(ctx, s.text, shapeTextRect(e, s), env.theme, { slideNumber: options.slideNumber });
  ctx.restore();
}

export const PLACEHOLDER_ICONS: [string, string][] = [
  ["tablecells", "table"], ["chart.bar", "chart"], ["square.grid.2x2", "smartart"], ["photo", "picture"], ["star", "icon"], ["film", "video"],
];

/** Where the insert-content icons sit in an empty placeholder. */
export function placeholderIconFrames(r: Rect, pictureOnly: boolean): [Rect, string][] {
  const list = pictureOnly ? [PLACEHOLDER_ICONS[3]] : PLACEHOLDER_ICONS;
  const size = Math.min(28, r.w / 8, r.h / 4);
  if (size < 12) return [];
  const gap = size * 0.5, columns = pictureOnly ? 1 : 3, rows = pictureOnly ? 1 : 2;
  const totalW = columns * size + (columns - 1) * gap, totalH = rows * size + (rows - 1) * gap;
  const ox = midX(r) - totalW / 2, oy = midY(r) - totalH / 2 + (pictureOnly ? 0 : size * 0.6);
  return list.map(([, kind], i) => [{ x: ox + (i % columns) * (size + gap), y: oy + Math.floor(i / columns) * (size + gap), w: size, h: size }, kind]);
}

function drawPlaceholderChrome(ctx: Ctx, e: SlideElement, s: ShapeContent, env: RenderEnv) {
  const r = R(e.frame);
  const background = fillRepresentative(env.theme.background, env.theme.colors) ?? WHITE;
  const dark = isDark(background);
  const ink = dark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.35)";
  ctx.save();
  ctx.strokeStyle = ink;
  ctx.lineWidth = 1 / Math.max(ctx.getTransform().a, 0.2);
  ctx.setLineDash([4, 3]);
  ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
  ctx.restore();
  drawText(ctx, s.text, shapeTextRect(e, s), env.theme, { showPrompt: true, promptColor: dark ? "rgba(255,255,255,0.55)" : "rgb(115,115,115)" });
  if (e.placeholder === "body" || e.placeholder === "picture") {
    for (const [frame, kind] of placeholderIconFrames(r, e.placeholder === "picture")) {
      const symbol = PLACEHOLDER_ICONS.find((x) => x[1] === kind)![0];
      drawSymbol(ctx, symbol, { x: frame.x + 3, y: frame.y + 3, w: frame.w - 6, h: frame.h - 6 }, ink);
    }
  }
}

// MARK: Pictures

function drawImage(ctx: Ctx, e: SlideElement, content: ImageContent, env: RenderEnv) {
  const r = R(e.frame);
  const clip = content.maskShape ? shapeGeometry(content.maskShape, r, resolvedAdjustments(content.maskShape, [])).path : rectPath(r);
  ctx.save();
  if (content.effects.glow) {
    ctx.save();
    applyGlow(ctx, content.effects.glow, env);
    ctx.fillStyle = cssColor(resolve(content.effects.glow.color, env.theme.colors));
    ctx.fill(clip);
    ctx.restore();
  }
  const image = adjustedPicture(content.mediaID, env.media, content.adjustments);
  if (content.effects.shadow) {
    ctx.save();
    applyShadow(ctx, content.effects.shadow);
    ctx.fillStyle = "rgba(0,0,0,1)";
    ctx.globalAlpha = 1 - content.adjustments.transparency;
    ctx.fill(clip);
    ctx.restore();
  }
  ctx.save();
  ctx.clip(clip);
  applyFlip(ctx, e);
  if (image) {
    const [iw, ih] = pictureSize(image);
    const cr = content.crop;
    const sx = iw * cr.left, sy = ih * cr.top;
    const sw = iw * Math.max(1 - cr.left - cr.right, 0.01), sh = ih * Math.max(1 - cr.top - cr.bottom, 0.01);
    ctx.globalAlpha = 1 - content.adjustments.transparency;
    // drawImage needs the source inside the picture; crops past the edge (outcrops) map through a scale.
    const scaleX = r.w / sw, scaleY = r.h / sh;
    ctx.drawImage(image, r.x - sx * scaleX, r.y - sy * scaleY, iw * scaleX, ih * scaleY);
  } else {
    ctx.fillStyle = "rgb(217,217,217)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    drawSymbol(ctx, "photo", { x: r.x + r.w * 0.35, y: r.y + r.h * 0.35, w: r.w * 0.3, h: r.h * 0.3 }, "rgb(128,128,128)");
  }
  ctx.restore();
  strokePath(ctx, clip, content.line, env);
  ctx.restore();
}

function rectPath(r: Rect) {
  const p = new Path2D();
  p.rect(r.x, r.y, r.w, r.h);
  return p;
}

// MARK: Lines

export function linePath(e: SlideElement, content: LineContent, start?: [number, number], end?: [number, number]): Path2D {
  const ends = lineEndpoints(e);
  const a = start ?? ends.start, b = end ?? ends.end;
  const p = new Path2D();
  p.moveTo(a[0], a[1]);
  const mx = (a[0] + b[0]) / 2;
  if (content.kind === "elbow") { p.lineTo(mx, a[1]); p.lineTo(mx, b[1]); p.lineTo(b[0], b[1]); }
  else if (content.kind === "curved") p.bezierCurveTo(mx, a[1], mx, b[1], b[0], b[1]);
  else p.lineTo(b[0], b[1]);
  return p;
}

function drawLine(ctx: Ctx, e: SlideElement, content: LineContent, env: RenderEnv) {
  if (!content.line.color) return;
  const ends = lineEndpoints(e);
  let startFrom = ends.end, endFrom = ends.start;
  if (content.kind !== "straight") {
    const mx = (ends.start[0] + ends.end[0]) / 2;
    startFrom = [mx, ends.start[1]];
    endFrom = [mx, ends.end[1]];
    if (Math.abs(ends.start[0] - ends.end[0]) < 0.5) { startFrom = ends.end; endFrom = ends.start; }
  }
  const pulled = (p: [number, number], q: [number, number], d: number): [number, number] => {
    const len = Math.hypot(q[0] - p[0], q[1] - p[1]);
    if (len <= d || d <= 0) return p;
    return [p[0] + ((q[0] - p[0]) / len) * d, p[1] + ((q[1] - p[1]) / len) * d];
  };
  const start = pulled(ends.start, startFrom, arrowInset(content.line.head, content.line.width));
  const end = pulled(ends.end, endFrom, arrowInset(content.line.tail, content.line.width));
  ctx.save();
  if (content.effects.glow) applyGlow(ctx, content.effects.glow, env);
  if (content.effects.shadow) applyShadow(ctx, content.effects.shadow);
  strokePath(ctx, linePath(e, content, start, end), content.line, env);
  clearShadow(ctx);
  const color = cssColor(resolve(content.line.color, env.theme.colors));
  arrowhead(ctx, content.line.head, ends.start, startFrom, content.line.width, color);
  arrowhead(ctx, content.line.tail, ends.end, endFrom, content.line.width, color);
  ctx.restore();
}

// MARK: Media

function drawMedia(ctx: Ctx, media: MediaContent, r: Rect, env: RenderEnv) {
  const poster = media.posterID ? picture(media.posterID, env.media) : null;
  if (poster) ctx.drawImage(poster, r.x, r.y, r.w, r.h);
  else if (media.kind === "video") {
    ctx.fillStyle = "rgb(20,20,20)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    drawSymbol(ctx, "film", { x: r.x + r.w * 0.38, y: r.y + r.h * 0.38, w: r.w * 0.24, h: r.h * 0.24 }, "rgb(178,178,178)");
  } else {
    const color = cssColor(env.theme.colors.accent1);
    ctx.fillStyle = color;
    const d = Math.min(r.w, r.h);
    ctx.beginPath();
    ctx.arc(midX(r), midY(r), d / 2, 0, Math.PI * 2);
    ctx.fill();
    drawSymbol(ctx, "speaker.wave.2", { x: midX(r) - d * 0.3, y: midY(r) - d * 0.3, w: d * 0.6, h: d * 0.6 }, "white");
  }
  if (media.kind === "video" && poster) {
    const d = Math.min(r.w, r.h) * 0.18;
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.beginPath();
    ctx.arc(midX(r), midY(r), d / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "rgba(0,0,0,0.7)";
    ctx.beginPath();
    ctx.moveTo(midX(r) - d * 0.15, midY(r) - d * 0.22);
    ctx.lineTo(midX(r) + d * 0.25, midY(r));
    ctx.lineTo(midX(r) - d * 0.15, midY(r) + d * 0.22);
    ctx.fill();
  }
}

// MARK: Reflection

function drawReflection(ctx: Ctx, e: SlideElement, env: RenderEnv, options: DrawOptions) {
  const reflection = effectsOf(e)?.reflection;
  if (!reflection) return;
  const r = R(e.frame);
  const top = maxY(r) + reflection.distance;
  const height = r.h * reflection.size;
  if (height <= 1 || typeof document === "undefined") return;
  const scale = Math.min(deviceScaleOf(ctx), 3);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.ceil((r.w + 40) * scale));
  canvas.height = Math.max(1, Math.ceil(height * scale));
  const off = canvas.getContext("2d")!;
  const copy = { ...e, rotation: 0 };
  // After the flip, the element's bottom edge sits at the top of the canvas.
  off.setTransform(scale, 0, 0, -scale, -(r.x - 20) * scale, maxY(r) * scale);
  drawElement(off as unknown as Ctx, copy, env, options, false);
  off.setTransform(1, 0, 0, 1, 0, 0);
  off.globalCompositeOperation = "destination-in";
  const fade = off.createLinearGradient(0, 0, 0, canvas.height);
  fade.addColorStop(0, "rgba(0,0,0,1)");
  fade.addColorStop(1, "rgba(0,0,0,0)");
  off.fillStyle = fade;
  off.fillRect(0, 0, canvas.width, canvas.height);
  ctx.save();
  ctx.globalAlpha *= reflection.opacity;
  ctx.drawImage(canvas, r.x - 20, top, r.w + 40, height);
  ctx.restore();
}

function deviceScaleOf(ctx: Ctx) {
  const m = ctx.getTransform();
  return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)) || 1;
}

/** The area an element covers once rotated, plus room for shadows and glow. */
export function visualBounds(e: SlideElement): Rect {
  let r = rotatedBounds(R(e.frame), e.rotation);
  const line = "line" in e.content ? e.content.line._0 : null;
  if (line) { const p = line.line.width * 3 + 6; r = { x: r.x - p, y: r.y - p, w: r.w + p * 2, h: r.h + p * 2 }; }
  const fx = effectsOf(e);
  if (fx) {
    let pad = 0;
    if (fx.shadow) pad = Math.max(pad, fx.shadow.blur * 2 + fx.shadow.distance);
    if (fx.glow) pad = Math.max(pad, fx.glow.radius * 2.5);
    r = { x: r.x - pad, y: r.y - pad, w: r.w + pad * 2, h: r.h + pad * 2 };
    if (fx.reflection) r.h += R(e.frame).h * fx.reflection.size + fx.reflection.distance;
  }
  return { x: r.x - 2, y: r.y - 2, w: r.w + 4, h: r.h + 4 };
}


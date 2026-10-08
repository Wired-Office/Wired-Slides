import type { ArrowHead, Fill, GlowEffect, GradientFill, ImageAdjustments, ImageFill, LineStyle, MediaItem, PatternKind, PresentationTheme, ShadowEffect, ThemeColors } from "../model/types";
import type { Rect } from "../model/core";
import { adjustmentsIdentity, cssColor, dashPattern, maxX, maxY, resolve, shaded, withAlpha } from "../model/core";

export type Ctx = CanvasRenderingContext2D;

/** What drawing needs besides the element itself. */
export interface RenderEnv {
  theme: PresentationTheme;
  media: Record<string, MediaItem>;
  slideSize: [number, number];
}

export const envColors = (env: RenderEnv): ThemeColors => env.theme.colors;

// MARK: Pictures

type Picture = HTMLImageElement | HTMLCanvasElement | ImageBitmap;

const MIME: Record<string, string> = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", bmp: "image/bmp", webp: "image/webp", svg: "image/svg+xml",
  tif: "image/tiff", tiff: "image/tiff", heic: "image/heic", avif: "image/avif", mp4: "video/mp4", mov: "video/quicktime", m4v: "video/mp4",
  webm: "video/webm", mp3: "audio/mpeg", m4a: "audio/mp4", wav: "audio/wav", aac: "audio/aac", ogg: "audio/ogg",
};

export function mimeType(filename: string): string {
  return MIME[filename.split(".").pop()?.toLowerCase() ?? ""] ?? "application/octet-stream";
}

const decoded = new Map<string, Picture | "loading" | "failed">();
const adjustedCache = new Map<string, HTMLCanvasElement>();
const urls = new Map<string, string>();
let onImageReady: () => void = () => {};

/** Called whenever a picture finishes decoding, so views can redraw. */
export function setImageReadyHandler(fn: () => void) { onImageReady = fn; }

/** A blob URL for media (pictures, video, audio), kept for the session. */
export function mediaURL(id: string, item: MediaItem): string {
  let url = urls.get(id);
  if (!url) {
    url = URL.createObjectURL(new Blob([item.data as BlobPart], { type: mimeType(item.filename) }));
    urls.set(id, url);
  }
  return url;
}

export function picture(id: string, media: Record<string, MediaItem>): Picture | null {
  const state = decoded.get(id);
  if (state === "loading" || state === "failed") return null;
  if (state) return state;
  const item = media[id];
  if (!item || typeof Image === "undefined") return null;
  decoded.set(id, "loading");
  const img = new Image();
  img.onload = () => { decoded.set(id, img); onImageReady(); };
  img.onerror = () => decoded.set(id, "failed");
  img.src = mediaURL(id, item);
  return null;
}

/** Resolves once every picture a presentation uses is decoded (for printing and export). */
export async function preloadPictures(media: Record<string, MediaItem>): Promise<void> {
  await Promise.all(Object.keys(media).filter((id) => mimeType(media[id].filename).startsWith("image/")).map((id) => new Promise<void>((done) => {
    if (picture(id, media) || decoded.get(id) === "failed") return done();
    const check = () => (decoded.get(id) === "loading" ? setTimeout(check, 30) : done());
    check();
  })));
}

export const pictureSize = (p: Picture) => ("naturalWidth" in p ? [p.naturalWidth, p.naturalHeight] : [p.width, p.height]) as [number, number];

/** A picture with brightness, contrast, saturation and sepia applied. */
export function adjustedPicture(id: string, media: Record<string, MediaItem>, a: ImageAdjustments): Picture | null {
  const base = picture(id, media);
  if (!base || adjustmentsIdentity(a)) return base;
  const key = `${id}|${a.brightness}|${a.contrast}|${a.saturation}|${a.sepia}`;
  let canvas = adjustedCache.get(key);
  if (canvas) return canvas;
  const [w, h] = pictureSize(base);
  const scale = Math.min(1, 2400 / Math.max(w, h, 1));
  canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(w * scale));
  canvas.height = Math.max(1, Math.round(h * scale));
  const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(base, 0, 0, canvas.width, canvas.height);
  try {
    const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const px = data.data;
    const bright = a.brightness * 0.5 * 255, contrast = 1 + a.contrast, sat = a.saturation;
    for (let i = 0; i < px.length; i += 4) {
      let r = px[i], g = px[i + 1], b = px[i + 2];
      r += bright; g += bright; b += bright;
      r = (r - 127.5) * contrast + 127.5; g = (g - 127.5) * contrast + 127.5; b = (b - 127.5) * contrast + 127.5;
      const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = l + (r - l) * sat; g = l + (g - l) * sat; b = l + (b - l) * sat;
      if (a.sepia) {
        const sr = r * 0.393 + g * 0.769 + b * 0.189, sg = r * 0.349 + g * 0.686 + b * 0.168, sb = r * 0.272 + g * 0.534 + b * 0.131;
        r = r + (sr - r) * 0.85; g = g + (sg - g) * 0.85; b = b + (sb - b) * 0.85;
      }
      px[i] = r; px[i + 1] = g; px[i + 2] = b;
    }
    ctx.putImageData(data, 0, 0);
  } catch {
    // Pixel access can fail for unusual image types; show the picture unadjusted.
  }
  if (adjustedCache.size > 60) adjustedCache.clear();
  adjustedCache.set(key, canvas);
  return canvas;
}

// MARK: Fills

export function fillPath(ctx: Ctx, path: Path2D, fill: Fill, bounds: Rect, env: RenderEnv, shade = 0, rule: CanvasFillRule = "evenodd") {
  if ("none" in fill) return;
  const colors = env.theme.colors;
  if ("solid" in fill) {
    ctx.fillStyle = cssColor(shaded(resolve(fill.solid._0, colors), shade));
    ctx.fill(path, rule);
    return;
  }
  ctx.save();
  ctx.clip(path, rule);
  if ("gradient" in fill) drawGradient(ctx, fill.gradient._0, bounds, colors, shade);
  else if ("image" in fill) drawImageFill(ctx, fill.image._0, bounds, env);
  else if ("pattern" in fill) {
    const p = fill.pattern._0;
    ctx.fillStyle = cssColor(shaded(resolve(p.background, colors), shade));
    ctx.fillRect(bounds.x, bounds.y, bounds.w, bounds.h);
    drawPattern(ctx, p.kind, cssColor(shaded(resolve(p.foreground, colors), shade)), bounds);
  }
  ctx.restore();
}

export function drawGradient(ctx: Ctx, g: GradientFill, r: Rect, colors: ThemeColors, shade = 0) {
  const stops = [...g.stops].sort((a, b) => a.position - b.position);
  if (!stops.length) return;
  let gradient: CanvasGradient;
  const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
  if (g.kind === "linear") {
    const angle = (g.angle * Math.PI) / 180, dx = Math.cos(angle), dy = Math.sin(angle);
    const half = (Math.abs(r.w * dx) + Math.abs(r.h * dy)) / 2;
    gradient = ctx.createLinearGradient(cx - dx * half, cy - dy * half, cx + dx * half, cy + dy * half);
  } else {
    gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(Math.hypot(r.w, r.h) / 2, 0.5));
  }
  for (const s of stops) gradient.addColorStop(Math.min(Math.max(s.position, 0), 1), cssColor(shaded(resolve(s.color, colors), shade)));
  ctx.fillStyle = gradient;
  ctx.fillRect(r.x - 1, r.y - 1, r.w + 2, r.h + 2);
}

function drawImageFill(ctx: Ctx, fill: ImageFill, r: Rect, env: RenderEnv) {
  const p = picture(fill.mediaID, env.media);
  if (!p) return;
  const [iw, ih] = pictureSize(p);
  ctx.globalAlpha *= 1 - fill.transparency;
  if (fill.mode === "stretch") ctx.drawImage(p, r.x, r.y, r.w, r.h);
  else if (fill.mode === "fit") {
    const s = Math.max(r.w / Math.max(iw, 1), r.h / Math.max(ih, 1));
    ctx.drawImage(p, r.x + r.w / 2 - (iw * s) / 2, r.y + r.h / 2 - (ih * s) / 2, iw * s, ih * s);
  } else if (iw > 2 && ih > 2) {
    for (let y = r.y; y < maxY(r); y += ih) for (let x = r.x; x < maxX(r); x += iw) ctx.drawImage(p, x, y, iw, ih);
  }
}

export function drawPattern(ctx: Ctx, kind: PatternKind, color: string, r: Rect) {
  const step = 12;
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = 1;
  ctx.beginPath();
  switch (kind) {
    case "horizontal": case "grid": {
      const s = kind === "grid" ? step * 2 : step;
      for (let y = r.y; y <= maxY(r); y += s) { ctx.moveTo(r.x, y); ctx.lineTo(maxX(r), y); }
      if (kind === "grid") for (let x = r.x; x <= maxX(r); x += s) { ctx.moveTo(x, r.y); ctx.lineTo(x, maxY(r)); }
      ctx.stroke();
      break;
    }
    case "vertical":
      for (let x = r.x; x <= maxX(r); x += step) { ctx.moveTo(x, r.y); ctx.lineTo(x, maxY(r)); }
      ctx.stroke();
      break;
    case "diagonalUp": case "diagonalDown":
      for (let d = -r.h; d <= r.w; d += step) {
        if (kind === "diagonalDown") { ctx.moveTo(r.x + d, r.y); ctx.lineTo(r.x + d + r.h, maxY(r)); }
        else { ctx.moveTo(r.x + d, maxY(r)); ctx.lineTo(r.x + d + r.h, r.y); }
      }
      ctx.stroke();
      break;
    case "dots":
      for (let y = r.y + step / 2; y < maxY(r); y += step) for (let x = r.x + step / 2; x < maxX(r); x += step) { ctx.moveTo(x + 1.5, y); ctx.arc(x, y, 1.5, 0, Math.PI * 2); }
      ctx.fill();
      break;
    case "checker": {
      let row = 0;
      for (let y = r.y; y < maxY(r); y += step, row++) for (let x = r.x + (row % 2 ? step : 0); x < maxX(r); x += step * 2) ctx.fillRect(x, y, step, step);
      break;
    }
  }
}

// MARK: Lines

export function strokePath(ctx: Ctx, path: Path2D, line: LineStyle, env: RenderEnv, widthScale = 1) {
  if (!line.color || line.width <= 0) return;
  ctx.save();
  ctx.strokeStyle = cssColor(resolve(line.color, env.theme.colors));
  ctx.lineWidth = line.width * widthScale;
  ctx.lineJoin = "round";
  ctx.lineCap = line.roundCaps || line.dash === "roundDot" ? "round" : "butt";
  ctx.setLineDash(dashPattern(line.dash, line.width));
  ctx.stroke(path);
  ctx.restore();
}

/** Draws an arrowhead at `tip`, pointing away from `from`. */
export function arrowhead(ctx: Ctx, kind: ArrowHead, tip: [number, number], from: [number, number], width: number, color: string) {
  if (kind === "none") return;
  const size = Math.max(width, 1) * 3 + 4;
  ctx.save();
  ctx.translate(tip[0], tip[1]);
  ctx.rotate(Math.atan2(tip[1] - from[1], tip[0] - from[0]));
  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineJoin = "round";
  ctx.setLineDash([]);
  ctx.beginPath();
  switch (kind) {
    case "triangle": ctx.moveTo(0, 0); ctx.lineTo(-size, -size / 2); ctx.lineTo(-size, size / 2); ctx.closePath(); ctx.fill(); break;
    case "stealth": ctx.moveTo(0, 0); ctx.lineTo(-size, -size / 2); ctx.lineTo(-size * 0.65, 0); ctx.lineTo(-size, size / 2); ctx.closePath(); ctx.fill(); break;
    case "open": ctx.moveTo(-size, -size / 2); ctx.lineTo(0, 0); ctx.lineTo(-size, size / 2); ctx.stroke(); break;
    case "diamond": ctx.moveTo(size / 2, 0); ctx.lineTo(0, -size / 2); ctx.lineTo(-size / 2, 0); ctx.lineTo(0, size / 2); ctx.closePath(); ctx.fill(); break;
    case "oval": ctx.arc(0, 0, size / 2, 0, Math.PI * 2); ctx.fill(); break;
  }
  ctx.restore();
}

/** How far to pull a line end back so it doesn't poke through its arrowhead. */
export const arrowInset = (kind: ArrowHead, width: number) => (kind === "triangle" || kind === "stealth" ? (Math.max(width, 1) * 3 + 4) * 0.6 : 0);

// MARK: Effects

/** Canvas shadows are in device pixels, so scale them with the current transform. */
export function deviceScale(ctx: Ctx): number {
  const m = ctx.getTransform();
  return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)) || 1;
}

export function applyShadow(ctx: Ctx, s: ShadowEffect) {
  const scale = deviceScale(ctx), angle = (s.angle * Math.PI) / 180;
  // Offsets ignore the rotation of the context; good enough for small shadows.
  ctx.shadowOffsetX = Math.cos(angle) * s.distance * scale;
  ctx.shadowOffsetY = Math.sin(angle) * s.distance * scale;
  ctx.shadowBlur = s.blur * scale;
  ctx.shadowColor = cssColor(withAlpha(s.color, s.opacity));
}

export function applyGlow(ctx: Ctx, g: GlowEffect, env: RenderEnv) {
  ctx.shadowOffsetX = 0;
  ctx.shadowOffsetY = 0;
  ctx.shadowBlur = g.radius * deviceScale(ctx) * 1.5;
  ctx.shadowColor = cssColor(resolve(g.color, env.theme.colors));
}

export function clearShadow(ctx: Ctx) {
  ctx.shadowColor = "transparent";
  ctx.shadowBlur = 0;
  ctx.shadowOffsetX = 0;
  ctx.shadowOffsetY = 0;
}

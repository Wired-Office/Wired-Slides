import type {
  ArrowHead, Bullet, ChartContent, ChartKind, ConnectorKind, CropInsets, DashStyle, Effects, ElementAction, ElementContent,
  Fill, Frame, GradientFill, GroupContent, IconContent, ImageAdjustments, ImageContent, LineContent, LineStyle, MediaContent,
  NumberingScheme, PaintColor, Paragraph, ParagraphStyle, Point, RGB, RunStyle, ShapeContent, ShapeKind, SlideElement,
  TableCell, TableContent, TextAlignment, TextBody, ThemeColors, ThemeSlot, UUID, VerticalAnchor, FontRole,
} from "./types";

// MARK: Identifiers

/** An uppercase UUID, as Swift's `UUID().uuidString` writes them. */
export function uuid(): UUID {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return crypto.randomUUID().toUpperCase();
  const hex = [...Array(32)].map(() => Math.floor(Math.random() * 16).toString(16)).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`.toUpperCase();
}

/** An ISO 8601 date without fractional seconds (what the Mac app's decoder accepts). */
export function isoNow(date = new Date()): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export const clone = <T>(value: T): T => structuredClone(value);
export const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

// MARK: Geometry

export interface Rect { x: number; y: number; w: number; h: number }

export const R = (f: Frame): Rect => ({ x: f[0][0], y: f[0][1], w: f[1][0], h: f[1][1] });
export const F = (r: Rect): Frame => [[r.x, r.y], [r.w, r.h]];
export const frame = (x: number, y: number, w: number, h: number): Frame => [[x, y], [w, h]];
export const midX = (r: Rect) => r.x + r.w / 2;
export const midY = (r: Rect) => r.y + r.h / 2;
export const maxX = (r: Rect) => r.x + r.w;
export const maxY = (r: Rect) => r.y + r.h;
export const inset = (r: Rect, dx: number, dy: number): Rect => ({ x: r.x + dx, y: r.y + dy, w: r.w - dx * 2, h: r.h - dy * 2 });
export const offsetRect = (r: Rect, dx: number, dy: number): Rect => ({ x: r.x + dx, y: r.y + dy, w: r.w, h: r.h });

export function unionRect(a: Rect | null, b: Rect): Rect {
  if (!a) return { ...b };
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(maxX(a), maxX(b)) - x, h: Math.max(maxY(a), maxY(b)) - y };
}

export function rectsIntersect(a: Rect, b: Rect) {
  return a.x < maxX(b) && maxX(a) > b.x && a.y < maxY(b) && maxY(a) > b.y;
}

/** The bounding box of a rectangle rotated about its center. */
export function rotatedBounds(r: Rect, degrees: number): Rect {
  if (!degrees) return r;
  const t = (degrees * Math.PI) / 180, c = Math.abs(Math.cos(t)), s = Math.abs(Math.sin(t));
  const w = r.w * c + r.h * s, h = r.w * s + r.h * c;
  return { x: midX(r) - w / 2, y: midY(r) - h / 2, w, h };
}

// MARK: Colors

export const rgbHex = (hex: number, a = 1): RGB => ({ r: ((hex >> 16) & 255) / 255, g: ((hex >> 8) & 255) / 255, b: (hex & 255) / 255, a });
export const BLACK: RGB = { r: 0, g: 0, b: 0, a: 1 };
export const WHITE: RGB = { r: 1, g: 1, b: 1, a: 1 };
export const CLEAR: RGB = { r: 0, g: 0, b: 0, a: 0 };

export function parseHex(text: string): RGB | null {
  const s = text.trim().replace(/^#/, "");
  if (!/^[0-9a-f]{6}$/i.test(s)) return null;
  return rgbHex(parseInt(s, 16));
}

export function hexString(c: RGB): string {
  const h = (v: number) => Math.round(clamp(v, 0, 1) * 255).toString(16).padStart(2, "0");
  return (h(c.r) + h(c.g) + h(c.b)).toUpperCase();
}

export function cssColor(c: RGB): string {
  const v = (n: number) => Math.round(clamp(n, 0, 1) * 255);
  return c.a >= 1 ? `rgb(${v(c.r)},${v(c.g)},${v(c.b)})` : `rgba(${v(c.r)},${v(c.g)},${v(c.b)},${Math.max(0, c.a)})`;
}

export const withAlpha = (c: RGB, a: number): RGB => ({ ...c, a });

/** Mixes toward white (positive) or black (negative); `amount` in -1…1. */
export function shaded(c: RGB, amount: number): RGB {
  if (!amount) return c;
  if (amount > 0) return { r: c.r + (1 - c.r) * amount, g: c.g + (1 - c.g) * amount, b: c.b + (1 - c.b) * amount, a: c.a };
  const f = 1 + amount;
  return { r: c.r * f, g: c.g * f, b: c.b * f, a: c.a };
}

export const mixed = (a: RGB, b: RGB, t: number): RGB => ({ r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t });
export const luminance = (c: RGB) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
export const isDark = (c: RGB) => luminance(c) < 0.5;
export const sameRGB = (a: RGB, b: RGB) => Math.abs(a.r - b.r) < 0.01 && Math.abs(a.g - b.g) < 0.01 && Math.abs(a.b - b.b) < 0.01 && Math.abs(a.a - b.a) < 0.02;

export const THEME_SLOTS: ThemeSlot[] = ["dark1", "light1", "dark2", "light2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink"];
export const PALETTE_COLUMNS: ThemeSlot[] = ["light1", "dark1", "light2", "dark2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"];
export const SLOT_TITLES: Record<ThemeSlot, string> = {
  dark1: "Text/Background – Dark 1", light1: "Text/Background – Light 1", dark2: "Text/Background – Dark 2", light2: "Text/Background – Light 2",
  accent1: "Accent 1", accent2: "Accent 2", accent3: "Accent 3", accent4: "Accent 4", accent5: "Accent 5", accent6: "Accent 6",
  hyperlink: "Hyperlink", followedHyperlink: "Followed Hyperlink",
};
export const SLOT_OOXML: Record<ThemeSlot, string> = {
  dark1: "dk1", light1: "lt1", dark2: "dk2", light2: "lt2", accent1: "accent1", accent2: "accent2", accent3: "accent3",
  accent4: "accent4", accent5: "accent5", accent6: "accent6", hyperlink: "hlink", followedHyperlink: "folHlink",
};

export function slotFromOOXML(name: string): ThemeSlot | null {
  switch (name) {
    case "tx1": return "dark1";
    case "bg1": return "light1";
    case "tx2": return "dark2";
    case "bg2": return "light2";
  }
  return THEME_SLOTS.find((s) => SLOT_OOXML[s] === name) ?? null;
}

export const STANDARD_COLORS: RGB[] = [0xc00000, 0xff0000, 0xffc000, 0xffff00, 0x92d050, 0x00b050, 0x00b0f0, 0x0070c0, 0x002060, 0x7030a0].map((h) => rgbHex(h));
export const PALETTE_SHADES = [0.8, 0.6, 0.4, -0.25, -0.5];

export function themeColors(dark1: RGB, light1: RGB, dark2: RGB, light2: RGB, accents: RGB[], hyperlink?: RGB, followed?: RGB): ThemeColors {
  const a = [...accents, ...Array(Math.max(0, 6 - accents.length)).fill(rgbHex(0x808080))];
  return {
    dark1, light1, dark2, light2, accent1: a[0], accent2: a[1], accent3: a[2], accent4: a[3], accent5: a[4], accent6: a[5],
    hyperlink: hyperlink ?? rgbHex(0x1f63c6), followedHyperlink: followed ?? rgbHex(0x6a3fa0),
  };
}

export const accents = (c: ThemeColors) => [c.accent1, c.accent2, c.accent3, c.accent4, c.accent5, c.accent6];

export const rgbPaint = (c: RGB): PaintColor => ({ rgb: { _0: c } });
export const themePaint = (slot: ThemeSlot, shade = 0, alpha = 1): PaintColor => ({ theme: { _0: slot, shade, alpha } });

export function resolve(color: PaintColor, colors: ThemeColors): RGB {
  if ("rgb" in color) return color.rgb._0;
  const t = color.theme;
  return withAlpha(shaded(colors[t._0], t.shade), t.alpha);
}

export const paintAlpha = (color: PaintColor) => ("rgb" in color ? color.rgb._0.a : color.theme.alpha);

export function paintWithAlpha(color: PaintColor, alpha: number): PaintColor {
  return "rgb" in color ? rgbPaint(withAlpha(color.rgb._0, alpha)) : themePaint(color.theme._0, color.theme.shade, alpha);
}

export function paintShaded(color: PaintColor, amount: number): PaintColor {
  return "rgb" in color ? rgbPaint(shaded(color.rgb._0, amount)) : themePaint(color.theme._0, color.theme.shade + amount, color.theme.alpha);
}

export const samePaint = (a?: PaintColor, b?: PaintColor) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

// MARK: Fills

export const NO_FILL: Fill = { none: {} };
export const solidFill = (color: PaintColor): Fill => ({ solid: { _0: color } });
export const gradientFill = (g: GradientFill): Fill => ({ gradient: { _0: g } });
export const twoTone = (a: PaintColor, b: PaintColor, angle = 90): GradientFill => ({
  kind: "linear", stops: [{ color: a, position: 0 }, { color: b, position: 1 }], angle,
});

export const isNoFill = (f: Fill | undefined) => !f || "none" in f;
export const fillSolid = (f: Fill | undefined): PaintColor | null => (f && "solid" in f ? f.solid._0 : null);

export function fillRepresentative(f: Fill, colors: ThemeColors): RGB | null {
  if ("solid" in f) return resolve(f.solid._0, colors);
  if ("gradient" in f) return f.gradient._0.stops[0] ? resolve(f.gradient._0.stops[0].color, colors) : null;
  if ("pattern" in f) return resolve(f.pattern._0.background, colors);
  return null;
}

export const fillMediaIDs = (f: Fill | undefined): string[] => (f && "image" in f ? [f.image._0.mediaID] : []);

// MARK: Lines and effects

export function lineStyle(color?: PaintColor, width = 1, extra: Partial<LineStyle> = {}): LineStyle {
  const line: LineStyle = { width, dash: "solid", head: "none", tail: "none", roundCaps: false, ...extra };
  if (color) line.color = color;
  return line;
}

export const NO_LINE = (): LineStyle => lineStyle(undefined, 1);
export const lineVisible = (l: LineStyle) => !!l.color && l.width > 0;
export const noEffects = (): Effects => ({ softEdges: 0 });
export const effectsEmpty = (e: Effects) => !e.shadow && !e.glow && !e.reflection && !e.softEdges;
export const OUTER_SHADOW = () => ({ color: { ...BLACK }, opacity: 0.35, blur: 8, distance: 4, angle: 45 });
export const SOFT_SHADOW = () => ({ color: { ...BLACK }, opacity: 0.25, blur: 18, distance: 6, angle: 90 });

export const DASH_TITLES: Record<DashStyle, string> = {
  solid: "Solid", roundDot: "Round Dot", squareDot: "Square Dot", dash: "Dash", dashDot: "Dash Dot", longDash: "Long Dash", longDashDot: "Long Dash Dot",
};
export const DASH_OOXML: Record<DashStyle, string> = {
  solid: "solid", roundDot: "sysDot", squareDot: "sysDash", dash: "dash", dashDot: "dashDot", longDash: "lgDash", longDashDot: "lgDashDot",
};
export function dashFromOOXML(v: string): DashStyle {
  const found = (Object.keys(DASH_OOXML) as DashStyle[]).find((k) => DASH_OOXML[k] === v);
  return found ?? (v === "sysDashDot" ? "dashDot" : "solid");
}
export function dashPattern(dash: DashStyle, width: number): number[] {
  const w = Math.max(width, 1);
  switch (dash) {
    case "solid": return [];
    case "roundDot": return [0.01, w * 2];
    case "squareDot": return [w, w];
    case "dash": return [w * 4, w * 3];
    case "dashDot": return [w * 4, w * 3, w, w * 3];
    case "longDash": return [w * 8, w * 3];
    case "longDashDot": return [w * 8, w * 3, w, w * 3];
  }
}

export const ARROW_TITLES: Record<ArrowHead, string> = { none: "None", triangle: "Arrow", open: "Open Arrow", stealth: "Stealth Arrow", diamond: "Diamond", oval: "Oval" };
export const ARROW_OOXML: Record<ArrowHead, string> = { none: "none", triangle: "triangle", open: "arrow", stealth: "stealth", diamond: "diamond", oval: "oval" };
export const arrowFromOOXML = (v: string): ArrowHead => (Object.keys(ARROW_OOXML) as ArrowHead[]).find((k) => ARROW_OOXML[k] === v) ?? "none";

export const identityAdjustments = (): ImageAdjustments => ({ brightness: 0, contrast: 0, saturation: 1, transparency: 0, sepia: false });
export const adjustmentsIdentity = (a: ImageAdjustments) => !a.brightness && !a.contrast && a.saturation === 1 && !a.sepia;
export const zeroCrop = (): CropInsets => ({ left: 0, top: 0, right: 0, bottom: 0 });
export const cropZero = (c: CropInsets) => !c.left && !c.top && !c.right && !c.bottom;

// MARK: Text

export const plainRun = (): RunStyle => ({
  underline: false, strikethrough: false, baseline: 0, allCaps: false, smallCaps: false, characterSpacing: 0, outlineWidth: 0, shadow: false,
});

export const NO_BULLET: Bullet = { none: {} };
export const symbolBullet = (s: string): Bullet => ({ symbol: { _0: s } });
export const numberedBullet = (scheme: NumberingScheme, start = 1): Bullet => ({ numbered: { _0: scheme, start } });
export const bulletIsNone = (b: Bullet) => "none" in b;
export const STANDARD_BULLETS = ["•", "◦", "▪", "–", "➢", "✓", "◆", "★"];

export const plainParagraphStyle = (alignment: TextAlignment = "left"): ParagraphStyle => ({
  alignment, level: 0, bullet: { none: {} }, lineSpacing: 1, spaceBefore: 0, spaceAfter: 0,
});

export const paragraph = (text: string, style = plainParagraphStyle(), run = plainRun()): Paragraph => ({ runs: [{ text, style: run }], style });
export const paragraphText = (p: Paragraph) => p.runs.map((r) => r.text).join("");

export function emptyTextBody(): TextBody {
  return {
    paragraphs: [paragraph("")], anchor: "top", autofit: "none", wrap: true, columns: 1, direction: "horizontal",
    insets: { top: 3.6, left: 7.2, bottom: 3.6, right: 7.2 }, defaultSize: 18, defaultColor: themePaint("dark1"), fontRole: "body",
  };
}

export function textBody(text: string, o: { size?: number; role?: FontRole; alignment?: TextAlignment; anchor?: VerticalAnchor; color?: PaintColor; bold?: boolean } = {}): TextBody {
  const body = emptyTextBody();
  const run = plainRun();
  if (o.bold !== undefined) run.bold = o.bold;
  body.paragraphs = text.split("\n").map((line) => paragraph(line, plainParagraphStyle(o.alignment ?? "left"), clone(run)));
  body.defaultSize = o.size ?? 18;
  body.fontRole = o.role ?? "body";
  body.anchor = o.anchor ?? "top";
  body.defaultColor = o.color ?? themePaint("dark1");
  return body;
}

export const plainText = (b: TextBody) => b.paragraphs.map(paragraphText).join("\n");
export const textIsEmpty = (b: TextBody) => b.paragraphs.every((p) => paragraphText(p) === "");

/** Replaces all text, keeping the first paragraph's and run's formatting. */
export function setPlainText(b: TextBody, text: string) {
  const style = b.paragraphs[0]?.style ?? plainParagraphStyle();
  const run = b.paragraphs[0]?.runs[0]?.style ?? plainRun();
  b.paragraphs = text.split("\n").map((line) => paragraph(line, clone(style), clone(run)));
}

export function updateRuns(b: TextBody, change: (r: RunStyle) => void) {
  for (const p of b.paragraphs) for (const r of p.runs) change(r.style);
}

export function updateParagraphs(b: TextBody, change: (p: ParagraphStyle) => void) {
  for (const p of b.paragraphs) change(p.style);
}

export const firstRunStyle = (b: TextBody): RunStyle => b.paragraphs[0]?.runs[0]?.style ?? plainRun();
export const firstParagraphStyle = (b: TextBody): ParagraphStyle => b.paragraphs[0]?.style ?? plainParagraphStyle();

export const NUMBERING_TITLES: Record<NumberingScheme, string> = {
  arabicPeriod: "1. 2. 3.", arabicParen: "1) 2) 3)", romanUpper: "I. II. III.", romanLower: "i. ii. iii.", alphaUpper: "A. B. C.", alphaLower: "a) b) c)",
};
export const NUMBERING_OOXML: Record<NumberingScheme, string> = {
  arabicPeriod: "arabicPeriod", arabicParen: "arabicParenR", romanUpper: "romanUcPeriod", romanLower: "romanLcPeriod", alphaUpper: "alphaUcPeriod", alphaLower: "alphaLcParenR",
};
export const numberingFromOOXML = (v: string): NumberingScheme =>
  (Object.keys(NUMBERING_OOXML) as NumberingScheme[]).find((k) => NUMBERING_OOXML[k] === v) ?? "arabicPeriod";

function roman(n: number): string {
  const table: [number, string][] = [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
  let v = Math.max(1, n), out = "";
  for (const [value, symbol] of table) while (v >= value) { out += symbol; v -= value; }
  return out;
}

function alpha(n: number): string {
  let v = Math.max(1, n), out = "";
  while (v > 0) { v -= 1; out = String.fromCharCode(65 + (v % 26)) + out; v = Math.floor(v / 26); }
  return out;
}

export function numberLabel(scheme: NumberingScheme, n: number): string {
  switch (scheme) {
    case "arabicPeriod": return `${n}.`;
    case "arabicParen": return `${n})`;
    case "romanUpper": return roman(n) + ".";
    case "romanLower": return roman(n).toLowerCase() + ".";
    case "alphaUpper": return alpha(n) + ".";
    case "alphaLower": return alpha(n).toLowerCase() + ")";
  }
}

// MARK: Element content

type ContentKey = "shape" | "image" | "line" | "table" | "chart" | "icon" | "media" | "group";
export const contentKind = (c: ElementContent): ContentKey => Object.keys(c)[0] as ContentKey;

export const shapeOf = (e: SlideElement): ShapeContent | null => ("shape" in e.content ? e.content.shape._0 : null);
export const imageOf = (e: SlideElement): ImageContent | null => ("image" in e.content ? e.content.image._0 : null);
export const lineOf = (e: SlideElement): LineContent | null => ("line" in e.content ? e.content.line._0 : null);
export const tableOf = (e: SlideElement): TableContent | null => ("table" in e.content ? e.content.table._0 : null);
export const chartOf = (e: SlideElement): ChartContent | null => ("chart" in e.content ? e.content.chart._0 : null);
export const iconOf = (e: SlideElement): IconContent | null => ("icon" in e.content ? e.content.icon._0 : null);
export const mediaOf = (e: SlideElement): MediaContent | null => ("media" in e.content ? e.content.media._0 : null);
export const groupOf = (e: SlideElement): GroupContent | null => ("group" in e.content ? e.content.group._0 : null);
export const textOf = (e: SlideElement): TextBody | null => shapeOf(e)?.text ?? null;
export const hasText = (e: SlideElement) => { const t = textOf(e); return !!t && !textIsEmpty(t); };

export function effectsOf(e: SlideElement): Effects | null {
  return shapeOf(e)?.effects ?? imageOf(e)?.effects ?? lineOf(e)?.effects ?? null;
}

export const isTitleRole = (role?: string) => role === "title" || role === "centeredTitle";

/** A new element with every field the Mac app expects. */
export function element(name: string, f: Frame, content: ElementContent, placeholder?: SlideElement["placeholder"]): SlideElement {
  const e: SlideElement = {
    id: uuid(), name, frame: f, rotation: 0, flipH: false, flipV: false, locked: false, hidden: false, lockAspectRatio: false, altText: "", content,
  };
  if (placeholder) e.placeholder = placeholder;
  return e;
}

export function shapeContent(kind: ShapeKind, fill: Fill, line: LineStyle, text = emptyTextBody()): ShapeContent {
  return { kind, fill, line, effects: noEffects(), text, adjustments: [] };
}

export function textBoxElement(text: string, f: Frame, o: { size?: number; role?: FontRole; alignment?: TextAlignment; color?: PaintColor; bold?: boolean; anchor?: VerticalAnchor } = {}): SlideElement {
  const body = textBody(text, o);
  body.autofit = "resizeShape";
  return element("TextBox", f, { shape: { _0: shapeContent("rect", NO_FILL, NO_LINE(), body) } });
}

export function shapeElement(kind: ShapeKind, f: Frame, fill: Fill = solidFill(themePaint("accent1")),
  line: LineStyle = lineStyle(themePaint("accent1", -0.25), 1), text = ""): SlideElement {
  const body = textBody(text, { size: 18, alignment: "center", anchor: "middle", color: themePaint("light1") });
  body.insets = { top: 3.6, left: 7.2, bottom: 3.6, right: 7.2 };
  return element(SHAPE_TITLE_LOOKUP(kind), f, { shape: { _0: shapeContent(kind, fill, line, body) } });
}

let SHAPE_TITLE_LOOKUP: (k: ShapeKind) => string = (k) => k;
/** Lets the shape catalog supply names without an import cycle. */
export function setShapeTitleLookup(fn: (k: ShapeKind) => string) { SHAPE_TITLE_LOOKUP = fn; }

export function lineElement(a: Point, b: Point, style: LineStyle, kind: ConnectorKind = "straight"): SlideElement {
  const e = element(kind === "straight" ? "Straight Connector" : "Connector",
    frame(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1])),
    { line: { _0: { kind, line: style, effects: noEffects() } } });
  e.flipH = b[0] < a[0];
  e.flipV = b[1] < a[1];
  return e;
}

/** Endpoints of a line in slide coordinates (flips choose the corners). */
export function lineEndpoints(e: SlideElement): { start: Point; end: Point } {
  const f = R(e.frame);
  const sx = e.flipH ? maxX(f) : f.x, ex = e.flipH ? f.x : maxX(f);
  const sy = e.flipV ? maxY(f) : f.y, ey = e.flipV ? f.y : maxY(f);
  return { start: [sx, sy], end: [ex, ey] };
}

export function setLineEndpoints(e: SlideElement, a: Point, b: Point) {
  e.frame = frame(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
  e.flipH = b[0] < a[0];
  e.flipV = b[1] < a[1];
}

export function imageContent(mediaID: string): ImageContent {
  return { mediaID, crop: zeroCrop(), line: NO_LINE(), effects: noEffects(), adjustments: identityAdjustments() };
}

export function tableCellBody(text: string): TextBody {
  const body = textBody(text, { size: 16 });
  body.insets = { top: 4, left: 7, bottom: 4, right: 7 };
  body.anchor = "middle";
  return body;
}

export const tableCell = (text = ""): TableCell => ({ text: tableCellBody(text), rowSpan: 1, columnSpan: 1, isMerged: false });

export function makeTable(rows: number, columns: number, width: number, rowHeight = 37): TableContent {
  return {
    rows: Array.from({ length: rows }, () => Array.from({ length: columns }, () => tableCell())),
    columnWidths: Array(columns).fill(width / columns),
    rowHeights: Array(rows).fill(rowHeight),
    style: {
      headerRow: true, totalRow: false, bandedRows: true, firstColumn: false, lastColumn: false, bandedColumns: false,
      color: themePaint("accent1"), intensity: 0, borderWidth: 1,
    },
  };
}

export function chartContent(kind: ChartKind, o: Partial<ChartContent> = {}): ChartContent {
  return {
    kind, categories: [], series: [], legend: "bottom", showDataLabels: false, showGridlines: true, fontSize: 12,
    textColor: themePaint("dark1", 0.25), background: NO_FILL, ...o,
  };
}

export const isRoundChart = (k: ChartKind) => k === "pie" || k === "doughnut";

export function sampleChart(kind: ChartKind): ChartContent {
  return chartContent(kind, {
    title: "Chart Title",
    categories: ["Category 1", "Category 2", "Category 3", "Category 4"],
    series: isRoundChart(kind)
      ? [{ name: "Sales", values: [8.2, 3.2, 1.4, 1.2] }]
      : [{ name: "Series 1", values: [4.3, 2.5, 3.5, 4.5] }, { name: "Series 2", values: [2.4, 4.4, 1.8, 2.8] }, { name: "Series 3", values: [2, 2, 3, 5] }],
  });
}

export const CHART_TITLES: Record<ChartKind, string> = {
  column: "Clustered Column", stackedColumn: "Stacked Column", bar: "Clustered Bar", stackedBar: "Stacked Bar", line: "Line",
  lineMarkers: "Line with Markers", area: "Area", pie: "Pie", doughnut: "Doughnut", scatter: "Scatter",
};

// MARK: Element tree helpers

export function findElement(elements: SlideElement[], id: UUID): SlideElement | null {
  for (const e of elements) {
    if (e.id === id) return e;
    const g = groupOf(e);
    if (g) { const found = findElement(g.children, id); if (found) return found; }
  }
  return null;
}

export function elementMediaIDs(e: SlideElement): string[] {
  const c = e.content;
  if ("shape" in c) return fillMediaIDs(c.shape._0.fill);
  if ("image" in c) return [c.image._0.mediaID];
  if ("media" in c) return [c.media._0.mediaID, ...(c.media._0.posterID ? [c.media._0.posterID] : [])];
  if ("group" in c) return c.group._0.children.flatMap(elementMediaIDs);
  if ("table" in c) return c.table._0.rows.flatMap((r) => r.flatMap((cell) => fillMediaIDs(cell.fill)));
  return [];
}

export function elementTexts(e: SlideElement): string[] {
  const c = e.content;
  if ("shape" in c) return [plainText(c.shape._0.text)];
  if ("table" in c) return c.table._0.rows.flatMap((r) => r.map((cell) => plainText(cell.text)));
  if ("group" in c) return c.group._0.children.flatMap(elementTexts);
  if ("chart" in c) return [c.chart._0.title ?? ""];
  return [];
}

/** Moves the element (and group children) by an offset. */
export function offsetElement(e: SlideElement, dx: number, dy: number) {
  e.frame = [[e.frame[0][0] + dx, e.frame[0][1] + dy], e.frame[1]];
  const g = groupOf(e);
  if (g) for (const child of g.children) offsetElement(child, dx, dy);
}

/** Resizes to a new frame, scaling group children and table geometry along. */
export function setElementFrame(e: SlideElement, next: Rect) {
  const old = R(e.frame);
  e.frame = F(next);
  const g = groupOf(e);
  if (g) {
    const sx = old.w > 0 ? next.w / old.w : 1, sy = old.h > 0 ? next.h / old.h : 1;
    for (const child of g.children) {
      const c = R(child.frame);
      setElementFrame(child, { x: next.x + (c.x - old.x) * sx, y: next.y + (c.y - old.y) * sy, w: c.w * sx, h: c.h * sy });
    }
  }
  const t = tableOf(e);
  if (t) {
    const total = t.columnWidths.reduce((a, b) => a + b, 0);
    if (total > 0) t.columnWidths = t.columnWidths.map((w) => (w * next.w) / total);
    const totalH = t.rowHeights.reduce((a, b) => a + b, 0);
    if (totalH > 0 && Math.abs(next.h - old.h) > 0.5) t.rowHeights = t.rowHeights.map((h) => (h * next.h) / totalH);
  }
}

/** A copy with fresh identifiers (children included). */
export function duplicateElement(e: SlideElement): SlideElement {
  const copy = clone(e);
  const refresh = (x: SlideElement) => { x.id = uuid(); const g = groupOf(x); if (g) g.children.forEach(refresh); };
  refresh(copy);
  return copy;
}

export function elementKindName(e: SlideElement, shapeTitle: (k: ShapeKind) => string): string {
  const c = e.content;
  if ("shape" in c) {
    if (e.placeholder) return isTitleRole(e.placeholder) ? "Title" : "Placeholder";
    const s = c.shape._0;
    return isNoFill(s.fill) && !lineVisible(s.line) ? "Text Box" : shapeTitle(s.kind);
  }
  if ("image" in c) return "Picture";
  if ("line" in c) return "Line";
  if ("table" in c) return "Table";
  if ("chart" in c) return "Chart";
  if ("icon" in c) return "Icon";
  if ("media" in c) return c.media._0.kind === "video" ? "Video" : "Audio";
  return "Group";
}

// MARK: Actions

export function actionTitle(a: ElementAction): string {
  if ("url" in a) return a.url._0;
  if ("slide" in a) return "Slide";
  if ("nextSlide" in a) return "Next Slide";
  if ("previousSlide" in a) return "Previous Slide";
  if ("firstSlide" in a) return "First Slide";
  if ("lastSlide" in a) return "Last Slide";
  return "End Show";
}

import type { PaintColor, ThemeColors } from "../model/types";
import { PALETTE_COLUMNS, PALETTE_SHADES, SLOT_TITLES, STANDARD_COLORS, cssColor, hexString, parseHex, resolve, rgbPaint, shaded, themePaint } from "../model/core";

let open: HTMLElement | null = null;

export function closePalette() {
  open?.remove();
  open = null;
}

export interface PaletteOptions {
  /** Shows a "No Fill"/"No Color" button with this label. */
  noneLabel?: string;
  /** Shows an "Automatic" button with this label. */
  automaticLabel?: string;
  /** Extra buttons at the bottom (e.g. "Gradient…", "Picture…"). */
  extras?: { label: string; action: () => void }[];
}

/**
 * The PowerPoint color palette: theme colors with tints and shades (kept as
 * theme references, so they follow theme changes), standard colors and More
 * Colors. Calls `pick` with the color, or null for none/automatic.
 */
export function showPalette(anchor: HTMLElement, colors: ThemeColors, pick: (color: PaintColor | null) => void, o: PaletteOptions = {}) {
  closePalette();
  const root = document.createElement("div");
  root.className = "palette";
  const add = (label: string, color: PaintColor, css: string) => {
    const b = document.createElement("button");
    b.title = label;
    b.style.background = css;
    b.addEventListener("click", () => { closePalette(); pick(color); });
    root.append(b);
  };
  const heading = (text: string) => {
    const l = document.createElement("div");
    l.className = "label";
    l.textContent = text;
    root.append(l);
  };
  const wide = (label: string, action: () => void) => {
    const b = document.createElement("button");
    b.className = "wide";
    b.textContent = label;
    b.addEventListener("click", () => { closePalette(); action(); });
    root.append(b);
  };
  if (o.automaticLabel) wide(o.automaticLabel, () => pick(null));
  heading("Theme Colors");
  for (const slot of PALETTE_COLUMNS) add(SLOT_TITLES[slot], themePaint(slot), cssColor(colors[slot]));
  for (const shade of PALETTE_SHADES) {
    for (const slot of PALETTE_COLUMNS) {
      // Very light colors get darker steps and very dark ones lighter steps, like PowerPoint.
      const base = colors[slot];
      const l = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b;
      let s = shade;
      if (l > 0.9) s = shade > 0 ? -[0.05, 0.15, 0.25][PALETTE_SHADES.indexOf(shade)] : shade;
      if (l < 0.1) s = shade < 0 ? [0.15, 0.05][PALETTE_SHADES.indexOf(shade) - 3] ?? 0.1 : shade;
      const percent = Math.round(Math.abs(s) * 100);
      add(`${SLOT_TITLES[slot]}, ${s > 0 ? "Lighter" : "Darker"} ${percent}%`, themePaint(slot, s), cssColor(shaded(base, s)));
    }
  }
  heading("Standard Colors");
  for (const c of STANDARD_COLORS) add(`#${hexString(c)}`, rgbPaint(c), cssColor(c));
  if (o.noneLabel) wide(o.noneLabel, () => pick(null));
  wide("More Colors…", () => {
    const input = document.createElement("input");
    input.type = "color";
    input.value = "#" + hexString(STANDARD_COLORS[7]).toLowerCase();
    input.style.position = "fixed";
    input.style.left = "-100px";
    document.body.append(input);
    input.addEventListener("change", () => { const c = parseHex(input.value); if (c) pick(rgbPaint(c)); input.remove(); });
    input.addEventListener("blur", () => setTimeout(() => input.remove(), 500));
    input.click();
  });
  for (const extra of o.extras ?? []) wide(extra.label, extra.action);
  document.body.append(root);
  const rect = anchor.getBoundingClientRect();
  let x = rect.left, y = rect.bottom + 2;
  if (x + root.offsetWidth > innerWidth - 6) x = innerWidth - root.offsetWidth - 6;
  if (y + root.offsetHeight > innerHeight - 6) y = Math.max(6, rect.top - root.offsetHeight - 2);
  root.style.left = `${Math.max(6, x)}px`;
  root.style.top = `${y}px`;
  open = root;
  const outside = (event: MouseEvent) => {
    if (open !== root) { document.removeEventListener("mousedown", outside, true); return; }
    if (!root.contains(event.target as Node) && !anchor.contains(event.target as Node)) { closePalette(); document.removeEventListener("mousedown", outside, true); }
  };
  setTimeout(() => document.addEventListener("mousedown", outside, true), 0);
  const keys = (event: KeyboardEvent) => { if (event.key === "Escape") { closePalette(); document.removeEventListener("keydown", keys, true); } };
  document.addEventListener("keydown", keys, true);
}

/** A CSS color for a swatch preview. */
export const swatchCSS = (color: PaintColor | null | undefined, colors: ThemeColors) => (color ? cssColor(resolve(color, colors)) : "transparent");

let galleryOpen: HTMLElement | null = null;

export function closeGallery() {
  galleryOpen?.remove();
  galleryOpen = null;
}

/** A popover panel under a button (shape and theme galleries, etc.). */
export function showGallery(anchor: HTMLElement, build: (root: HTMLElement, close: () => void) => void, width?: number) {
  closeGallery();
  closePalette();
  const root = document.createElement("div");
  root.className = "gallery";
  if (width) root.style.width = `${width}px`;
  build(root, closeGallery);
  document.body.append(root);
  const rect = anchor.getBoundingClientRect();
  let x = rect.left, y = rect.bottom + 2;
  if (x + root.offsetWidth > innerWidth - 6) x = innerWidth - root.offsetWidth - 6;
  if (y + root.offsetHeight > innerHeight - 6) y = Math.max(6, innerHeight - root.offsetHeight - 6);
  root.style.left = `${Math.max(6, x)}px`;
  root.style.top = `${y}px`;
  galleryOpen = root;
  const outside = (event: MouseEvent) => {
    if (galleryOpen !== root) { document.removeEventListener("mousedown", outside, true); return; }
    const target = event.target as Node;
    if (!root.contains(target) && !anchor.contains(target) && !document.querySelector(".palette")?.contains(target)) { closeGallery(); document.removeEventListener("mousedown", outside, true); }
  };
  setTimeout(() => document.addEventListener("mousedown", outside, true), 0);
  const keys = (event: KeyboardEvent) => { if (event.key === "Escape" && galleryOpen === root) { closeGallery(); document.removeEventListener("keydown", keys, true); } };
  document.addEventListener("keydown", keys, true);
}

/**
 * Mac theme fonts (Helvetica Neue, Avenir Next, Gill Sans…) are rarely
 * installed on Windows or Linux, so each family gets a stack of look-alikes.
 */
const SANS = ["Segoe UI", "Helvetica Neue", "Helvetica", "Arial", "Liberation Sans", "Noto Sans", "DejaVu Sans", "Ubuntu", "Cantarell", "sans-serif"];
const SERIF = ["Georgia", "Cambria", "Times New Roman", "Liberation Serif", "Noto Serif", "DejaVu Serif", "serif"];
const MONO = ["Consolas", "Menlo", "Cascadia Mono", "Liberation Mono", "DejaVu Sans Mono", "Noto Sans Mono", "monospace"];

const SIMILAR: Record<string, string[]> = {
  "Helvetica Neue": ["Helvetica", "Arial", "Liberation Sans", "Segoe UI", "Noto Sans"],
  "Avenir Next": ["Avenir", "Nunito Sans", "Segoe UI", "Montserrat", "Noto Sans"],
  "Avenir Next Condensed": ["Avenir Next Condensed", "Roboto Condensed", "Arial Narrow", "Liberation Sans Narrow", "Segoe UI"],
  Avenir: ["Avenir Next", "Nunito Sans", "Segoe UI", "Noto Sans"],
  "Gill Sans": ["Gill Sans MT", "Lato", "Segoe UI", "Calibri", "Noto Sans"],
  Futura: ["Futura PT", "Century Gothic", "URW Gothic", "Montserrat", "Segoe UI"],
  Baskerville: ["Baskerville Old Face", "Libre Baskerville", "Georgia", "Cambria"],
  Didot: ["Bodoni MT", "Bodoni 72", "Playfair Display", "Georgia"],
  Optima: ["Candara", "Optima nova", "URW Classico", "Segoe UI"],
  Palatino: ["Palatino Linotype", "Book Antiqua", "URW Palladio L", "P052", "Georgia"],
  Rockwell: ["Rockwell", "Roboto Slab", "Courier New"],
  "American Typewriter": ["Courier New", "Courier Prime", "Liberation Mono"],
  "SF Pro Display": ["Segoe UI", "Helvetica Neue", "Roboto", "Noto Sans"],
  "SF Pro Text": ["Segoe UI", "Helvetica Neue", "Roboto", "Noto Sans"],
  "Calibri Light": ["Calibri", "Carlito", "Segoe UI Light", "Segoe UI"],
  Calibri: ["Carlito", "Segoe UI", "Noto Sans"],
  Cambria: ["Caladea", "Georgia"],
  "Trebuchet MS": ["Trebuchet MS", "Fira Sans", "Ubuntu", "Segoe UI"],
  Arial: ["Liberation Sans", "Helvetica", "Noto Sans"],
  "Times New Roman": ["Liberation Serif", "Times", "Noto Serif"],
  "Courier New": ["Liberation Mono", "Courier", "Noto Sans Mono"],
  Menlo: ["Consolas", "Cascadia Mono", "DejaVu Sans Mono"],
  "Segoe UI": ["Helvetica Neue", "Noto Sans", "Ubuntu", "Cantarell"],
  "Segoe UI Light": ["Segoe UI", "Helvetica Neue", "Noto Sans"],
};

const SERIF_HINTS = /serif|georgia|times|baskerville|didot|palatino|garamond|cambria|bodoni|book|caslon|minion|rockwell|typewriter/i;
const MONO_HINTS = /mono|menlo|consolas|courier|code/i;

const quote = (name: string) => (/^(serif|sans-serif|monospace|system-ui)$/.test(name) ? name : `"${name.replace(/"/g, "")}"`);
const stacks = new Map<string, string>();

/** A CSS font-family list for a theme or run font. */
export function fontStack(family: string): string {
  let cached = stacks.get(family);
  if (cached) return cached;
  const generic = MONO_HINTS.test(family) ? MONO : SERIF_HINTS.test(family) && !/sans/i.test(family) ? SERIF : SANS;
  const names = [family, ...(SIMILAR[family] ?? []), ...generic];
  cached = [...new Set(names)].map(quote).join(", ");
  stacks.set(family, cached);
  return cached;
}

/** The canvas `font` shorthand. */
export function fontString(family: string, size: number, bold: boolean, italic: boolean, smallCaps = false): string {
  const weight = /light/i.test(family) && !bold ? "300 " : bold ? "bold " : "";
  return `${italic ? "italic " : ""}${smallCaps ? "small-caps " : ""}${weight}${Math.max(size, 0.5).toFixed(2)}px ${fontStack(family)}`;
}

const CANDIDATES = [
  "Arial", "Calibri", "Cambria", "Candara", "Century Gothic", "Consolas", "Constantia", "Corbel", "Courier New", "Franklin Gothic Medium",
  "Garamond", "Georgia", "Gill Sans", "Helvetica", "Helvetica Neue", "Avenir Next", "Futura", "Impact", "Lucida Sans", "Palatino Linotype",
  "Segoe UI", "Segoe UI Light", "Tahoma", "Times New Roman", "Trebuchet MS", "Verdana", "Menlo", "Baskerville", "Optima", "Didot", "Rockwell",
  "Liberation Sans", "Liberation Serif", "Liberation Mono", "DejaVu Sans", "DejaVu Serif", "DejaVu Sans Mono", "Noto Sans", "Noto Serif",
  "Ubuntu", "Cantarell", "Roboto", "Open Sans", "Lato", "Montserrat", "Source Sans Pro", "Fira Sans", "Carlito", "Caladea", "Inter",
];

let installed: string[] | null = null;

/** Fonts installed on this computer (measured, since document.fonts.check is unreliable). */
export function installedFonts(): string[] {
  if (installed) return installed;
  const ctx = typeof document !== "undefined" ? document.createElement("canvas").getContext("2d") : null;
  if (!ctx) return (installed = CANDIDATES);
  const sample = "mmmmmmmmmmlli1WQ@#";
  const width = (font: string) => { ctx.font = `32px ${font}`; return ctx.measureText(sample).width; };
  const bases = ["monospace", "serif", "sans-serif"].map((b) => [b, width(b)] as const);
  installed = CANDIDATES.filter((name) => bases.some(([base, w]) => width(`"${name}", ${base}`) !== w)).sort();
  return installed;
}

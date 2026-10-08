import type { Fill, PaintColor, PresentationTheme, ShapeKind, SlideElement, ThemeColors } from "./types";
import {
  NO_LINE, frame, gradientFill, lineElement, lineStyle, rgbHex, rgbPaint, shapeElement, shapeOf, solidFill, themeColors, themePaint, twoTone,
} from "./core";

function deco(kind: ShapeKind, x: number, y: number, w: number, h: number, fill: Fill, rotation = 0): SlideElement {
  const e = shapeElement(kind, frame(x, y, w, h), fill, NO_LINE());
  e.name = "Decoration";
  e.rotation = rotation;
  return e;
}

function rule(a: [number, number], b: [number, number], color: PaintColor, width = 1): SlideElement {
  const e = lineElement(a, b, lineStyle(color, width));
  e.name = "Decoration";
  return e;
}

const colors = (d1: number, l1: number, d2: number, l2: number, a: number[]): ThemeColors =>
  themeColors(rgbHex(d1), rgbHex(l1), rgbHex(d2), rgbHex(l2), a.map((h) => rgbHex(h)));

function theme(id: string, name: string, c: ThemeColors, heading: string, body: string, build: (t: PresentationTheme) => void = () => {}): PresentationTheme {
  const t: PresentationTheme = {
    id, name, colors: c, headingFont: heading, bodyFont: body, background: solidFill(themePaint("light1")), decorations: [], titleDecorations: [],
    titleColor: themePaint("dark1"), titleSize: 40, titleBold: false, titleCaps: false, bodySize: 24, bulletSymbol: "•", variants: [],
  };
  build(t);
  return t;
}

const adjust = (e: SlideElement, values: number[]) => { const s = shapeOf(e); if (s) s.adjustments = values; return e; };
const flipped = (e: SlideElement) => { e.flipH = true; return e; };

/** Builds the themes fresh each time so callers can change them freely. */
export function builtInThemes(): PresentationTheme[] {
  return [
    theme("wired", "Wired", colors(0x1c1c1e, 0xffffff, 0x3a3a3c, 0xf4f2ee, [0xf57a1b, 0x2f6fdb, 0x1e9a5f, 0xd64545, 0x8e5cd9, 0x13a3a3]), "Helvetica Neue", "Helvetica Neue", (t) => {
      t.titleBold = true;
      t.decorations = [deco("ellipse", 904, 26, 18, 18, solidFill(themePaint("accent1"))), rule([60, 512], [900, 512], themePaint("dark1", 0.85))];
      t.titleDecorations = [deco("ellipse", 456, 70, 48, 48, solidFill(themePaint("accent1")))];
      t.bulletColor = themePaint("accent1");
      t.variants = [
        colors(0x1c1c1e, 0xffffff, 0x3a3a3c, 0xeef3fb, [0x2f6fdb, 0xf57a1b, 0x1e9a5f, 0xd64545, 0x8e5cd9, 0x13a3a3]),
        colors(0x1c1c1e, 0xffffff, 0x3a3a3c, 0xedf7f1, [0x1e9a5f, 0x2f6fdb, 0xf57a1b, 0xd64545, 0x8e5cd9, 0x13a3a3]),
        colors(0xf5f5f7, 0x161618, 0xd1d1d6, 0x2c2c2e, [0xf57a1b, 0x5e9bff, 0x3ccb8a, 0xff6b6b, 0xb48cff, 0x3fd1d1]),
      ];
    }),
    theme("clean", "Clean", colors(0x000000, 0xffffff, 0x44546a, 0xe7e6e6, [0x4472c4, 0xed7d31, 0xa5a5a5, 0xffc000, 0x5b9bd5, 0x70ad47]), "Avenir Next", "Avenir Next", (t) => {
      t.variants = [
        colors(0x000000, 0xffffff, 0x0e2841, 0xe8e8e8, [0x156082, 0xe97132, 0x196b24, 0x0f9ed5, 0xa02b93, 0x4ea72e]),
        colors(0x000000, 0xffffff, 0x323232, 0xe3ded1, [0xa5644e, 0xb58b80, 0xc3986d, 0xa19574, 0xc17529, 0x7a6a55]),
      ];
    }),
    theme("graphite", "Graphite", colors(0xf2f2f2, 0x1e1f22, 0xbdbdc2, 0x2b2d31, [0xff9f43, 0x54a0ff, 0x1dd1a1, 0xff6b6b, 0xc8a2ff, 0x48dbfb]), "Avenir Next", "Avenir Next", (t) => {
      t.titleBold = true;
      t.titleBackground = gradientFill({ kind: "radial", stops: [{ color: themePaint("light2"), position: 0 }, { color: themePaint("light1"), position: 1 }], angle: 0 });
      t.decorations = [deco("rect", 0, 0, 8, 540, solidFill(themePaint("accent1")))];
      t.titleDecorations = [deco("rect", 380, 300, 200, 4, solidFill(themePaint("accent1")))];
      t.bulletColor = themePaint("accent1");
      t.variants = [
        colors(0xf2f2f2, 0x1e1f22, 0xbdbdc2, 0x2b2d31, [0x54a0ff, 0xff9f43, 0x1dd1a1, 0xff6b6b, 0xc8a2ff, 0x48dbfb]),
        colors(0xf2f2f2, 0x14201b, 0xbdc2bf, 0x22302a, [0x1dd1a1, 0x54a0ff, 0xff9f43, 0xff6b6b, 0xc8a2ff, 0x48dbfb]),
        colors(0xf2f2f2, 0x241a26, 0xc2bdc4, 0x33283a, [0xff6b9a, 0x54a0ff, 0x1dd1a1, 0xff9f43, 0xc8a2ff, 0x48dbfb]),
      ];
    }),
    theme("ocean", "Ocean", colors(0xffffff, 0x0b3d63, 0xd6e9f8, 0x0f5a8f, [0x4fc3f7, 0xffd54f, 0x81c784, 0xff8a65, 0xba68c8, 0x4dd0e1]), "Gill Sans", "Gill Sans", (t) => {
      t.background = gradientFill(twoTone(themePaint("light2"), themePaint("light1"), 60));
      t.decorations = [
        deco("ellipse", 760, -160, 380, 380, solidFill(themePaint("accent1", 0, 0.12))),
        deco("ellipse", -120, 430, 260, 260, solidFill(themePaint("accent1", 0, 0.10))),
      ];
      t.titleDecorations = [
        deco("ellipse", 640, -200, 520, 520, solidFill(themePaint("accent1", 0, 0.14))),
        deco("ellipse", -160, 360, 400, 400, solidFill(themePaint("accent2", 0, 0.10))),
      ];
      t.bulletColor = themePaint("accent1");
      t.variants = [
        colors(0xffffff, 0x1b4332, 0xd8f3dc, 0x2d6a4f, [0x95d5b2, 0xffd166, 0x74c69d, 0xff8a65, 0xb7e4c7, 0x52b788]),
        colors(0xffffff, 0x3c096c, 0xe0c3fc, 0x5a189a, [0xc77dff, 0xffd166, 0x7bdff2, 0xff8fab, 0xe0aaff, 0x9d4edd]),
        colors(0xffffff, 0x6a040f, 0xffd6a5, 0x9d0208, [0xffba08, 0xfaa307, 0x90e0ef, 0xf48c06, 0xffd6a5, 0xe85d04]),
      ];
    }),
    theme("paper", "Paper", colors(0x3d3226, 0xfbf7f0, 0x5c4b37, 0xede4d3, [0xa5644e, 0x6b8f71, 0xc3986d, 0x4f6d7a, 0xc17529, 0x7a6a55]), "Baskerville", "Gill Sans", (t) => {
      t.decorations = [adjust(deco("frame", 16, 16, 928, 508, solidFill(themePaint("dark2", 0.7))), [0.004])];
      t.titleDecorations = [rule([400, 300], [560, 300], themePaint("accent1"), 1.5), adjust(deco("frame", 16, 16, 928, 508, solidFill(themePaint("dark2", 0.7))), [0.004])];
      t.bulletSymbol = "–";
      t.variants = [
        colors(0x2b2b2b, 0xf7f7f2, 0x4a4a4a, 0xe8e8df, [0x8c3b3b, 0x3b5f8c, 0x8c7b3b, 0x3b8c6e, 0x6e3b8c, 0x8c5a3b]),
        colors(0x24323d, 0xf3f6f8, 0x3e5463, 0xdde6ec, [0x3e7cb1, 0xd17a22, 0x5e9c76, 0xb74f6f, 0x7e6baf, 0x4fa3a5]),
      ];
    }),
    theme("sunset", "Sunset", colors(0x2d1e2f, 0xffffff, 0x5b3758, 0xfff1e6, [0xf76b1c, 0xe8365d, 0xfab32b, 0x8e44ad, 0x16a085, 0x2980b9]), "Futura", "Avenir Next", (t) => {
      t.titleBackground = gradientFill(twoTone(themePaint("accent1"), themePaint("accent2"), 45));
      t.titleColor = themePaint("dark1");
      t.decorations = [deco("rect", 0, 0, 960, 10, gradientFill(twoTone(themePaint("accent1"), themePaint("accent2"), 0)))];
      t.titleDecorations = [deco("ellipse", 700, 320, 360, 360, solidFill(rgbPaint({ r: 1, g: 1, b: 1, a: 0.12 })))];
      t.titleCaps = true;
      t.variants = [
        colors(0x1e2a3a, 0xffffff, 0x34495e, 0xeaf2f8, [0x2e86de, 0x10ac84, 0xfeca57, 0x5f27cd, 0xee5253, 0x01a3a4]),
        colors(0x2c1b18, 0xffffff, 0x5d4037, 0xfbe9e7, [0xff7043, 0xffca28, 0xef5350, 0x8d6e63, 0x26a69a, 0x5c6bc0]),
      ];
    }),
    theme("mono", "Mono", colors(0x000000, 0xffffff, 0x222222, 0xf0f0f0, [0x000000, 0x555555, 0x888888, 0xbbbbbb, 0xe63946, 0x1d3557]), "Futura", "Helvetica Neue", (t) => {
      t.titleBold = true;
      t.titleCaps = true;
      t.decorations = [deco("rect", 60, 126, 60, 6, solidFill(themePaint("dark1")))];
      t.titleBackground = solidFill(themePaint("dark1"));
      t.titleColor = themePaint("light1");
      t.titleDecorations = [deco("rect", 450, 300, 60, 6, solidFill(themePaint("accent5")))];
      t.bulletSymbol = "▪";
    }),
    theme("blueprint", "Blueprint", colors(0xe8f1ff, 0x0d2b52, 0xa9c5eb, 0x123a6d, [0x6fb1ff, 0xffd166, 0x06d6a0, 0xef476f, 0xc3a6ff, 0x7ae7ff]), "Avenir Next Condensed", "Avenir Next", (t) => {
      t.background = { pattern: { _0: { kind: "grid", foreground: themePaint("dark1", 0, 0.07), background: themePaint("light1") } } };
      t.titleBold = true;
      t.decorations = [rule([60, 128], [900, 128], themePaint("accent1"), 1.5)];
      t.titleDecorations = [adjust(deco("frame", 40, 40, 880, 460, solidFill(themePaint("accent1", 0, 0.5))), [0.006])];
      t.bulletColor = themePaint("accent1");
    }),
    theme("pastel", "Pastel", colors(0x3a3550, 0xfbf8ff, 0x5e5878, 0xf1ebff, [0x9c89ff, 0xff9aa2, 0x7fd8be, 0xffd3a5, 0x8ec5ff, 0xf7a8e0]), "Avenir Next", "Avenir Next", (t) => {
      t.decorations = [
        deco("ellipse", 850, -60, 180, 180, solidFill(themePaint("accent1", 0, 0.25))),
        deco("ellipse", 905, 90, 70, 70, solidFill(themePaint("accent2", 0, 0.35))),
      ];
      t.titleDecorations = [
        deco("ellipse", -100, -100, 320, 320, solidFill(themePaint("accent1", 0, 0.25))),
        deco("ellipse", 760, 360, 280, 280, solidFill(themePaint("accent2", 0, 0.3))),
        deco("ellipse", 820, 60, 90, 90, solidFill(themePaint("accent3", 0, 0.35))),
      ];
      t.bulletColor = themePaint("accent1");
    }),
    theme("forest", "Forest", colors(0x1f2d24, 0xffffff, 0x2f4a39, 0xeef4ef, [0x2e7d4f, 0xc9a227, 0x5fa777, 0xa4572b, 0x3e6a8a, 0x8aa05a]), "Georgia", "Gill Sans", (t) => {
      t.titleBackground = solidFill(themePaint("dark2"));
      t.titleColor = themePaint("light1");
      t.decorations = [deco("rect", 0, 0, 24, 540, solidFill(themePaint("accent1")))];
      t.titleDecorations = [
        deco("triangle", 700, 330, 300, 210, solidFill(themePaint("accent1", 0, 0.6))),
        deco("triangle", 800, 260, 220, 280, solidFill(themePaint("accent3", 0, 0.5))),
      ];
    }),
    theme("midnight", "Midnight", colors(0xf2f2f7, 0x0f172a, 0xcbd5e1, 0x1e293b, [0xf59e0b, 0x60a5fa, 0x34d399, 0xf87171, 0xa78bfa, 0x22d3ee]), "Helvetica Neue", "Helvetica Neue", (t) => {
      t.titleBold = true;
      t.background = gradientFill(twoTone(themePaint("light1"), themePaint("light2"), 90));
      t.decorations = [deco("ellipse", 896, 28, 16, 16, solidFill(themePaint("accent1")))];
      t.titleDecorations = [
        adjust(deco("donut", 660, 240, 420, 420, solidFill(themePaint("accent1", 0, 0.15))), [0.08]),
        deco("ellipse", 120, 90, 24, 24, solidFill(themePaint("accent1"))),
      ];
      t.bulletColor = themePaint("accent1");
    }),
    theme("facet", "Facet", colors(0x213f21, 0xffffff, 0x2c3c43, 0xebebeb, [0x90c226, 0x54a021, 0xe6b91e, 0xe76618, 0xc42f1a, 0x918655]), "Trebuchet MS", "Trebuchet MS", (t) => {
      t.titleColor = themePaint("accent2", -0.25);
      t.decorations = [
        flipped(deco("rtTriangle", 880, 380, 80, 160, solidFill(themePaint("accent1")))),
        flipped(deco("rtTriangle", 840, 460, 120, 80, solidFill(themePaint("accent2", 0, 0.8)))),
      ];
      t.titleDecorations = [
        flipped(deco("rtTriangle", 760, 220, 200, 320, solidFill(themePaint("accent1")))),
        flipped(deco("rtTriangle", 680, 380, 280, 160, solidFill(themePaint("accent2", 0, 0.85)))),
      ];
      t.bulletColor = themePaint("accent1");
    }),
  ];
}

export const THEMES = builtInThemes();

export function themeById(id: string): PresentationTheme {
  return structuredClone(THEMES.find((t) => t.id === id) ?? THEMES[0]);
}

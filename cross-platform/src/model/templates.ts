import type {
  AnimationEffect, AnimationTrigger, Effects, Fill, LayoutKind, LineStyle, PaintColor, Presentation, PresentationTheme, RunStyle, ShapeKind,
  SlideElement, ThemeSlot, TransitionKind,
} from "./types";
import {
  NO_LINE, R, chartContent, element, frame, gradientFill, lineElement, lineOf, lineStyle, makeTable, noEffects, rgbPaint, setPlainText, shapeElement, shapeOf,
  solidFill, tableCellBody, textBoxElement, textOf, themePaint, twoTone, unionRect, CLEAR, SOFT_SHADOW, clone,
} from "./core";
import { SHAPE_TITLES, newAnimation } from "./catalog";
import { THEMES, themeById } from "./themes";
import { bodyLines, makeSlide, newPresentation } from "./presentation";

// MARK: Shape and WordArt styles

export interface ShapeStylePreset { id: string; fill: Fill; line: LineStyle; effects: Effects; textColor: PaintColor }

export function shapeStylePresets(): ShapeStylePreset[] {
  const slots: ThemeSlot[] = ["dark1", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"];
  const result: ShapeStylePreset[] = [];
  slots.forEach((slot, n) => result.push({ id: `outline-${n}`, fill: solidFill(themePaint("light1")), line: lineStyle(themePaint(slot), 1.5), effects: noEffects(), textColor: themePaint("dark1") }));
  slots.forEach((slot, n) => result.push({ id: `solid-${n}`, fill: solidFill(themePaint(slot)), line: lineStyle(themePaint(slot, -0.25), 1), effects: noEffects(), textColor: themePaint("light1") }));
  slots.forEach((slot, n) => result.push({ id: `light-${n}`, fill: solidFill(themePaint(slot, 0.8)), line: lineStyle(themePaint(slot), 1), effects: noEffects(), textColor: themePaint("dark1") }));
  slots.forEach((slot, n) => result.push({
    id: `intense-${n}`, fill: gradientFill(twoTone(themePaint(slot, 0.25), themePaint(slot, -0.2))), line: NO_LINE(),
    effects: { softEdges: 0, shadow: SOFT_SHADOW() }, textColor: themePaint("light1"),
  }));
  return result;
}

export const WORDART_PRESETS: { id: string; apply: (r: RunStyle) => void }[] = [
  { id: "fill-dark", apply: (r) => { r.color = themePaint("dark1"); r.bold = true; } },
  { id: "fill-accent", apply: (r) => { r.color = themePaint("accent1"); r.bold = true; } },
  { id: "fill-accent-shadow", apply: (r) => { r.color = themePaint("accent1"); r.bold = true; r.shadow = true; } },
  { id: "outline-accent", apply: (r) => { r.color = themePaint("light1"); r.outlineColor = themePaint("accent1"); r.outlineWidth = 1.5; r.bold = true; } },
  { id: "outline-dark", apply: (r) => { r.color = rgbPaint(CLEAR); r.outlineColor = themePaint("dark1"); r.outlineWidth = 1.25; } },
  { id: "fill-accent2-shadow", apply: (r) => { r.color = themePaint("accent2"); r.bold = true; r.shadow = true; } },
  { id: "fill-white-outline", apply: (r) => { r.color = themePaint("light1"); r.outlineColor = themePaint("dark1"); r.outlineWidth = 2; r.bold = true; r.shadow = true; } },
  { id: "caps-spaced", apply: (r) => { r.color = themePaint("accent1"); r.allCaps = true; r.characterSpacing = 6; r.bold = true; } },
  { id: "fill-accent3", apply: (r) => { r.color = themePaint("accent3"); r.bold = true; r.italic = true; } },
];

// MARK: SmartArt

export type SmartArtKind = "basicList" | "process" | "cycle" | "hierarchy" | "pyramid" | "venn" | "chevrons" | "timeline" | "matrix";
export const SMARTART: [SmartArtKind, string, string][] = [
  ["basicList", "Basic Block List", "List"], ["process", "Basic Process", "Process"], ["chevrons", "Chevron Process", "Process"],
  ["timeline", "Basic Timeline", "Process"], ["cycle", "Basic Cycle", "Cycle"], ["hierarchy", "Hierarchy", "Hierarchy"],
  ["pyramid", "Basic Pyramid", "Pyramid"], ["venn", "Basic Venn", "Relationship"], ["matrix", "Basic Matrix", "Relationship"],
];

export function smartArtSample(kind: SmartArtKind): string[] {
  switch (kind) {
    case "hierarchy": return ["Leader", "Team A", "Team B", "Team C"];
    case "timeline": return ["2023", "2024", "2025", "2026"];
    case "venn": return ["Design", "Engineering", "Business"];
    case "matrix": return ["Strengths", "Weaknesses", "Opportunities", "Threats"];
    case "pyramid": return ["Vision", "Strategy", "Execution"];
  }
  return ["Plan", "Build", "Test", "Launch"];
}

/** Builds a SmartArt-style diagram as editable grouped shapes. */
export function buildSmartArt(kind: SmartArtKind, rawItems: string[], f: { x: number; y: number; w: number; h: number }): SlideElement {
  const items = rawItems.length ? rawItems : smartArtSample(kind);
  const n = items.length;
  const slots: ThemeSlot[] = ["accent1", "accent2", "accent3", "accent4", "accent5", "accent6"];
  const color = (i: number) => themePaint(slots[i % slots.length]);
  const box = (k: ShapeKind, x: number, y: number, w: number, h: number, text: string, i: number, alpha = 1, textColor = themePaint("light1")) => {
    const e = shapeElement(k, frame(x, y, w, h), solidFill(alpha < 1 ? themePaint(slots[i % slots.length], 0, alpha) : color(i)), lineStyle(themePaint("light1"), 1.5), text);
    const t = textOf(e)!;
    t.defaultColor = textColor;
    t.defaultSize = Math.min(24, Math.max(12, h / 4));
    t.autofit = "shrink";
    e.name = `${SHAPE_TITLES[k]} ${i + 1}`;
    return e;
  };
  const arrowShape = (x: number, y: number, w: number, h: number, i: number, rotation = 0) => {
    const a = shapeElement("rightArrow", frame(x, y, w, h), solidFill(themePaint("dark1", 0.6)), NO_LINE());
    a.rotation = rotation;
    a.name = `Arrow ${i + 1}`;
    return a;
  };
  const children: SlideElement[] = [];
  const cx = f.x + f.w / 2, cy = f.y + f.h / 2;
  switch (kind) {
    case "basicList": {
      const columns = Math.min(n, 3), rows = Math.ceil(n / columns), gap = 16;
      const w = (f.w - gap * (columns - 1)) / columns;
      const h = Math.min((f.h - gap * (rows - 1)) / rows, w * 0.6);
      items.forEach((item, i) => {
        const r = Math.floor(i / columns), c = i % columns;
        children.push(box("rect", f.x + c * (w + gap), f.y + r * (h + gap), w, h, item, i));
      });
      break;
    }
    case "process":
    case "chevrons": {
      const arrowW = kind === "process" ? 34 : -18;
      const w = (f.w - arrowW * (n - 1)) / n;
      const h = Math.min(f.h, w * 0.65), y = cy - h / 2;
      items.forEach((item, i) => {
        const x = f.x + i * (w + arrowW);
        if (kind === "process") {
          children.push(box("roundRect", x, y, w, h, item, i));
          if (i < n - 1) children.push(arrowShape(x + w + 6, cy - 12, arrowW - 12, 24, i));
        } else {
          children.push(box(i === 0 ? "homePlate" : "chevron", x, y, w, h, item, i));
        }
      });
      break;
    }
    case "cycle": {
      const radius = Math.min(f.w, f.h) / 2 - 50, d = Math.min(120, radius * 1.1);
      items.forEach((item, i) => {
        const a = -Math.PI / 2 + (i * 2 * Math.PI) / n;
        const px = cx + Math.cos(a) * radius, py = cy + Math.sin(a) * radius;
        children.push(box("ellipse", px - d / 2, py - d / 2, d, d, item, i));
        const mid = a + Math.PI / n;
        const qx = cx + Math.cos(mid) * radius, qy = cy + Math.sin(mid) * radius;
        children.push(arrowShape(qx - 14, qy - 10, 28, 20, i, ((mid + Math.PI / 2) * 180) / Math.PI));
      });
      break;
    }
    case "hierarchy": {
      const top = items[0] ?? "", rest = items.slice(1);
      const h = Math.min(f.h / 3, 70), topW = Math.min(f.w / 3, 220);
      const topRect = { x: cx - topW / 2, y: f.y + 10, w: topW, h };
      const gap = 20, count = Math.max(rest.length, 1);
      const w = Math.min((f.w - gap * (count - 1)) / count, 200);
      const total = w * count + gap * (count - 1);
      const y = f.y + f.h - h - 10, busY = (topRect.y + topRect.h + y) / 2;
      const connector = (a: [number, number], b: [number, number]) => {
        const line = lineElement(a, b, lineStyle(themePaint("dark1", 0.5), 1.5));
        line.name = "Connector";
        children.push(line);
      };
      if (rest.length) connector([cx, topRect.y + topRect.h], [cx, busY]);
      rest.forEach((item, i) => {
        const rx = cx - total / 2 + i * (w + gap);
        connector([rx + w / 2, busY], [rx + w / 2, y]);
        children.push(box("roundRect", rx, y, w, h, item, i + 1));
      });
      if (rest.length > 1) connector([cx - total / 2 + w / 2, busY], [cx + total / 2 - w / 2, busY]);
      children.push(box("roundRect", topRect.x, topRect.y, topRect.w, topRect.h, top, 0));
      break;
    }
    case "pyramid": {
      const h = f.h / n;
      items.forEach((item, i) => {
        const wTop = f.w * 0.8 * (i / n), wBottom = f.w * 0.8 * ((i + 1) / n);
        const e = box(i === 0 ? "triangle" : "trapezoid", cx - wBottom / 2, f.y + i * h, wBottom, h - 4, item, i);
        if (i > 0) shapeOf(e)!.adjustments = [(wBottom - wTop) / 2 / Math.max(Math.min(wBottom, h - 4), 1)];
        children.push(e);
      });
      break;
    }
    case "venn": {
      const d = Math.min(f.h * 0.8, (f.w / Math.max(n, 1)) * 1.4), spread = d * 0.32, m = Math.min(n, 4);
      items.slice(0, 4).forEach((item, i) => {
        const a = -Math.PI / 2 + (i * 2 * Math.PI) / m;
        const px = n === 1 ? cx : cx + Math.cos(a) * spread, py = n === 1 ? cy : cy + Math.sin(a) * spread;
        children.push(box("ellipse", px - d / 2, py - d / 2, d, d, item, i, 0.55, themePaint("dark1")));
      });
      break;
    }
    case "timeline": {
      const line = lineElement([f.x, cy], [f.x + f.w, cy], lineStyle(themePaint("dark1", 0.5), 3));
      lineOf(line)!.line.tail = "triangle";
      line.name = "Timeline";
      children.push(line);
      const step = f.w / n;
      items.forEach((item, i) => {
        const x = f.x + step * (i + 0.5);
        const dot = shapeElement("ellipse", frame(x - 11, cy - 11, 22, 22), solidFill(color(i)), lineStyle(themePaint("light1"), 2));
        dot.name = `Milestone ${i + 1}`;
        children.push(dot);
        const above = i % 2 === 0;
        const label = textBoxElement(item, frame(x - step / 2, above ? cy - 70 : cy + 22, step, 44),
          { size: 20, alignment: "center", color: themePaint("dark1"), bold: true, anchor: above ? "bottom" : "top" });
        textOf(label)!.autofit = "none";
        children.push(label);
      });
      break;
    }
    case "matrix": {
      const gap = 8, s = Math.min(f.w, f.h * 1.6), w = (s - gap) / 2, h = (f.h - gap) / 2, x0 = cx - s / 2;
      items.slice(0, 4).forEach((item, i) => {
        const r = Math.floor(i / 2), c = i % 2;
        children.push(box("rect", x0 + c * (w + gap), f.y + r * (h + gap), w, h, item, i));
      });
      break;
    }
  }
  let bounds = null;
  for (const c of children) bounds = unionRect(bounds, R(c.frame));
  const b = bounds ?? f;
  const title = SMARTART.find((s) => s[0] === kind)![1];
  return element(title, frame(b.x, b.y, b.w, b.h), { group: { _0: { children } } });
}

// MARK: Icons

export const ICON_CATEGORIES: [string, string[]][] = [
  ["Business", ["briefcase", "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "dollarsign.circle", "creditcard", "building.2", "cart", "bag", "banknote",
    "target", "flag", "trophy", "rosette", "signature", "doc.text", "folder", "tray.full", "calendar", "clock"]],
  ["People", ["person", "person.2", "person.3", "person.crop.circle", "figure.walk", "figure.run", "hand.raised", "hand.thumbsup", "person.badge.plus",
    "person.wave.2", "figure.2.and.child.holdinghands", "brain.head.profile", "heart"]],
  ["Communication", ["envelope", "phone", "message", "bubble.left.and.bubble.right", "megaphone", "antenna.radiowaves.left.and.right", "wifi",
    "paperplane", "bell", "quote.bubble", "video", "mic"]],
  ["Technology", ["desktopcomputer", "laptopcomputer", "iphone", "server.rack", "cpu", "memorychip", "externaldrive", "network", "cloud", "lock", "key",
    "shield", "gearshape", "wrench.and.screwdriver", "hammer", "terminal", "qrcode", "barcode"]],
  ["Arrows", ["arrow.right", "arrow.left", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.triangle.2.circlepath", "arrow.up.right", "arrow.left.arrow.right",
    "chevron.right.2", "arrowshape.turn.up.right", "arrow.uturn.left", "arrow.triangle.branch"]],
  ["Nature", ["leaf", "tree", "sun.max", "moon", "cloud.sun", "cloud.rain", "snowflake", "flame", "drop", "bolt", "globe.americas", "mountain.2", "pawprint", "ladybug"]],
  ["Education", ["book", "books.vertical", "graduationcap", "pencil", "highlighter", "ruler", "function", "x.squareroot", "lightbulb", "puzzlepiece",
    "atom", "flask", "testtube.2", "microscope"]],
  ["Travel", ["airplane", "car", "bus", "tram", "bicycle", "ferry", "map", "mappin.and.ellipse", "location", "house", "suitcase", "globe"]],
  ["Symbols", ["checkmark.circle", "xmark.circle", "exclamationmark.triangle", "questionmark.circle", "info.circle", "plus.circle", "minus.circle", "star",
    "heart.fill", "bookmark", "tag", "sparkles", "crown", "infinity", "number", "percent"]],
  ["Media", ["play.circle", "pause.circle", "music.note", "headphones", "camera", "photo", "film", "tv", "gamecontroller", "paintpalette", "theatermasks"]],
  ["Health", ["cross.case", "pills", "stethoscope", "heart.text.square", "bandage", "syringe", "bed.double", "figure.mind.and.body"]],
];

// MARK: Templates

export interface PresentationTemplate { id: string; name: string; subtitle: string; theme: PresentationTheme; build: () => Presentation }

class DeckBuilder {
  presentation: Presentation;
  constructor(theme: PresentationTheme) {
    this.presentation = newPresentation(theme, []);
  }

  slide(layout: LayoutKind, o: { title?: string; body?: string[]; body2?: string[]; subtitle?: string; notes?: string; transition?: TransitionKind; extra?: SlideElement[] } = {}): number {
    const p = this.presentation;
    const slide = makeSlide(layout, p.theme, p.slideSize);
    const bodies = [o.body ?? [], o.body2 ?? []];
    for (const e of slide.elements) {
      const text = textOf(e);
      if (!e.placeholder || !text) continue;
      if ((e.placeholder === "title" || e.placeholder === "centeredTitle") && o.title !== undefined) setPlainText(text, o.title);
      else if (e.placeholder === "subtitle" && o.subtitle !== undefined) setPlainText(text, o.subtitle);
      else if (e.placeholder === "body" && bodies.length) {
        const lines = bodies.shift()!;
        if (lines.length) text.paragraphs = bodyLines(lines, clone(text.paragraphs[0]));
      }
    }
    slide.elements.push(...(o.extra ?? []));
    slide.notes = o.notes ?? "";
    slide.transition.kind = o.transition ?? "none";
    p.slides.push(slide);
    return p.slides.length - 1;
  }

  animate(index: number, effect: AnimationEffect, trigger: AnimationTrigger = "onClick") {
    const slide = this.presentation.slides[index];
    slide.elements.filter((e) => e.placeholder === "body").forEach((e, i) => slide.animations.push(newAnimation(e.id, effect, i === 0 ? trigger : "afterPrevious")));
  }
}

const chartElement = (name: string, x: number, y: number, w: number, h: number, c: ReturnType<typeof chartContent>) => element(name, frame(x, y, w, h), { chart: { _0: c } });

export function contentTemplates(): PresentationTemplate[] {
  return [
    {
      id: "pitch", name: "Pitch Deck", subtitle: "Problem, solution, market, ask", theme: themeById("midnight"), build: () => {
        const b = new DeckBuilder(themeById("midnight"));
        b.slide("title", { title: "Company Name", subtitle: "The one-line description of what you do", notes: "Introduce yourself and the company in one breath.", transition: "fade" });
        b.animate(b.slide("titleContent", { title: "The Problem", body: ["Who has the problem", "How they solve it today", "Why that isn't good enough"], transition: "push" }), "floatIn");
        b.slide("titleContent", { title: "Our Solution", body: ["What the product does", "The moment it clicks for customers", "Why now"], transition: "push" });
        b.slide("titleOnly", { title: "Market Opportunity", transition: "push", extra: [chartElement("Market Chart", 120, 140, 720, 340, chartContent("column", {
          title: "Market size ($B)", categories: ["2024", "2025", "2026", "2027"], series: [{ name: "Market", values: [4.2, 5.9, 8.1, 11.4] }], legend: "none", showDataLabels: true,
        }))] });
        b.slide("bigNumber", { title: "3×", body: ["faster than the leading alternative"], transition: "zoom" });
        b.slide("twoContent", { title: "Business Model", body: ["Pricing", "\tPer seat, billed annually", "\tFree tier for teams under 5"], body2: ["Go-to-market", "\tBottom-up adoption", "\tSales-assisted expansion"], transition: "push" });
        b.slide("sectionHeader", { title: "The Ask", body: ["Raising $2M to reach 1,000 customers"], transition: "fadeThroughBlack" });
        return b.presentation;
      },
    },
    {
      id: "quarterly", name: "Quarterly Review", subtitle: "Results, charts and outlook", theme: themeById("wired"), build: () => {
        const b = new DeckBuilder(themeById("wired"));
        b.slide("title", { title: "Q3 Business Review", subtitle: "Results and outlook", transition: "morph" });
        b.slide("titleOnly", { title: "Revenue", transition: "fade", extra: [
          chartElement("Revenue", 60, 140, 520, 340, chartContent("lineMarkers", { title: "Revenue ($M)", categories: ["Q4", "Q1", "Q2", "Q3"],
            series: [{ name: "2026", values: [12.1, 13.4, 14.8, 16.2] }, { name: "Plan", values: [12, 13, 14, 15] }] })),
          chartElement("Mix", 600, 160, 300, 300, chartContent("doughnut", { title: "Revenue mix", categories: ["Product", "Services", "Other"],
            series: [{ name: "Mix", values: [62, 30, 8] }], legend: "bottom", showDataLabels: true })),
        ] });
        b.slide("bigNumber", { title: "+18%", body: ["year-over-year growth"], transition: "zoom" });
        b.slide("twoContent", { title: "Highlights & Lowlights", body: ["Highlights", "\tRecord quarter for new customers", "\tChurn down 2 points"], body2: ["Lowlights", "\tHiring behind plan", "\tEMEA pipeline soft"] });
        b.slide("sectionHeader", { title: "Outlook", body: ["What we expect next quarter"] });
        return b.presentation;
      },
    },
    {
      id: "status", name: "Project Status", subtitle: "Weekly or monthly update", theme: themeById("clean"), build: () => {
        const b = new DeckBuilder(themeById("clean"));
        b.slide("title", { title: "Project Status Update", subtitle: new Date().toLocaleDateString(undefined, { dateStyle: "long" }) });
        b.slide("titleContent", { title: "Summary", body: ["Overall status: On track", "Key milestone reached this period", "One risk needs attention"] });
        const table = makeTable(5, 4, 840);
        const data = [["Workstream", "Owner", "Status", "Due"], ["Design", "Alex", "Done", "Mar 1"], ["Build", "Sam", "In progress", "Apr 15"],
          ["Testing", "Jordan", "Not started", "May 1"], ["Launch", "Riley", "Not started", "May 20"]];
        data.forEach((row, r) => row.forEach((text, c) => { table.rows[r][c].text = tableCellBody(text); }));
        b.slide("titleOnly", { title: "Milestones", extra: [element("Milestones", frame(60, 150, 840, 185), { table: { _0: table } })] });
        b.slide("twoContent", { title: "Risks & Next Steps", body: ["Risks", "\tVendor delay could push testing", "\tTwo open hires"], body2: ["Next steps", "\tConfirm vendor dates", "\tStart test planning"] });
        return b.presentation;
      },
    },
    {
      id: "lesson", name: "Lesson", subtitle: "Objectives, content and a quiz", theme: themeById("pastel"), build: () => {
        const b = new DeckBuilder(themeById("pastel"));
        b.slide("title", { title: "Lesson Title", subtitle: "Course · Unit 1" });
        b.animate(b.slide("titleContent", { title: "Today's Objectives", body: ["Understand the key idea", "Practice with examples", "Check understanding"] }), "fadeIn");
        b.slide("titleOnly", { title: "How We'll Learn", extra: [buildSmartArt("cycle", ["Learn", "Practice", "Reflect", "Apply"], { x: 230, y: 140, w: 500, h: 360 })] });
        b.slide("quote", { title: "“Tell me and I forget. Teach me and I remember. Involve me and I learn.”", body: ["— Attributed to Benjamin Franklin"] });
        b.slide("titleContent", { title: "Quick Quiz", body: ["Question 1?", "Question 2?", "Question 3?"] });
        return b.presentation;
      },
    },
    {
      id: "photo", name: "Photo Story", subtitle: "Big pictures with captions", theme: themeById("graphite"), build: () => {
        const b = new DeckBuilder(themeById("graphite"));
        b.slide("title", { title: "A Photo Story", subtitle: "Add your pictures", transition: "fade" });
        for (let i = 1; i <= 3; i++) b.slide("pictureCaption", { title: `Chapter ${i}`, body: ["A sentence about this picture."], transition: "fade" });
        return b.presentation;
      },
    },
  ];
}

export function themeTemplates(): PresentationTemplate[] {
  return THEMES.map((t) => ({ id: "theme-" + t.id, name: t.name, subtitle: "Theme", theme: t, build: () => newPresentation(themeById(t.id)) }));
}

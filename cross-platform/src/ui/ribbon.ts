import type { AnimationEffect, ChartKind, LayoutKind, PaintColor, ShapeKind, ThemeColors, TransitionKind } from "../model/types";
import {
  ARROW_TITLES, CHART_TITLES, DASH_TITLES, NUMBERING_TITLES, NO_FILL, OUTER_SHADOW, SOFT_SHADOW, STANDARD_BULLETS, chartOf, clone, cssColor, frame,
  gradientFill, groupOf, iconOf, imageOf, isRoundChart, lineOf, mediaOf, resolve, shapeElement, shapeOf, solidFill, tableOf, textOf,
  themePaint, twoTone, WHITE, textBoxElement, updateRuns,
} from "../model/core";
import {
  ANIMATION_CATEGORIES, ANIMATION_TITLES, COLOR_SCHEMES, DIRECTIONS, DIRECTION_TITLES, FONT_PAIRS, LAYOUTS, LAYOUT_TITLES, SHAPE_CATEGORIES, SHAPE_TITLES,
  TRANSITIONS, TRANSITION_TITLES, TRIGGER_TITLES, effectHasDirection, effectsIn, transitionHasDirection,
} from "../model/catalog";
import { THEMES, themeById } from "../model/themes";
import { WORDART_PRESETS, shapeStylePresets } from "../model/templates";
import { makeSlide, newPresentation } from "../model/presentation";
import type { PresentationController } from "../engine/controller";
import { installedFonts } from "../render/fonts";
import { drawElement } from "../render/elements";
import { renderSlide } from "../render/slide";
import type { AppActions } from "./actions";
import { closeGallery, closePalette, showGallery, showPalette } from "./colors";
import { icon } from "./icons";
import type { MenuEntry } from "./menubar";
import { showPopupMenu } from "./popup";
import { modKey } from "../version";
import { promptText } from "./dialogs";

type Tab = "home" | "insert" | "design" | "transitions" | "animations" | "slideShow" | "review" | "view" | "shapeFormat" | "pictureFormat" | "tableDesign" | "chartDesign";
const TABS: [Tab, string][] = [["home", "Home"], ["insert", "Insert"], ["design", "Design"], ["transitions", "Transitions"], ["animations", "Animations"], ["slideShow", "Slide Show"], ["review", "Review"], ["view", "View"]];
const CONTEXTUAL: [Tab, string][] = [["shapeFormat", "Shape Format"], ["pictureFormat", "Picture Format"], ["tableDesign", "Table Design"], ["chartDesign", "Chart Design"]];
const FONT_SIZES = [8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96];

interface ButtonOptions {
  isOn?: () => boolean;
  enabled?: () => boolean;
  menu?: () => MenuEntry[];
  title?: string;
  gallery?: (root: HTMLElement, close: () => void) => void;
  galleryWidth?: number;
}

/** The PowerPoint-style ribbon: tabs over the selected tab's commands, with contextual tabs for the selection. */
export class Ribbon {
  private tab: Tab = "home";
  private collapsed = false;
  private updaters: (() => void)[] = [];
  private body!: HTMLDivElement;
  private tabButtons = new Map<Tab, HTMLButtonElement>();
  private fonts = installedFonts();
  private lastTextColor: PaintColor = themePaint("accent2");
  private lastFill: PaintColor = themePaint("accent1");
  private lastLine: PaintColor = themePaint("accent1", -0.25);
  private lastHighlight = { r: 1, g: 1, b: 0, a: 1 };
  private contextual: Tab | null = null;

  constructor(private root: HTMLElement, private c: PresentationController, private actions: AppActions) {
    this.build();
  }

  showTab(tab: Tab) { this.tab = tab; this.collapsed = false; this.render(); }

  private build() {
    const strip = document.createElement("div");
    strip.className = "ribbon-tabs";
    for (const [id, title] of [...TABS, ...CONTEXTUAL]) {
      const button = document.createElement("button");
      button.className = "ribbon-tab" + (CONTEXTUAL.some((x) => x[0] === id) ? " contextual" : "");
      button.textContent = title;
      button.addEventListener("mousedown", (e) => e.preventDefault());
      button.addEventListener("click", () => { if (this.tab === id && !this.collapsed) return; this.tab = id; this.collapsed = false; this.render(); });
      button.addEventListener("dblclick", () => { this.collapsed = !this.collapsed; this.render(); });
      this.tabButtons.set(id, button);
      strip.append(button);
    }
    const collapse = document.createElement("button");
    collapse.className = "ribbon-collapse";
    collapse.title = "Collapse the Ribbon";
    collapse.textContent = "⌃";
    collapse.addEventListener("click", () => {
      this.collapsed = !this.collapsed;
      collapse.textContent = this.collapsed ? "⌄" : "⌃";
      this.render();
    });
    strip.append(collapse);
    this.body = document.createElement("div");
    this.body.className = "ribbon-body";
    this.root.append(strip, this.body);
    this.render();
  }

  /** The contextual tab for the selection. */
  private contextualTab(): Tab | null {
    const e = this.c.primary;
    if (!e) return null;
    if (tableOf(e)) return "tableDesign";
    if (chartOf(e)) return "chartDesign";
    if (imageOf(e)) return "pictureFormat";
    if (shapeOf(e) || lineOf(e) || groupOf(e) || iconOf(e) || mediaOf(e)) return "shapeFormat";
    return null;
  }

  private render() {
    const contextual = this.contextualTab();
    if (CONTEXTUAL.some((x) => x[0] === this.tab) && this.tab !== contextual) this.tab = "home";
    this.contextual = contextual;
    for (const [id, button] of this.tabButtons) {
      button.classList.toggle("selected", id === this.tab && !this.collapsed);
      if (CONTEXTUAL.some((x) => x[0] === id)) button.hidden = id !== contextual;
    }
    this.body.classList.toggle("collapsed", this.collapsed);
    this.body.replaceChildren();
    this.updaters = [];
    const builders: Record<Tab, () => HTMLElement[]> = {
      home: () => this.home(), insert: () => this.insert(), design: () => this.design(), transitions: () => this.transitions(),
      animations: () => this.animations(), slideShow: () => this.slideShow(), review: () => this.review(), view: () => this.view(),
      shapeFormat: () => this.shapeFormat(), pictureFormat: () => this.pictureFormat(), tableDesign: () => this.tableDesign(), chartDesign: () => this.chartDesign(),
    };
    this.body.append(...builders[this.tab]());
    this.refresh();
  }

  /** Updates toggles and fields for the current selection. */
  refresh() {
    if (this.contextualTab() !== this.contextual) { this.render(); return; }
    for (const update of this.updaters) update();
  }

  // MARK: Builders

  private group(title: string, ...children: HTMLElement[]): HTMLElement {
    const group = document.createElement("div");
    group.className = "rb-group";
    const content = document.createElement("div");
    content.className = "rb-group-content";
    content.append(...children);
    const caption = document.createElement("div");
    caption.className = "rb-group-title";
    caption.textContent = title;
    group.append(content, caption);
    return group;
  }

  private stack(...rows: HTMLElement[][]): HTMLElement {
    const stack = document.createElement("div");
    stack.className = "rb-stack";
    for (const items of rows) {
      const row = document.createElement("div");
      row.className = "rb-row";
      row.append(...items);
      stack.append(row);
    }
    return stack;
  }

  private button(iconName: string | null, label: string | null, action: (() => void) | null, o: ButtonOptions & { large?: boolean; text?: string } = {}): HTMLButtonElement {
    const b = document.createElement("button");
    b.className = "rb" + (o.large ? " large" : "");
    b.type = "button";
    if (iconName) b.append(icon(iconName));
    if (o.text) {
      const t = document.createElement("span");
      t.className = "rb-text";
      t.textContent = o.text;
      b.append(t);
    }
    if (label) {
      const l = document.createElement("span");
      l.className = "label";
      l.textContent = label;
      b.append(l);
    }
    if ((o.menu || o.gallery) && !action) b.insertAdjacentHTML("beforeend", '<span class="caret">▾</span>');
    b.title = o.title ?? label ?? "";
    b.addEventListener("mousedown", (e) => e.preventDefault());
    b.addEventListener("click", () => {
      closePalette();
      if (action) { closeGallery(); action(); return; }
      if (o.menu) showPopupMenu(b, o.menu());
      else if (o.gallery) showGallery(b, o.gallery, o.galleryWidth);
    });
    if (o.isOn || o.enabled) {
      this.updaters.push(() => {
        if (o.isOn) b.classList.toggle("on", o.isOn());
        if (o.enabled) b.disabled = !o.enabled();
      });
    }
    return b;
  }

  private large(iconName: string, label: string, action: (() => void) | null, o: ButtonOptions = {}) {
    if (action && (o.menu || o.gallery)) return this.split(this.button(iconName, label, action, { ...o, large: true, menu: undefined, gallery: undefined }), o, true);
    return this.button(iconName, label, action, { ...o, large: true });
  }

  private small(iconName: string | null, label: string | null, action: (() => void) | null, o: ButtonOptions & { text?: string } = {}) {
    if (action && (o.menu || o.gallery)) return this.split(this.button(iconName, label, action, { ...o, menu: undefined, gallery: undefined }), o, false);
    return this.button(iconName, label, action, o);
  }

  private split(main: HTMLButtonElement, o: ButtonOptions, large: boolean): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "rb-split";
    if (large) wrap.style.flexDirection = "column";
    const arrow = document.createElement("button");
    arrow.className = "rb";
    arrow.type = "button";
    arrow.innerHTML = '<span class="caret">▾</span>';
    if (large) Object.assign(arrow.style, { height: "14px", width: "100%", borderRadius: "0 0 5px 5px" });
    arrow.title = main.title;
    arrow.addEventListener("mousedown", (e) => e.preventDefault());
    arrow.addEventListener("click", () => {
      if (o.menu) showPopupMenu(arrow, o.menu());
      else if (o.gallery) showGallery(arrow, o.gallery, o.galleryWidth);
    });
    if (large) main.style.height = "48px";
    if (o.enabled) this.updaters.push(() => { arrow.disabled = !o.enabled!(); });
    wrap.append(main, arrow);
    return wrap;
  }

  private select(className: string, options: [string, string][], current: () => string, onChange: (value: string) => void, title: string, editable = false): HTMLElement {
    if (editable) {
      const input = document.createElement("input");
      input.className = "rb-select " + className;
      input.title = title;
      const list = document.createElement("datalist");
      list.id = `list-${className}`;
      for (const [value] of options) list.append(new Option(value, value));
      input.setAttribute("list", list.id);
      input.addEventListener("change", () => onChange(input.value));
      input.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); onChange(input.value); } });
      this.updaters.push(() => { if (document.activeElement !== input) input.value = current(); });
      const wrap = document.createElement("span");
      wrap.append(input, list);
      return wrap;
    }
    const select = document.createElement("select");
    select.className = "rb-select " + className;
    select.title = title;
    for (const [label, value] of options) select.append(new Option(label, value));
    select.addEventListener("change", () => onChange(select.value));
    this.updaters.push(() => {
      if (document.activeElement === select) return;
      const value = current();
      if (![...select.options].some((o) => o.value === value)) {
        select.querySelector("option[data-custom]")?.remove();
        const option = new Option(value, value);
        option.dataset.custom = "1";
        select.append(option);
      }
      select.value = value;
    });
    return select;
  }

  private number(title: string, current: () => number, onChange: (v: number) => void, o: { min?: number; max?: number; step?: number; width?: number } = {}): HTMLElement {
    const input = document.createElement("input");
    input.type = "number";
    input.className = "rb-select";
    input.style.width = `${o.width ?? 64}px`;
    input.title = title;
    if (o.min !== undefined) input.min = String(o.min);
    if (o.max !== undefined) input.max = String(o.max);
    input.step = String(o.step ?? 1);
    input.addEventListener("change", () => { const v = Number(input.value); if (Number.isFinite(v)) onChange(v); });
    this.updaters.push(() => { if (document.activeElement !== input) input.value = String(Math.round(current() * 100) / 100); });
    const label = document.createElement("label");
    label.className = "rb-row";
    label.style.gap = "4px";
    label.style.fontSize = "12px";
    label.append(title, input);
    return label;
  }

  private colorButton(iconName: string, title: string, last: () => PaintColor, apply: (c: PaintColor | null) => void, o: { none?: string; automatic?: string; extras?: { label: string; action: () => void }[] } = {}): HTMLElement {
    const main = this.button(iconName, null, () => apply(last()), { title });
    const swatch = document.createElement("span");
    swatch.className = "swatch";
    main.append(swatch);
    const colors = () => this.c.theme.colors;
    this.updaters.push(() => { swatch.style.background = cssColor(resolve(last(), colors())); });
    const wrap = document.createElement("div");
    wrap.className = "rb-split";
    const arrow = document.createElement("button");
    arrow.className = "rb";
    arrow.type = "button";
    arrow.title = title;
    arrow.innerHTML = '<span class="caret">▾</span>';
    arrow.addEventListener("mousedown", (e) => e.preventDefault());
    arrow.addEventListener("click", () => showPalette(arrow, colors(), (color) => { apply(color); this.refresh(); }, { noneLabel: o.none, automaticLabel: o.automatic, extras: o.extras }));
    wrap.append(main, arrow);
    return wrap;
  }

  private gridGallery(root: HTMLElement, title: string | null, items: { label: string; draw?: (canvas: HTMLCanvasElement) => void; svg?: SVGSVGElement; selected?: boolean; action: () => void }[], columns: number, size: [number, number]) {
    if (title) {
      const h = document.createElement("h4");
      h.textContent = title;
      root.append(h);
    }
    const grid = document.createElement("div");
    grid.className = "grid";
    grid.style.gridTemplateColumns = `repeat(${columns}, auto)`;
    for (const item of items) {
      const b = document.createElement("button");
      b.title = item.label;
      if (item.selected) b.classList.add("selected");
      if (item.draw) {
        const canvas = document.createElement("canvas");
        const dpr = window.devicePixelRatio || 1;
        canvas.width = size[0] * dpr;
        canvas.height = size[1] * dpr;
        canvas.style.width = `${size[0]}px`;
        canvas.style.height = `${size[1]}px`;
        item.draw(canvas);
        b.append(canvas);
      }
      if (item.svg) b.append(item.svg);
      if (size[1] > 40) { const l = document.createElement("span"); l.textContent = item.label; b.append(l); }
      b.addEventListener("mousedown", (e) => e.preventDefault());
      b.addEventListener("click", () => { closeGallery(); item.action(); });
      grid.append(b);
    }
    root.append(grid);
  }

  // MARK: Galleries

  private drawPreview(canvas: HTMLCanvasElement, draw: (ctx: CanvasRenderingContext2D, w: number, h: number) => void) {
    const ctx = canvas.getContext("2d")!;
    const dpr = window.devicePixelRatio || 1;
    ctx.scale(dpr, dpr);
    draw(ctx, canvas.width / dpr, canvas.height / dpr);
  }

  private shapeGallery(onPick: (kind: ShapeKind) => void, withLines = true) {
    return (root: HTMLElement) => {
      const theme = this.c.theme;
      const env = { theme, media: {}, slideSize: [960, 540] as [number, number] };
      if (withLines) {
        this.gridGallery(root, "Lines", [
          { label: "Line", svg: icon("line"), action: () => this.c.setPendingInsert({ line: "straight", arrow: false }) },
          { label: "Arrow", svg: icon("arrow"), action: () => this.c.setPendingInsert({ line: "straight", arrow: true }) },
          { label: "Elbow Connector", svg: icon("elbow"), action: () => this.c.setPendingInsert({ line: "elbow", arrow: true }) },
          { label: "Curved Connector", svg: icon("curve"), action: () => this.c.setPendingInsert({ line: "curved", arrow: true }) },
          { label: "Text Box", svg: icon("textBox"), action: () => this.c.setPendingInsert({ textBox: false }) },
        ], 12, [26, 26]);
      }
      for (const [category, kinds] of SHAPE_CATEGORIES) {
        this.gridGallery(root, category, kinds.map((kind) => ({
          label: SHAPE_TITLES[kind],
          draw: (canvas) => this.drawPreview(canvas, (ctx, w, h) => {
            const e = shapeElement(kind, frame(3, 3, w - 6, h - 6), NO_FILL, { color: { rgb: { _0: { r: 0.35, g: 0.35, b: 0.38, a: 1 } } }, width: 1.2, dash: "solid", head: "none", tail: "none", roundCaps: false });
            drawElement(ctx, e, env);
          }),
          action: () => onPick(kind),
        })), 12, [26, 26]);
      }
    };
  }

  private themeGallery(root: HTMLElement) {
    const current = this.c.theme.id;
    this.gridGallery(root, "Themes", THEMES.map((t) => ({
      label: t.name,
      selected: t.id === current,
      draw: (canvas) => {
        const p = newPresentation(themeById(t.id));
        const r = renderSlide(p.slides[0], 1, p, canvas.width);
        canvas.getContext("2d")!.drawImage(r, 0, 0, canvas.width, canvas.height);
      },
      action: () => this.c.applyTheme(themeById(t.id)),
    })), 4, [128, 72]);
  }

  private layoutGallery(onPick: (l: LayoutKind) => void) {
    return (root: HTMLElement) => {
      const p = this.c.presentation;
      this.gridGallery(root, null, LAYOUTS.map((l) => ({
        label: LAYOUT_TITLES[l],
        selected: this.c.currentSlide.layout === l,
        draw: (canvas) => {
          const slide = makeSlide(l, p.theme, p.slideSize);
          const r = renderSlide(slide, 1, { ...p, slides: [slide] }, canvas.width, { element: { editorChrome: true } });
          canvas.getContext("2d")!.drawImage(r, 0, 0, canvas.width, canvas.height);
        },
        action: () => onPick(l),
      })), 3, [112, 63]);
    };
  }

  private variantGallery(root: HTMLElement) {
    const t = this.c.theme;
    const base = THEMES.find((x) => x.id === t.id);
    const variants = [base?.colors ?? t.colors, ...(base?.variants ?? t.variants)];
    this.gridGallery(root, "Variants", variants.map((colors, i) => ({
      label: `Variant ${i + 1}`,
      draw: (canvas) => this.drawSwatchStrip(canvas, colors),
      action: () => this.c.applyColors(clone(colors)),
    })), 4, [96, 30]);
    this.gridGallery(root, "Colors", COLOR_SCHEMES.map(([name, colors]) => ({
      label: name, draw: (canvas) => this.drawSwatchStrip(canvas, colors), action: () => this.c.applyColors(clone(colors)),
    })), 4, [96, 30]);
    const fonts = document.createElement("h4");
    fonts.textContent = "Fonts";
    root.append(fonts);
    const list = document.createElement("div");
    list.style.display = "grid";
    list.style.gridTemplateColumns = "1fr 1fr";
    list.style.gap = "2px";
    for (const pair of FONT_PAIRS) {
      const b = document.createElement("button");
      b.style.cssText = "border:0;background:none;text-align:left;padding:5px 8px;border-radius:6px";
      b.innerHTML = `<div style="font-family:'${pair.heading}';font-size:15px">${pair.name}</div><div class="note" style="font-family:'${pair.body}'">${pair.heading} / ${pair.body}</div>`;
      b.addEventListener("mouseenter", () => (b.style.background = "var(--hover)"));
      b.addEventListener("mouseleave", () => (b.style.background = "none"));
      b.addEventListener("click", () => { closeGallery(); this.c.applyFonts(pair.heading, pair.body); });
      list.append(b);
    }
    root.append(list);
  }

  private drawSwatchStrip(canvas: HTMLCanvasElement, colors: ThemeColors) {
    this.drawPreview(canvas, (ctx, w, h) => {
      const list = [colors.light1, colors.dark1, colors.accent1, colors.accent2, colors.accent3, colors.accent4, colors.accent5, colors.accent6];
      list.forEach((c, i) => { ctx.fillStyle = cssColor(c); ctx.fillRect((i * w) / list.length, 0, w / list.length + 0.5, h); });
      ctx.strokeStyle = "rgba(0,0,0,0.2)";
      ctx.strokeRect(0.5, 0.5, w - 1, h - 1);
    });
  }

  private shapeStyleGallery(root: HTMLElement) {
    const env = { theme: this.c.theme, media: {}, slideSize: [960, 540] as [number, number] };
    this.gridGallery(root, "Shape Styles", shapeStylePresets().map((preset) => ({
      label: preset.id,
      draw: (canvas) => this.drawPreview(canvas, (ctx, w, h) => {
        const e = shapeElement("roundRect", frame(4, 4, w - 8, h - 8), preset.fill, preset.line, "Abc");
        shapeOf(e)!.effects = clone(preset.effects);
        textOf(e)!.defaultColor = preset.textColor;
        textOf(e)!.defaultSize = 12;
        drawElement(ctx, e, env);
      }),
      action: () => this.c.applyShapeStyle(preset),
    })), 7, [52, 36]);
  }

  private wordArtGallery(onPick: (i: number) => void) {
    return (root: HTMLElement) => {
      const env = { theme: this.c.theme, media: {}, slideSize: [960, 540] as [number, number] };
      this.gridGallery(root, null, WORDART_PRESETS.map((preset, i) => ({
        label: preset.id,
        draw: (canvas) => this.drawPreview(canvas, (ctx, w, h) => {
          ctx.fillStyle = cssColor(this.c.theme.colors.light1);
          ctx.fillRect(0, 0, w, h);
          const e = textBoxElement("A", frame(0, 0, w, h), { size: 34, role: "heading", alignment: "center", anchor: "middle" });
          updateRuns(textOf(e)!, preset.apply);
          textOf(e)!.autofit = "none";
          drawElement(ctx, e, env);
        }),
        action: () => onPick(i),
      })), 5, [48, 48]);
    };
  }

  private transitionGallery(root: HTMLElement) {
    const current = this.c.currentSlide.transition.kind;
    this.gridGallery(root, null, TRANSITIONS.map((k) => ({
      label: TRANSITION_TITLES[k],
      selected: current === k,
      svg: icon(k === "none" ? "close" : k === "morph" ? "sparkle" : "preview"),
      action: () => this.applyTransition(k),
    })), 6, [64, 56]);
  }

  private applyTransition(kind: TransitionKind) {
    this.c.setTransition((t) => { t.kind = kind; if (kind === "morph" && t.duration < 1) t.duration = 1.5; });
  }

  private animationGallery(replacing: boolean) {
    return (root: HTMLElement) => {
      const current = this.c.targetAnimations[0]?.effect;
      if (replacing) {
        const none = document.createElement("button");
        none.className = "wide";
        none.textContent = "None";
        none.style.cssText = "border:0;background:var(--hover);border-radius:5px;padding:4px 10px;margin-bottom:6px";
        none.addEventListener("click", () => { closeGallery(); this.c.removeAnimations(this.c.targetIDs); });
        root.append(none);
      }
      for (const [category, title] of ANIMATION_CATEGORIES) {
        this.gridGallery(root, title, effectsIn(category).map((effect: AnimationEffect) => ({
          label: ANIMATION_TITLES[effect],
          selected: effect === current,
          svg: icon(category === "entrance" ? "sparkle" : category === "emphasis" ? "star" : category === "exit" ? "close" : "curve"),
          action: () => this.c.addAnimation(effect, replacing),
        })), 6, [62, 50]);
      }
    };
  }

  // MARK: Tabs

  private home(): HTMLElement[] {
    const c = this.c, m = modKey();
    const hasSelection = () => c.selection.length > 0 || !!c.textEditor;
    return [
      this.group("Clipboard",
        this.large("paste", "Paste", () => this.actions.paste(), { menu: () => [
          { label: "Paste", shortcut: `${m}V`, action: () => this.actions.paste() },
          { label: "Paste as Text", shortcut: `${m}⇧V`, action: () => this.actions.paste(true) },
        ] }),
        this.stack(
          [this.small("cut", null, () => this.actions.cut(), { title: `Cut (${m}X)`, enabled: hasSelection })],
          [this.small("copy", null, () => this.actions.copy(), { title: `Copy (${m}C)`, enabled: hasSelection })],
          [this.small("painter", null, () => c.copyFormat(), { title: "Format Painter", isOn: () => !!c.formatPainter, enabled: () => !!c.primary })],
        )),
      this.group("Slides",
        this.large("newSlide", "New Slide", () => c.addSlide(), { gallery: this.layoutGallery((l) => c.addSlide(l)), galleryWidth: 380 }),
        this.stack(
          [this.small("layout", "Layout", null, { gallery: this.layoutGallery((l) => c.setLayout(l)), galleryWidth: 380 })],
          [this.small("reset", "Reset", () => c.resetSlides())],
          [this.small("section", "Section", null, { menu: () => [
            { label: "Add Section", action: () => void this.addSection() },
            { label: "Remove All Sections", enabled: c.presentation.sections.length > 0, action: () => c.removeAllSections() },
          ] })],
        )),
      this.group("Font", this.fontControls()),
      this.group("Paragraph", this.paragraphControls()),
      this.group("Drawing",
        this.button("shapes", "Shapes", null, { large: true, gallery: this.shapeGallery((k) => c.setPendingInsert({ shape: k })), galleryWidth: 400 }),
        this.button("arrange", "Arrange", null, { large: true, menu: () => this.arrangeMenu(), enabled: hasSelection }),
        this.stack(
          [this.colorButton("fill", "Shape Fill", () => this.lastFill, (p) => { if (p) this.lastFill = p; c.setFill(p ? solidFill(p) : NO_FILL); }, { none: "No Fill", extras: this.fillExtras() })],
          [this.colorButton("outlineIcon", "Shape Outline", () => this.lastLine, (p) => { if (p) this.lastLine = p; c.setLine((l) => { if (p) { l.color = p; if (!l.width) l.width = 1; } else delete l.color; }); }, { none: "No Outline" })],
          [this.small("effects", "Effects", null, { menu: () => this.effectsMenu(), enabled: hasSelection })],
        )),
      this.group("Editing",
        this.stack(
          [this.small("search", "Find", () => this.actions.findReplace(false))],
          [this.small("replace", "Replace", () => this.actions.findReplace(true), { menu: () => [
            { label: "Replace…", action: () => this.actions.findReplace(true) },
            { label: "Replace Fonts…", action: () => this.actions.replaceFonts() },
          ] })],
          [this.small("selectAll", "Select", () => c.selectAll(), { menu: () => [
            { label: "Select All", shortcut: `${m}A`, action: () => c.selectAll() },
            { label: "Selection Pane…", action: () => c.setView({ sidePane: "selection" }) },
          ] })],
        )),
    ];
  }

  private async addSection() {
    const name = await promptText("Add Section", "Section name:", "Untitled Section");
    if (name) this.c.addSection(name);
  }

  private fontControls(): HTMLElement {
    const c = this.c, m = modKey();
    const family = () => c.currentRunStyle.fontFamily ?? (c.currentBody?.fontRole === "heading" ? c.theme.headingFont : c.theme.bodyFont);
    const size = () => String(c.currentRunStyle.size ?? c.currentBody?.defaultSize ?? 18);
    const fonts = [`${c.theme.headingFont} (Headings)`, `${c.theme.bodyFont} (Body)`, ...this.fonts];
    return this.stack(
      [
        this.select("rb-font", fonts.map((f) => [f, f.replace(/ \((Headings|Body)\)$/, "")]), family, (v) => c.setFontFamily(v.replace(/ \((Headings|Body)\)$/, "")), "Font", true),
        this.select("rb-size", FONT_SIZES.map((s) => [String(s), String(s)]), size, (v) => { const n = Number(v); if (n > 0) c.setFontSize(n); }, "Font Size", true),
        this.small("grow", null, () => c.growFont(true), { title: `Increase Font Size (${m}⇧>)` }),
        this.small("shrink", null, () => c.growFont(false), { title: `Decrease Font Size (${m}⇧<)` }),
        this.small("clearFormat", null, () => c.clearFormatting(), { title: "Clear All Formatting" }),
      ],
      [
        this.small("bold", null, () => c.toggleBold(), { title: `Bold (${m}B)`, isOn: () => !!c.currentRunStyle.bold }),
        this.small("italic", null, () => c.toggleItalic(), { title: `Italic (${m}I)`, isOn: () => !!c.currentRunStyle.italic }),
        this.small("underline", null, () => c.toggleUnderline(), { title: `Underline (${m}U)`, isOn: () => c.currentRunStyle.underline }),
        this.small("strike", null, () => c.toggleStrikethrough(), { title: "Strikethrough", isOn: () => c.currentRunStyle.strikethrough }),
        this.small("shadowText", null, () => c.toggleShadow(), { title: "Text Shadow", isOn: () => c.currentRunStyle.shadow }),
        this.small("superscript", null, () => c.setBaseline(1), { title: "Superscript", isOn: () => c.currentRunStyle.baseline > 0 }),
        this.small("subscript", null, () => c.setBaseline(-1), { title: "Subscript", isOn: () => c.currentRunStyle.baseline < 0 }),
        this.small(null, "Aa", null, { title: "Change Case", menu: () => [
          { label: "Sentence case.", action: () => c.changeCase("sentence") }, { label: "lowercase", action: () => c.changeCase("lower") },
          { label: "UPPERCASE", action: () => c.changeCase("upper") }, { label: "Capitalize Each Word", action: () => c.changeCase("title") },
          { label: "tOGGLE cASE", action: () => c.changeCase("toggle") },
        ] }),
        this.colorButton("highlight", "Text Highlight Color", () => ({ rgb: { _0: this.lastHighlight } }), (p) => {
          if (p && "rgb" in p) this.lastHighlight = p.rgb._0;
          c.setHighlight(p ? resolve(p, c.theme.colors) : null);
        }, { none: "No Color" }),
        this.colorButton("fontColor", "Font Color", () => this.lastTextColor, (p) => { if (p) this.lastTextColor = p; c.setTextColor(p); }, { automatic: "Automatic" }),
        this.small(null, "AV", null, { title: "Character Spacing", menu: () => [
          ["Very Tight", -3], ["Tight", -1.5], ["Normal", 0], ["Loose", 3], ["Very Loose", 6],
        ].map(([label, v]) => ({ label: String(label), checked: c.currentRunStyle.characterSpacing === v, action: () => c.setCharacterSpacing(Number(v)) })) }),
      ],
    );
  }

  private paragraphControls(): HTMLElement {
    const c = this.c;
    const align = () => c.currentParagraphStyle.alignment;
    const anchor = () => c.currentBody?.anchor ?? "top";
    return this.stack(
      [
        this.small("bullets", null, () => c.toggleBullets(), { title: "Bullets", isOn: () => c.bulletOn, menu: () => [
          { label: "None", action: () => c.applyParagraphStyle("Bullets", (p) => { p.bullet = { none: {} }; }) },
          ...STANDARD_BULLETS.map((s) => ({ label: s, action: () => c.toggleBullets(s) })),
        ] }),
        this.small("numbering", null, () => c.toggleNumbering(), { title: "Numbering", isOn: () => c.numberingOn, menu: () => [
          { label: "None", action: () => c.applyParagraphStyle("Numbering", (p) => { p.bullet = { none: {} }; }) },
          ...(Object.keys(NUMBERING_TITLES) as (keyof typeof NUMBERING_TITLES)[]).map((s) => ({ label: NUMBERING_TITLES[s], action: () => c.toggleNumbering(s) })),
        ] }),
        this.small("indentLess", null, () => c.changeIndent(-1), { title: "Decrease List Level" }),
        this.small("indentMore", null, () => c.changeIndent(1), { title: "Increase List Level" }),
        this.small("lineSpacing", null, null, { title: "Line Spacing", menu: () => [
          ...[0.9, 1, 1.15, 1.5, 2, 2.5, 3].map((v) => ({ label: String(v), checked: c.currentParagraphStyle.lineSpacing === v, action: () => c.setLineSpacing(v) })),
          "-",
          { label: "Space Before: 0", action: () => c.setParagraphSpacing(0, null) }, { label: "Space Before: 12 pt", action: () => c.setParagraphSpacing(12, null) },
          { label: "Space After: 0", action: () => c.setParagraphSpacing(null, 0) }, { label: "Space After: 12 pt", action: () => c.setParagraphSpacing(null, 12) },
        ] }),
        this.small("columns", null, null, { title: "Columns", menu: () => [1, 2, 3].map((n) => ({ label: `${n} Column${n > 1 ? "s" : ""}`, checked: (c.currentBody?.columns ?? 1) === n, action: () => c.setColumns(n) })) }),
      ],
      [
        this.small("alignLeft", null, () => c.setAlignment("left"), { title: "Align Left", isOn: () => align() === "left" }),
        this.small("alignCenter", null, () => c.setAlignment("center"), { title: "Center", isOn: () => align() === "center" }),
        this.small("alignRight", null, () => c.setAlignment("right"), { title: "Align Right", isOn: () => align() === "right" }),
        this.small("justify", null, () => c.setAlignment("justify"), { title: "Justify", isOn: () => align() === "justify" }),
        this.small("anchorTop", null, () => c.setVerticalAnchor("top"), { title: "Align Text Top", isOn: () => anchor() === "top" }),
        this.small("anchorMiddle", null, () => c.setVerticalAnchor("middle"), { title: "Align Text Middle", isOn: () => anchor() === "middle" }),
        this.small("anchorBottom", null, () => c.setVerticalAnchor("bottom"), { title: "Align Text Bottom", isOn: () => anchor() === "bottom" }),
        this.small("textDirection", null, null, { title: "Text Direction", menu: () => [
          { label: "Horizontal", action: () => c.setTextDirection("horizontal") }, { label: "Rotate all text 90°", action: () => c.setTextDirection("rotated90") },
          { label: "Rotate all text 270°", action: () => c.setTextDirection("rotated270") },
        ] }),
      ],
    );
  }

  private fillExtras() {
    const c = this.c;
    return [
      { label: "Gradient", action: () => c.setFill(gradientFill(twoTone(this.lastFill, themePaint("light1")))) },
      { label: "Picture…", action: () => this.actions.insertPictures() },
    ];
  }

  private arrangeMenu(): MenuEntry[] {
    const c = this.c, m = modKey();
    return [
      { label: "Bring to Front", action: () => c.arrange("front") }, { label: "Bring Forward", action: () => c.arrange("forward") },
      { label: "Send Backward", action: () => c.arrange("backward") }, { label: "Send to Back", action: () => c.arrange("back") },
      "-",
      { label: "Group", shortcut: `${m}G`, enabled: c.selection.length > 1, action: () => c.group() },
      { label: "Ungroup", shortcut: `${m}⇧G`, enabled: c.selectedElements.some((e) => groupOf(e)), action: () => c.ungroup() },
      "-",
      { label: "Align", submenu: [
        { label: "Align Left", action: () => c.align("left") }, { label: "Align Center", action: () => c.align("center") }, { label: "Align Right", action: () => c.align("right") },
        "-",
        { label: "Align Top", action: () => c.align("top") }, { label: "Align Middle", action: () => c.align("middle") }, { label: "Align Bottom", action: () => c.align("bottom") },
        "-",
        { label: "Distribute Horizontally", enabled: c.selection.length > 2, action: () => c.distribute(true) },
        { label: "Distribute Vertically", enabled: c.selection.length > 2, action: () => c.distribute(false) },
      ] },
      { label: "Rotate", submenu: [
        { label: "Rotate Right 90°", action: () => c.rotate(90) }, { label: "Rotate Left 90°", action: () => c.rotate(-90) },
        { label: "Flip Vertical", action: () => c.flip(false) }, { label: "Flip Horizontal", action: () => c.flip(true) },
      ] },
      "-",
      { label: c.selectedElements.every((e) => e.locked) ? "Unlock" : "Lock", action: () => c.toggleLock() },
      { label: "Selection Pane…", action: () => c.setView({ sidePane: "selection" }) },
    ];
  }

  private effectsMenu(): MenuEntry[] {
    const c = this.c;
    return [
      { label: "Shadow", submenu: [
        { label: "No Shadow", action: () => c.setEffects((fx) => { delete fx.shadow; }) },
        { label: "Outer Shadow", action: () => c.setEffects((fx) => { fx.shadow = OUTER_SHADOW(); }) },
        { label: "Soft Shadow", action: () => c.setEffects((fx) => { fx.shadow = SOFT_SHADOW(); }) },
      ] },
      { label: "Glow", submenu: [
        { label: "No Glow", action: () => c.setEffects((fx) => { delete fx.glow; }) },
        ...[5, 8, 11, 18].map((r) => ({ label: `${r} pt Glow`, action: () => c.setEffects((fx) => { fx.glow = { color: themePaint("accent1", 0, 0.6), radius: r }; }) })),
      ] },
      { label: "Reflection", submenu: [
        { label: "No Reflection", action: () => c.setEffects((fx) => { delete fx.reflection; }) },
        { label: "Tight Reflection", action: () => c.setEffects((fx) => { fx.reflection = { opacity: 0.4, size: 0.3, distance: 0 }; }) },
        { label: "Half Reflection", action: () => c.setEffects((fx) => { fx.reflection = { opacity: 0.4, size: 0.5, distance: 2 }; }) },
        { label: "Full Reflection", action: () => c.setEffects((fx) => { fx.reflection = { opacity: 0.35, size: 1, distance: 4 }; }) },
      ] },
      { label: "Soft Edges", submenu: [0, 2.5, 5, 10].map((v) => ({ label: v ? `${v} pt` : "No Soft Edges", action: () => c.setEffects((fx) => { fx.softEdges = v; }) })) },
    ];
  }

  private insert(): HTMLElement[] {
    const c = this.c;
    const charts = Object.keys(CHART_TITLES) as ChartKind[];
    return [
      this.group("Slides", this.large("newSlide", "New Slide", () => c.addSlide(), { menu: () => [
        ...LAYOUTS.map((l) => ({ label: LAYOUT_TITLES[l], action: () => c.addSlide(l) })),
        "-",
        { label: "Duplicate Selected Slides", action: () => c.duplicateSlides() },
        { label: "Slides from Outline…", action: () => this.actions.insertSlidesFromOutline() },
        { label: "Reuse Slides…", action: () => this.actions.reuseSlides() },
      ] })),
      this.group("Tables", this.large("table", "Table", () => this.actions.insertTable())),
      this.group("Images",
        this.large("picture", "Pictures", () => this.actions.insertPictures()),
        this.large("picture", "Photo Album", () => this.actions.photoAlbum())),
      this.group("Illustrations",
        this.button("shapes", "Shapes", null, { large: true, gallery: this.shapeGallery((k) => c.setPendingInsert({ shape: k })), galleryWidth: 400 }),
        this.large("icons", "Icons", () => this.actions.insertIcon()),
        this.large("smartArt", "SmartArt", () => this.actions.insertSmartArt()),
        this.button("chart", "Chart", null, { large: true, menu: () => charts.map((k) => ({ label: CHART_TITLES[k], action: () => c.insertChart(k) })) })),
      this.group("Links",
        this.large("link", "Link", () => this.actions.hyperlink(), { enabled: () => !!c.primary || !!c.textEditor }),
        this.large("action", "Action", () => this.actions.action(), { enabled: () => !!c.primary })),
      this.group("Comments", this.large("comment", "Comment", () => c.setView({ sidePane: "comments" }))),
      this.group("Text",
        this.large("textBox", "Text Box", () => c.setPendingInsert({ textBox: false }), { menu: () => [
          { label: "Draw Horizontal Text Box", action: () => c.setPendingInsert({ textBox: false }) },
          { label: "Draw Vertical Text Box", action: () => c.setPendingInsert({ textBox: true }) },
        ] }),
        this.stack(
          [this.small("headerFooter", "Header & Footer", () => this.actions.headerFooter())],
          [this.small("wordArt", "WordArt", null, { gallery: this.wordArtGallery((i) => c.insertWordArt(i)), galleryWidth: 290 })],
          [this.small("dateTime", "Date & Time", () => this.actions.insertDateTime())],
        ),
        this.stack(
          [this.small("slideNumber", "Slide Number", () => this.actions.headerFooter())],
          [this.small("symbol", "Symbol", () => this.actions.insertSymbol())],
        )),
      this.group("Media",
        this.large("video", "Video", () => this.actions.insertMedia("video")),
        this.large("audio", "Audio", () => this.actions.insertMedia("audio"))),
    ];
  }

  private design(): HTMLElement[] {
    const c = this.c;
    return [
      this.group("Themes", this.button("themes", "Themes", null, { large: true, gallery: (root) => this.themeGallery(root), galleryWidth: 560 })),
      this.group("Variants", this.button("variants", "Variants", null, { large: true, gallery: (root) => this.variantGallery(root), galleryWidth: 440 }),
        this.stack(
          [this.small("colors", "Colors", null, { gallery: (root) => this.variantGallery(root), galleryWidth: 440 })],
          [this.small("fonts", "Fonts", null, { menu: () => FONT_PAIRS.map((p) => ({ label: `${p.name} — ${p.heading} / ${p.body}`, checked: c.theme.headingFont === p.heading && c.theme.bodyFont === p.body, action: () => c.applyFonts(p.heading, p.body) })) })],
          [this.small("background", "Background Styles", null, { menu: () => this.backgroundMenu() })],
        )),
      this.group("Customize",
        this.large("slideSize", "Slide Size", () => this.actions.slideSize(), { menu: () => [
          { label: "Standard (4:3)", action: () => c.setSlideSize([720, 540], true) },
          { label: "Widescreen (16:9)", action: () => c.setSlideSize([960, 540], true) },
          "-",
          { label: "Custom Slide Size…", action: () => this.actions.slideSize() },
        ] }),
        this.large("background", "Format Background", () => this.actions.formatBackground())),
      this.group("Designer", this.large("designIdeas", "Design Ideas", () => this.actions.designIdeas())),
    ];
  }

  private backgroundMenu(): MenuEntry[] {
    const c = this.c;
    const styles: [string, () => ReturnType<typeof solidFill>][] = [
      ["Light", () => solidFill(themePaint("light1"))], ["Light 2", () => solidFill(themePaint("light2"))],
      ["Dark", () => solidFill(themePaint("dark1"))], ["Dark 2", () => solidFill(themePaint("dark2"))],
      ["Accent Gradient", () => gradientFill(twoTone(themePaint("accent1"), themePaint("accent2"), 45))],
      ["Soft Gradient", () => gradientFill(twoTone(themePaint("light1"), themePaint("light2"), 90))],
    ];
    return [
      ...styles.map(([label, fill]) => ({ label, submenu: [
        { label: "Apply to Selected Slides", action: () => c.setBackground(fill(), false) },
        { label: "Apply to All Slides", action: () => c.setBackground(fill(), true) },
      ] })),
      "-",
      { label: "Reset Slide Background", action: () => c.setBackground(null, false) },
      { label: "Hide Background Graphics", checked: c.currentSlide.hideBackgroundGraphics, action: () => c.setHideBackgroundGraphics(!c.currentSlide.hideBackgroundGraphics) },
    ];
  }

  private transitions(): HTMLElement[] {
    const c = this.c;
    const t = () => c.currentSlide.transition;
    return [
      this.group("Preview", this.large("preview", "Preview", () => this.actions.startShow("current"))),
      this.group("Transition to This Slide",
        this.button("preview", TRANSITION_TITLES[t().kind], null, { large: true, gallery: (root) => this.transitionGallery(root), galleryWidth: 440 }),
        this.button("textDirection", "Effect Options", null, { large: true, enabled: () => transitionHasDirection(t().kind), menu: () => DIRECTIONS.map((d) => ({ label: DIRECTION_TITLES[d], checked: t().direction === d, action: () => c.setTransition((x) => { x.direction = d; }) })) })),
      this.group("Timing",
        this.stack(
          [this.number("Duration (s)", () => t().duration, (v) => c.setTransition((x) => { x.duration = Math.max(0.01, Math.min(v, 60)); }), { min: 0.01, max: 60, step: 0.25 })],
          [this.small("applyAll", "Apply To All", () => c.applyTransitionToAll())],
        ),
        this.stack(
          [this.toggle("On Mouse Click", () => t().advanceOnClick, (on) => c.setTransition((x) => { x.advanceOnClick = on; }))],
          [this.toggle("After (s)", () => t().advanceAfter !== undefined, (on) => c.setTransition((x) => { if (on) x.advanceAfter = x.advanceAfter ?? 5; else delete x.advanceAfter; })),
            this.number("", () => t().advanceAfter ?? 0, (v) => c.setTransition((x) => { x.advanceAfter = Math.max(0, v); }), { min: 0, step: 0.5, width: 56 })],
        )),
    ];
  }

  private toggle(label: string, isOn: () => boolean, set: (on: boolean) => void): HTMLElement {
    const l = document.createElement("label");
    l.className = "rb-row";
    l.style.gap = "4px";
    l.style.fontSize = "12px";
    const box = document.createElement("input");
    box.type = "checkbox";
    box.style.accentColor = "var(--accent)";
    box.addEventListener("change", () => set(box.checked));
    this.updaters.push(() => { box.checked = isOn(); });
    l.append(box, label);
    return l;
  }

  private animations(): HTMLElement[] {
    const c = this.c;
    const a = () => c.targetAnimations[0];
    const has = () => !!a();
    return [
      this.group("Preview", this.large("preview", "Preview", () => this.actions.startShow("current"))),
      this.group("Animation",
        this.button("sparkle", has() ? ANIMATION_TITLES[a()!.effect] : "None", null, { large: true, enabled: () => c.targetIDs.length > 0, gallery: this.animationGallery(true), galleryWidth: 440 }),
        this.button("textDirection", "Effect Options", null, { large: true, enabled: () => has() && effectHasDirection(a()!.effect), menu: () => DIRECTIONS.map((d) => ({ label: DIRECTION_TITLES[d], checked: a()?.direction === d, action: () => c.updateSelectedAnimations((x) => { x.direction = d; }) })) })),
      this.group("Advanced Animation",
        this.button("plus", "Add Animation", null, { large: true, enabled: () => c.targetIDs.length > 0, gallery: this.animationGallery(false), galleryWidth: 440 }),
        this.stack(
          [this.small("animationPane", "Animation Pane", () => c.setView({ sidePane: c.sidePane === "animations" ? null : "animations" }), { isOn: () => c.sidePane === "animations" })],
          [this.small("painterAnimation", "Animation Painter", () => this.copyAnimation(), { enabled: has })],
        )),
      this.group("Timing", this.stack(
        [this.select("rb-format", (Object.keys(TRIGGER_TITLES) as (keyof typeof TRIGGER_TITLES)[]).map((k) => [TRIGGER_TITLES[k], k]), () => a()?.trigger ?? "onClick", (v) => c.updateSelectedAnimations((x) => { x.trigger = v as keyof typeof TRIGGER_TITLES; }), "Start")],
        [this.number("Duration (s)", () => a()?.duration ?? 0, (v) => c.updateSelectedAnimations((x) => { x.duration = Math.max(0, v); }), { min: 0, step: 0.25 })],
        [this.number("Delay (s)", () => a()?.delay ?? 0, (v) => c.updateSelectedAnimations((x) => { x.delay = Math.max(0, v); }), { min: 0, step: 0.25 })],
      ), this.stack(
        [this.number("Repeat", () => a()?.repeatCount ?? 1, (v) => c.updateSelectedAnimations((x) => { x.repeatCount = Math.max(1, Math.round(v)); }), { min: 1, max: 99, width: 52 })],
        [this.small("up", "Move Earlier", () => { const x = a(); if (x) c.moveAnimation(x.id, -1); }, { enabled: has })],
        [this.small("down", "Move Later", () => { const x = a(); if (x) c.moveAnimation(x.id, 1); }, { enabled: has })],
      )),
    ];
  }

  /** Animation Painter: copies the animation, then applies it to the next object selected. */
  private copyAnimation() {
    const from = this.c.targetAnimations[0];
    if (!from) return;
    const source = clone(from);
    this.c.flash("Click another object to give it the same animation.");
    const listener = (kind: string) => {
      if (kind !== "selection" || !this.c.targetIDs.length || this.c.targetIDs.includes(source.elementID)) return;
      this.c.offChange(listener);
      this.c.addAnimation(source.effect, true);
      this.c.updateSelectedAnimations((x) => { x.duration = source.duration; x.delay = source.delay; x.direction = source.direction; x.trigger = source.trigger; x.repeatCount = source.repeatCount; });
    };
    this.c.onChange(listener);
  }

  private slideShow(): HTMLElement[] {
    const c = this.c;
    return [
      this.group("Start Slide Show",
        this.large("fromStart", "From Beginning", () => this.actions.startShow(0)),
        this.large("play", "From Current Slide", () => this.actions.startShow("current")),
        this.large("presenter", "Presenter View", () => this.actions.startShow("current", true))),
      this.group("Set Up",
        this.large("setUp", "Set Up Slide Show", () => this.actions.setUpShow()),
        this.stack(
          [this.small("hide", "Hide Slide", () => c.toggleHideSlides(), { isOn: () => c.currentSlide.hidden })],
          [this.small("rehearse", "Rehearse Timings", () => this.actions.startShow(0, false, true))],
        ),
        this.stack(
          [this.toggle("Use Timings", () => c.presentation.showSettings.useTimings, (on) => c.setShowSettings({ ...c.presentation.showSettings, useTimings: on }))],
          [this.toggle("Loop Until Esc", () => c.presentation.showSettings.loopUntilEscape, (on) => c.setShowSettings({ ...c.presentation.showSettings, loopUntilEscape: on }))],
        )),
      this.group("Monitors", this.stack(
        [this.toggle("Use Presenter View", () => c.presentation.showSettings.usePresenterView, (on) => c.setShowSettings({ ...c.presentation.showSettings, usePresenterView: on }))],
      )),
    ];
  }

  private review(): HTMLElement[] {
    const c = this.c;
    return [
      this.group("Proofing", this.large("spelling", "Spelling", () => this.actions.spelling())),
      this.group("Accessibility", this.large("accessibility", "Check Accessibility", () => this.actions.accessibility())),
      this.group("Insights", this.large("wordCount", "Word Count", () => this.actions.wordCount())),
      this.group("Comments",
        this.large("comment", "New Comment", () => c.setView({ sidePane: "comments" })),
        this.stack(
          [this.small("trash", "Delete", null, { menu: () => [
            { label: "Delete All Comments on This Slide", action: () => c.deleteAllComments(false) },
            { label: "Delete All Comments in This Presentation", action: () => c.deleteAllComments(true) },
          ] })],
          [this.small("prev", "Previous", () => c.goToComment(false))],
          [this.small("next", "Next", () => c.goToComment(true))],
        ),
        this.large("comment", "Show Comments", () => c.setView({ sidePane: c.sidePane === "comments" ? null : "comments" }), { isOn: () => c.sidePane === "comments" })),
    ];
  }

  private view(): HTMLElement[] {
    const c = this.c;
    return [
      this.group("Presentation Views",
        this.large("normal", "Normal", () => c.setView({ viewMode: "normal" }), { isOn: () => c.viewMode === "normal" }),
        this.large("outline", "Outline View", () => c.setView({ viewMode: "outline" }), { isOn: () => c.viewMode === "outline" }),
        this.large("sorter", "Slide Sorter", () => c.setView({ viewMode: "sorter" }), { isOn: () => c.viewMode === "sorter" }),
        this.large("notesPage", "Notes Page", () => c.setView({ viewMode: "notesPage" }), { isOn: () => c.viewMode === "notesPage" }),
        this.large("reading", "Reading View", () => this.actions.readingView())),
      this.group("Show", this.stack(
        [this.toggle("Gridlines", () => c.showGridlines, (on) => c.setView({ showGridlines: on }))],
        [this.toggle("Guides", () => c.showGuides, (on) => c.setView({ showGuides: on }))],
        [this.toggle("Notes", () => c.showNotes, (on) => c.setView({ showNotes: on }))],
      )),
      this.group("Zoom",
        this.large("zoom", "Zoom", null, { menu: () => [0.5, 0.66, 0.75, 1, 1.5, 2].map((z) => ({ label: `${Math.round(z * 100)}%`, action: () => c.setView({ fitToWindow: false, zoom: z }) })) }),
        this.large("fit", "Fit to Window", () => c.setView({ fitToWindow: true }), { isOn: () => c.fitToWindow })),
      this.group("Panes",
        this.large("formatPane", "Format", () => c.setView({ sidePane: c.sidePane === "format" ? null : "format" }), { isOn: () => c.sidePane === "format" }),
        this.large("animationPane", "Animation Pane", () => c.setView({ sidePane: c.sidePane === "animations" ? null : "animations" }), { isOn: () => c.sidePane === "animations" }),
        this.large("selectionPane", "Selection", () => c.setView({ sidePane: c.sidePane === "selection" ? null : "selection" }), { isOn: () => c.sidePane === "selection" }),
        this.large("comment", "Comments", () => c.setView({ sidePane: c.sidePane === "comments" ? null : "comments" }), { isOn: () => c.sidePane === "comments" })),
    ];
  }

  // MARK: Contextual tabs

  private shapeFormat(): HTMLElement[] {
    const c = this.c;
    const e = () => c.primary;
    const line = () => { const x = e(); return x ? shapeOf(x)?.line ?? lineOf(x)?.line ?? imageOf(x)?.line : undefined; };
    return [
      this.group("Insert Shapes",
        this.button("shapes", "Shapes", null, { large: true, gallery: this.shapeGallery((k) => c.setPendingInsert({ shape: k })), galleryWidth: 400 }),
        this.button("reset", "Change Shape", null, { large: true, enabled: () => !!(e() && shapeOf(e()!)), gallery: this.shapeGallery((k) => c.changeShapeKind(k), false), galleryWidth: 400 })),
      this.group("Shape Styles",
        this.button("styles", "Styles", null, { large: true, enabled: () => !!(e() && shapeOf(e()!)), gallery: (root) => this.shapeStyleGallery(root), galleryWidth: 420 }),
        this.stack(
          [this.colorButton("fill", "Shape Fill", () => this.lastFill, (p) => { if (p) this.lastFill = p; c.setFill(p ? solidFill(p) : NO_FILL); }, { none: "No Fill", extras: this.fillExtras() })],
          [this.colorButton("outlineIcon", "Shape Outline", () => this.lastLine, (p) => { if (p) this.lastLine = p; c.setLine((l) => { if (p) { l.color = p; if (!l.width) l.width = 1; } else delete l.color; }); }, { none: "No Outline" })],
          [this.small("effects", "Effects", null, { menu: () => this.effectsMenu() })],
        ),
        this.stack(
          [this.small(null, "Weight", null, { menu: () => [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6].map((w) => ({ label: `${w} pt`, checked: line()?.width === w, action: () => c.setLine((l) => { l.width = w; if (!l.color) l.color = this.lastLine; }) })) })],
          [this.small(null, "Dashes", null, { menu: () => (Object.keys(DASH_TITLES) as (keyof typeof DASH_TITLES)[]).map((d) => ({ label: DASH_TITLES[d], checked: line()?.dash === d, action: () => c.setLine((l) => { l.dash = d; }) })) })],
          [this.small(null, "Arrows", null, { enabled: () => !!(e() && lineOf(e()!)), menu: () => [
            ...(Object.keys(ARROW_TITLES) as (keyof typeof ARROW_TITLES)[]).map((a) => ({ label: `End: ${ARROW_TITLES[a]}`, checked: line()?.tail === a, action: () => c.setLine((l) => { l.tail = a; }) })),
            "-",
            ...(Object.keys(ARROW_TITLES) as (keyof typeof ARROW_TITLES)[]).map((a) => ({ label: `Start: ${ARROW_TITLES[a]}`, checked: line()?.head === a, action: () => c.setLine((l) => { l.head = a; }) })),
          ] })],
        )),
      this.group("WordArt Styles",
        this.button("wordArt", "Quick Styles", null, { large: true, enabled: () => c.canFormatText, gallery: this.wordArtGallery((i) => c.applyRunStyle("WordArt", WORDART_PRESETS[i].apply)), galleryWidth: 290 }),
        this.stack(
          [this.colorButton("fontColor", "Text Fill", () => this.lastTextColor, (p) => { if (p) this.lastTextColor = p; c.setTextColor(p); }, { automatic: "Automatic" })],
          [this.colorButton("outlineIcon", "Text Outline", () => c.currentRunStyle.outlineColor ?? themePaint("dark1"), (p) => c.setTextOutline(p, 1), { none: "No Outline" })],
          [this.small("shadowText", "Text Shadow", () => c.toggleShadow(), { isOn: () => c.currentRunStyle.shadow })],
        )),
      this.group("Arrange", this.stack(
        [this.small("bringFront", "Bring Forward", () => c.arrange("forward"), { menu: () => [{ label: "Bring to Front", action: () => c.arrange("front") }, { label: "Bring Forward", action: () => c.arrange("forward") }] })],
        [this.small("sendBack", "Send Backward", () => c.arrange("backward"), { menu: () => [{ label: "Send to Back", action: () => c.arrange("back") }, { label: "Send Backward", action: () => c.arrange("backward") }] })],
        [this.small("selectionPane", "Selection Pane", () => c.setView({ sidePane: "selection" }))],
      ), this.stack(
        [this.small("align", "Align", null, { menu: () => (this.arrangeMenu().find((x) => x !== "-" && x.label === "Align") as { submenu: MenuEntry[] }).submenu })],
        [this.small("group", "Group", null, { menu: () => [
          { label: "Group", enabled: c.selection.length > 1, action: () => c.group() },
          { label: "Ungroup", enabled: c.selectedElements.some((x) => groupOf(x)), action: () => c.ungroup() },
        ] })],
        [this.small("rotate", "Rotate", null, { menu: () => (this.arrangeMenu().find((x) => x !== "-" && x.label === "Rotate") as { submenu: MenuEntry[] }).submenu })],
      )),
      this.group("Size", this.sizeFields()),
    ];
  }

  private sizeFields(): HTMLElement {
    const c = this.c;
    const r = () => { const e = c.primary; return e ? { w: e.frame[1][0], h: e.frame[1][1] } : { w: 0, h: 0 }; };
    const setSize = (w: number | null, h: number | null) => {
      const e = c.primary;
      if (!e) return;
      const [[x, y], [ow, oh]] = e.frame;
      let nw = w ?? ow, nh = h ?? oh;
      if (e.lockAspectRatio && ow > 0 && oh > 0) { if (w !== null) nh = (nw * oh) / ow; else nw = (nh * ow) / oh; }
      c.setElementRect(e.id, { x, y, w: Math.max(1, nw), h: Math.max(1, nh) });
    };
    return this.stack(
      [this.number("Height", () => r().h / 72, (v) => setSize(null, v * 72), { min: 0.01, step: 0.1 })],
      [this.number("Width", () => r().w / 72, (v) => setSize(v * 72, null), { min: 0.01, step: 0.1 })],
      [this.toggle("Lock Aspect Ratio", () => !!c.primary?.lockAspectRatio, (on) => c.changeTargets("Lock Aspect Ratio", (e) => { e.lockAspectRatio = on; }))],
    );
  }

  private pictureFormat(): HTMLElement[] {
    const c = this.c;
    const img = () => (c.primary ? imageOf(c.primary) : null);
    return [
      this.group("Adjust",
        this.large("corrections", "Corrections", null, { menu: () => [
          ...[-0.4, -0.2, 0, 0.2, 0.4].map((b) => ({ label: `Brightness ${b > 0 ? "+" : ""}${Math.round(b * 100)}%`, checked: img()?.adjustments.brightness === b, action: () => c.setImageAdjustments((a) => { a.brightness = b; }) })),
          "-",
          ...[-0.4, -0.2, 0, 0.2, 0.4].map((v) => ({ label: `Contrast ${v > 0 ? "+" : ""}${Math.round(v * 100)}%`, checked: img()?.adjustments.contrast === v, action: () => c.setImageAdjustments((a) => { a.contrast = v; }) })),
        ] }),
        this.large("colorIcon", "Color", null, { menu: () => [
          ...[0, 0.33, 0.66, 1, 1.5, 2].map((s) => ({ label: s === 0 ? "Grayscale" : `Saturation ${Math.round(s * 100)}%`, checked: img()?.adjustments.saturation === s && !img()?.adjustments.sepia, action: () => c.setImageAdjustments((a) => { a.saturation = s; a.sepia = false; }) })),
          "-",
          { label: "Sepia", checked: !!img()?.adjustments.sepia, action: () => c.setImageAdjustments((a) => { a.sepia = !a.sepia; }) },
        ] }),
        this.large("transparency", "Transparency", null, { menu: () => [0, 0.15, 0.3, 0.5, 0.65, 0.8].map((t) => ({ label: `${Math.round(t * 100)}%`, checked: img()?.adjustments.transparency === t, action: () => c.setImageAdjustments((a) => { a.transparency = t; }) })) }),
        this.stack(
          [this.small("picture", "Change Picture", () => this.actions.insertPictures(c.primary?.id))],
          [this.small("resetPicture", "Reset Picture", () => c.resetPicture(false))],
        )),
      this.group("Picture Styles",
        this.large("styles", "Styles", null, { menu: () => [
          { label: "Simple Frame, White", action: () => { c.setLine((l) => { l.color = { rgb: { _0: { ...WHITE } } }; l.width = 8; }); c.setEffects((fx) => { fx.shadow = SOFT_SHADOW(); }); } },
          { label: "Thin Border", action: () => { c.setLine((l) => { l.color = themePaint("dark1"); l.width = 1; }); } },
          { label: "Drop Shadow", action: () => c.setEffects((fx) => { fx.shadow = OUTER_SHADOW(); }) },
          { label: "Reflected", action: () => c.setEffects((fx) => { fx.reflection = { opacity: 0.4, size: 0.4, distance: 2 }; }) },
          { label: "Soft Glow", action: () => c.setEffects((fx) => { fx.glow = { color: themePaint("accent1", 0, 0.6), radius: 10 }; }) },
          "-",
          { label: "No Style", action: () => { c.setLine((l) => { delete l.color; }); c.setEffects((fx) => { delete fx.shadow; delete fx.glow; delete fx.reflection; }); } },
        ] }),
        this.stack(
          [this.colorButton("outlineIcon", "Picture Border", () => this.lastLine, (p) => { if (p) this.lastLine = p; c.setLine((l) => { if (p) { l.color = p; if (!l.width) l.width = 1; } else delete l.color; }); }, { none: "No Outline" })],
          [this.small("effects", "Picture Effects", null, { menu: () => this.effectsMenu() })],
          [this.small("altText", "Alt Text", () => this.actions.altText())],
        )),
      this.group("Arrange", this.stack(
        [this.small("bringFront", "Bring Forward", () => c.arrange("forward"))],
        [this.small("sendBack", "Send Backward", () => c.arrange("backward"))],
        [this.small("align", "Align", null, { menu: () => (this.arrangeMenu().find((x) => x !== "-" && x.label === "Align") as { submenu: MenuEntry[] }).submenu })],
      )),
      this.group("Size",
        this.large("crop", "Crop", () => this.actions.cropPicture(), { menu: () => [
          { label: "Crop…", action: () => this.actions.cropPicture() },
          { label: "Crop to Shape", submenu: SHAPE_CATEGORIES.slice(0, 2).flatMap(([, kinds]) => kinds.slice(0, 12)).map((k) => ({ label: SHAPE_TITLES[k], action: () => c.changeShapeKind(k) })) },
          { label: "Remove Crop to Shape", action: () => c.setImage((i) => { delete i.maskShape; }) },
        ] }),
        this.sizeFields()),
    ];
  }

  private tableDesign(): HTMLElement[] {
    const c = this.c;
    const t = () => (c.primary ? tableOf(c.primary) : null);
    const opt = (label: string, key: "headerRow" | "totalRow" | "bandedRows" | "firstColumn" | "lastColumn" | "bandedColumns") =>
      this.toggle(label, () => !!t()?.style[key], (on) => c.setTableStyle((s) => { s[key] = on; }));
    const slots = ["accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "dark1"] as const;
    return [
      this.group("Table Style Options",
        this.stack([opt("Header Row", "headerRow")], [opt("Total Row", "totalRow")], [opt("Banded Rows", "bandedRows")]),
        this.stack([opt("First Column", "firstColumn")], [opt("Last Column", "lastColumn")], [opt("Banded Columns", "bandedColumns")])),
      this.group("Table Styles", this.button("styles", "Styles", null, { large: true, gallery: (root) => {
        const colors = c.theme.colors;
        this.gridGallery(root, null, [1, 0, 2].flatMap((intensity) => slots.map((slot) => ({
          label: `${["Medium", "Light", "Dark"][intensity]} ${slot}`,
          draw: (canvas: HTMLCanvasElement) => this.drawPreview(canvas, (ctx, w, h) => {
            const base = resolve(themePaint(slot), colors);
            for (let r = 0; r < 4; r++) {
              const color = intensity === 1 ? (r === 0 ? null : r % 2 ? { ...base, a: 0.15 } : null) : intensity === 2 ? (r === 0 ? colors.dark1 : { ...base, a: r % 2 ? 1 : 0.8 }) : r === 0 ? base : { ...base, a: r % 2 ? 0.25 : 0.12 };
              if (color) { ctx.fillStyle = cssColor(color); ctx.fillRect(2, 2 + (r * (h - 4)) / 4, w - 4, (h - 4) / 4 - 1); }
            }
            ctx.strokeStyle = cssColor(base);
            ctx.strokeRect(2.5, 2.5, w - 5, h - 5);
          }),
          action: () => c.setTableStyle((s) => { s.intensity = intensity; s.color = themePaint(slot); delete s.borderColor; }),
        }))), 7, [44, 32]);
      }, galleryWidth: 380 }),
        this.stack(
          [this.colorButton("fill", "Shading", () => this.lastFill, (p) => { if (p) this.lastFill = p; c.setCellFill(p ? solidFill(p) : null); }, { none: "No Fill" })],
          [this.colorButton("outlineIcon", "Borders", () => this.lastLine, (p) => { if (p) this.lastLine = p; c.setTableStyle((s) => { if (p) s.borderColor = p; else delete s.borderColor; }); }, { none: "Default Borders" })],
          [this.small(null, "Border Weight", null, { menu: () => [0.5, 1, 1.5, 2.25, 3].map((w) => ({ label: `${w} pt`, action: () => c.setTableStyle((s) => { s.borderWidth = w; if (!s.borderColor) s.borderColor = this.lastLine; }) })) })],
        )),
      this.group("Rows & Columns",
        this.stack(
          [this.small("insertRowAbove", "Insert Above", () => c.insertTableRow(false))],
          [this.small("insertRowBelow", "Insert Below", () => c.insertTableRow(true))],
          [this.small("trash", "Delete", null, { menu: () => [
            { label: "Delete Rows", action: () => c.deleteTableRows() }, { label: "Delete Columns", action: () => c.deleteTableColumns() },
            { label: "Delete Table", action: () => c.deleteSelection() },
          ] })],
        ),
        this.stack(
          [this.small("insertColumnLeft", "Insert Left", () => c.insertTableColumn(false))],
          [this.small("insertColumnRight", "Insert Right", () => c.insertTableColumn(true))],
        )),
      this.group("Merge", this.stack(
        [this.small("merge", "Merge Right", () => c.mergeCells("right"), { title: "Merge the cell with the one to its right (click in a cell first)" })],
        [this.small("merge", "Merge Down", () => c.mergeCells("down"))],
        [this.small("split", "Split Cells", () => c.splitCells())],
      )),
      this.group("Cell Size", this.stack(
        [this.small("columns", "Distribute Rows", () => c.distributeTable(true))],
        [this.small("columns", "Distribute Columns", () => c.distributeTable(false))],
      )),
    ];
  }

  private chartDesign(): HTMLElement[] {
    const c = this.c;
    const ch = () => (c.primary ? chartOf(c.primary) : null);
    const kinds = Object.keys(CHART_TITLES) as ChartKind[];
    return [
      this.group("Type", this.large("chartType", "Change Chart Type", null, { menu: () => kinds.map((k) => ({ label: CHART_TITLES[k], checked: ch()?.kind === k, action: () => c.setSelectedChart((x) => {
        x.kind = k;
        if (isRoundChart(k)) x.series = x.series.slice(0, 1);
      }) })) })),
      this.group("Data", this.large("editData", "Edit Data", () => { const e = c.primary; if (e) this.actions.editChart(e.id); })),
      this.group("Chart Layouts",
        this.large("legend", "Legend", null, { menu: () => (["none", "bottom", "right", "top", "left"] as const).map((l) => ({ label: l[0].toUpperCase() + l.slice(1), checked: ch()?.legend === l, action: () => c.setSelectedChart((x) => { x.legend = l; }) })) }),
        this.stack(
          [this.toggle("Data Labels", () => !!ch()?.showDataLabels, (on) => c.setSelectedChart((x) => { x.showDataLabels = on; }))],
          [this.toggle("Gridlines", () => !!ch()?.showGridlines, (on) => c.setSelectedChart((x) => { x.showGridlines = on; }))],
          [this.toggle("Chart Title", () => !!ch()?.title, (on) => c.setSelectedChart((x) => { if (on) x.title = x.title ?? "Chart Title"; else delete x.title; }))],
        )),
      this.group("Chart Styles", this.stack(
        [this.colorButton("fontColor", "Text Color", () => ch()?.textColor ?? themePaint("dark1"), (p) => c.setSelectedChart((x) => { x.textColor = p ?? themePaint("dark1", 0.25); }), { automatic: "Automatic" })],
        [this.colorButton("fill", "Chart Background", () => this.lastFill, (p) => c.setSelectedChart((x) => { x.background = p ? solidFill(p) : NO_FILL; }), { none: "No Fill" })],
        [this.number("Font Size", () => ch()?.fontSize ?? 12, (v) => c.setSelectedChart((x) => { x.fontSize = Math.max(6, Math.min(48, v)); }), { min: 6, max: 48 })],
      )),
      this.group("Arrange", this.stack(
        [this.small("bringFront", "Bring Forward", () => c.arrange("forward"))],
        [this.small("sendBack", "Send Backward", () => c.arrange("backward"))],
        [this.small("altText", "Alt Text", () => this.actions.altText())],
      )),
    ];
  }
}


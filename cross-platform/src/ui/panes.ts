import type { PaintColor, SlideElement } from "../model/types";
import {
  NO_FILL, R, clone, fillSolid, gradientFill, imageOf, lineOf, shapeOf, solidFill, tableOf, textOf, themePaint, twoTone, elementKindName,
  OUTER_SHADOW, chartOf, groupOf, mediaOf,
} from "../model/core";
import { ANIMATION_TITLES, DIRECTIONS, DIRECTION_TITLES, SHAPE_TITLES, TRIGGER_TITLES, animationCategory, effectHasDirection } from "../model/catalog";
import type { PresentationController } from "../engine/controller";
import { settings } from "../settings";
import { showPalette, swatchCSS } from "./colors";
import { icon } from "./icons";
import { escape } from "./dialogs";

const el = (tag: string, cls = "", text = "") => { const e = document.createElement(tag); if (cls) e.className = cls; if (text) e.textContent = text; return e; };

/** The pane on the right: Format, Animation, Selection or Comments. */
export class SidePane {
  private formatTab: "fill" | "size" | "text" = "fill";
  private open = new Set(["fill", "line", "size", "position", "textbox", "effects", "picture", "media"]);

  constructor(private root: HTMLElement, private c: PresentationController) {}

  render() {
    const pane = this.c.sidePane;
    this.root.hidden = !pane;
    if (!pane) return;
    // Don't rebuild under the user's typing.
    if (this.root.contains(document.activeElement) && document.activeElement?.matches("input[type=text], input[type=number], textarea")) return;
    const scroll = this.root.scrollTop;
    this.root.replaceChildren();
    const titles = { format: "Format", animations: "Animation Pane", selection: "Selection", comments: "Comments" };
    const header = el("div", "pane-header");
    header.append(el("span", "", titles[pane]));
    const close = el("button", "", "×");
    close.title = "Close";
    close.addEventListener("click", () => this.c.setView({ sidePane: null }));
    header.append(close);
    this.root.append(header);
    if (pane === "format") this.format();
    else if (pane === "animations") this.animations();
    else if (pane === "selection") this.selection();
    else this.comments();
    this.root.scrollTop = scroll;
  }

  // MARK: Helpers

  private section(id: string, title: string, build: (body: HTMLElement) => void) {
    const details = document.createElement("details");
    details.className = "pane-section";
    details.open = this.open.has(id);
    details.addEventListener("toggle", () => { if (details.open) this.open.add(id); else this.open.delete(id); });
    const summary = document.createElement("summary");
    summary.textContent = title;
    const body = el("div", "pane-body");
    build(body);
    details.append(summary, body);
    this.root.append(details);
  }

  private row(body: HTMLElement, label: string, ...controls: HTMLElement[]) {
    const r = el("div", "pane-row");
    const l = el("label", "", label);
    r.append(l, ...controls);
    body.append(r);
    return r;
  }

  private number(value: number, onChange: (v: number) => void, o: { min?: number; max?: number; step?: number } = {}) {
    const input = document.createElement("input");
    input.type = "number";
    input.value = String(Math.round(value * 100) / 100);
    if (o.min !== undefined) input.min = String(o.min);
    if (o.max !== undefined) input.max = String(o.max);
    input.step = String(o.step ?? 1);
    input.addEventListener("change", () => { const v = Number(input.value); if (Number.isFinite(v)) onChange(v); });
    return input;
  }

  private slider(value: number, onChange: (v: number) => void, min = 0, max = 100) {
    const input = document.createElement("input");
    input.type = "range";
    input.min = String(min);
    input.max = String(max);
    input.value = String(value);
    input.addEventListener("change", () => onChange(Number(input.value)));
    return input;
  }

  private swatch(color: PaintColor | undefined | null, pick: (c: PaintColor | null) => void, noneLabel?: string) {
    const b = el("button", "swatch-button") as HTMLButtonElement;
    const s = el("span");
    s.style.background = swatchCSS(color, this.c.theme.colors);
    if (!color) s.style.background = "repeating-linear-gradient(45deg, #ddd 0 3px, #fff 3px 6px)";
    b.append(s);
    b.addEventListener("click", () => showPalette(b, this.c.theme.colors, pick, { noneLabel }));
    return b;
  }

  private select(options: [string, string][], value: string, onChange: (v: string) => void) {
    const s = document.createElement("select");
    for (const [label, v] of options) s.append(new Option(label, v));
    s.value = value;
    s.addEventListener("change", () => onChange(s.value));
    return s;
  }

  private check(label: string, checked: boolean, onChange: (v: boolean) => void) {
    const l = el("label", "pane-row");
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = checked;
    box.addEventListener("change", () => onChange(box.checked));
    l.append(box, document.createTextNode(label));
    return l;
  }

  // MARK: Format

  private format() {
    const e = this.c.primary;
    if (!e) {
      const empty = el("div", "pane-empty", "Select an object to format it, or format the slide background from Design ▸ Format Background.");
      this.root.append(empty);
      return;
    }
    const tabs = el("div", "pane-tabs");
    for (const [id, label] of [["fill", "Fill & Line"], ["size", "Size & Position"], ["text", "Text"]] as const) {
      const b = el("button", this.formatTab === id ? "selected" : "", label);
      b.addEventListener("click", () => { this.formatTab = id; this.render(); });
      tabs.append(b);
    }
    this.root.append(tabs);
    if (this.formatTab === "fill") this.fillAndLine(e);
    else if (this.formatTab === "size") this.sizeAndPosition(e);
    else this.textOptions(e);
  }

  private fillAndLine(e: SlideElement) {
    const c = this.c;
    const s = shapeOf(e), image = imageOf(e), line = lineOf(e);
    if (s || chartOf(e) || groupOf(e)) {
      const fill = s?.fill ?? chartOf(e)?.background ?? NO_FILL;
      this.section("fill", "Fill", (body) => {
        const kind = Object.keys(fill)[0];
        const radios = el("div", "pane-radio");
        for (const [value, label] of [["none", "No fill"], ["solid", "Solid fill"], ["gradient", "Gradient fill"], ["pattern", "Pattern fill"]]) {
          const l = el("label");
          const r = document.createElement("input");
          r.type = "radio";
          r.name = "fill-kind";
          r.checked = kind === value;
          r.addEventListener("change", () => {
            const base = fillSolid(fill) ?? themePaint("accent1");
            if (value === "none") c.setFill(NO_FILL);
            else if (value === "solid") c.setFill(solidFill(base));
            else if (value === "gradient") c.setFill(gradientFill(twoTone(base, themePaint("light1"))));
            else c.setFill({ pattern: { _0: { kind: "diagonalUp", foreground: base, background: themePaint("light1") } } });
          });
          l.append(r, label);
          radios.append(l);
        }
        body.append(radios);
        if ("solid" in fill) {
          this.row(body, "Color", this.swatch(fill.solid._0, (p) => c.setFill(p ? solidFill(p) : NO_FILL), "No Fill"));
          const alpha = "rgb" in fill.solid._0 ? fill.solid._0.rgb._0.a : fill.solid._0.theme.alpha;
          this.row(body, "Transparency", this.slider(Math.round((1 - alpha) * 100), (v) => {
            const p = clone(fill.solid._0);
            if ("rgb" in p) p.rgb._0.a = 1 - v / 100; else p.theme.alpha = 1 - v / 100;
            c.setFill(solidFill(p));
          }));
        } else if ("gradient" in fill) {
          const g = fill.gradient._0;
          this.row(body, "Type", this.select([["Linear", "linear"], ["Radial", "radial"]], g.kind, (v) => c.setFill(gradientFill({ ...clone(g), kind: v as "linear" | "radial" }))));
          this.row(body, "Angle", this.number(g.angle, (v) => c.setFill(gradientFill({ ...clone(g), angle: v })), { min: 0, max: 359 }), el("span", "unit", "°"));
          g.stops.forEach((stop, i) => this.row(body, `Stop ${i + 1}`, this.swatch(stop.color, (p) => { if (!p) return; const ng = clone(g); ng.stops[i].color = p; c.setFill(gradientFill(ng)); }),
            this.number(stop.position * 100, (v) => { const ng = clone(g); ng.stops[i].position = Math.max(0, Math.min(1, v / 100)); c.setFill(gradientFill(ng)); }, { min: 0, max: 100 }), el("span", "unit", "%")));
        } else if ("pattern" in fill) {
          const p = fill.pattern._0;
          this.row(body, "Foreground", this.swatch(p.foreground, (x) => { if (x) c.setFill({ pattern: { _0: { ...clone(p), foreground: x } } }); }));
          this.row(body, "Background", this.swatch(p.background, (x) => { if (x) c.setFill({ pattern: { _0: { ...clone(p), background: x } } }); }));
        }
      });
    }
    const ls = s?.line ?? line?.line ?? image?.line;
    if (ls) {
      this.section("line", line ? "Line" : "Outline", (body) => {
        this.row(body, "Color", this.swatch(ls.color, (p) => c.setLine((l) => { if (p) { l.color = p; if (!l.width) l.width = 1; } else delete l.color; }), "No Line"));
        this.row(body, "Width", this.number(ls.width, (v) => c.setLine((l) => { l.width = Math.max(0, v); }), { min: 0, max: 100, step: 0.25 }), el("span", "unit", "pt"));
        this.row(body, "Dash", this.select([["Solid", "solid"], ["Round Dot", "roundDot"], ["Square Dot", "squareDot"], ["Dash", "dash"], ["Dash Dot", "dashDot"], ["Long Dash", "longDash"], ["Long Dash Dot", "longDashDot"]], ls.dash, (v) => c.setLine((l) => { l.dash = v as typeof l.dash; })));
        if (line) {
          const heads: [string, string][] = [["None", "none"], ["Arrow", "triangle"], ["Open Arrow", "open"], ["Stealth", "stealth"], ["Diamond", "diamond"], ["Oval", "oval"]];
          this.row(body, "Begin arrow", this.select(heads, ls.head, (v) => c.setLine((l) => { l.head = v as typeof l.head; })));
          this.row(body, "End arrow", this.select(heads, ls.tail, (v) => c.setLine((l) => { l.tail = v as typeof l.tail; })));
          this.row(body, "Connector", this.select([["Straight", "straight"], ["Elbow", "elbow"], ["Curved", "curved"]], line.kind, (v) => c.changeTargets("Connector", (x) => { const lc = lineOf(x); if (lc) lc.kind = v as typeof lc.kind; })));
        }
      });
    }
    const fx = s?.effects ?? image?.effects ?? line?.effects;
    if (fx) {
      this.section("effects", "Effects", (body) => {
        body.append(this.check("Shadow", !!fx.shadow, (on) => c.setEffects((x) => { if (on) x.shadow = OUTER_SHADOW(); else delete x.shadow; })));
        if (fx.shadow) {
          const sh = fx.shadow;
          this.row(body, "Transparency", this.slider(Math.round((1 - sh.opacity) * 100), (v) => c.setEffects((x) => { if (x.shadow) x.shadow.opacity = 1 - v / 100; })));
          this.row(body, "Blur", this.number(sh.blur, (v) => c.setEffects((x) => { if (x.shadow) x.shadow.blur = Math.max(0, v); }), { min: 0, max: 100 }), el("span", "unit", "pt"));
          this.row(body, "Distance", this.number(sh.distance, (v) => c.setEffects((x) => { if (x.shadow) x.shadow.distance = Math.max(0, v); }), { min: 0, max: 200 }), el("span", "unit", "pt"));
          this.row(body, "Angle", this.number(sh.angle, (v) => c.setEffects((x) => { if (x.shadow) x.shadow.angle = v; }), { min: 0, max: 359 }), el("span", "unit", "°"));
        }
        body.append(this.check("Glow", !!fx.glow, (on) => c.setEffects((x) => { if (on) x.glow = { color: themePaint("accent1", 0, 0.6), radius: 8 }; else delete x.glow; })));
        if (fx.glow) {
          const glow = fx.glow;
          this.row(body, "Glow color", this.swatch(glow.color, (p) => { if (p) c.setEffects((x) => { if (x.glow) x.glow.color = p; }); }));
          this.row(body, "Glow size", this.number(glow.radius, (v) => c.setEffects((x) => { if (x.glow) x.glow.radius = Math.max(0, v); }), { min: 0, max: 100 }), el("span", "unit", "pt"));
        }
        body.append(this.check("Reflection", !!fx.reflection, (on) => c.setEffects((x) => { if (on) x.reflection = { opacity: 0.4, size: 0.4, distance: 2 }; else delete x.reflection; })));
      });
    }
    if (image) {
      this.section("picture", "Picture", (body) => {
        const a = image.adjustments;
        this.row(body, "Brightness", this.slider(Math.round(a.brightness * 100), (v) => c.setImageAdjustments((x) => { x.brightness = v / 100; }), -100, 100));
        this.row(body, "Contrast", this.slider(Math.round(a.contrast * 100), (v) => c.setImageAdjustments((x) => { x.contrast = v / 100; }), -100, 100));
        this.row(body, "Saturation", this.slider(Math.round(a.saturation * 100), (v) => c.setImageAdjustments((x) => { x.saturation = v / 100; }), 0, 200));
        this.row(body, "Transparency", this.slider(Math.round(a.transparency * 100), (v) => c.setImageAdjustments((x) => { x.transparency = v / 100; })));
        body.append(this.check("Sepia", a.sepia, (on) => c.setImageAdjustments((x) => { x.sepia = on; })));
      });
    }
    const media = mediaOf(e);
    if (media) {
      this.section("media", "Playback", (body) => {
        body.append(this.check("Start automatically", media.autoplay, (on) => c.setMedia((m) => { m.autoplay = on; })));
        body.append(this.check("Loop until stopped", media.loop, (on) => c.setMedia((m) => { m.loop = on; })));
        body.append(this.check("Hide while not playing", media.hideWhenNotPlaying, (on) => c.setMedia((m) => { m.hideWhenNotPlaying = on; })));
        this.row(body, "Volume", this.slider(Math.round(media.volume * 100), (v) => c.setMedia((m) => { m.volume = v / 100; })));
      });
    }
  }

  private sizeAndPosition(e: SlideElement) {
    const c = this.c;
    const r = R(e.frame);
    const inches = (v: number) => v / 72;
    this.section("size", "Size", (body) => {
      const set = (w: number | null, h: number | null) => {
        let nw = w ?? r.w, nh = h ?? r.h;
        if (e.lockAspectRatio && r.w > 0 && r.h > 0) { if (w !== null) nh = (nw * r.h) / r.w; else nw = (nh * r.w) / r.h; }
        c.setElementRect(e.id, { ...r, w: Math.max(1, nw), h: Math.max(1, nh) });
      };
      this.row(body, "Height", this.number(inches(r.h), (v) => set(null, v * 72), { min: 0.01, step: 0.05 }), el("span", "unit", "in"));
      this.row(body, "Width", this.number(inches(r.w), (v) => set(v * 72, null), { min: 0.01, step: 0.05 }), el("span", "unit", "in"));
      this.row(body, "Rotation", this.number(e.rotation, (v) => c.setRotation(v), { min: -360, max: 360 }), el("span", "unit", "°"));
      body.append(this.check("Lock aspect ratio", e.lockAspectRatio, (on) => c.changeTargets("Lock Aspect Ratio", (x) => { x.lockAspectRatio = on; })));
    });
    this.section("position", "Position", (body) => {
      this.row(body, "Horizontal", this.number(inches(r.x), (v) => c.setElementRect(e.id, { ...r, x: v * 72 }), { step: 0.05 }), el("span", "unit", "in"));
      this.row(body, "Vertical", this.number(inches(r.y), (v) => c.setElementRect(e.id, { ...r, y: v * 72 }), { step: 0.05 }), el("span", "unit", "in"));
    });
    const alt = el("div", "pane-actions");
    const name = document.createElement("input");
    name.type = "text";
    name.value = e.name;
    name.style.cssText = "flex:1;height:26px;border:1px solid var(--bar-border);border-radius:5px;background:var(--field);padding:0 6px";
    name.addEventListener("change", () => c.rename(e.id, name.value));
    alt.append(el("span", "note", "Name"), name);
    this.root.append(alt);
  }

  private textOptions(e: SlideElement) {
    const c = this.c;
    const body = textOf(e) ?? (tableOf(e) ? tableOf(e)!.rows[0]?.[0]?.text : null);
    if (!body) { this.root.append(el("div", "pane-empty", "This object has no text.")); return; }
    this.section("textbox", "Text Box", (b) => {
      this.row(b, "Vertical align", this.select([["Top", "top"], ["Middle", "middle"], ["Bottom", "bottom"]], body.anchor, (v) => c.setVerticalAnchor(v as typeof body.anchor)));
      this.row(b, "Direction", this.select([["Horizontal", "horizontal"], ["Rotate 90°", "rotated90"], ["Rotate 270°", "rotated270"]], body.direction, (v) => c.setTextDirection(v as typeof body.direction)));
      const fit = el("div", "pane-radio");
      for (const [value, label] of [["none", "Do not Autofit"], ["shrink", "Shrink text on overflow"], ["resizeShape", "Resize shape to fit text"]]) {
        const l = el("label");
        const r = document.createElement("input");
        r.type = "radio";
        r.name = "autofit";
        r.checked = body.autofit === value;
        r.addEventListener("change", () => c.setAutofit(value as typeof body.autofit));
        l.append(r, label);
        fit.append(l);
      }
      b.append(fit);
      for (const side of ["left", "right", "top", "bottom"] as const) {
        this.row(b, `${side[0].toUpperCase() + side.slice(1)} margin`, this.number(body.insets[side], (v) => c.setInsets({ ...body.insets, [side]: Math.max(0, v) }), { min: 0, step: 0.5 }), el("span", "unit", "pt"));
      }
      b.append(this.check("Wrap text in shape", body.wrap, (on) => c.setWrap(on)));
      this.row(b, "Columns", this.number(body.columns, (v) => c.setColumns(v), { min: 1, max: 6 }));
    });
  }

  // MARK: Animation pane

  private animations() {
    const c = this.c;
    const slide = c.currentSlide;
    const actions = el("div", "pane-actions");
    const play = el("button", "primary", "▶ Play All");
    play.addEventListener("click", () => document.dispatchEvent(new CustomEvent("ws-preview-animations")));
    actions.append(play);
    this.root.append(actions);
    if (!slide.animations.length) { this.root.append(el("div", "pane-empty", "Select an object on the slide and add an animation from the Animations tab.")); return; }
    const list = el("div", "pane-list");
    let step = 0;
    slide.animations.forEach((a, i) => {
      if (a.trigger === "onClick" || i === 0) step += a.trigger === "onClick" ? 1 : 0;
      const target = slide.elements.find((e) => e.id === a.elementID) ?? null;
      const item = el("div", "item" + (c.selectedAnimation === a.id ? " selected" : ""));
      const badge = el("span", "badge", a.trigger === "onClick" ? String(step) : "");
      const category = animationCategory(a.effect);
      const name = el("span", "grow");
      name.innerHTML = `<span style="color:${({ entrance: "#2f9d55", emphasis: "#d8a200", exit: "#d64545", motionPath: "#2f6fdb" })[category]}">★</span> ${escape(target?.name ?? "(missing)")}`;
      name.title = `${ANIMATION_TITLES[a.effect]} · ${TRIGGER_TITLES[a.trigger]}`;
      const muted = el("span", "muted", ANIMATION_TITLES[a.effect]);
      const up = el("button", "", "▲"), down = el("button", "", "▼"), remove = el("button", "", "×");
      up.title = "Move Earlier"; down.title = "Move Later"; remove.title = "Remove";
      up.addEventListener("click", (ev) => { ev.stopPropagation(); c.moveAnimation(a.id, -1); });
      down.addEventListener("click", (ev) => { ev.stopPropagation(); c.moveAnimation(a.id, 1); });
      remove.addEventListener("click", (ev) => { ev.stopPropagation(); c.removeAnimation(a.id); });
      item.append(badge, name, muted, up, down, remove);
      item.addEventListener("click", () => c.selectAnimation(a.id));
      list.append(item);
    });
    this.root.append(list);
    const a = c.targetAnimations[0];
    if (a) {
      this.section("timing", "Timing", (body) => {
        this.row(body, "Start", this.select(Object.entries(TRIGGER_TITLES).map(([k, v]) => [v, k]), a.trigger, (v) => c.updateAnimation(a.id, (x) => { x.trigger = v as typeof x.trigger; })));
        this.row(body, "Duration", this.number(a.duration, (v) => c.updateAnimation(a.id, (x) => { x.duration = Math.max(0, v); }), { min: 0, step: 0.25 }), el("span", "unit", "s"));
        this.row(body, "Delay", this.number(a.delay, (v) => c.updateAnimation(a.id, (x) => { x.delay = Math.max(0, v); }), { min: 0, step: 0.25 }), el("span", "unit", "s"));
        this.row(body, "Repeat", this.number(a.repeatCount, (v) => c.updateAnimation(a.id, (x) => { x.repeatCount = Math.max(1, Math.round(v)); }), { min: 1, max: 99 }));
        if (effectHasDirection(a.effect)) this.row(body, "Direction", this.select(DIRECTIONS.map((d) => [DIRECTION_TITLES[d], d]), a.direction, (v) => c.updateAnimation(a.id, (x) => { x.direction = v as typeof x.direction; })));
        if (animationCategory(a.effect) === "emphasis" || animationCategory(a.effect) === "motionPath") {
          this.row(body, "Amount", this.number(a.amount, (v) => c.updateAnimation(a.id, (x) => { x.amount = Math.max(0.1, v); }), { min: 0.1, max: 5, step: 0.1 }));
        }
      });
    }
  }

  // MARK: Selection pane

  private selection() {
    const c = this.c;
    const slide = c.currentSlide;
    const actions = el("div", "pane-actions");
    const showAll = el("button", "", "Show All"), hideAll = el("button", "", "Hide All");
    showAll.addEventListener("click", () => c.changeSlide("Show All", (s) => { for (const e of s.elements) e.hidden = false; }));
    hideAll.addEventListener("click", () => c.changeSlide("Hide All", (s) => { for (const e of s.elements) e.hidden = true; }));
    actions.append(showAll, hideAll);
    this.root.append(actions);
    if (!slide.elements.length) { this.root.append(el("div", "pane-empty", "There are no objects on this slide.")); return; }
    const list = el("div", "pane-list");
    // Top of the list is the front, like PowerPoint.
    [...slide.elements].reverse().forEach((e) => {
      const item = el("div", "item" + (c.selection.includes(e.id) ? " selected" : "") + (e.hidden ? " dimmed" : ""));
      item.draggable = true;
      const kind = el("span", "muted", elementKindName(e, (k) => SHAPE_TITLES[k]));
      const name = el("span", "grow", e.name);
      const eye = el("button") as HTMLButtonElement;
      eye.append(icon(e.hidden ? "eyeOff" : "eye", 15));
      eye.title = e.hidden ? "Show" : "Hide";
      eye.addEventListener("click", (ev) => { ev.stopPropagation(); c.setHidden(e.id, !e.hidden); });
      const lock = el("button") as HTMLButtonElement;
      lock.append(icon("lock", 14));
      lock.style.opacity = e.locked ? "1" : "0.3";
      lock.title = e.locked ? "Unlock" : "Lock";
      lock.addEventListener("click", (ev) => { ev.stopPropagation(); c.changeElements([e.id], e.locked ? "Unlock" : "Lock", (x) => { x.locked = !x.locked; }); });
      item.append(name, kind, lock, eye);
      item.addEventListener("click", (ev) => c.select([e.id], ev.shiftKey || ev.ctrlKey || ev.metaKey));
      item.addEventListener("dblclick", () => {
        const input = document.createElement("input");
        input.className = "rename";
        input.value = e.name;
        name.replaceWith(input);
        input.focus();
        input.select();
        const done = () => { if (input.value.trim() && input.value !== e.name) c.rename(e.id, input.value.trim()); else this.render(); };
        input.addEventListener("blur", done);
        input.addEventListener("keydown", (k) => { if (k.key === "Enter") input.blur(); if (k.key === "Escape") { input.value = e.name; input.blur(); } });
      });
      item.addEventListener("dragstart", (ev) => ev.dataTransfer?.setData("text/x-element", e.id));
      item.addEventListener("dragover", (ev) => ev.preventDefault());
      item.addEventListener("drop", (ev) => {
        const id = ev.dataTransfer?.getData("text/x-element");
        if (!id || id === e.id) return;
        c.moveElement(id, slide.elements.findIndex((x) => x.id === e.id));
      });
      list.append(item);
    });
    this.root.append(list);
  }

  // MARK: Comments

  private comments() {
    const c = this.c;
    const slide = c.currentSlide;
    const box = el("div", "comment-card");
    const text = document.createElement("textarea");
    text.placeholder = "Add a comment";
    const add = el("button", "primary", "Post") as HTMLButtonElement;
    add.style.cssText = "margin-top:6px;height:26px;border:0;border-radius:5px;background:var(--accent);color:var(--accent-text);padding:0 12px";
    add.addEventListener("click", () => { if (text.value.trim()) c.addComment(text.value.trim(), settings().authorName); });
    text.addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) add.click(); });
    box.append(text, add);
    this.root.append(box);
    if (!slide.comments.length) this.root.append(el("div", "pane-empty", "No comments on this slide."));
    slide.comments.forEach((comment, i) => {
      const card = el("div", "comment-card" + (comment.resolved ? " resolved" : ""));
      const who = el("div", "who");
      who.innerHTML = `<b>${i + 1}. ${escape(comment.author)}</b><span>${escape(new Date(comment.date).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" }))}</span>`;
      card.append(who, el("div", "text", comment.text));
      for (const reply of comment.replies) {
        const r = el("div", "reply");
        r.innerHTML = `<div class="who"><b>${escape(reply.author)}</b><span>${escape(new Date(reply.date).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" }))}</span></div>`;
        r.append(el("div", "text", reply.text));
        card.append(r);
      }
      const tools = el("div", "tools");
      const reply = el("button", "", "Reply"), resolve = el("button", "", comment.resolved ? "Reopen" : "Resolve"), remove = el("button", "", "Delete");
      reply.addEventListener("click", () => {
        const t = document.createElement("textarea");
        t.placeholder = "Reply";
        card.append(t);
        t.focus();
        t.addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); if (t.value.trim()) c.replyToComment(comment.id, t.value.trim(), settings().authorName); } });
      });
      resolve.addEventListener("click", () => c.resolveComment(comment.id, !comment.resolved));
      remove.addEventListener("click", () => c.deleteComment(comment.id));
      tools.append(reply, resolve, remove);
      card.append(tools);
      this.root.append(card);
    });
  }
}

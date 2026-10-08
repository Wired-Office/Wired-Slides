import type { MotionDirection, Presentation, Slide, SlideAnimation, SlideElement, UUID } from "../model/types";
import type { Rect } from "../model/core";
import { R, cssColor, mediaOf, midX, midY, textOf } from "../model/core";
import { animationCategory, buildPlan, initiallyHidden, type BuildItem } from "../model/catalog";
import { visibleSlideIndices } from "../model/presentation";
import { drawElement, visualBounds } from "../render/elements";
import { drawSlide, envOf, renderSlide } from "../render/slide";
import { mediaURL } from "../render/paint";
import { openURL, setFullscreen } from "../platform";

export interface ShowOptions {
  presenter?: boolean;
  rehearse?: boolean;
  /** Reading View: in the window, without full screen. */
  windowed?: boolean;
  /** Plays the current slide's animations once, then closes (Preview). */
  previewOnly?: boolean;
  onExit: (result: { timings?: Map<UUID, number>; lastSlide: number }) => void;
}

interface ElementState { node: HTMLElement; e: SlideElement; tx: number; ty: number; scale: number; rotate: number; opacity: number; hidden: boolean }

const ease = "cubic-bezier(0.42, 0, 0.58, 1)";

/** A running slide show, drawn into its own full-window layer. */
export class SlideShow {
  private root: HTMLDivElement;
  private viewport: HTMLDivElement;
  private stage: HTMLDivElement;
  private ink: HTMLCanvasElement;
  private toolbar: HTMLDivElement;
  private blank: HTMLDivElement;
  private laser: HTMLDivElement;
  private order: number[];
  private position = 0;
  private step = 0;
  private steps: BuildItem[][] = [];
  private states = new Map<UUID, ElementState>();
  private current: HTMLDivElement | null = null;
  private running: Animation[] = [];
  private timers: number[] = [];
  private advanceTimer = 0;
  private scale = 1;
  private tool: "none" | "pen" | "highlighter" | "laser" | "eraser" = "none";
  private strokes: { points: [number, number][]; color: string; width: number; alpha: number }[] = [];
  private jump = "";
  private jumpLabel: HTMLDivElement | null = null;
  private cursorTimer = 0;
  private started = performance.now();
  private slideStarted = performance.now();
  private timings = new Map<UUID, number>();
  private ended = false;
  private presenterRoot: HTMLDivElement | null = null;
  private presenterParts: { timer: HTMLElement; clock: HTMLElement; notes: HTMLElement; next: HTMLElement; count: HTMLElement } | null = null;
  private presenterTick = 0;
  private resizeObserver: ResizeObserver;

  constructor(private p: Presentation, start: number, private o: ShowOptions) {
    this.order = visibleSlideIndices(p);
    if (!this.order.length) this.order = [0];
    const visibleStart = this.order.indexOf(start);
    this.position = visibleStart >= 0 ? visibleStart : Math.max(0, this.order.findIndex((i) => i > start));
    if (this.position < 0) this.position = 0;

    this.root = document.createElement("div");
    this.root.className = "show";
    this.root.tabIndex = 0;
    this.viewport = document.createElement("div");
    this.viewport.style.cssText = "position:absolute;inset:0;overflow:hidden";
    this.stage = document.createElement("div");
    this.stage.className = "show-stage";
    this.ink = document.createElement("canvas");
    this.ink.className = "show-ink";
    this.blank = document.createElement("div");
    this.blank.className = "show-blank";
    this.blank.hidden = true;
    this.laser = document.createElement("div");
    this.laser.className = "show-laser";
    this.laser.hidden = true;
    this.laser.style.background = cssColor(p.showSettings.laserColor);
    this.laser.style.color = cssColor(p.showSettings.laserColor);
    this.toolbar = this.buildToolbar();
    this.viewport.append(this.stage, this.ink, this.laser);
    this.root.append(this.viewport, this.blank, this.toolbar);

    if (o.presenter) {
      this.presenterRoot = this.buildPresenter();
      document.body.append(this.presenterRoot);
      this.presenterRoot.querySelector(".current")!.append(this.root);
      this.root.style.position = "absolute";
      this.presenterRoot.focus();
    } else {
      document.body.append(this.root);
      this.root.focus();
    }
    if (!o.windowed) void setFullscreen(true);

    this.resizeObserver = new ResizeObserver(() => this.layout());
    this.resizeObserver.observe(this.viewport);
    const keyTarget = this.presenterRoot ?? this.root;
    keyTarget.addEventListener("keydown", this.keydown);
    this.root.addEventListener("pointerdown", (e) => this.pointerDown(e));
    this.root.addEventListener("pointermove", (e) => this.pointerMove(e));
    this.root.addEventListener("pointerup", () => this.pointerUp());
    this.root.addEventListener("contextmenu", (e) => { e.preventDefault(); this.previous(); });
    this.root.addEventListener("wheel", (e) => { if (Math.abs(e.deltaY) > 20) (e.deltaY > 0 ? this.next() : this.previous()); }, { passive: true });
    this.layout();
    this.show(this.position, false);
    if (this.presenterRoot) this.presenterTick = window.setInterval(() => this.updatePresenter(), 500);
  }

  private get slide(): Slide { return this.p.slides[this.order[this.position]]; }
  private get settings() { return this.p.showSettings; }

  // MARK: Layout

  private layout() {
    const [w, h] = this.p.slideSize;
    const box = this.viewport.getBoundingClientRect();
    this.scale = Math.min(box.width / w, box.height / h) || 1;
    const left = (box.width - w * this.scale) / 2, top = (box.height - h * this.scale) / 2;
    Object.assign(this.stage.style, { width: `${w}px`, height: `${h}px`, transform: `translate(${left}px, ${top}px) scale(${this.scale})` });
    const dpr = window.devicePixelRatio || 1;
    this.ink.width = Math.round(box.width * dpr);
    this.ink.height = Math.round(box.height * dpr);
    this.ink.style.width = `${box.width}px`;
    this.ink.style.height = `${box.height}px`;
    this.redrawInk();
    // Re-render the current slide at the new resolution.
    if (this.current) {
      const built = this.step;
      this.show(this.position, false, built);
    }
  }

  /** Converts a pointer position to slide coordinates. */
  private slidePoint(e: { clientX: number; clientY: number }): [number, number] {
    const rect = this.stage.getBoundingClientRect();
    return [(e.clientX - rect.left) / this.scale, (e.clientY - rect.top) / this.scale];
  }

  // MARK: Building slides

  private buildSlide(index: number, built: boolean | number): { node: HTMLDivElement; states: Map<UUID, ElementState>; steps: BuildItem[][] } {
    const slide = this.p.slides[index];
    const [w, h] = this.p.slideSize;
    const steps = buildPlan(slide, !this.settings.showWithoutAnimation);
    const animated = new Set(steps.flat().map((i) => i.animation.elementID));
    const media = new Set(slide.elements.filter((e) => mediaOf(e)).map((e) => e.id));
    const node = document.createElement("div");
    node.className = "show-slide";
    node.style.width = `${w}px`;
    node.style.height = `${h}px`;
    const dpr = window.devicePixelRatio || 1;
    const pixel = Math.max(1, this.scale * dpr);
    const base = renderSlide(slide, index + 1, this.p, Math.round(w * pixel), { skip: new Set([...animated, ...media]) });
    base.style.cssText = `left:0;top:0;width:${w}px;height:${h}px`;
    node.append(base);
    const states = new Map<UUID, ElementState>();
    const env = envOf(this.p);
    for (const e of slide.elements) {
      if (!animated.has(e.id) && !media.has(e.id)) continue;
      const wrapper = document.createElement("div");
      const vb = visualBounds(e);
      wrapper.style.cssText = `position:absolute;left:${vb.x}px;top:${vb.y}px;width:${vb.w}px;height:${vb.h}px;transform-origin:${midX(R(e.frame)) - vb.x}px ${midY(R(e.frame)) - vb.y}px`;
      if (media.has(e.id)) this.mediaNode(e, wrapper, vb);
      else {
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(vb.w * pixel));
        canvas.height = Math.max(1, Math.round(vb.h * pixel));
        canvas.style.cssText = `left:0;top:0;width:${vb.w}px;height:${vb.h}px`;
        const ctx = canvas.getContext("2d")!;
        ctx.scale(pixel, pixel);
        ctx.translate(-vb.x, -vb.y);
        drawElement(ctx, e, env, { slideNumber: index + 1 });
        wrapper.append(canvas);
      }
      node.append(wrapper);
      states.set(e.id, { node: wrapper, e, tx: 0, ty: 0, scale: 1, rotate: 0, opacity: 1, hidden: false });
    }
    // Elements whose first effect is an entrance start hidden.
    for (const id of initiallyHidden(steps)) { const s = states.get(id); if (s) { s.hidden = true; s.node.style.visibility = "hidden"; } }
    const target = built === true ? steps.length - 1 : built === false ? 0 : built;
    for (let i = 1; i <= target && i < steps.length; i++) for (const item of steps[i]) this.applyFinal(item.animation, states);
    return { node, states, steps };
  }

  private mediaNode(e: SlideElement, wrapper: HTMLElement, vb: Rect) {
    const m = mediaOf(e)!;
    const item = this.p.media[m.mediaID];
    if (!item) return;
    const r = R(e.frame);
    const el = document.createElement(m.kind === "video" ? "video" : "audio");
    el.src = mediaURL(m.mediaID, item);
    el.loop = m.loop;
    el.volume = Math.max(0, Math.min(1, m.volume));
    el.preload = "auto";
    if (m.kind === "video") {
      const video = el as HTMLVideoElement;
      if (m.posterID && this.p.media[m.posterID]) video.poster = mediaURL(m.posterID, this.p.media[m.posterID]);
      video.style.cssText = `left:${r.x - vb.x}px;top:${r.y - vb.y}px;width:${r.w}px;height:${r.h}px;object-fit:contain;background:#000`;
      video.playsInline = true;
    } else {
      // Audio shows its icon (or nothing when it should hide).
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.round(vb.w * 2));
      canvas.height = Math.max(1, Math.round(vb.h * 2));
      canvas.style.cssText = `left:0;top:0;width:${vb.w}px;height:${vb.h}px`;
      const ctx = canvas.getContext("2d")!;
      ctx.scale(2, 2);
      ctx.translate(-vb.x, -vb.y);
      drawElement(ctx, e, envOf(this.p));
      if (!m.hideWhenNotPlaying) wrapper.append(canvas);
    }
    wrapper.append(el);
    wrapper.dataset.media = e.id;
    if (m.hideWhenNotPlaying && !m.autoplay) wrapper.style.opacity = "0";
    el.addEventListener("play", () => { if (m.hideWhenNotPlaying) wrapper.style.opacity = "1"; });
    el.addEventListener("ended", () => { if (m.hideWhenNotPlaying) wrapper.style.opacity = "0"; });
  }

  private startAutoplay() {
    for (const e of this.slide.elements) {
      const m = mediaOf(e);
      if (m?.autoplay) (this.current?.querySelector(`[data-media="${e.id}"] video, [data-media="${e.id}"] audio`) as HTMLMediaElement | null)?.play().catch(() => {});
    }
  }

  private stopMedia(node: HTMLElement | null) {
    node?.querySelectorAll<HTMLMediaElement>("video, audio").forEach((m) => m.pause());
  }

  // MARK: Navigation

  private show(position: number, transition: boolean, built: boolean | number = false) {
    this.finishAnimations();
    clearTimeout(this.advanceTimer);
    const index = this.order[position];
    const { node, states, steps } = this.buildSlide(index, built);
    const old = this.current;
    this.stopMedia(old);
    this.position = position;
    this.steps = steps;
    this.states = states;
    this.step = built === true ? steps.length - 1 : built === false ? 0 : Math.min(built, steps.length - 1);
    this.current = node;
    this.stage.append(node);
    this.strokes = [];
    this.redrawInk();
    this.slideStarted = performance.now();
    const t = this.p.slides[index].transition;
    const finish = () => {
      if (old && old !== node) old.remove();
      this.startAutoplay();
      // Step 0 runs as soon as the slide appears.
      if (this.step === 0) this.runStep(0);
      else this.scheduleAdvance();
    };
    if (transition && old && t.kind !== "none" && !this.settings.showWithoutAnimation) this.transition(old, node, finish);
    else finish();
    this.updateToolbar();
    this.updatePresenter();
  }

  next() {
    if (this.ended) { this.exit(); return; }
    if (this.running.length) { this.finishAnimations(); return; }
    if (this.step < this.steps.length - 1) { this.step++; this.runStep(this.step); return; }
    this.recordTiming();
    if (this.o.previewOnly) { this.exit(); return; }
    if (this.position < this.order.length - 1) this.show(this.position + 1, true);
    else if (this.settings.loopUntilEscape && !this.o.rehearse) this.show(0, true);
    else this.showEnd();
  }

  previous() {
    if (this.ended) { this.ended = false; this.blank.hidden = true; this.show(this.position, false, true); return; }
    if (this.running.length) this.finishAnimations();
    if (this.step > 0) { this.show(this.position, false, this.step - 1); return; }
    if (this.position > 0) this.show(this.position - 1, false, true);
  }

  goTo(position: number) {
    if (position < 0 || position >= this.order.length) return;
    this.ended = false;
    this.blank.hidden = true;
    this.show(position, true);
  }

  private showEnd() {
    this.ended = true;
    this.blank.hidden = false;
    this.blank.style.background = "#000";
    this.blank.innerHTML = '<div style="color:#bbb;font:16px system-ui,sans-serif;position:absolute;top:24px;left:0;right:0;text-align:center">End of slide show, click to exit.</div>';
    clearTimeout(this.advanceTimer);
  }

  /** Advances on the slide's timing once its last step has finished. */
  private scheduleAdvance() {
    clearTimeout(this.advanceTimer);
    if (this.step < this.steps.length - 1) return;
    const t = this.slide.transition;
    if (!this.settings.useTimings || t.advanceAfter === undefined || this.o.rehearse) return;
    const elapsed = (performance.now() - this.slideStarted) / 1000;
    this.advanceTimer = window.setTimeout(() => this.next(), Math.max(0, t.advanceAfter - elapsed) * 1000);
  }

  private recordTiming() {
    if (this.o.rehearse) this.timings.set(this.slide.id, Math.round((performance.now() - this.slideStarted) / 100) / 10);
  }

  // MARK: Animations

  private runStep(index: number) {
    const items = this.steps[index] ?? [];
    let longest = 0;
    for (const item of items) {
      longest = Math.max(longest, item.end);
      const timer = window.setTimeout(() => this.animate(item.animation), item.start * 1000);
      this.timers.push(timer);
    }
    const done = window.setTimeout(() => { this.timers = []; this.scheduleAdvance(); }, longest * 1000 + 30);
    this.timers.push(done);
    // A step with no On Click items before the next one runs the following After/With items automatically.
    if (!items.length) this.scheduleAdvance();
  }

  finishAnimations() {
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
    // Apply the end state of everything in the current step that hasn't finished.
    for (const a of this.running) a.finish();
    this.running = [];
    const items = this.steps[this.step] ?? [];
    for (const item of items) this.applyFinal(item.animation, this.states);
    this.scheduleAdvance();
  }

  private transformOf(s: ElementState, extra = "") {
    return `translate(${s.tx}px, ${s.ty}px) rotate(${s.rotate}deg) scale(${s.scale}) ${extra}`.trim();
  }

  private offscreen(direction: MotionDirection, e: SlideElement): [number, number] {
    const r = R(e.frame), [w, h] = this.p.slideSize;
    switch (direction) {
      case "fromBottom": return [0, h - r.y + 20];
      case "fromTop": return [0, -(r.y + r.h + 20)];
      case "fromLeft": return [-(r.x + r.w + 20), 0];
      case "fromRight": return [w - r.x + 20, 0];
    }
  }

  private pathOffset(a: SlideAnimation): [number, number][] {
    const d = 100 * a.amount;
    const dir: Record<MotionDirection, [number, number]> = { fromBottom: [0, -d], fromTop: [0, d], fromLeft: [d, 0], fromRight: [-d, 0] };
    const [dx, dy] = dir[a.direction];
    switch (a.effect) {
      case "pathLine": return [[0, 0], [dx, dy]];
      case "pathArc": return [[0, 0], [dx / 2 - dy / 3, dy / 2 - dx / 3], [dx, dy]];
      case "pathCircle": return Array.from({ length: 13 }, (_, i) => { const t = (i / 12) * Math.PI * 2; return [Math.sin(t) * d * 0.6, (1 - Math.cos(t)) * d * 0.6 * -1] as [number, number]; });
      default: return Array.from({ length: 7 }, (_, i) => [(i * d) / 6, i % 2 ? -d / 5 : 0] as [number, number]);
    }
  }

  /** Sets an element's state to where an animation leaves it. */
  private applyFinal(a: SlideAnimation, states: Map<UUID, ElementState>) {
    const s = states.get(a.elementID);
    if (!s) return;
    const category = animationCategory(a.effect);
    if (category === "entrance") { s.hidden = false; s.opacity = 1; }
    else if (category === "exit") s.hidden = true;
    else if (category === "emphasis") {
      if (a.effect === "growShrink") s.scale *= 1.5 * a.amount;
      if (a.effect === "transparency") s.opacity = 0.5;
      if (a.effect === "spin") s.rotate += 360 * a.amount;
    } else {
      const path = this.pathOffset(a);
      const [dx, dy] = path[path.length - 1];
      s.tx += dx;
      s.ty += dy;
    }
    s.node.style.visibility = s.hidden ? "hidden" : "visible";
    s.node.style.opacity = String(s.opacity);
    s.node.style.transform = this.transformOf(s);
  }

  private animate(a: SlideAnimation) {
    const s = this.states.get(a.elementID);
    if (!s) return;
    const node = s.node, e = s.e;
    const duration = Math.max(a.duration * 1000, 1);
    const base = this.transformOf(s);
    const category = animationCategory(a.effect);
    let frames: Keyframe[] = [];
    const opts: KeyframeAnimationOptions = { duration, iterations: Math.max(1, a.repeatCount), easing: ease, fill: "both" };
    const [ox, oy] = this.offscreen(a.direction, e);
    const wipe = (from: string): Keyframe[] => [{ clipPath: from }, { clipPath: "inset(0 0 0 0)" }];
    const wipeFrom: Record<MotionDirection, string> = { fromLeft: "inset(0 100% 0 0)", fromRight: "inset(0 0 0 100%)", fromTop: "inset(0 0 100% 0)", fromBottom: "inset(100% 0 0 0)" };
    switch (a.effect) {
      case "appear": frames = [{ opacity: 0 }, { opacity: s.opacity }]; opts.duration = 1; break;
      case "fadeIn": frames = [{ opacity: 0 }, { opacity: s.opacity }]; break;
      case "flyIn": frames = [{ transform: `translate(${ox}px, ${oy}px) ${base}` }, { transform: base }]; break;
      case "floatIn": frames = [{ opacity: 0, transform: `translateY(${a.direction === "fromTop" ? -40 : 40}px) ${base}` }, { opacity: s.opacity, transform: base }]; break;
      case "wipeIn": frames = wipe(wipeFrom[a.direction]); break;
      case "splitIn": frames = wipe("inset(0 50% 0 50%)"); break;
      case "zoomIn": frames = [{ opacity: 0, transform: `${base} scale(0.3)` }, { opacity: s.opacity, transform: base }]; break;
      case "growTurnIn": frames = [{ opacity: 0, transform: `${base} rotate(-90deg) scale(0.2)` }, { opacity: s.opacity, transform: base }]; break;
      case "swivelIn": frames = [{ transform: `perspective(800px) ${base} rotateY(90deg)` }, { transform: `perspective(800px) ${base} rotateY(0deg)` }]; break;
      case "bounceIn": frames = [
        { transform: `translateY(-300px) ${base}`, offset: 0 }, { transform: `translateY(0) ${base}`, offset: 0.5 }, { transform: `translateY(-60px) ${base}`, offset: 0.7 },
        { transform: `translateY(0) ${base}`, offset: 0.85 }, { transform: `translateY(-15px) ${base}`, offset: 0.93 }, { transform: base, offset: 1 },
      ]; opts.easing = "ease-in"; break;
      case "spinIn": frames = [{ opacity: 0, transform: `${base} rotate(-360deg) scale(0)` }, { opacity: s.opacity, transform: base }]; break;
      case "pulse": frames = [{ transform: base }, { transform: `${base} scale(1.1)` }, { transform: base }]; break;
      case "spin": frames = [{ transform: base }, { transform: `${base} rotate(${360 * a.amount}deg)` }]; break;
      case "growShrink": frames = [{ transform: base }, { transform: `${base} scale(${1.5 * a.amount})` }]; break;
      case "teeter": frames = [0, 5, -5, 5, -5, 0].map((d) => ({ transform: `${base} rotate(${d}deg)` })); break;
      case "transparency": frames = [{ opacity: s.opacity }, { opacity: 0.5 }]; break;
      case "colorPulse": frames = [{ filter: "brightness(1)" }, { filter: "brightness(1.6) saturate(1.4)" }, { filter: "brightness(1)" }]; break;
      case "wave": frames = [{ transform: base }, { transform: `translateY(-12px) ${base} skewX(-6deg)` }, { transform: `translateY(6px) ${base} skewX(4deg)` }, { transform: base }]; break;
      case "disappear": frames = [{ opacity: s.opacity }, { opacity: 0 }]; opts.duration = 1; break;
      case "fadeOut": frames = [{ opacity: s.opacity }, { opacity: 0 }]; break;
      case "flyOut": { const [fx, fy] = this.offscreen(a.direction === "fromBottom" ? "fromBottom" : a.direction, e); frames = [{ transform: base }, { transform: `translate(${fx}px, ${fy}px) ${base}` }]; break; }
      case "floatOut": frames = [{ opacity: s.opacity, transform: base }, { opacity: 0, transform: `translateY(${a.direction === "fromTop" ? -40 : 40}px) ${base}` }]; break;
      case "wipeOut": frames = [...wipe(wipeFrom[a.direction])].reverse(); break;
      case "splitOut": frames = [...wipe("inset(0 50% 0 50%)")].reverse(); break;
      case "zoomOut": frames = [{ opacity: s.opacity, transform: base }, { opacity: 0, transform: `${base} scale(0.3)` }]; break;
      case "shrinkTurnOut": frames = [{ opacity: s.opacity, transform: base }, { opacity: 0, transform: `${base} rotate(90deg) scale(0.2)` }]; break;
      case "swivelOut": frames = [{ transform: `perspective(800px) ${base} rotateY(0deg)` }, { transform: `perspective(800px) ${base} rotateY(90deg)` }]; break;
      case "bounceOut": frames = [{ transform: base }, { transform: `translateY(-40px) ${base}` }, { opacity: 0, transform: `translateY(400px) ${base}` }]; break;
      default: {
        const path = this.pathOffset(a);
        frames = path.map(([dx, dy]) => ({ transform: `translate(${dx}px, ${dy}px) ${base}` }));
      }
    }
    if (category === "entrance") { s.node.style.visibility = "visible"; s.hidden = false; }
    const anim = node.animate(frames, opts);
    this.running.push(anim);
    anim.finished.then(() => {
      this.running = this.running.filter((x) => x !== anim);
      this.applyFinal(a, this.states);
      anim.cancel();
      if (mediaOf(e) && category === "entrance") (node.querySelector("video, audio") as HTMLMediaElement | null)?.play().catch(() => {});
    }).catch(() => {});
  }

  // MARK: Transitions

  private transition(old: HTMLDivElement, next: HTMLDivElement, done: () => void) {
    const t = this.slide.transition;
    const [w, h] = this.p.slideSize;
    const duration = Math.max(t.duration, 0.05) * 1000;
    const dirs: Record<MotionDirection, [number, number]> = { fromRight: [w, 0], fromLeft: [-w, 0], fromBottom: [0, h], fromTop: [0, -h] };
    const [dx, dy] = dirs[t.direction];
    const animations: Animation[] = [];
    const run = (el: HTMLElement, frames: Keyframe[], o: KeyframeAnimationOptions = {}) => animations.push(el.animate(frames, { duration, easing: ease, fill: "both", ...o }));
    const wipeFrom: Record<MotionDirection, string> = { fromLeft: "inset(0 100% 0 0)", fromRight: "inset(0 0 0 100%)", fromTop: "inset(0 0 100% 0)", fromBottom: "inset(100% 0 0 0)" };
    switch (t.kind) {
      case "fade": run(next, [{ opacity: 0 }, { opacity: 1 }]); break;
      case "dissolve": run(next, [{ opacity: 0 }, { opacity: 1 }], { easing: "steps(12)" }); break;
      case "fadeThroughBlack":
        run(old, [{ opacity: 1 }, { opacity: 0 }], { duration: duration / 2 });
        run(next, [{ opacity: 0 }, { opacity: 1 }], { duration: duration / 2, delay: duration / 2 });
        break;
      case "push":
        run(old, [{ transform: "translate(0,0)" }, { transform: `translate(${-dx}px, ${-dy}px)` }]);
        run(next, [{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "translate(0,0)" }]);
        break;
      case "cover": run(next, [{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "translate(0,0)" }]); break;
      case "reveal": case "uncover":
        this.stage.insertBefore(next, old);
        run(old, [{ transform: "translate(0,0)", opacity: 1 }, { transform: `translate(${-dx}px, ${-dy}px)`, opacity: t.kind === "reveal" ? 0 : 1 }]);
        break;
      case "wipe": run(next, [{ clipPath: wipeFrom[t.direction] }, { clipPath: "inset(0 0 0 0)" }]); break;
      case "split": run(next, [{ clipPath: "inset(0 50% 0 50%)" }, { clipPath: "inset(0 0 0 0)" }]); break;
      case "zoom": run(next, [{ opacity: 0, transform: "scale(0.3)" }, { opacity: 1, transform: "scale(1)" }]); break;
      case "circle": run(next, [{ clipPath: "circle(0% at 50% 50%)" }, { clipPath: "circle(75% at 50% 50%)" }]); break;
      case "blinds": run(next, [{ clipPath: "inset(0 0 100% 0)" }, { clipPath: "inset(0 0 0 0)" }], { easing: "steps(8)" }); break;
      case "flip": case "cube": {
        const axis = t.direction === "fromTop" || t.direction === "fromBottom" ? "X" : "Y";
        const sign = t.direction === "fromLeft" || t.direction === "fromTop" ? -1 : 1;
        const persp = "perspective(1800px)";
        const z = t.kind === "cube" ? ` translateZ(${-(axis === "Y" ? w : h) / 2}px)` : "";
        const zBack = t.kind === "cube" ? ` translateZ(${(axis === "Y" ? w : h) / 2}px)` : "";
        run(old, [{ transform: `${persp}${z} rotate${axis}(0deg)${zBack}` }, { transform: `${persp}${z} rotate${axis}(${-90 * sign}deg)${zBack}` }], { duration: t.kind === "cube" ? duration : duration / 2, easing: "ease-in" });
        run(next, [{ transform: `${persp}${z} rotate${axis}(${90 * sign}deg)${zBack}` }, { transform: `${persp}${z} rotate${axis}(0deg)${zBack}` }], t.kind === "cube" ? {} : { duration: duration / 2, delay: duration / 2, easing: "ease-out" });
        break;
      }
      case "morph": this.morph(old, next, duration, animations); break;
      default: run(next, [{ opacity: 0 }, { opacity: 1 }]);
    }
    this.running.push(...animations);
    Promise.all(animations.map((a) => a.finished)).then(() => {
      this.running = this.running.filter((a) => !animations.includes(a));
      for (const a of animations) a.cancel();
      done();
    }).catch(() => done());
  }

  /** Morph: objects with the same name move and resize to their new place while the slides crossfade. */
  private morph(old: HTMLDivElement, next: HTMLDivElement, duration: number, animations: Animation[]) {
    const previous = this.p.slides[this.order[this.position - 1] ?? this.order[this.position]];
    const current = this.slide;
    const env = envOf(this.p);
    const dpr = window.devicePixelRatio || 1;
    const matches = current.elements.flatMap((e) => {
      const before = previous.elements.find((x) => x.id === e.id) ?? previous.elements.find((x) => x.name === e.name && !x.name.startsWith("Content Placeholder"));
      return before ? [[before, e] as const] : [];
    });
    const layer = document.createElement("div");
    layer.style.cssText = "position:absolute;inset:0;pointer-events:none";
    for (const [before, after] of matches) {
      const a = R(before.frame), b = R(after.frame);
      const vb = visualBounds(after);
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.round(vb.w * this.scale * dpr));
      canvas.height = Math.max(1, Math.round(vb.h * this.scale * dpr));
      canvas.style.cssText = `position:absolute;left:${vb.x}px;top:${vb.y}px;width:${vb.w}px;height:${vb.h}px;transform-origin:${midX(b) - vb.x}px ${midY(b) - vb.y}px`;
      const ctx = canvas.getContext("2d")!;
      ctx.scale(this.scale * dpr, this.scale * dpr);
      ctx.translate(-vb.x, -vb.y);
      drawElement(ctx, after, env, { slideNumber: this.order[this.position] + 1 });
      layer.append(canvas);
      const sx = b.w ? a.w / b.w : 1, sy = b.h ? a.h / b.h : 1;
      animations.push(canvas.animate([
        { transform: `translate(${midX(a) - midX(b)}px, ${midY(a) - midY(b)}px) rotate(${before.rotation - after.rotation}deg) scale(${sx}, ${sy})` },
        { transform: "none" },
      ], { duration, easing: ease, fill: "both" }));
    }
    // The new slide (without the moving objects) fades in under them.
    const skip = new Set(matches.map(([, after]) => after.id));
    const [w, h] = this.p.slideSize;
    const backdrop = document.createElement("canvas");
    backdrop.width = Math.round(w * this.scale * dpr);
    backdrop.height = Math.round(h * this.scale * dpr);
    backdrop.style.cssText = `position:absolute;left:0;top:0;width:${w}px;height:${h}px`;
    const bctx = backdrop.getContext("2d")!;
    bctx.scale(this.scale * dpr, this.scale * dpr);
    drawSlide(bctx, current, this.order[this.position] + 1, this.p, { skip });
    const wrapper = document.createElement("div");
    wrapper.style.cssText = "position:absolute;inset:0";
    wrapper.append(backdrop, layer);
    this.stage.append(wrapper);
    next.style.opacity = "0";
    animations.push(wrapper.animate([{ opacity: 0 }, { opacity: 1 }], { duration: duration * 0.6, easing: ease, fill: "both" }));
    animations.push(old.animate([{ opacity: 1 }, { opacity: 0 }], { duration, easing: ease, fill: "both" }));
    Promise.all(animations.map((a) => a.finished)).then(() => { next.style.opacity = ""; wrapper.remove(); }).catch(() => { next.style.opacity = ""; wrapper.remove(); });
  }

  // MARK: Input

  private keydown = (e: KeyboardEvent) => {
    const key = e.key;
    this.showCursor();
    if (/^[0-9]$/.test(key)) { this.jump += key; this.showJump(); e.preventDefault(); return; }
    if (key === "Enter" && this.jump) { this.goTo(Number(this.jump) - 1 >= 0 ? this.order.indexOf(Number(this.jump) - 1) : 0); this.jump = ""; this.showJump(); e.preventDefault(); return; }
    this.jump = "";
    this.showJump();
    const ctrl = e.ctrlKey || e.metaKey;
    switch (key) {
      case "Escape": case "-":
        if (this.tool !== "none") { this.setTool("none"); break; }
        this.exit();
        break;
      case " ": case "ArrowRight": case "ArrowDown": case "PageDown": case "Enter": case "n": case "N": this.next(); break;
      case "ArrowLeft": case "ArrowUp": case "PageUp": case "Backspace": this.previous(); break;
      case "Home": this.goTo(0); break;
      case "End": this.goTo(this.order.length - 1); break;
      case "b": case "B": case ".": this.toggleBlank("#000"); break;
      case "w": case "W": case ",": this.toggleBlank("#fff"); break;
      case "g": case "G": this.toggleGrid(); break;
      case "p": case "P": if (ctrl) this.setTool(this.tool === "pen" ? "none" : "pen"); else this.previous(); break;
      case "l": case "L": this.setTool(this.tool === "laser" ? "none" : "laser"); break;
      case "i": case "I": if (ctrl) this.setTool(this.tool === "highlighter" ? "none" : "highlighter"); break;
      case "e": case "E": if (ctrl) this.setTool("eraser"); else { this.strokes = []; this.redrawInk(); } break;
      case "a": case "A": if (ctrl) this.setTool("none"); break;
      default: return;
    }
    e.preventDefault();
    e.stopPropagation();
  };

  private toggleBlank(color: string) {
    if (!this.blank.hidden && !this.ended && this.blank.style.background === (color === "#000" ? "rgb(0, 0, 0)" : "rgb(255, 255, 255)")) { this.blank.hidden = true; return; }
    this.blank.innerHTML = "";
    this.blank.style.background = color;
    this.blank.hidden = false;
  }

  private showJump() {
    if (!this.jump) { this.jumpLabel?.remove(); this.jumpLabel = null; return; }
    if (!this.jumpLabel) { this.jumpLabel = document.createElement("div"); this.jumpLabel.className = "show-jump"; this.root.append(this.jumpLabel); }
    this.jumpLabel.textContent = `Go to slide ${this.jump}`;
  }

  private pointerDown(e: PointerEvent) {
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest(".show-toolbar, .show-grid")) return;
    if (!this.blank.hidden && !this.ended) { this.blank.hidden = true; return; }
    if (this.tool === "pen" || this.tool === "highlighter") {
      const highlighter = this.tool === "highlighter";
      this.strokes.push({ points: [this.slidePoint(e)], color: highlighter ? "#ffe600" : cssColor(this.settings.penColor), width: highlighter ? 18 : 3, alpha: highlighter ? 0.45 : 1 });
      this.root.setPointerCapture(e.pointerId);
      return;
    }
    if (this.tool === "eraser") { this.erase(this.slidePoint(e)); return; }
    if (this.tool === "laser") return;
    // Media and actions respond to clicks; otherwise a click advances.
    const p = this.slidePoint(e);
    const elements = this.slide.elements;
    for (let i = elements.length - 1; i >= 0; i--) {
      const el = elements[i];
      const r = R(el.frame);
      if (p[0] < r.x || p[0] > r.x + r.w || p[1] < r.y || p[1] > r.y + r.h || el.hidden) continue;
      if (mediaOf(el)) {
        const m = this.current?.querySelector(`[data-media="${el.id}"] video, [data-media="${el.id}"] audio`) as HTMLMediaElement | null;
        if (m) { if (m.paused) m.play().catch(() => {}); else m.pause(); return; }
      }
      if (el.action) { this.runAction(el); return; }
      const link = textOf(el)?.paragraphs.flatMap((x) => x.runs).find((r) => r.style.link)?.style.link;
      if (link) { this.openLink(link); return; }
    }
    this.next();
  }

  private runAction(e: SlideElement) {
    const a = e.action!;
    if ("url" in a) this.openLink(a.url._0);
    else if ("slide" in a) { const index = this.p.slides.findIndex((s) => s.id === a.slide._0); const pos = this.order.indexOf(index); if (pos >= 0) this.goTo(pos); }
    else if ("nextSlide" in a) this.goTo(Math.min(this.position + 1, this.order.length - 1));
    else if ("previousSlide" in a) this.goTo(Math.max(this.position - 1, 0));
    else if ("firstSlide" in a) this.goTo(0);
    else if ("lastSlide" in a) this.goTo(this.order.length - 1);
    else this.exit();
  }

  private openLink(url: string) {
    const m = /^#slide(\d+)$/.exec(url);
    if (m) { const pos = this.order.indexOf(Number(m[1]) - 1); if (pos >= 0) this.goTo(pos); return; }
    void openURL(url);
  }

  private pointerMove(e: PointerEvent) {
    this.showCursor();
    if (this.tool === "laser") {
      const box = this.viewport.getBoundingClientRect();
      this.laser.hidden = false;
      this.laser.style.left = `${e.clientX - box.left}px`;
      this.laser.style.top = `${e.clientY - box.top}px`;
    }
    const stroke = this.strokes[this.strokes.length - 1];
    if (stroke && this.root.hasPointerCapture(e.pointerId)) { stroke.points.push(this.slidePoint(e)); this.redrawInk(); }
    if (this.tool === "eraser" && e.buttons) this.erase(this.slidePoint(e));
  }

  private pointerUp() {}

  private erase(p: [number, number]) {
    const before = this.strokes.length;
    this.strokes = this.strokes.filter((s) => !s.points.some(([x, y]) => Math.hypot(x - p[0], y - p[1]) < 12));
    if (this.strokes.length !== before) this.redrawInk();
  }

  private redrawInk() {
    const ctx = this.ink.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.ink.width, this.ink.height);
    const stage = this.stage.getBoundingClientRect(), box = this.viewport.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr * this.scale, 0, 0, dpr * this.scale, (stage.left - box.left) * dpr, (stage.top - box.top) * dpr);
    for (const s of this.strokes) {
      ctx.globalAlpha = s.alpha;
      ctx.strokeStyle = s.color;
      ctx.lineWidth = s.width;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      s.points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  private setTool(tool: SlideShow["tool"]) {
    this.tool = tool;
    this.laser.hidden = tool !== "laser";
    this.root.style.cursor = tool === "pen" || tool === "highlighter" ? "crosshair" : tool === "eraser" ? "cell" : tool === "laser" ? "none" : "";
    this.updateToolbar();
  }

  private showCursor() {
    this.root.classList.add("cursor");
    clearTimeout(this.cursorTimer);
    this.cursorTimer = window.setTimeout(() => { if (this.tool === "none") this.root.classList.remove("cursor"); }, 2500);
  }

  // MARK: Chrome

  private buildToolbar(): HTMLDivElement {
    const bar = document.createElement("div");
    bar.className = "show-toolbar";
    const add = (label: string, title: string, action: () => void, tool?: SlideShow["tool"]) => {
      const b = document.createElement("button");
      b.textContent = label;
      b.title = title;
      if (tool) b.dataset.tool = tool;
      b.addEventListener("click", (e) => { e.stopPropagation(); action(); });
      bar.append(b);
    };
    add("◀", "Previous", () => this.previous());
    add("▶", "Next", () => this.next());
    add("✎", "Pen (Ctrl+P)", () => this.setTool(this.tool === "pen" ? "none" : "pen"), "pen");
    add("▬", "Highlighter (Ctrl+I)", () => this.setTool(this.tool === "highlighter" ? "none" : "highlighter"), "highlighter");
    add("●", "Laser Pointer (L)", () => this.setTool(this.tool === "laser" ? "none" : "laser"), "laser");
    add("⌫", "Eraser (Ctrl+E); E erases all", () => this.setTool(this.tool === "eraser" ? "none" : "eraser"), "eraser");
    add("▦", "See All Slides (G)", () => this.toggleGrid());
    add("■", "Black Screen (B)", () => this.toggleBlank("#000"));
    add("✕", "End Show (Esc)", () => this.exit());
    const count = document.createElement("span");
    count.className = "count";
    bar.append(count);
    return bar;
  }

  private updateToolbar() {
    this.toolbar.querySelectorAll<HTMLElement>("[data-tool]").forEach((b) => b.classList.toggle("on", b.dataset.tool === this.tool));
    const count = this.toolbar.querySelector(".count");
    if (count) count.textContent = `${this.order[this.position] + 1} / ${this.p.slides.length}`;
  }

  private toggleGrid() {
    const existing = this.root.querySelector(".show-grid");
    if (existing) { existing.remove(); return; }
    const grid = document.createElement("div");
    grid.className = "show-grid";
    this.order.forEach((index, pos) => {
      const canvas = renderSlide(this.p.slides[index], index + 1, this.p, 360);
      canvas.style.width = "220px";
      canvas.title = `Slide ${index + 1}`;
      canvas.addEventListener("click", (e) => { e.stopPropagation(); grid.remove(); this.goTo(pos); });
      grid.append(canvas);
    });
    this.root.append(grid);
  }

  private buildPresenter(): HTMLDivElement {
    const root = document.createElement("div");
    root.className = "presenter";
    root.tabIndex = 0;
    root.innerHTML = `
      <div class="top"><span class="timer">0:00</span><button data-a="pause">Pause</button><button data-a="reset">Reset</button><span class="clock"></span><span class="spacer"></span><button data-a="swap">Hide Presenter View</button><button data-a="end">End Show</button></div>
      <div class="current"></div>
      <div class="side"><div class="label">Next</div><div class="next"></div><div class="label">Notes</div><div class="notes"></div></div>
      <div class="bottom"><button data-a="prev">◀ Previous</button><button data-a="next">Next ▶</button><span class="count"></span><span style="flex:1"></span><button data-a="pen">Pen</button><button data-a="laser">Laser</button><button data-a="grid">All Slides</button><button data-a="black">Black Screen</button></div>`;
    this.presenterParts = {
      timer: root.querySelector(".timer")!, clock: root.querySelector(".clock")!, notes: root.querySelector(".notes")!,
      next: root.querySelector(".next")!, count: root.querySelector(".count")!,
    };
    let paused = 0, pausedAt = 0;
    root.addEventListener("click", (e) => {
      const a = (e.target as HTMLElement).closest<HTMLElement>("[data-a]")?.dataset.a;
      switch (a) {
        case "prev": this.previous(); break;
        case "next": this.next(); break;
        case "end": this.exit(); break;
        case "pen": this.setTool(this.tool === "pen" ? "none" : "pen"); break;
        case "laser": this.setTool(this.tool === "laser" ? "none" : "laser"); break;
        case "grid": this.toggleGrid(); break;
        case "black": this.toggleBlank("#000"); break;
        case "reset": this.started = performance.now(); paused = 0; break;
        case "pause":
          if (pausedAt) { paused += performance.now() - pausedAt; pausedAt = 0; (e.target as HTMLElement).textContent = "Pause"; }
          else { pausedAt = performance.now(); (e.target as HTMLElement).textContent = "Resume"; }
          break;
        case "swap": {
          // Show only the slide, full window.
          root.querySelector(".current")!.removeChild(this.root);
          document.body.append(this.root);
          this.root.style.position = "";
          root.remove();
          this.presenterRoot = null;
          clearInterval(this.presenterTick);
          this.root.addEventListener("keydown", this.keydown);
          this.root.focus();
          this.layout();
          break;
        }
      }
    });
    this.elapsed = () => (pausedAt ? pausedAt : performance.now()) - this.started - paused;
    return root;
  }

  private elapsed = () => performance.now() - this.started;

  private updatePresenter() {
    const parts = this.presenterParts;
    if (!parts || !this.presenterRoot) return;
    const s = Math.floor(this.elapsed() / 1000);
    parts.timer.textContent = `${Math.floor(s / 3600) ? Math.floor(s / 3600) + ":" : ""}${String(Math.floor((s % 3600) / 60)).padStart(Math.floor(s / 3600) ? 2 : 1, "0")}:${String(s % 60).padStart(2, "0")}`;
    parts.clock.textContent = new Date().toLocaleTimeString(undefined, { timeStyle: "short" });
    parts.count.textContent = `Slide ${this.order[this.position] + 1} of ${this.p.slides.length}`;
    const key = `${this.position}`;
    if (parts.next.dataset.key !== key) {
      parts.next.dataset.key = key;
      parts.next.replaceChildren();
      const nextIndex = this.order[this.position + 1];
      if (nextIndex !== undefined) parts.next.append(renderSlide(this.p.slides[nextIndex], nextIndex + 1, this.p, 640));
      else parts.next.textContent = "End of slide show";
      parts.notes.textContent = this.slide.notes || "No notes.";
    }
  }

  // MARK: Exit

  exit() {
    this.finishAnimations();
    clearTimeout(this.advanceTimer);
    clearInterval(this.presenterTick);
    this.recordTiming();
    this.stopMedia(this.current);
    this.resizeObserver.disconnect();
    this.root.remove();
    this.presenterRoot?.remove();
    if (!this.o.windowed) void setFullscreen(false);
    this.o.onExit({ timings: this.o.rehearse ? this.timings : undefined, lastSlide: this.order[this.position] });
  }
}


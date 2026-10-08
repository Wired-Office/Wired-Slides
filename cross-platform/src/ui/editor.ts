import type { SlideElement, UUID } from "../model/types";
import type { Rect } from "../model/core";
import {
  R, F, clamp, groupOf, hasText, imageOf, lineEndpoints, lineOf, maxX, maxY, midX, midY, rotatedBounds, setElementFrame, setLineEndpoints, shapeOf,
  tableOf, textOf, chartOf, unionRect, offsetElement, findElement, isNoFill, lineVisible, mediaOf,
} from "../model/core";
import { hasAdjustHandle } from "../model/catalog";
import type { PresentationController } from "../engine/controller";
import { fitHeight } from "../engine/controller";
import { adjustHandle, adjustTo } from "../render/geometry";
import { drawSlide, envOf } from "../render/slide";
import { elementGeometry, linePath, placeholderIconFrames, shapeTextRect } from "../render/elements";
import { TableGeometry } from "../render/table";
import { settings } from "../settings";
import type { AppActions } from "./actions";
import { TextEditor } from "./textEditor";
import { showPopupMenu } from "./popup";
import type { MenuEntry } from "./menubar";
import { modKey } from "../version";

type Point = [number, number];

type Drag =
  | { kind: "move"; start: Point; ids: UUID[]; origin: Map<UUID, Rect>; moved: boolean; duplicate: boolean }
  | { kind: "resize"; handle: number; id: UUID; start: Rect; rotation: number }
  | { kind: "rotate"; id: UUID; center: Point; startAngle: number; startRotation: number }
  | { kind: "adjust"; id: UUID }
  | { kind: "endpoint"; id: UUID; end: "start" | "end" }
  | { kind: "marquee"; start: Point; current: Point; extend: boolean }
  | { kind: "insert"; start: Point; current: Point }
  | { kind: "column"; id: UUID; column: number; startX: number; widths: number[] };

/** Handle positions as fractions of the frame: corners and edge midpoints, clockwise from top-left. */
const HANDLES: Point[] = [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]];
const CURSORS = ["nwse-resize", "ns-resize", "nesw-resize", "ew-resize", "nwse-resize", "ns-resize", "nesw-resize", "ew-resize"];

const rotate = ([x, y]: Point, deg: number): Point => {
  const t = (deg * Math.PI) / 180;
  return [x * Math.cos(t) - y * Math.sin(t), x * Math.sin(t) + y * Math.cos(t)];
};

/** The editable slide: draws the slide and selection, and handles mouse and keyboard editing. */
export class SlideEditor {
  readonly host: HTMLDivElement;
  private canvas: HTMLCanvasElement;
  private overlay: HTMLCanvasElement;
  private input: HTMLDivElement;
  /** Holds the text editor and comment markers, in slide units, scaled by the zoom. */
  private layer: HTMLDivElement;
  private drag: Drag | null = null;
  private guides: { x: number[]; y: number[] } = { x: [], y: [] };
  private frameRequested = false;
  private editor: TextEditor | null = null;
  zoom = 1;

  constructor(private stage: HTMLElement, private c: PresentationController, private actions: AppActions) {
    this.host = document.createElement("div");
    this.host.className = "slide-host";
    this.canvas = document.createElement("canvas");
    this.canvas.className = "slide-canvas";
    this.overlay = document.createElement("canvas");
    this.overlay.className = "slide-overlay";
    this.input = document.createElement("div");
    this.input.className = "slide-input";
    this.layer = document.createElement("div");
    this.layer.className = "slide-overlay";
    this.layer.style.transformOrigin = "0 0";
    this.host.append(this.canvas, this.overlay, this.input, this.layer);
    stage.append(this.host);
    stage.tabIndex = 0;

    this.input.addEventListener("pointerdown", (e) => this.pointerDown(e));
    this.input.addEventListener("pointermove", (e) => this.pointerMove(e));
    this.input.addEventListener("pointerup", (e) => this.pointerUp(e));
    this.input.addEventListener("dblclick", (e) => this.doubleClick(e));
    this.input.addEventListener("contextmenu", (e) => this.contextMenu(e));
    stage.addEventListener("keydown", (e) => this.keyDown(e));
    stage.addEventListener("wheel", (e) => {
      if (!(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      this.c.setView({ fitToWindow: false, zoom: clamp(this.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1), 0.1, 4) });
    }, { passive: false });
    new ResizeObserver(() => this.layout()).observe(stage);
    c.onBeginEditing = (id, cell) => this.beginEditing(id, cell);
  }

  // MARK: Layout and drawing

  /** Sizes the slide for the zoom (or fits it to the window). */
  layout() {
    const [w, h] = this.c.slideSize;
    if (this.c.fitToWindow) {
      const availableW = this.stage.clientWidth - 48, availableH = this.stage.clientHeight - 48;
      this.zoom = Math.max(0.05, Math.min(availableW / w, availableH / h));
      if (Math.abs(this.c.zoom - this.zoom) > 0.001) this.c.zoom = this.zoom;
    } else this.zoom = this.c.zoom;
    const pw = Math.round(w * this.zoom), ph = Math.round(h * this.zoom);
    const marginX = Math.max(24, (this.stage.clientWidth - pw) / 2), marginY = Math.max(24, (this.stage.clientHeight - ph) / 2);
    Object.assign(this.host.style, { width: `${pw}px`, height: `${ph}px`, margin: `${marginY}px ${marginX}px` });
    const dpr = window.devicePixelRatio || 1;
    for (const cv of [this.canvas, this.overlay]) {
      cv.width = Math.round(pw * dpr);
      cv.height = Math.round(ph * dpr);
      cv.style.width = `${pw}px`;
      cv.style.height = `${ph}px`;
    }
    Object.assign(this.layer.style, { width: `${w}px`, height: `${h}px`, transform: `scale(${this.zoom})` });
    this.drawNow();
  }

  redraw() {
    if (this.frameRequested) return;
    this.frameRequested = true;
    requestAnimationFrame(() => { this.frameRequested = false; this.drawNow(); });
  }

  private drawNow() {
    const dpr = window.devicePixelRatio || 1;
    const ctx = this.canvas.getContext("2d")!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    ctx.setTransform(this.zoom * dpr, 0, 0, this.zoom * dpr, 0, 0);
    const slide = this.c.currentSlide;
    drawSlide(ctx, slide, this.c.currentSlideIndex + 1, this.c.presentation, {
      element: { editorChrome: true, editingTextElement: this.c.editingElement ?? undefined, editingCell: this.c.editingCell ?? undefined, drawHidden: false },
    });
    if (this.c.showGridlines) this.drawGrid(ctx);
    this.drawOverlay();
    this.renderComments();
  }

  private drawGrid(ctx: CanvasRenderingContext2D) {
    const [w, h] = this.c.slideSize, step = 24;
    ctx.save();
    ctx.strokeStyle = "rgba(120,120,120,0.35)";
    ctx.lineWidth = 0.5 / this.zoom;
    ctx.setLineDash([2 / this.zoom, 2 / this.zoom]);
    ctx.beginPath();
    for (let x = step; x < w; x += step) { ctx.moveTo(x, 0); ctx.lineTo(x, h); }
    for (let y = step; y < h; y += step) { ctx.moveTo(0, y); ctx.lineTo(w, y); }
    ctx.stroke();
    ctx.restore();
  }

  private drawOverlay() {
    const dpr = window.devicePixelRatio || 1;
    const ctx = this.overlay.getContext("2d")!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.overlay.width, this.overlay.height);
    ctx.setTransform(this.zoom * dpr, 0, 0, this.zoom * dpr, 0, 0);
    const z = this.zoom;
    const accent = getComputedStyle(document.documentElement).getPropertyValue("--selection").trim() || "#e8700f";
    if (this.c.showGuides) {
      const [w, h] = this.c.slideSize;
      ctx.strokeStyle = "rgba(120,120,120,0.6)";
      ctx.lineWidth = 1 / z;
      ctx.setLineDash([4 / z, 3 / z]);
      ctx.beginPath();
      ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h);
      ctx.moveTo(0, h / 2); ctx.lineTo(w, h / 2);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    const slide = this.c.currentSlide;
    const selected = this.c.selection.map((id) => findElement(slide.elements, id)).filter((e): e is SlideElement => !!e);
    for (const e of selected) {
      const editing = this.c.editingElement === e.id;
      if (lineOf(e)) {
        const { start, end } = lineEndpoints(e);
        ctx.strokeStyle = accent;
        ctx.lineWidth = 1 / z;
        if (selected.length === 1) for (const p of [start, end]) this.handle(ctx, p, accent, "circle");
        continue;
      }
      this.outline(ctx, e, accent, editing ? [4 / z, 3 / z] : []);
      if (selected.length === 1 && !e.locked && !editing) {
        const r = R(e.frame);
        for (const [fx, fy] of HANDLES) this.handle(ctx, this.worldPoint(r, e.rotation, [fx, fy]), accent, "square");
        const top = this.worldPoint(r, e.rotation, [0.5, 0]);
        const knob = this.rotationKnob(e);
        ctx.strokeStyle = accent;
        ctx.lineWidth = 1 / z;
        ctx.beginPath();
        ctx.moveTo(...top);
        ctx.lineTo(...knob);
        ctx.stroke();
        this.handle(ctx, knob, accent, "rotate");
        const s = shapeOf(e);
        if (s && hasAdjustHandle(s.kind)) {
          const a = adjustHandle(s.kind, r, this.c.adjustmentsOf(e));
          if (a) this.handle(ctx, this.toWorld(r, e.rotation, a), "#f5c518", "diamond");
        }
      }
      if (e.locked && selected.length === 1) {
        const r = R(e.frame);
        ctx.fillStyle = accent;
        ctx.font = `${11 / z}px system-ui, sans-serif`;
        ctx.fillText("🔒", maxX(r) - 14 / z, r.y - 4 / z);
      }
    }
    // A child picked inside a group gets its own outline.
    if (this.c.selectedChild) {
      const child = findElement(slide.elements, this.c.selectedChild);
      if (child) this.outline(ctx, child, accent, [3 / z, 2 / z]);
    }
    if (this.drag?.kind === "marquee" || this.drag?.kind === "insert") {
      const r = rectFrom(this.drag.start, this.drag.current);
      ctx.strokeStyle = accent;
      ctx.lineWidth = 1 / z;
      ctx.fillStyle = this.drag.kind === "marquee" ? "rgba(232,112,15,0.08)" : "transparent";
      if (this.drag.kind === "insert" && this.c.pendingInsert && "line" in this.c.pendingInsert) {
        ctx.beginPath();
        ctx.moveTo(...this.drag.start);
        ctx.lineTo(...this.drag.current);
        ctx.stroke();
      } else {
        ctx.fillRect(r.x, r.y, r.w, r.h);
        ctx.strokeRect(r.x, r.y, r.w, r.h);
      }
    }
    if (this.guides.x.length || this.guides.y.length) {
      const [w, h] = this.c.slideSize;
      ctx.strokeStyle = "#e0389b";
      ctx.lineWidth = 1 / z;
      ctx.setLineDash([4 / z, 3 / z]);
      ctx.beginPath();
      for (const x of this.guides.x) { ctx.moveTo(x, 0); ctx.lineTo(x, h); }
      for (const y of this.guides.y) { ctx.moveTo(0, y); ctx.lineTo(w, y); }
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  private outline(ctx: CanvasRenderingContext2D, e: SlideElement, color: string, dash: number[]) {
    const r = R(e.frame);
    ctx.save();
    ctx.translate(midX(r), midY(r));
    ctx.rotate((e.rotation * Math.PI) / 180);
    ctx.strokeStyle = color;
    ctx.lineWidth = 1 / this.zoom;
    ctx.setLineDash(dash);
    ctx.strokeRect(-r.w / 2, -r.h / 2, r.w, r.h);
    ctx.restore();
  }

  private handle(ctx: CanvasRenderingContext2D, [x, y]: Point, color: string, shape: "square" | "circle" | "rotate" | "diamond") {
    const s = 4.5 / this.zoom;
    ctx.save();
    ctx.fillStyle = shape === "diamond" ? color : "white";
    ctx.strokeStyle = shape === "diamond" ? "#7a6100" : color;
    ctx.lineWidth = 1.25 / this.zoom;
    ctx.setLineDash([]);
    ctx.beginPath();
    if (shape === "square") ctx.rect(x - s, y - s, s * 2, s * 2);
    else if (shape === "diamond") { ctx.moveTo(x, y - s * 1.2); ctx.lineTo(x + s * 1.2, y); ctx.lineTo(x, y + s * 1.2); ctx.lineTo(x - s * 1.2, y); ctx.closePath(); }
    else ctx.arc(x, y, shape === "rotate" ? s * 1.1 : s, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /** A point given as a fraction of the frame, in slide coordinates after rotation. */
  private worldPoint(r: Rect, rotation: number, [fx, fy]: Point): Point {
    const [dx, dy] = rotate([(fx - 0.5) * r.w, (fy - 0.5) * r.h], rotation);
    return [midX(r) + dx, midY(r) + dy];
  }

  private toWorld(r: Rect, rotation: number, [x, y]: Point): Point {
    const [dx, dy] = rotate([x - midX(r), y - midY(r)], rotation);
    return [midX(r) + dx, midY(r) + dy];
  }

  private toLocal(r: Rect, rotation: number, [x, y]: Point): Point {
    const [dx, dy] = rotate([x - midX(r), y - midY(r)], -rotation);
    return [midX(r) + dx, midY(r) + dy];
  }

  private rotationKnob(e: SlideElement): Point {
    const r = R(e.frame);
    const [dx, dy] = rotate([0, -r.h / 2 - 22 / this.zoom], e.rotation);
    return [midX(r) + dx, midY(r) + dy];
  }

  // MARK: Comments

  private renderComments() {
    for (const m of this.layer.querySelectorAll(".comment-marker")) m.remove();
    this.c.currentSlide.comments.forEach((comment, i) => {
      const m = document.createElement("div");
      m.className = "comment-marker" + (comment.resolved ? " resolved" : "");
      m.textContent = String(i + 1);
      m.title = `${comment.author}: ${comment.text}`;
      Object.assign(m.style, { left: `${comment.position[0]}px`, top: `${comment.position[1]}px`, transform: `scale(${1 / this.zoom})`, transformOrigin: "0 0" });
      m.addEventListener("click", () => this.c.setView({ sidePane: "comments" }));
      this.layer.append(m);
    });
  }

  // MARK: Hit testing

  pointFromEvent(e: { clientX: number; clientY: number }): Point {
    const rect = this.host.getBoundingClientRect();
    return [(e.clientX - rect.left) / this.zoom, (e.clientY - rect.top) / this.zoom];
  }

  private hitsElement(e: SlideElement, p: Point, tolerance: number): boolean {
    if (e.hidden) return false;
    const r = R(e.frame);
    const local = this.toLocal(r, e.rotation, p);
    const line = lineOf(e);
    if (line) {
      const ctx = this.scratch();
      ctx.lineWidth = Math.max(line.line.width, 1) + tolerance * 2;
      return ctx.isPointInStroke(linePath(e, line), local[0], local[1]);
    }
    const inside = local[0] >= r.x - tolerance && local[0] <= maxX(r) + tolerance && local[1] >= r.y - tolerance && local[1] <= maxY(r) + tolerance;
    if (!inside) return false;
    const s = shapeOf(e);
    // Empty-looking shapes (text boxes and placeholders) are hit anywhere in their frame.
    if (!s || e.placeholder || (isNoFill(s.fill) && !lineVisible(s.line)) || s.kind === "rect") return true;
    const geo = elementGeometry(e, s);
    const ctx = this.scratch();
    ctx.lineWidth = Math.max(s.line.width, 1) + tolerance * 2;
    return ctx.isPointInPath(geo.path, local[0], local[1], geo.evenOdd ? "evenodd" : "nonzero") || ctx.isPointInStroke(geo.path, local[0], local[1])
      || (hasText(e) && local[0] >= shapeTextRect(e, s).x && local[0] <= maxX(shapeTextRect(e, s)) && local[1] >= shapeTextRect(e, s).y && local[1] <= maxY(shapeTextRect(e, s)));
  }

  private scratchCtx: CanvasRenderingContext2D | null = null;
  private scratch() {
    if (!this.scratchCtx) this.scratchCtx = document.createElement("canvas").getContext("2d")!;
    return this.scratchCtx;
  }

  /** The topmost element under a point (locked elements only when nothing else is there). */
  elementAt(p: Point): SlideElement | null {
    const tolerance = 4 / this.zoom;
    const elements = this.c.currentSlide.elements;
    for (let i = elements.length - 1; i >= 0; i--) if (!elements[i].locked && this.hitsElement(elements[i], p, tolerance)) return elements[i];
    for (let i = elements.length - 1; i >= 0; i--) if (elements[i].locked && this.hitsElement(elements[i], p, tolerance)) return elements[i];
    return null;
  }

  private childAt(group: SlideElement, p: Point): SlideElement | null {
    const children = groupOf(group)?.children ?? [];
    for (let i = children.length - 1; i >= 0; i--) if (this.hitsElement(children[i], p, 3 / this.zoom)) return children[i];
    return null;
  }

  private handleAt(p: Point): { kind: "resize"; index: number } | { kind: "rotate" } | { kind: "adjust" } | { kind: "endpoint"; end: "start" | "end" } | null {
    const selected = this.c.selectedElements;
    if (selected.length !== 1) return null;
    const e = selected[0];
    if (e.locked || this.c.editingElement === e.id) return null;
    const near = (q: Point) => Math.hypot(q[0] - p[0], q[1] - p[1]) <= 7 / this.zoom;
    if (lineOf(e)) {
      const { start, end } = lineEndpoints(e);
      if (near(start)) return { kind: "endpoint", end: "start" };
      if (near(end)) return { kind: "endpoint", end: "end" };
      return null;
    }
    const r = R(e.frame);
    const s = shapeOf(e);
    if (s && hasAdjustHandle(s.kind)) {
      const a = adjustHandle(s.kind, r, this.c.adjustmentsOf(e));
      if (a && near(this.toWorld(r, e.rotation, a))) return { kind: "adjust" };
    }
    if (near(this.rotationKnob(e))) return { kind: "rotate" };
    for (let i = 0; i < HANDLES.length; i++) if (near(this.worldPoint(r, e.rotation, HANDLES[i]))) return { kind: "resize", index: i };
    return null;
  }

  /** A table column border near the point, for resizing columns. */
  private columnBorderAt(p: Point): { id: UUID; column: number } | null {
    const e = this.c.selectedElements[0];
    const t = e && !e.rotation ? tableOf(e) : null;
    if (!t) return null;
    const r = R(e.frame);
    if (p[1] < r.y || p[1] > maxY(r)) return null;
    const geo = new TableGeometry(t, r);
    for (let i = 1; i < geo.xs.length - 1; i++) if (Math.abs(geo.xs[i] - p[0]) <= 3 / this.zoom) return { id: e.id, column: i - 1 };
    return null;
  }

  // MARK: Pointer

  private pointerDown(ev: PointerEvent) {
    this.stage.focus({ preventScroll: true });
    if (ev.button !== 0) return;
    const p = this.pointFromEvent(ev);
    if (this.c.editingElement) {
      // Clicks outside the edited element finish editing.
      const editing = findElement(this.c.currentSlide.elements, this.c.editingElement);
      if (editing && this.hitsElement(editing, p, 2 / this.zoom) && tableOf(editing)) {
        const cell = new TableGeometry(tableOf(editing)!, R(editing.frame)).cellAt(p[0], p[1]);
        if (cell) { this.c.commitTextEditing(); this.c.beginEditing(editing.id, cell); return; }
      }
      this.c.commitTextEditing();
    }
    if (this.c.pendingInsert) {
      this.drag = { kind: "insert", start: p, current: p };
      this.input.setPointerCapture(ev.pointerId);
      return;
    }
    const handle = this.handleAt(p);
    const selected = this.c.selectedElements[0];
    if (handle && selected) {
      this.c.beginInteractive();
      if (handle.kind === "resize") this.drag = { kind: "resize", handle: handle.index, id: selected.id, start: R(selected.frame), rotation: selected.rotation };
      else if (handle.kind === "rotate") {
        const r = R(selected.frame), center: Point = [midX(r), midY(r)];
        this.drag = { kind: "rotate", id: selected.id, center, startAngle: Math.atan2(p[1] - center[1], p[0] - center[0]), startRotation: selected.rotation };
      } else if (handle.kind === "adjust") this.drag = { kind: "adjust", id: selected.id };
      else this.drag = { kind: "endpoint", id: selected.id, end: handle.end };
      this.input.setPointerCapture(ev.pointerId);
      return;
    }
    const border = this.columnBorderAt(p);
    if (border) {
      const t = tableOf(findElement(this.c.currentSlide.elements, border.id)!)!;
      this.c.beginInteractive();
      this.drag = { kind: "column", id: border.id, column: border.column, startX: p[0], widths: [...t.columnWidths] };
      this.input.setPointerCapture(ev.pointerId);
      return;
    }
    const hit = this.elementAt(p);
    if (this.c.formatPainter && hit) { this.c.paintFormat(hit.id); return; }
    // Placeholder icons insert content.
    if (hit?.placeholder && !hasText(hit)) {
      for (const [frame, kind] of placeholderIconFrames(R(hit.frame), hit.placeholder === "picture")) {
        if (p[0] >= frame.x && p[0] <= maxX(frame) && p[1] >= frame.y && p[1] <= maxY(frame) && (hit.placeholder === "body" || hit.placeholder === "picture")) {
          this.c.select([hit.id]);
          this.placeholderAction(kind, hit.id);
          return;
        }
      }
    }
    if (!hit) {
      this.c.select([]);
      this.drag = { kind: "marquee", start: p, current: p, extend: ev.shiftKey };
      this.input.setPointerCapture(ev.pointerId);
      return;
    }
    const extend = ev.shiftKey || ev.ctrlKey || ev.metaKey;
    // A second click on a selected group picks the child under the pointer.
    if (!extend && this.c.selection.length === 1 && this.c.selection[0] === hit.id && groupOf(hit)) {
      const child = this.childAt(hit, p);
      if (child && child.id !== this.c.selectedChild) { this.c.selectChild(child.id); }
    } else if (!this.c.selection.includes(hit.id) || extend) {
      this.c.select([hit.id], extend);
      if (extend) return;
    } else if (this.c.selectedChild) {
      const child = this.childAt(hit, p);
      if (!child) this.c.selectChild(null);
    }
    // Clicking into the text of an already selected text box starts editing.
    if (hit.locked) return;
    const ids = this.c.selectedChild ? [this.c.selectedChild] : this.c.selection;
    const origin = new Map<UUID, Rect>();
    for (const id of ids) { const e = findElement(this.c.currentSlide.elements, id); if (e) origin.set(id, R(e.frame)); }
    this.drag = { kind: "move", start: p, ids, origin, moved: false, duplicate: ev.altKey || ev.ctrlKey };
    this.input.setPointerCapture(ev.pointerId);
  }

  private pointerMove(ev: PointerEvent) {
    const p = this.pointFromEvent(ev);
    const drag = this.drag;
    if (!drag) {
      this.updateCursor(p);
      return;
    }
    switch (drag.kind) {
      case "marquee":
      case "insert":
        drag.current = ev.shiftKey && drag.kind === "insert" ? squareFrom(drag.start, p, this.c.pendingInsert) : p;
        this.drawOverlay();
        break;
      case "move": {
        let dx = p[0] - drag.start[0], dy = p[1] - drag.start[1];
        if (!drag.moved && Math.hypot(dx, dy) * this.zoom < 3) return;
        if (!drag.moved) { drag.moved = true; this.c.beginInteractive(); }
        if (ev.shiftKey) { if (Math.abs(dx) > Math.abs(dy)) dy = 0; else dx = 0; }
        [dx, dy] = this.snapMove(drag, dx, dy);
        const ids = new Set(drag.ids);
        this.c.updateInteractive((slide) => {
          const apply = (e: SlideElement) => {
            if (ids.has(e.id)) { const o = drag.origin.get(e.id)!; const r = R(e.frame); offsetElement(e, o.x + dx - r.x, o.y + dy - r.y); return; }
            const g = groupOf(e);
            if (g) {
              g.children.forEach(apply);
              let b: Rect | null = null;
              for (const c of g.children) b = unionRect(b, R(c.frame));
              if (b) e.frame = F(b);
            }
          };
          slide.elements.forEach(apply);
        });
        break;
      }
      case "resize": this.resizeTo(drag, p, ev); break;
      case "rotate": {
        let angle = drag.startRotation + ((Math.atan2(p[1] - drag.center[1], p[0] - drag.center[0]) - drag.startAngle) * 180) / Math.PI;
        if (ev.shiftKey) angle = Math.round(angle / 15) * 15;
        angle = ((angle % 360) + 360) % 360;
        this.c.updateInteractive((slide) => { const e = findElement(slide.elements, drag.id); if (e) e.rotation = Math.round(angle * 10) / 10; });
        break;
      }
      case "adjust":
        this.c.updateInteractive((slide) => {
          const e = findElement(slide.elements, drag.id);
          const s = e && shapeOf(e);
          if (!e || !s) return;
          const r = R(e.frame);
          s.adjustments = adjustTo(s.kind, r, s.adjustments, this.toLocal(r, e.rotation, p));
        });
        break;
      case "endpoint":
        this.c.updateInteractive((slide) => {
          const e = findElement(slide.elements, drag.id);
          if (!e) return;
          const ends = lineEndpoints(e);
          const fixed = drag.end === "start" ? ends.end : ends.start;
          let q = p;
          if (ev.shiftKey) {
            const angle = Math.round(Math.atan2(p[1] - fixed[1], p[0] - fixed[0]) / (Math.PI / 4)) * (Math.PI / 4);
            const len = Math.hypot(p[0] - fixed[0], p[1] - fixed[1]);
            q = [fixed[0] + Math.cos(angle) * len, fixed[1] + Math.sin(angle) * len];
          }
          if (drag.end === "start") setLineEndpoints(e, q, fixed); else setLineEndpoints(e, fixed, q);
        });
        break;
      case "column":
        this.c.updateInteractive((slide) => {
          const e = findElement(slide.elements, drag.id);
          const t = e && tableOf(e);
          if (!e || !t) return;
          const r = R(e.frame);
          const total = drag.widths.reduce((a, b) => a + b, 0);
          const scale = r.w / total;
          const delta = (p[0] - drag.startX) / scale;
          const a = drag.widths[drag.column], b = drag.widths[drag.column + 1];
          const d = clamp(delta, -a + 12 / scale, b - 12 / scale);
          t.columnWidths = drag.widths.map((w, i) => (i === drag.column ? a + d : i === drag.column + 1 ? b - d : w));
        });
        break;
    }
  }

  private pointerUp(ev: PointerEvent) {
    const drag = this.drag;
    this.drag = null;
    this.guides = { x: [], y: [] };
    if (this.input.hasPointerCapture(ev.pointerId)) this.input.releasePointerCapture(ev.pointerId);
    if (!drag) return;
    switch (drag.kind) {
      case "marquee": {
        const r = rectFrom(drag.start, drag.current);
        if (r.w * this.zoom > 3 || r.h * this.zoom > 3) this.c.select(this.c.elementsIn(r), drag.extend);
        this.drawOverlay();
        break;
      }
      case "insert": this.finishInsert(drag.start, drag.current); break;
      case "move":
        if (drag.moved) {
          if (drag.duplicate) this.finishDuplicateDrag(drag);
          else this.c.endInteractive("Move");
        } else if (this.c.selection.length === 1 && !this.c.selectedChild) {
          // A click (not a drag) on a selected text object puts the cursor in its text.
          const e = findElement(this.c.currentSlide.elements, drag.ids[0]);
          if (e && e.id === drag.ids[0] && textOf(e) && (hasText(e) || e.placeholder) && this.wasSelectedBefore === e.id) this.c.beginEditing(e.id);
        }
        break;
      case "resize": this.c.endInteractive("Resize"); break;
      case "rotate": this.c.endInteractive("Rotate"); break;
      case "adjust": this.c.endInteractive("Adjust Shape"); break;
      case "endpoint": this.c.endInteractive("Move Line"); break;
      case "column": this.c.endInteractive("Column Width"); break;
    }
    this.wasSelectedBefore = this.c.selection.length === 1 ? this.c.selection[0] : null;
    this.redraw();
  }

  /** The element selected before the last click, so a second click edits its text. */
  private wasSelectedBefore: UUID | null = null;

  private finishDuplicateDrag(drag: Extract<Drag, { kind: "move" }>) {
    // Ctrl/Alt-drag leaves the originals and drops copies.
    const moved = drag.ids.map((id) => findElement(this.c.currentSlide.elements, id)).filter((e): e is SlideElement => !!e).map((e) => structuredClone(e));
    this.c.cancelInteractive();
    const copies = moved.map((e) => {
      const copy = structuredClone(e);
      const refresh = (x: SlideElement) => { x.id = crypto.randomUUID().toUpperCase(); groupOf(x)?.children.forEach(refresh); };
      refresh(copy);
      return copy;
    });
    this.c.insert(copies, "Duplicate");
  }

  private updateCursor(p: Point) {
    let cursor = "default";
    if (this.c.pendingInsert) cursor = "crosshair";
    else if (this.c.formatPainter) cursor = "copy";
    else {
      const h = this.handleAt(p);
      if (h?.kind === "resize") {
        const rotation = this.c.selectedElements[0]?.rotation ?? 0;
        cursor = CURSORS[(h.index + Math.round(rotation / 45) + 8) % 8];
      } else if (h?.kind === "rotate") cursor = "grab";
      else if (h) cursor = "pointer";
      else if (this.columnBorderAt(p)) cursor = "col-resize";
      else {
        const hit = this.elementAt(p);
        if (hit && !hit.locked) cursor = this.c.selection.includes(hit.id) && textOf(hit) && !this.c.editingElement ? "move" : "move";
        if (hit?.placeholder && !hasText(hit) && placeholderIconFrames(R(hit.frame), hit.placeholder === "picture").some(([f]) => p[0] >= f.x && p[0] <= maxX(f) && p[1] >= f.y && p[1] <= maxY(f))) cursor = "pointer";
      }
    }
    this.input.style.cursor = cursor;
  }

  // MARK: Snapping

  private snapMove(drag: Extract<Drag, { kind: "move" }>, dx: number, dy: number): [number, number] {
    this.guides = { x: [], y: [] };
    let bounds: Rect | null = null;
    for (const [id, r] of drag.origin) {
      const e = findElement(this.c.currentSlide.elements, id);
      bounds = unionRect(bounds, rotatedBounds(r, e?.rotation ?? 0));
    }
    if (!bounds) return [dx, dy];
    if (settings().snapToGrid || this.c.showGridlines) {
      const step = 12;
      const nx = Math.round((bounds.x + dx) / step) * step, ny = Math.round((bounds.y + dy) / step) * step;
      return [nx - bounds.x, ny - bounds.y];
    }
    if (!settings().smartGuides) return [dx, dy];
    const [w, h] = this.c.slideSize;
    const xs = [0, w / 2, w], ys = [0, h / 2, h];
    for (const e of this.c.currentSlide.elements) {
      if (drag.origin.has(e.id) || e.hidden) continue;
      const r = rotatedBounds(R(e.frame), e.rotation);
      xs.push(r.x, midX(r), maxX(r));
      ys.push(r.y, midY(r), maxY(r));
    }
    const threshold = 6 / this.zoom;
    const moved = { x: bounds.x + dx, y: bounds.y + dy, w: bounds.w, h: bounds.h };
    const snap = (values: number[], candidates: number[]): [number, number] | null => {
      let best: [number, number] | null = null;
      for (const v of values) for (const cand of candidates) {
        const d = cand - v;
        if (Math.abs(d) <= threshold && (!best || Math.abs(d) < Math.abs(best[0]))) best = [d, cand];
      }
      return best;
    };
    const sx = snap([moved.x, midX(moved), maxX(moved)], xs);
    const sy = snap([moved.y, midY(moved), maxY(moved)], ys);
    if (sx) { dx += sx[0]; this.guides.x.push(sx[1]); }
    if (sy) { dy += sy[0]; this.guides.y.push(sy[1]); }
    return [dx, dy];
  }

  // MARK: Resizing

  private resizeTo(drag: Extract<Drag, { kind: "resize" }>, p: Point, ev: PointerEvent) {
    const r = drag.start, θ = drag.rotation;
    const [ax, ay] = HANDLES[drag.handle];
    const opp: Point = [1 - ax, 1 - ay];
    const fromCenter = ev.altKey;
    const fixed = fromCenter ? [midX(r), midY(r)] as Point : this.worldPoint(r, θ, opp);
    const v = rotate([p[0] - fixed[0], p[1] - fixed[1]], -θ);
    const affectsX = ax !== 0.5, affectsY = ay !== 0.5;
    let w = r.w, h = r.h;
    if (affectsX) w = fromCenter ? Math.abs(v[0]) * 2 : (ax - opp[0]) * v[0];
    if (affectsY) h = fromCenter ? Math.abs(v[1]) * 2 : (ay - opp[1]) * v[1];
    w = Math.max(w, 2);
    h = Math.max(h, 2);
    const e = findElement(this.c.currentSlide.elements, drag.id);
    const keepAspect = ev.shiftKey !== !!(e?.lockAspectRatio || (e && imageOf(e)));
    if (keepAspect && r.w > 0 && r.h > 0) {
      const aspect = r.w / r.h;
      if (affectsX && affectsY) { if (w / r.w > h / r.h) h = w / aspect; else w = h * aspect; }
      else if (affectsX) h = w / aspect;
      else w = h * aspect;
    }
    // The opposite handle stays put (for edge handles it sits on the centerline, so that axis stays centered).
    const [ox, oy] = rotate([(0.5 - opp[0]) * w, (0.5 - opp[1]) * h], θ);
    const center: Point = fromCenter ? [midX(r), midY(r)] : [fixed[0] + ox, fixed[1] + oy];
    const next = { x: center[0] - w / 2, y: center[1] - h / 2, w, h };
    const theme = this.c.theme;
    this.c.updateInteractive((slide) => {
      const target = findElement(slide.elements, drag.id);
      if (!target) return;
      setElementFrame(target, next);
      if (affectsX && !affectsY) fitHeight(target, theme);
    });
  }

  // MARK: Inserting

  private finishInsert(a: Point, b: Point) {
    const pending = this.c.pendingInsert;
    this.c.setPendingInsert(null);
    if (!pending) return;
    const r = rectFrom(a, b);
    const clicked = r.w * this.zoom < 4 && r.h * this.zoom < 4;
    if ("line" in pending) {
      const end: Point = clicked ? [a[0] + 160, a[1]] : b;
      this.c.insertLine(a, end, pending.line, pending.arrow);
    } else if ("textBox" in pending) {
      const frame = clicked ? { x: a[0], y: a[1], w: 300, h: 40 } : r;
      this.c.insertTextBox(frame, "", pending.textBox);
    } else {
      this.c.insertShape(pending.shape, clicked ? { x: a[0] - 70, y: a[1] - 70, w: 140, h: 140 } : r);
    }
  }

  private placeholderAction(kind: string, id: UUID) {
    switch (kind) {
      case "table": this.actions.insertTable(); break;
      case "chart": this.c.insertChart("column"); break;
      case "smartart": this.actions.insertSmartArt(); break;
      case "picture": this.actions.insertPictures(id); break;
      case "icon": this.actions.insertIcon(); break;
      case "video": this.actions.insertMedia("video"); break;
    }
  }

  // MARK: Double click and text editing

  private doubleClick(ev: MouseEvent) {
    const p = this.pointFromEvent(ev);
    const hit = this.elementAt(p);
    if (!hit || hit.locked) return;
    const g = groupOf(hit);
    if (g) {
      const child = this.childAt(hit, p);
      if (child) {
        this.c.select([hit.id]);
        this.c.selectChild(child.id);
        if (textOf(child)) this.c.beginEditing(child.id);
      }
      return;
    }
    const t = tableOf(hit);
    if (t) {
      const cell = new TableGeometry(t, R(hit.frame)).cellAt(...this.toLocal(R(hit.frame), hit.rotation, p));
      if (cell) this.c.beginEditing(hit.id, cell);
      return;
    }
    if (chartOf(hit)) { this.actions.editChart(hit.id); return; }
    if (imageOf(hit)) { this.actions.cropPicture(); return; }
    if (mediaOf(hit)) return;
    if (textOf(hit)) this.c.beginEditing(hit.id);
  }

  beginEditing(id: UUID, cell: [number, number] | null): void {
    const slide = this.c.currentSlide;
    const e = findElement(slide.elements, id);
    if (!e || e.locked) return;
    let body = textOf(e);
    let area: Rect;
    const t = tableOf(e);
    if (t && cell) {
      const covered = t.rows[cell[0]]?.[cell[1]];
      if (!covered) return;
      const geo = new TableGeometry(t, R(e.frame));
      area = geo.rect(cell[0], cell[1], covered.rowSpan, covered.columnSpan);
      body = covered.text;
    } else if (t) {
      this.beginEditing(id, [0, 0]);
      return;
    } else {
      const s = shapeOf(e);
      if (!s || !body) return;
      area = shapeTextRect(e, s);
    }
    if (!body) return;
    this.editor?.cancel();
    this.c.editingElement = id;
    this.c.editingCell = cell;
    const editor = new TextEditor(this.c, id, cell, body, area, e.rotation, this.c.theme, this.layer, () => {
      if (this.editor === editor) this.editor = null;
      this.stage.focus({ preventScroll: true });
      this.redraw();
    });
    if (t && cell) {
      editor.tabToCell = (delta) => {
        const rows = t.rows.length, columns = t.columnWidths.length;
        let index = cell[0] * columns + cell[1];
        do { index += delta; } while (index >= 0 && index < rows * columns && t.rows[Math.floor(index / columns)][index % columns].isMerged);
        if (index >= rows * columns) { this.c.insertTableRow(true); index = rows * columns; }
        if (index < 0) return;
        const tableNow = tableOf(findElement(this.c.currentSlide.elements, id)!);
        if (tableNow) this.c.beginEditing(id, [Math.floor(index / tableNow.columnWidths.length), index % tableNow.columnWidths.length]);
      };
    }
    this.editor = editor;
    this.c.textEditor = editor;
    this.c.emit("selection");
    this.redraw();
  }

  /** Selects all text in the current editor (Ctrl+A while editing). */
  selectAllText() { this.editor?.selectAll(); }

  // MARK: Keyboard

  private keyDown(ev: KeyboardEvent) {
    if (ev.target !== this.stage) return;
    const mod = ev.ctrlKey || ev.metaKey;
    const step = ev.shiftKey ? 10 : ev.altKey ? 0.5 : 2;
    switch (ev.key) {
      case "ArrowLeft": case "ArrowRight": case "ArrowUp": case "ArrowDown":
        if (!this.c.selection.length) {
          if (ev.key === "ArrowLeft" || ev.key === "ArrowUp") this.c.previousSlide(); else this.c.nextSlide();
        } else {
          const dx = ev.key === "ArrowLeft" ? -step : ev.key === "ArrowRight" ? step : 0;
          const dy = ev.key === "ArrowUp" ? -step : ev.key === "ArrowDown" ? step : 0;
          if (mod) this.c.rotate(dx > 0 ? 15 : dx < 0 ? -15 : 0); else this.c.nudge(dx, dy);
        }
        ev.preventDefault();
        return;
      case "Delete": case "Backspace":
        if (this.c.selection.length) { this.c.deleteSelection(); ev.preventDefault(); }
        return;
      case "Escape":
        if (this.c.pendingInsert) this.c.setPendingInsert(null);
        else if (this.c.formatPainter) { this.c.formatPainter = null; this.c.emit("view"); }
        else if (this.c.selectedChild) this.c.selectChild(null);
        else this.c.clearSelection();
        ev.preventDefault();
        return;
      case "Enter": case "F2": {
        const e = this.c.primary;
        if (e && (textOf(e) || tableOf(e))) { this.c.beginEditing(e.id, tableOf(e) ? [0, 0] : null); ev.preventDefault(); }
        return;
      }
      case "Tab": {
        const list = this.c.currentSlide.elements.filter((e) => !e.hidden);
        if (!list.length) return;
        const i = list.findIndex((e) => e.id === this.c.selection[0]);
        const next = list[(i + (ev.shiftKey ? -1 : 1) + list.length) % list.length];
        this.c.select([next.id]);
        ev.preventDefault();
        return;
      }
      case "PageDown": this.c.nextSlide(); ev.preventDefault(); return;
      case "PageUp": this.c.previousSlide(); ev.preventDefault(); return;
      case "Home": if (!this.c.selection.length) { this.c.setCurrentSlide(0); ev.preventDefault(); } return;
      case "End": if (!this.c.selection.length) { this.c.setCurrentSlide(this.c.slides.length - 1); ev.preventDefault(); } return;
    }
    // Typing on a selected text object starts editing it.
    if (!mod && !ev.altKey && ev.key.length === 1 && this.c.selection.length === 1) {
      const e = this.c.primary;
      if (e && textOf(e) && !e.locked) {
        ev.preventDefault();
        this.c.beginEditing(e.id);
        setTimeout(() => this.c.textEditor?.insertText(ev.key), 0);
      }
    }
  }

  // MARK: Context menu

  private contextMenu(ev: MouseEvent) {
    ev.preventDefault();
    const p = this.pointFromEvent(ev);
    const hit = this.elementAt(p);
    if (hit && !this.c.selection.includes(hit.id)) this.c.select([hit.id]);
    const m = modKey();
    const has = this.c.selection.length > 0;
    const e = this.c.primary;
    const entries: MenuEntry[] = [
      { label: "Cut", shortcut: `${m}X`, enabled: has, action: () => this.actions.cut() },
      { label: "Copy", shortcut: `${m}C`, enabled: has, action: () => this.actions.copy() },
      { label: "Paste", shortcut: `${m}V`, action: () => this.actions.paste() },
      "-",
    ];
    if (has) {
      if (e && (textOf(e) || tableOf(e))) entries.push({ label: "Edit Text", action: () => this.c.beginEditing(e.id, tableOf(e) ? [0, 0] : null) });
      if (e && chartOf(e)) entries.push({ label: "Edit Data…", action: () => this.actions.editChart(e.id) });
      entries.push(
        { label: "Duplicate", shortcut: `${m}D`, action: () => this.c.duplicateSelection() },
        { label: "Delete", action: () => this.c.deleteSelection() },
        "-",
        { label: "Bring to Front", action: () => this.c.arrange("front") },
        { label: "Bring Forward", action: () => this.c.arrange("forward") },
        { label: "Send Backward", action: () => this.c.arrange("backward") },
        { label: "Send to Back", action: () => this.c.arrange("back") },
        "-",
      );
      if (this.c.selection.length > 1) entries.push({ label: "Group", shortcut: `${m}G`, action: () => this.c.group() });
      if (e && groupOf(e)) entries.push({ label: "Ungroup", shortcut: `${m}⇧G`, action: () => this.c.ungroup() });
      entries.push(
        { label: e?.locked ? "Unlock" : "Lock", action: () => this.c.toggleLock() },
        { label: "Link…", shortcut: `${m}K`, action: () => this.actions.hyperlink() },
        { label: "Action…", action: () => this.actions.action() },
        { label: "Edit Alt Text…", action: () => this.actions.altText() },
        { label: "New Comment", action: () => this.c.setView({ sidePane: "comments" }) },
        "-",
        { label: "Format…", action: () => this.c.setView({ sidePane: "format" }) },
      );
    } else {
      entries.push(
        { label: "Layout", submenu: [] },
        { label: "Reset Slide", action: () => this.c.resetSlides() },
        { label: "Format Background…", action: () => this.actions.formatBackground() },
        { label: "New Comment", action: () => this.c.setView({ sidePane: "comments" }) },
        "-",
        { label: "Gridlines", checked: this.c.showGridlines, action: () => this.c.setView({ showGridlines: !this.c.showGridlines }) },
        { label: "Guides", checked: this.c.showGuides, action: () => this.c.setView({ showGuides: !this.c.showGuides }) },
      );
      entries.splice(entries.findIndex((x) => x !== "-" && x.label === "Layout"), 1);
    }
    showPopupMenu({ x: ev.clientX, y: ev.clientY }, entries);
  }

  /** Slide coordinates for a drop at a client point. */
  slidePoint(clientX: number, clientY: number): Point { return this.pointFromEvent({ clientX, clientY }); }

  envForTests() { return envOf(this.c.presentation); }
}

function rectFrom(a: Point, b: Point): Rect {
  return { x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: Math.abs(b[0] - a[0]), h: Math.abs(b[1] - a[1]) };
}

/** Shift while drawing keeps shapes square and lines at 45° steps. */
function squareFrom(a: Point, b: Point, pending: PresentationController["pendingInsert"]): Point {
  if (pending && "line" in pending) {
    const angle = Math.round(Math.atan2(b[1] - a[1], b[0] - a[0]) / (Math.PI / 4)) * (Math.PI / 4);
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    return [a[0] + Math.cos(angle) * len, a[1] + Math.sin(angle) * len];
  }
  const s = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
  return [a[0] + Math.sign(b[0] - a[0] || 1) * s, a[1] + Math.sign(b[1] - a[1] || 1) * s];
}

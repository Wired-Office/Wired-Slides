import type {
  AnimationEffect, ChartContent, ChartKind, ConnectorKind, Effects, ElementAction, Fill, HeaderFooter, ImageContent, LayoutKind, LineStyle,
  MediaContent, NumberingScheme, PaintColor, ParagraphStyle, Presentation, PresentationTheme, RGB, RunStyle, ShapeKind, Slide, SlideAnimation,
  SlideElement, SlideShowSettings, TableContent, TableStyleOptions, TextAlignment, TextBody, TextDirection, ThemeColors, Transition, UUID, VerticalAnchor,
  AutoFit, ImageAdjustments, CropInsets,
} from "../model/types";
import type { Rect } from "../model/core";
import {
  F, R, clone, duplicateElement, element, elementTexts, emptyTextBody, findElement, groupOf, imageContent,
  isTitleRole, lineElement, lineStyle, makeTable, maxX, maxY, midX, midY, numberedBullet, offsetElement, plainRun, rotatedBounds, sampleChart,
  setElementFrame, shapeElement, shapeOf, symbolBullet, tableCellBody, tableOf, textBoxElement, textOf, themePaint, unionRect, updateParagraphs, updateRuns,
  uuid, isoNow, bulletIsNone, NO_BULLET, firstRunStyle, firstParagraphStyle, chartOf, imageOf, mediaOf, rectsIntersect, paragraphText,
  identityAdjustments, zeroCrop,
} from "../model/core";
import { SHAPE_CATEGORIES, SHAPE_TITLES, newAnimation, resolvedAdjustments } from "../model/catalog";
import { addMedia, applyLayout, makeSlide, resetSlide, slideIndex } from "../model/presentation";
import { buildSmartArt, type ShapeStylePreset, type SmartArtKind, WORDART_PRESETS } from "../model/templates";
import { requiredHeight } from "../render/text";
import { fittedRowHeights } from "../render/table";
import { envOf } from "../render/slide";

export type ViewMode = "normal" | "outline" | "sorter" | "notesPage";
export type SidePane = "format" | "animations" | "selection" | "comments";
export type AlignMode = "left" | "center" | "right" | "top" | "middle" | "bottom";
export type ArrangeOrder = "front" | "forward" | "backward" | "back";
export type PendingInsert = { shape: ShapeKind } | { textBox: boolean } | { line: ConnectorKind; arrow: boolean };
export type ChangeKind = "model" | "selection" | "slide" | "view" | "text";

/** The text editor the controller talks to for formatting while editing. */
export interface TextEditing {
  commit(): void;
  cancel(): void;
  currentRunStyle(): RunStyle;
  currentParagraphStyle(): ParagraphStyle;
  applyRunStyle(change: (r: RunStyle) => void): void;
  applyParagraphStyle(change: (p: ParagraphStyle) => void): void;
  insertText(text: string): void;
  selectedText(): string;
}

/** Dialogs and views the controller asks the interface to show. */
export interface Presenter {
  insertTable(): void;
  editChart(id: UUID): void;
  hyperlink(): void;
  findReplace(replace: boolean): void;
  headerFooter(): void;
  slideSize(): void;
  insertIcon(): void;
  smartArt(): void;
  action(): void;
  setUpShow(): void;
  startShow(from: number, presenter: boolean, rehearse: boolean): void;
  insertPictures(): void;
  insertMedia(): void;
}

interface Snapshot { presentation: Presentation; selection: UUID[]; slide: number; name: string }

export interface FormatPainter { element: SlideElement; runStyle?: RunStyle; sticky: boolean }

export interface FindOptions { text: string; replacement: string; matchCase: boolean; wholeWords: boolean }

export class PresentationController {
  presentation: Presentation;
  currentSlideIndex = 0;
  /** Slides selected in the navigator (always includes the current slide). */
  selectedSlides = new Set<number>([0]);
  /** Elements selected on the current slide (top-level ids). */
  selection: UUID[] = [];
  /** A child selected inside a group. */
  selectedChild: UUID | null = null;
  editingElement: UUID | null = null;
  editingCell: [number, number] | null = null;
  zoom = 1;
  fitToWindow = true;
  viewMode: ViewMode = "normal";
  sidePane: SidePane | null = null;
  formatPainter: FormatPainter | null = null;
  showGridlines = false;
  showGuides = false;
  showNotes = true;
  pendingInsert: PendingInsert | null = null;
  selectedAnimation: UUID | null = null;
  textEditor: TextEditing | null = null;
  presenter: Presenter | null = null;
  status: string | null = null;
  dirty = false;

  private undoStack: Snapshot[] = [];
  private redoStack: Snapshot[] = [];
  private interactive: Snapshot | null = null;
  private listeners = new Set<(kind: ChangeKind) => void>();
  private findCursor: { slide: number; element: number } | null = null;

  constructor(presentation: Presentation) {
    this.presentation = presentation;
  }

  onChange(listener: (kind: ChangeKind) => void) { this.listeners.add(listener); }
  offChange(listener: (kind: ChangeKind) => void) { this.listeners.delete(listener); }
  emit(kind: ChangeKind) { for (const l of [...this.listeners]) l(kind); }

  // MARK: Accessors

  get slides() { return this.presentation.slides; }
  get theme() { return this.presentation.theme; }
  get slideSize() { return this.presentation.slideSize; }
  get currentSlide(): Slide { return this.presentation.slides[Math.min(this.currentSlideIndex, this.presentation.slides.length - 1)]; }
  get selectedElements(): SlideElement[] { return this.selection.map((id) => findElement(this.currentSlide.elements, id)).filter((e): e is SlideElement => !!e); }
  /** The elements formatting commands act on: the drilled-in child, else the selection. */
  get targetIDs(): UUID[] { return this.selectedChild ? [this.selectedChild] : this.selection; }
  get targetElements(): SlideElement[] { return this.targetIDs.map((id) => findElement(this.currentSlide.elements, id)).filter((e): e is SlideElement => !!e); }
  get primary(): SlideElement | null { return this.targetElements[0] ?? null; }
  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }
  get undoName() { return this.undoStack[this.undoStack.length - 1]?.name ?? ""; }
  get redoName() { return this.redoStack[this.redoStack.length - 1]?.name ?? ""; }
  get isInteracting() { return !!this.interactive; }

  // MARK: Loading

  load(p: Presentation) {
    this.presentation = p;
    this.currentSlideIndex = 0;
    this.selectedSlides = new Set([0]);
    this.selection = [];
    this.selectedChild = null;
    this.editingElement = null;
    this.undoStack = [];
    this.redoStack = [];
    this.dirty = false;
    this.emit("model");
  }

  // MARK: Changes

  /** A deep copy for editing; media bytes are shared since they never change. */
  private draft(): Presentation {
    const media = this.presentation.media;
    const copy = structuredClone({ ...this.presentation, media: {} }) as Presentation;
    copy.media = { ...media };
    return copy;
  }

  /** Reuses unchanged slides, elements and theme so caches keyed by object stay valid. */
  private reconcile(next: Presentation, old: Presentation) {
    const oldSlides = new Map(old.slides.map((s) => [s.id, s]));
    next.slides = next.slides.map((s) => {
      const before = oldSlides.get(s.id);
      if (!before) return s;
      if (JSON.stringify(before) === JSON.stringify(s)) return before;
      const oldElements = new Map(before.elements.map((e) => [e.id, e]));
      s.elements = s.elements.map((e) => { const b = oldElements.get(e.id); return b && JSON.stringify(b) === JSON.stringify(e) ? b : e; });
      return s;
    });
    if (JSON.stringify(next.theme) === JSON.stringify(old.theme)) next.theme = old.theme;
  }

  /** Applies a change with undo support. */
  change(name: string, body: (p: Presentation) => void): boolean {
    this.commitTextEditing();
    const before = this.presentation;
    const updated = this.draft();
    body(updated);
    this.reconcile(updated, before);
    const same = updated.theme === before.theme && updated.slides.length === before.slides.length && updated.slides.every((s, i) => s === before.slides[i])
      && JSON.stringify({ ...updated, slides: 0, theme: 0, media: Object.keys(updated.media) }) === JSON.stringify({ ...before, slides: 0, theme: 0, media: Object.keys(before.media) });
    if (same) return false;
    this.undoStack.push({ presentation: before, selection: this.selection, slide: this.currentSlideIndex, name });
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.redoStack = [];
    this.commit(updated);
    return true;
  }

  changeSlide(name: string, body: (s: Slide) => void) {
    const index = this.currentSlideIndex;
    return this.change(name, (p) => body(p.slides[index]));
  }

  /** Changes elements on the current slide (descending into groups for child ids). */
  changeElements(ids: UUID[], name: string, body: (e: SlideElement) => void) {
    if (!ids.length) return;
    const set = new Set(ids);
    this.changeSlide(name, (slide) => { for (const e of slide.elements) update(e, set, body); });
  }

  changeTargets(name: string, body: (e: SlideElement) => void) { this.changeElements(this.targetIDs, name, body); }

  private commit(updated: Presentation) {
    this.presentation = updated;
    this.dirty = true;
    if (this.currentSlideIndex >= updated.slides.length) this.currentSlideIndex = Math.max(updated.slides.length - 1, 0);
    this.selectedSlides = new Set([...this.selectedSlides].filter((i) => i < updated.slides.length));
    if (!this.selectedSlides.size) this.selectedSlides.add(this.currentSlideIndex);
    this.selection = this.selection.filter((id) => findElement(this.currentSlide.elements, id));
    if (this.selectedChild && !findElement(this.currentSlide.elements, this.selectedChild)) this.selectedChild = null;
    this.emit("model");
  }

  undo() {
    if (this.editingElement) { this.commitTextEditing(); }
    const snap = this.undoStack.pop();
    if (!snap) return;
    this.redoStack.push({ presentation: this.presentation, selection: this.selection, slide: this.currentSlideIndex, name: snap.name });
    this.restore(snap);
  }

  redo() {
    const snap = this.redoStack.pop();
    if (!snap) return;
    this.undoStack.push({ presentation: this.presentation, selection: this.selection, slide: this.currentSlideIndex, name: snap.name });
    this.restore(snap);
  }

  private restore(snap: Snapshot) {
    this.cancelTextEditing();
    this.commit(snap.presentation);
    this.setCurrentSlide(Math.min(snap.slide, snap.presentation.slides.length - 1), true);
    this.selection = snap.selection.filter((id) => findElement(this.currentSlide.elements, id));
    this.emit("selection");
  }

  /** Marks the document saved (for the unsaved-changes prompt). */
  markSaved() { this.dirty = false; this.emit("view"); }

  // MARK: Interactive changes (drags)

  beginInteractive() { this.interactive = { presentation: this.presentation, selection: this.selection, slide: this.currentSlideIndex, name: "" }; }

  /** Updates the current slide live; only that slide is copied, so dragging stays fast. */
  updateInteractive(body: (slide: Slide, p: Presentation) => void) {
    const index = this.currentSlideIndex;
    const base = this.interactive?.presentation ?? this.presentation;
    const p: Presentation = { ...this.presentation, slides: [...this.presentation.slides] };
    p.slides[index] = structuredClone(base.slides[index]);
    body(p.slides[index], p);
    this.presentation = p;
    this.emit("model");
  }

  endInteractive(name: string) {
    const snap = this.interactive;
    this.interactive = null;
    if (!snap) return;
    const index = this.currentSlideIndex;
    const before = snap.presentation;
    const now = this.presentation;
    if (JSON.stringify(now.slides[index]) === JSON.stringify(before.slides[index])) { this.presentation = before; this.emit("model"); return; }
    const oldElements = new Map(before.slides[index].elements.map((e) => [e.id, e]));
    now.slides[index].elements = now.slides[index].elements.map((e) => { const b = oldElements.get(e.id); return b && JSON.stringify(b) === JSON.stringify(e) ? b : e; });
    this.undoStack.push({ ...snap, name });
    this.redoStack = [];
    this.commit(now);
  }

  cancelInteractive() {
    const snap = this.interactive;
    this.interactive = null;
    if (snap) { this.presentation = snap.presentation; this.emit("model"); }
  }

  // MARK: Navigation and selection

  setCurrentSlide(index: number, keepSelection = false, extend = false) {
    if (index < 0 || index >= this.slides.length) return;
    if (index !== this.currentSlideIndex) this.commitTextEditing();
    const changed = index !== this.currentSlideIndex;
    this.currentSlideIndex = index;
    if (extend) this.selectedSlides.add(index); else this.selectedSlides = new Set([index]);
    if (changed && !keepSelection) { this.selection = []; this.selectedChild = null; }
    this.emit("slide");
  }

  /** Shift-click in the navigator: selects a range of slides. */
  selectSlideRange(to: number) {
    const from = this.currentSlideIndex;
    this.selectedSlides = new Set(Array.from({ length: Math.abs(to - from) + 1 }, (_, i) => Math.min(from, to) + i));
    this.emit("slide");
  }

  toggleSlideSelection(index: number) {
    if (this.selectedSlides.has(index) && this.selectedSlides.size > 1) this.selectedSlides.delete(index);
    else this.selectedSlides.add(index);
    this.emit("slide");
  }

  nextSlide() { this.setCurrentSlide(Math.min(this.currentSlideIndex + 1, this.slides.length - 1)); }
  previousSlide() { this.setCurrentSlide(Math.max(this.currentSlideIndex - 1, 0)); }

  select(ids: UUID[], extend = false) {
    if (this.editingElement && !ids.includes(this.editingElement)) this.commitTextEditing();
    this.selectedChild = null;
    if (extend) {
      const current = [...this.selection];
      for (const id of ids) { const i = current.indexOf(id); if (i >= 0) current.splice(i, 1); else current.push(id); }
      this.selection = current;
    } else this.selection = ids;
    this.emit("selection");
  }

  selectChild(id: UUID | null) { this.selectedChild = id; this.emit("selection"); }

  clearSelection() {
    this.commitTextEditing();
    this.selection = [];
    this.selectedChild = null;
    this.emit("selection");
  }

  selectAll() {
    this.selection = this.currentSlide.elements.filter((e) => !e.locked && !e.hidden).map((e) => e.id);
    this.emit("selection");
  }

  // MARK: Text editing

  commitTextEditing() { if (this.editingElement) this.textEditor?.commit(); }

  cancelTextEditing() {
    if (!this.editingElement) return;
    this.textEditor?.cancel();
    this.editingElement = null;
    this.editingCell = null;
  }

  onBeginEditing: (id: UUID, cell: [number, number] | null) => void = () => {};

  beginEditing(id: UUID, cell: [number, number] | null = null) {
    if (this.selection.length !== 1 || this.selection[0] !== id) this.select([id]);
    this.onBeginEditing(id, cell);
  }

  /** Called by the text editor when editing ends with the new text. */
  finishTextEditing(id: UUID, cell: [number, number] | null, text: TextBody, changed: boolean) {
    this.editingElement = null;
    this.editingCell = null;
    this.textEditor = null;
    if (!changed) { this.emit("selection"); return; }
    const index = this.currentSlideIndex;
    const env = envOf(this.presentation);
    const before = this.presentation;
    const updated = this.draft();
    const slide = updated.slides[index];
    if (!slide) return;
    for (const e of slide.elements) update(e, new Set([id]), (target) => {
      const t = tableOf(target);
      if (cell && t) {
        if (!t.rows[cell[0]]?.[cell[1]]) return;
        t.rows[cell[0]][cell[1]].text = text;
        t.rowHeights = fittedRowHeights(t, R(target.frame).w, env);
        target.frame = [target.frame[0], [target.frame[1][0], t.rowHeights.reduce((a, b) => a + b, 0)]];
      } else if (shapeOf(target)) {
        shapeOf(target)!.text = text;
        fitHeight(target, this.theme);
      }
    });
    this.reconcile(updated, before);
    this.undoStack.push({ presentation: before, selection: this.selection, slide: index, name: "Typing" });
    this.redoStack = [];
    this.commit(updated);
  }

  flash(message: string) {
    this.status = message;
    this.emit("view");
    setTimeout(() => { if (this.status === message) { this.status = null; this.emit("view"); } }, 3000);
  }

  setView(change: Partial<Pick<PresentationController, "viewMode" | "sidePane" | "zoom" | "fitToWindow" | "showGridlines" | "showGuides" | "showNotes">>) {
    if (change.viewMode && change.viewMode !== this.viewMode) this.commitTextEditing();
    Object.assign(this, change);
    this.emit("view");
  }

  setPendingInsert(insert: PendingInsert | null) { this.pendingInsert = insert; this.emit("view"); }

  // MARK: Inserting

  centeredFrame(w: number, h: number): Rect {
    return { x: (this.slideSize[0] - w) / 2, y: (this.slideSize[1] - h) / 2, w, h };
  }

  insert(elements: SlideElement[], name: string, editText = false) {
    if (!elements.length) return;
    this.changeSlide(name, (s) => { s.elements.push(...elements); });
    this.select(elements.map((e) => e.id));
    if (editText) this.beginEditing(elements[0].id);
  }

  insertTextBox(r?: Rect, text = "", vertical = false) {
    const box = textBoxElement(text, F(r ?? this.centeredFrame(300, 40)), { size: 18 });
    box.name = `TextBox ${this.currentSlide.elements.length + 1}`;
    if (vertical) { textOf(box)!.direction = "rotated90"; textOf(box)!.autofit = "none"; }
    fitHeight(box, this.theme);
    this.insert([box], "Insert Text Box", true);
  }

  insertShape(kind: ShapeKind, r?: Rect) {
    const arrows = SHAPE_CATEGORIES.find((c) => c[0] === "Block Arrows")![1];
    const [w, h] = kind === "rect" || arrows.includes(kind) ? [180, 110] : [140, 140];
    const shape = shapeElement(kind, F(r ?? this.centeredFrame(w, h)));
    shape.name = `${SHAPE_TITLES[kind]} ${this.currentSlide.elements.length + 1}`;
    this.insert([shape], "Insert Shape");
  }

  insertLine(a: [number, number], b: [number, number], kind: ConnectorKind = "straight", arrow = false) {
    const style = lineStyle(themePaint("accent1"), 1.5);
    if (arrow) style.tail = "triangle";
    const line = lineElement(a, b, style, kind);
    line.name = `${arrow ? "Arrow" : "Line"} ${this.currentSlide.elements.length + 1}`;
    this.insert([line], "Insert Line");
  }

  /** Inserts a picture, filling an empty placeholder (cropped to fit) or centered on the slide. */
  insertPicture(data: Uint8Array, filename: string, natural: [number, number], at?: [number, number], replacing?: UUID) {
    const slide = this.currentSlide;
    const placeholder = (replacing ? findElement(slide.elements, replacing) : null)
      ?? (!at ? slide.elements.find((e) => (e.placeholder === "picture" || e.placeholder === "body") && !textOf(e)?.paragraphs.some((p) => paragraphText(p)) && !imageOf(e)) ?? null : null);
    const [nw, nh] = natural[0] > 0 ? natural : [400, 300];
    let target: Rect;
    const content = imageContent("");
    if (placeholder) {
      target = R(placeholder.frame);
      const imageAspect = nw / Math.max(nh, 1), boxAspect = target.w / Math.max(target.h, 1);
      if (imageAspect > boxAspect) { const excess = 1 - boxAspect / imageAspect; content.crop.left = excess / 2; content.crop.right = excess / 2; }
      else { const excess = 1 - imageAspect / boxAspect; content.crop.top = excess / 2; content.crop.bottom = excess / 2; }
    } else {
      const s = Math.min(1, (this.slideSize[0] * 0.7) / nw, (this.slideSize[1] * 0.7) / nh);
      const w = nw * s, h = nh * s;
      target = at ? { x: at[0] - w / 2, y: at[1] - h / 2, w, h } : this.centeredFrame(w, h);
    }
    const picture = element(`Picture ${slide.elements.length + 1}`, F(target), { image: { _0: content } });
    picture.lockAspectRatio = true;
    picture.altText = filename.replace(/\.[^.]+$/, "");
    const index = this.currentSlideIndex;
    this.change("Insert Picture", (p) => {
      content.mediaID = addMedia(p, data, filename);
      const s = p.slides[index];
      const i = placeholder ? s.elements.findIndex((e) => e.id === placeholder.id) : -1;
      if (i >= 0) {
        if (s.elements[i].placeholder === "picture") picture.placeholder = "picture";
        s.elements[i] = picture;
      } else s.elements.push(picture);
    });
    this.select([picture.id]);
  }

  insertMedia(data: Uint8Array, filename: string, kind: "video" | "audio") {
    const index = this.currentSlideIndex;
    const r = kind === "video" ? this.centeredFrame(480, 270) : this.centeredFrame(64, 64);
    const content: MediaContent = { kind, mediaID: "", autoplay: false, loop: false, volume: 1, hideWhenNotPlaying: false };
    const e = element(`${kind === "video" ? "Video" : "Audio"} ${this.currentSlide.elements.length + 1}`, F(r), { media: { _0: content } });
    e.lockAspectRatio = true;
    this.change(`Insert ${kind === "video" ? "Video" : "Audio"}`, (p) => {
      content.mediaID = addMedia(p, data, filename);
      p.slides[index].elements.push(e);
    });
    this.select([e.id]);
  }

  /** Puts content into an empty body placeholder (as PowerPoint's placeholder icons do), else centers it. */
  private placeIntoPlaceholder(e: SlideElement, name: string) {
    const target = this.currentSlide.elements.find((x) => x.placeholder === "body" && !textOf(x)?.paragraphs.some((p) => paragraphText(p)));
    if (target) {
      const r = R(target.frame), er = R(e.frame);
      if (tableOf(e)) setElementFrame(e, { x: r.x, y: r.y, w: r.w, h: er.h });
      else setElementFrame(e, r);
      this.changeSlide(name, (s) => { const i = s.elements.findIndex((x) => x.id === target.id); s.elements.splice(i, 1, e); });
      this.select([e.id]);
    } else this.insert([e], name);
  }

  insertTable(rows: number, columns: number) {
    const width = Math.min(this.slideSize[0] - 120, columns * 160);
    const table = makeTable(rows, columns, width);
    const h = table.rowHeights.reduce((a, b) => a + b, 0);
    const e = element(`Table ${this.currentSlide.elements.length + 1}`, F(this.centeredFrame(width, h)), { table: { _0: table } });
    this.placeIntoPlaceholder(e, "Insert Table");
  }

  insertChart(kind: ChartKind) {
    const e = element(`Chart ${this.currentSlide.elements.length + 1}`, F(this.centeredFrame(560, 340)), { chart: { _0: sampleChart(kind) } });
    this.placeIntoPlaceholder(e, "Insert Chart");
    this.presenter?.editChart(e.id);
  }

  insertIcon(symbol: string) {
    const e = element(`Icon ${this.currentSlide.elements.length + 1}`, F(this.centeredFrame(96, 96)), { icon: { _0: { symbol, color: themePaint("accent1") } } });
    e.lockAspectRatio = true;
    this.insert([e], "Insert Icon");
  }

  insertSmartArt(kind: SmartArtKind, items: string[]) {
    const r = this.centeredFrame(Math.min(760, this.slideSize[0] - 120), Math.min(340, this.slideSize[1] - 160));
    const e = buildSmartArt(kind, items, { ...r, y: r.y + 30 });
    this.placeIntoPlaceholder(e, "Insert SmartArt");
  }

  insertWordArt(index: number) {
    const box = textBoxElement("Your text here", F(this.centeredFrame(520, 90)), { size: 54, role: "heading", alignment: "center" });
    updateRuns(textOf(box)!, WORDART_PRESETS[index].apply);
    textOf(box)!.autofit = "resizeShape";
    box.name = `WordArt ${this.currentSlide.elements.length + 1}`;
    fitHeight(box, this.theme);
    this.insert([box], "Insert WordArt", true);
  }

  insertText(text: string) {
    if (this.textEditor) { this.textEditor.insertText(text); return; }
    this.insertTextBox(undefined, text);
  }

  // MARK: Arranging

  deleteSelection() {
    const ids = new Set(this.targetIDs);
    if (!ids.size) return;
    this.changeSlide("Delete", (slide) => {
      const remove = (list: SlideElement[]): SlideElement[] => list.filter((e) => !ids.has(e.id)).map((e) => {
        const g = groupOf(e);
        if (g) g.children = remove(g.children);
        return e;
      }).filter((e) => !groupOf(e) || groupOf(e)!.children.length);
      slide.elements = remove(slide.elements);
      slide.animations = slide.animations.filter((a) => findElement(slide.elements, a.elementID));
    });
    this.selection = [];
    this.selectedChild = null;
    this.emit("selection");
  }

  duplicateSelection() {
    const copies = this.selectedElements.map((e) => { const c = duplicateElement(e); offsetElement(c, 18, 18); return c; });
    this.insert(copies, "Duplicate");
  }

  nudge(dx: number, dy: number) {
    const elements = this.selectedElements.filter((e) => !e.locked);
    if (!elements.length) return;
    this.changeElements(elements.map((e) => e.id), "Move", (e) => offsetElement(e, dx, dy));
  }

  setElementRect(id: UUID, r: Rect, name = "Size and Position") {
    this.changeElements([id], name, (e) => setElementFrame(e, r));
  }

  setRotation(degrees: number) { this.changeTargets("Rotate", (e) => { e.rotation = ((degrees % 360) + 360) % 360; }); }
  rotate(by: number) { this.changeTargets("Rotate", (e) => { e.rotation = (((e.rotation + by) % 360) + 360) % 360; }); }
  flip(horizontal: boolean) { this.changeTargets("Flip", (e) => { if (horizontal) e.flipH = !e.flipH; else e.flipV = !e.flipV; }); }

  arrange(order: ArrangeOrder) {
    const ids = new Set(this.selection);
    if (!ids.size) return;
    this.changeSlide("Arrange", (slide) => {
      const list = slide.elements;
      const chosen = list.filter((e) => ids.has(e.id)), rest = list.filter((e) => !ids.has(e.id));
      if (order === "front") slide.elements = [...rest, ...chosen];
      else if (order === "back") slide.elements = [...chosen, ...rest];
      else if (order === "forward") {
        for (let i = list.length - 2; i >= 0; i--) if (ids.has(list[i].id) && !ids.has(list[i + 1].id)) [list[i], list[i + 1]] = [list[i + 1], list[i]];
      } else {
        for (let i = 1; i < list.length; i++) if (ids.has(list[i].id) && !ids.has(list[i - 1].id)) [list[i], list[i - 1]] = [list[i - 1], list[i]];
      }
    });
  }

  align(mode: AlignMode, toSlide = false) {
    const elements = this.selectedElements;
    if (!elements.length) return;
    const bounds = toSlide || elements.length === 1
      ? { x: 0, y: 0, w: this.slideSize[0], h: this.slideSize[1] }
      : elements.map((e) => rotatedBounds(R(e.frame), e.rotation)).reduce<Rect | null>((a, b) => unionRect(a, b), null)!;
    this.changeElements(elements.map((e) => e.id), "Align", (e) => {
      const r = rotatedBounds(R(e.frame), e.rotation);
      let dx = 0, dy = 0;
      if (mode === "left") dx = bounds.x - r.x;
      if (mode === "center") dx = midX(bounds) - midX(r);
      if (mode === "right") dx = maxX(bounds) - maxX(r);
      if (mode === "top") dy = bounds.y - r.y;
      if (mode === "middle") dy = midY(bounds) - midY(r);
      if (mode === "bottom") dy = maxY(bounds) - maxY(r);
      offsetElement(e, dx, dy);
    });
  }

  distribute(horizontally: boolean) {
    const elements = [...this.selectedElements].sort((a, b) => (horizontally ? R(a.frame).x - R(b.frame).x : R(a.frame).y - R(b.frame).y));
    if (elements.length < 3) return;
    const sizes = elements.map((e) => (horizontally ? R(e.frame).w : R(e.frame).h));
    const first = R(elements[0].frame), last = R(elements[elements.length - 1].frame);
    const start = horizontally ? first.x : first.y, end = horizontally ? maxX(last) : maxY(last);
    const gap = (end - start - sizes.reduce((a, b) => a + b, 0)) / (elements.length - 1);
    const targets = new Map<UUID, number>();
    let cursor = start;
    elements.forEach((e, i) => { targets.set(e.id, cursor); cursor += sizes[i] + gap; });
    this.changeElements(elements.map((e) => e.id), "Distribute", (e) => {
      const r = R(e.frame), t = targets.get(e.id)!;
      offsetElement(e, horizontally ? t - r.x : 0, horizontally ? 0 : t - r.y);
    });
  }

  group() {
    const ids = new Set(this.selection);
    if (ids.size < 2) return;
    let groupID = "";
    this.changeSlide("Group", (slide) => {
      const index = Math.max(...slide.elements.map((e, i) => (ids.has(e.id) ? i : -1)));
      const children = slide.elements.filter((e) => ids.has(e.id)).map((e) => { delete e.placeholder; return e; });
      let bounds: Rect | null = null;
      for (const c of children) bounds = unionRect(bounds, R(c.frame));
      const g = element(`Group ${slide.elements.length}`, F(bounds!), { group: { _0: { children } } });
      groupID = g.id;
      const rest = slide.elements.filter((e) => !ids.has(e.id));
      const insertAt = Math.min(index - children.length + 1, rest.length);
      rest.splice(Math.max(insertAt, 0), 0, g);
      slide.elements = rest;
    });
    this.select([groupID]);
  }

  ungroup() {
    const groups = this.selectedElements.filter((e) => groupOf(e));
    if (!groups.length) return;
    const ids = new Set(groups.map((g) => g.id));
    const childIDs: UUID[] = [];
    this.changeSlide("Ungroup", (slide) => {
      slide.elements = slide.elements.flatMap((e) => {
        if (!ids.has(e.id)) return [e];
        const children = groupOf(e)!.children;
        childIDs.push(...children.map((c) => c.id));
        return children;
      });
    });
    this.select(childIDs);
  }

  toggleLock() {
    const lock = !this.selectedElements.every((e) => e.locked);
    this.changeElements(this.selection, lock ? "Lock" : "Unlock", (e) => { e.locked = lock; });
  }

  setHidden(id: UUID, hidden: boolean) { this.changeElements([id], hidden ? "Hide" : "Show", (e) => { e.hidden = hidden; }); }
  rename(id: UUID, name: string) { this.changeElements([id], "Rename", (e) => { e.name = name; }); }

  moveElement(id: UUID, toIndex: number) {
    this.changeSlide("Reorder", (slide) => {
      const i = slide.elements.findIndex((e) => e.id === id);
      if (i < 0) return;
      const [e] = slide.elements.splice(i, 1);
      slide.elements.splice(Math.max(0, Math.min(toIndex, slide.elements.length)), 0, e);
    });
  }

  // MARK: Formatting objects

  setFill(fill: Fill) {
    this.changeTargets("Shape Fill", (e) => {
      const s = shapeOf(e);
      if (s) { s.fill = clone(fill); return; }
      const c = chartOf(e);
      if (c) c.background = clone(fill);
      const g = groupOf(e);
      if (g) for (const child of g.children) { const cs = shapeOf(child); if (cs) cs.fill = clone(fill); }
    });
  }

  setLine(change: (l: LineStyle) => void) {
    this.changeTargets("Shape Outline", (e) => {
      const c = e.content;
      if ("shape" in c) change(c.shape._0.line);
      else if ("image" in c) change(c.image._0.line);
      else if ("line" in c) change(c.line._0.line);
      else if ("group" in c) for (const child of c.group._0.children) { const s = shapeOf(child); if (s) change(s.line); }
    });
  }

  setEffects(change: (fx: Effects) => void) {
    this.changeTargets("Shape Effects", (e) => {
      const c = e.content;
      if ("shape" in c) change(c.shape._0.effects);
      else if ("image" in c) change(c.image._0.effects);
      else if ("line" in c) change(c.line._0.effects);
    });
  }

  changeShapeKind(kind: ShapeKind) {
    this.changeTargets("Change Shape", (e) => { const s = shapeOf(e); if (s) { s.kind = kind; s.adjustments = []; } const i = imageOf(e); if (i) i.maskShape = kind; });
  }

  setAdjustments(id: UUID, values: number[]) { this.changeElements([id], "Adjust Shape", (e) => { const s = shapeOf(e); if (s) s.adjustments = values; }); }

  applyShapeStyle(style: ShapeStylePreset) {
    this.changeTargets("Shape Style", (e) => {
      const s = shapeOf(e);
      if (!s) return;
      s.fill = clone(style.fill);
      s.line = clone(style.line);
      s.effects = clone(style.effects);
      s.text.defaultColor = clone(style.textColor);
    });
  }

  setImage(change: (i: ImageContent) => void, name = "Format Picture") {
    this.changeTargets(name, (e) => { const i = imageOf(e); if (i) change(i); });
  }

  setImageAdjustments(change: (a: ImageAdjustments) => void) { this.setImage((i) => change(i.adjustments), "Picture Corrections"); }
  setCrop(crop: CropInsets) { this.setImage((i) => { i.crop = clone(crop); }, "Crop"); }

  resetPicture(size: boolean, natural?: [number, number]) {
    this.setImage((i) => { i.adjustments = identityAdjustments(); i.crop = zeroCrop(); delete i.maskShape; }, "Reset Picture");
    if (size && natural && this.primary) {
      const r = R(this.primary.frame);
      const s = Math.min(1, (this.slideSize[0] * 0.9) / natural[0], (this.slideSize[1] * 0.9) / natural[1]);
      this.setElementRect(this.primary.id, { x: r.x, y: r.y, w: natural[0] * s, h: natural[1] * s });
    }
  }

  setMedia(change: (m: MediaContent) => void) { this.changeTargets("Playback", (e) => { const m = mediaOf(e); if (m) change(m); }); }
  setAction(action: ElementAction | null) { this.changeTargets("Action", (e) => { if (action) e.action = clone(action); else delete e.action; }); }
  setAltText(text: string) { this.changeTargets("Alt Text", (e) => { e.altText = text; }); }

  /** Copies formatting for the Format Painter. */
  copyFormat(sticky = false) {
    const e = this.primary;
    if (!e) return;
    const runStyle = this.textEditor ? this.textEditor.currentRunStyle() : textOf(e) ? firstRunStyle(textOf(e)!) : undefined;
    this.formatPainter = { element: clone(e), runStyle: runStyle && clone(runStyle), sticky };
    this.flash("Click an object to paste the formatting.");
  }

  paintFormat(onto: UUID) {
    const painter = this.formatPainter;
    if (!painter) return;
    this.changeElements([onto], "Paste Formatting", (e) => {
      const from = painter.element.content, to = e.content;
      if ("shape" in from && "shape" in to) {
        to.shape._0.fill = clone(from.shape._0.fill);
        to.shape._0.line = clone(from.shape._0.line);
        to.shape._0.effects = clone(from.shape._0.effects);
      } else if ("line" in from && "line" in to) to.line._0.line = clone(from.line._0.line);
      else if ("image" in from && "image" in to) {
        to.image._0.line = clone(from.image._0.line);
        to.image._0.effects = clone(from.image._0.effects);
        to.image._0.adjustments = clone(from.image._0.adjustments);
      }
      const text = textOf(e);
      if (text && painter.runStyle) {
        const rs = painter.runStyle;
        updateRuns(text, (r) => Object.assign(r, clone({ ...rs, link: r.link })));
      }
    });
    if (!painter.sticky) this.formatPainter = null;
    this.emit("view");
  }

  // MARK: Tables

  changeTable(name: string, body: (t: TableContent, r: Rect) => Rect | void) {
    const e = this.primary;
    if (!e || !tableOf(e)) return;
    this.changeElements([e.id], name, (target) => {
      const t = tableOf(target)!;
      const result = body(t, R(target.frame));
      if (result) target.frame = F(result);
      target.frame = [target.frame[0], [target.frame[1][0], t.rowHeights.reduce((a, b) => a + b, 0)]];
    });
  }

  /** The cell commands act on: the cell being edited, else the last row/column. */
  private activeCell(t: TableContent): [number, number] {
    return this.editingCell ?? [t.rows.length - 1, t.columnWidths.length - 1];
  }

  insertTableRow(below: boolean) {
    const cell = this.primary && tableOf(this.primary) ? this.activeCell(tableOf(this.primary)!) : null;
    this.commitTextEditing();
    this.changeTable("Insert Row", (t) => {
      const at = (cell?.[0] ?? t.rows.length - 1) + (below ? 1 : 0);
      t.rows.splice(at, 0, t.columnWidths.map(() => ({ text: tableCellBody(""), rowSpan: 1, columnSpan: 1, isMerged: false })));
      t.rowHeights.splice(at, 0, t.rowHeights[Math.min(at, t.rowHeights.length - 1)] ?? 37);
    });
  }

  insertTableColumn(right: boolean) {
    const cell = this.primary && tableOf(this.primary) ? this.activeCell(tableOf(this.primary)!) : null;
    this.commitTextEditing();
    this.changeTable("Insert Column", (t, r) => {
      const at = (cell?.[1] ?? t.columnWidths.length - 1) + (right ? 1 : 0);
      const width = r.w / t.columnWidths.length;
      for (const row of t.rows) row.splice(at, 0, { text: tableCellBody(""), rowSpan: 1, columnSpan: 1, isMerged: false });
      t.columnWidths.splice(at, 0, width);
      return { ...r, w: r.w + width };
    });
  }

  deleteTableRows() {
    const cell = this.primary && tableOf(this.primary) ? this.activeCell(tableOf(this.primary)!) : null;
    this.cancelTextEditing();
    this.changeTable("Delete Row", (t) => {
      if (t.rows.length <= 1) return;
      const at = cell?.[0] ?? t.rows.length - 1;
      t.rows.splice(at, 1);
      t.rowHeights.splice(at, 1);
      normalizeMerges(t);
    });
  }

  deleteTableColumns() {
    const cell = this.primary && tableOf(this.primary) ? this.activeCell(tableOf(this.primary)!) : null;
    this.cancelTextEditing();
    this.changeTable("Delete Column", (t, r) => {
      if (t.columnWidths.length <= 1) return;
      const at = cell?.[1] ?? t.columnWidths.length - 1;
      const w = (t.columnWidths[at] / t.columnWidths.reduce((a, b) => a + b, 0)) * r.w;
      for (const row of t.rows) row.splice(at, 1);
      t.columnWidths.splice(at, 1);
      normalizeMerges(t);
      return { ...r, w: r.w - w };
    });
  }

  /** Merges the edited cell with the one to its right (or below when it's the last column). */
  mergeCells(direction: "right" | "down") {
    const cell = this.primary && tableOf(this.primary) ? this.editingCell : null;
    if (!cell) { this.flash("Click in a table cell first."); return; }
    this.commitTextEditing();
    this.changeTable("Merge Cells", (t) => {
      const [r, c] = cell;
      const host = t.rows[r][c];
      if (direction === "right") {
        const next = c + host.columnSpan;
        if (next >= t.columnWidths.length) return;
        const other = t.rows[r][next];
        host.columnSpan += other.columnSpan;
        appendText(host.text, other.text);
        for (let rr = r; rr < r + host.rowSpan; rr++) for (let cc = next; cc < c + host.columnSpan; cc++) { t.rows[rr][cc].isMerged = true; t.rows[rr][cc].text = tableCellBody(""); }
      } else {
        const next = r + host.rowSpan;
        if (next >= t.rows.length) return;
        const other = t.rows[next][c];
        host.rowSpan += other.rowSpan;
        appendText(host.text, other.text);
        for (let rr = next; rr < r + host.rowSpan; rr++) for (let cc = c; cc < c + host.columnSpan; cc++) { t.rows[rr][cc].isMerged = true; t.rows[rr][cc].text = tableCellBody(""); }
      }
    });
  }

  splitCells() {
    const cell = this.editingCell;
    if (!cell) return;
    this.commitTextEditing();
    this.changeTable("Split Cells", (t) => {
      const host = t.rows[cell[0]][cell[1]];
      for (let r = cell[0]; r < cell[0] + host.rowSpan; r++) for (let c = cell[1]; c < cell[1] + host.columnSpan; c++) t.rows[r][c].isMerged = false;
      host.rowSpan = 1;
      host.columnSpan = 1;
    });
  }

  setTableStyle(change: (s: TableStyleOptions) => void) { this.changeTable("Table Style", (t) => change(t.style)); }

  setCellFill(fill: Fill | null) {
    const cell = this.editingCell;
    this.commitTextEditing();
    this.changeTable("Cell Shading", (t) => {
      const cells = cell ? [t.rows[cell[0]][cell[1]]] : t.rows.flat();
      for (const c of cells) { if (fill) c.fill = clone(fill); else delete c.fill; }
    });
  }

  distributeTable(rows: boolean) {
    this.changeTable(rows ? "Distribute Rows" : "Distribute Columns", (t) => {
      if (rows) { const total = t.rowHeights.reduce((a, b) => a + b, 0); t.rowHeights = t.rowHeights.map(() => total / t.rowHeights.length); }
      else { const total = t.columnWidths.reduce((a, b) => a + b, 0); t.columnWidths = t.columnWidths.map(() => total / t.columnWidths.length); }
    });
  }

  // MARK: Charts

  setChart(id: UUID, change: (c: ChartContent) => void) { this.changeElements([id], "Edit Chart", (e) => { const c = chartOf(e); if (c) change(c); }); }
  setSelectedChart(change: (c: ChartContent) => void) { const e = this.primary; if (e && chartOf(e)) this.setChart(e.id, change); }

  // MARK: Animations

  addAnimation(effect: AnimationEffect, replacing: boolean) {
    const ids = this.targetIDs;
    if (!ids.length) { this.flash("Select an object to animate."); return; }
    let last: UUID | null = null;
    this.changeSlide("Add Animation", (slide) => {
      if (replacing) slide.animations = slide.animations.filter((a) => !ids.includes(a.elementID));
      ids.forEach((id, i) => {
        const a = newAnimation(id, effect, i === 0 ? "onClick" : "withPrevious");
        slide.animations.push(a);
        last = a.id;
      });
    });
    this.selectedAnimation = last;
    this.emit("view");
  }

  removeAnimations(ids: UUID[]) { this.changeSlide("Remove Animation", (s) => { s.animations = s.animations.filter((a) => !ids.includes(a.elementID)); }); }
  removeAnimation(id: UUID) { this.changeSlide("Remove Animation", (s) => { s.animations = s.animations.filter((a) => a.id !== id); }); }
  updateAnimation(id: UUID, change: (a: SlideAnimation) => void) { this.changeSlide("Animation", (s) => { const a = s.animations.find((x) => x.id === id); if (a) change(a); }); }

  /** The animations the timing controls edit: the one picked in the pane, else the selected objects'. */
  get targetAnimations(): SlideAnimation[] {
    const slide = this.currentSlide;
    if (this.selectedAnimation) { const a = slide.animations.find((x) => x.id === this.selectedAnimation); if (a) return [a]; }
    return slide.animations.filter((a) => this.targetIDs.includes(a.elementID));
  }

  updateSelectedAnimations(change: (a: SlideAnimation) => void) {
    const ids = new Set(this.targetAnimations.map((a) => a.id));
    if (!ids.size) return;
    this.changeSlide("Animation", (s) => { for (const a of s.animations) if (ids.has(a.id)) change(a); });
  }

  moveAnimation(id: UUID, by: number) {
    this.changeSlide("Reorder Animation", (s) => {
      const i = s.animations.findIndex((a) => a.id === id), j = i + by;
      if (i < 0 || j < 0 || j >= s.animations.length) return;
      [s.animations[i], s.animations[j]] = [s.animations[j], s.animations[i]];
    });
  }

  selectAnimation(id: UUID | null) {
    this.selectedAnimation = id;
    const a = id ? this.currentSlide.animations.find((x) => x.id === id) : null;
    if (a) this.selection = [a.elementID];
    this.emit("selection");
  }

  // MARK: Find and replace

  private matcher(o: FindOptions): RegExp | null {
    if (!o.text) return null;
    const escaped = o.text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(o.wholeWords ? `\\b${escaped}\\b` : escaped, o.matchCase ? "g" : "gi");
  }

  /** Selects the next element containing the text; returns false when there is none. */
  findNext(o: FindOptions, backwards = false): boolean {
    const re = this.matcher(o);
    if (!re) return false;
    this.commitTextEditing();
    const order: { slide: number; element: number }[] = [];
    this.slides.forEach((s, si) => s.elements.forEach((e, ei) => { if (elementTexts(e).some((t) => { re.lastIndex = 0; return re.test(t); })) order.push({ slide: si, element: ei }); }));
    if (!order.length) return false;
    const key = (c: { slide: number; element: number }) => c.slide * 100000 + c.element;
    const cursor = this.findCursor ? key(this.findCursor) : backwards ? Infinity : -1;
    const next = backwards ? [...order].reverse().find((c) => key(c) < cursor) ?? order[order.length - 1] : order.find((c) => key(c) > cursor) ?? order[0];
    this.findCursor = next;
    this.setCurrentSlide(next.slide);
    this.select([this.slides[next.slide].elements[next.element].id]);
    return true;
  }

  replaceAll(o: FindOptions): number {
    const re = this.matcher(o);
    if (!re) return 0;
    let count = 0;
    this.change("Replace All", (p) => {
      const fix = (body: TextBody) => {
        for (const para of body.paragraphs) for (const run of para.runs) {
          run.text = run.text.replace(re, () => { count++; return o.replacement; });
        }
      };
      const walk = (e: SlideElement) => {
        const c = e.content;
        if ("shape" in c) fix(c.shape._0.text);
        else if ("table" in c) c.table._0.rows.flat().forEach((cell) => fix(cell.text));
        else if ("group" in c) c.group._0.children.forEach(walk);
      };
      p.slides.forEach((s) => s.elements.forEach(walk));
    });
    return count;
  }

  replaceCurrent(o: FindOptions) {
    const re = this.matcher(o);
    const e = this.primary;
    if (!re || !e) return;
    this.changeElements([e.id], "Replace", (target) => {
      const body = textOf(target);
      if (!body) return;
      let done = false;
      for (const para of body.paragraphs) for (const run of para.runs) {
        if (done) continue;
        re.lastIndex = 0;
        const m = re.exec(run.text);
        if (m) { run.text = run.text.slice(0, m.index) + o.replacement + run.text.slice(m.index + m[0].length); done = true; }
      }
    });
  }

  /** Every font family used in the presentation. */
  usedFonts(): string[] {
    const fonts = new Set([this.theme.headingFont, this.theme.bodyFont]);
    const walk = (e: SlideElement) => {
      const t = textOf(e);
      if (t) updateRuns(clone(t), (r) => { if (r.fontFamily) fonts.add(r.fontFamily); });
      groupOf(e)?.children.forEach(walk);
    };
    this.slides.forEach((s) => s.elements.forEach(walk));
    return [...fonts].sort();
  }

  replaceFont(oldFont: string, newFont: string) {
    this.change("Replace Fonts", (p) => {
      if (p.theme.headingFont === oldFont) p.theme.headingFont = newFont;
      if (p.theme.bodyFont === oldFont) p.theme.bodyFont = newFont;
      const walk = (e: SlideElement) => {
        const c = e.content;
        if ("shape" in c) updateRuns(c.shape._0.text, (r) => { if (r.fontFamily === oldFont) r.fontFamily = newFont; });
        if ("table" in c) c.table._0.rows.flat().forEach((cell) => updateRuns(cell.text, (r) => { if (r.fontFamily === oldFont) r.fontFamily = newFont; }));
        if ("group" in c) c.group._0.children.forEach(walk);
      };
      p.slides.forEach((s) => s.elements.forEach(walk));
    });
  }

  // MARK: Slides

  addSlide(layout?: LayoutKind) {
    const current = this.currentSlide;
    const kind = layout ?? (current.layout === "title" ? "titleContent" : current.layout);
    const slide = makeSlide(kind, this.theme, this.slideSize);
    const at = this.currentSlideIndex + 1;
    this.change("New Slide", (p) => { p.slides.splice(at, 0, slide); });
    this.setCurrentSlide(at);
  }

  duplicateSlides() {
    const indices = [...this.selectedSlides].sort((a, b) => a - b);
    const at = indices[indices.length - 1] + 1;
    this.change("Duplicate Slide", (p) => {
      const copies = indices.map((i) => {
        const s = structuredClone(p.slides[i]);
        s.id = uuid();
        const remap = new Map<UUID, UUID>();
        const refresh = (e: SlideElement) => { const old = e.id; e.id = uuid(); remap.set(old, e.id); groupOf(e)?.children.forEach(refresh); };
        s.elements.forEach(refresh);
        s.animations = s.animations.map((a) => ({ ...a, id: uuid(), elementID: remap.get(a.elementID) ?? a.elementID }));
        s.comments = [];
        return s;
      });
      p.slides.splice(at, 0, ...copies);
    });
    this.setCurrentSlide(at);
  }

  deleteSlides() {
    const indices = new Set(this.selectedSlides);
    if (indices.size >= this.slides.length) { this.flash("A presentation needs at least one slide."); return; }
    const first = Math.min(...indices);
    this.change("Delete Slide", (p) => {
      const removed = new Set(p.slides.filter((_, i) => indices.has(i)).map((s) => s.id));
      p.slides = p.slides.filter((_, i) => !indices.has(i));
      // Sections that started at a deleted slide move to the next surviving one.
      p.sections = p.sections.flatMap((sec) => {
        if (!removed.has(sec.firstSlideID)) return [sec];
        const old = this.slides.findIndex((s) => s.id === sec.firstSlideID);
        const next = this.slides.slice(old).find((s) => !removed.has(s.id));
        return next && !p.sections.some((x) => x.firstSlideID === next.id) ? [{ ...sec, firstSlideID: next.id }] : [];
      });
    });
    this.selectedSlides = new Set([Math.min(first, this.slides.length - 1)]);
    this.setCurrentSlide(Math.min(first, this.slides.length - 1));
  }

  moveSlides(indices: number[], to: number) {
    const sorted = [...new Set(indices)].sort((a, b) => a - b);
    const ids = sorted.map((i) => this.slides[i].id);
    const currentID = this.currentSlide.id;
    this.change("Move Slide", (p) => {
      const moving = sorted.map((i) => p.slides[i]);
      const before = sorted.filter((i) => i < to).length;
      p.slides = p.slides.filter((_, i) => !sorted.includes(i));
      p.slides.splice(Math.max(0, to - before), 0, ...moving);
    });
    this.selectedSlides = new Set(ids.map((id) => slideIndex(this.presentation, id)));
    this.currentSlideIndex = slideIndex(this.presentation, currentID);
    this.emit("slide");
  }

  moveSlideUp() { if (this.currentSlideIndex > 0) this.moveSlides([this.currentSlideIndex], this.currentSlideIndex - 1); }
  moveSlideDown() { if (this.currentSlideIndex < this.slides.length - 1) this.moveSlides([this.currentSlideIndex], this.currentSlideIndex + 2); }

  toggleHideSlides() {
    const indices = [...this.selectedSlides];
    const hide = !indices.every((i) => this.slides[i].hidden);
    this.change(hide ? "Hide Slide" : "Show Slide", (p) => { for (const i of indices) p.slides[i].hidden = hide; });
  }

  setLayout(layout: LayoutKind) {
    const indices = [...this.selectedSlides];
    this.change("Layout", (p) => { for (const i of indices) applyLayout(layout, p.slides[i], p.theme, p.slideSize); });
  }

  resetSlides() {
    const indices = [...this.selectedSlides];
    this.change("Reset Slide", (p) => { for (const i of indices) resetSlide(p.slides[i], p.theme, p.slideSize); });
  }

  addSection(name = "Untitled Section") {
    const id = this.currentSlide.id;
    this.change("Add Section", (p) => {
      const existing = p.sections.find((s) => s.firstSlideID === id);
      if (existing) existing.name = name;
      else p.sections.push({ id: uuid(), name, firstSlideID: id });
      // A first section is needed so earlier slides belong somewhere.
      if (p.slides[0].id !== id && !p.sections.some((s) => s.firstSlideID === p.slides[0].id)) p.sections.push({ id: uuid(), name: "Default Section", firstSlideID: p.slides[0].id });
    });
  }

  renameSection(id: UUID, name: string) { this.change("Rename Section", (p) => { const s = p.sections.find((x) => x.id === id); if (s) s.name = name; }); }
  removeSection(id: UUID) { this.change("Remove Section", (p) => { p.sections = p.sections.filter((s) => s.id !== id); }); }
  removeAllSections() { this.change("Remove All Sections", (p) => { p.sections = []; }); }

  setNotes(notes: string, index = this.currentSlideIndex) {
    if (this.slides[index]?.notes === notes) return;
    const last = this.undoStack[this.undoStack.length - 1];
    // Typing in the notes pane coalesces into one undo step per slide.
    const coalesce = last?.name === "Notes" && last.slide === index;
    if (this.change("Notes", (p) => { p.slides[index].notes = notes; }) && coalesce) this.undoStack.pop();
  }

  // MARK: Comments

  addComment(text: string, author: string, position?: [number, number]) {
    this.changeSlide("New Comment", (s) => {
      s.comments.push({ id: uuid(), author: author || "Author", date: isoNow(), text, resolved: false, replies: [], position: position ?? [10 + s.comments.length * 24, 10] });
    });
  }

  replyToComment(id: UUID, text: string, author: string) {
    this.changeSlide("Reply", (s) => { const c = s.comments.find((x) => x.id === id); if (c) c.replies.push({ id: uuid(), author: author || "Author", date: isoNow(), text, resolved: false, replies: [], position: c.position }); });
  }

  deleteComment(id: UUID) { this.changeSlide("Delete Comment", (s) => { s.comments = s.comments.filter((c) => c.id !== id); }); }
  resolveComment(id: UUID, resolved: boolean) { this.changeSlide("Resolve Comment", (s) => { const c = s.comments.find((x) => x.id === id); if (c) c.resolved = resolved; }); }
  deleteAllComments(all: boolean) {
    const index = this.currentSlideIndex;
    this.change("Delete Comments", (p) => { p.slides.forEach((s, i) => { if (all || i === index) s.comments = []; }); });
  }

  goToComment(forward: boolean) {
    const n = this.slides.length;
    for (let step = 1; step <= n; step++) {
      const i = (this.currentSlideIndex + (forward ? step : -step) + n * 2) % n;
      if (this.slides[i].comments.length) { this.setCurrentSlide(i); this.setView({ sidePane: "comments" }); return; }
    }
    this.flash("There are no comments.");
  }

  // MARK: Transitions

  setTransition(change: (t: Transition) => void, name = "Transition") {
    const indices = [...this.selectedSlides];
    this.change(name, (p) => { for (const i of indices) change(p.slides[i].transition); });
  }

  applyTransitionToAll() {
    const t = clone(this.currentSlide.transition);
    this.change("Apply To All", (p) => { for (const s of p.slides) s.transition = clone(t); });
  }

  // MARK: Design

  applyTheme(next: PresentationTheme) {
    const old = this.theme;
    this.change("Theme", (p) => {
      p.theme = clone(next);
      // Placeholder text follows the new theme's sizes and title styling.
      for (const s of p.slides) for (const e of s.elements) {
        const t = textOf(e);
        if (!e.placeholder || !t) continue;
        if (isTitleRole(e.placeholder)) {
          if (t.defaultSize > 0) t.defaultSize *= next.titleSize / old.titleSize;
          t.defaultColor = clone(next.titleColor);
          updateRuns(t, (r) => {
            if (old.titleBold && r.bold === true) delete r.bold;
            if (next.titleBold && r.bold === undefined) r.bold = true;
            if (old.titleCaps) r.allCaps = false;
            if (next.titleCaps) r.allCaps = true;
          });
        } else {
          t.defaultSize *= next.bodySize / old.bodySize;
          updateParagraphs(t, (para) => {
            if ("symbol" in para.bullet && para.bullet.symbol._0 === old.bulletSymbol) para.bullet = symbolBullet(next.bulletSymbol);
            if (next.bulletColor) para.bulletColor = clone(next.bulletColor); else delete para.bulletColor;
          });
        }
      }
    });
  }

  applyColors(colors: ThemeColors) { this.change("Theme Colors", (p) => { p.theme.colors = clone(colors); }); }
  applyFonts(heading: string, body: string) { this.change("Theme Fonts", (p) => { p.theme.headingFont = heading; p.theme.bodyFont = body; }); }

  setBackground(fill: Fill | null, all: boolean) {
    const indices = all ? this.slides.map((_, i) => i) : [...this.selectedSlides];
    this.change("Format Background", (p) => { for (const i of indices) { if (fill) p.slides[i].background = clone(fill); else delete p.slides[i].background; } });
  }

  setHideBackgroundGraphics(hide: boolean) {
    const indices = [...this.selectedSlides];
    this.change("Hide Background Graphics", (p) => { for (const i of indices) p.slides[i].hideBackgroundGraphics = hide; });
  }

  setSlideSize(size: [number, number], scaleContent: boolean) {
    const [ow, oh] = this.slideSize;
    this.change("Slide Size", (p) => {
      p.slideSize = size;
      if (!scaleContent) return;
      const sx = size[0] / ow, sy = size[1] / oh, s = Math.min(sx, sy);
      for (const slide of p.slides) for (const e of slide.elements) {
        const r = R(e.frame);
        setElementFrame(e, { x: r.x * sx, y: r.y * sy, w: r.w * sx, h: r.h * sy });
        scaleText(e, s);
      }
    });
  }

  setHeaderFooter(hf: HeaderFooter) { this.change("Header & Footer", (p) => { p.headerFooter = clone(hf); }); }
  setShowSettings(s: SlideShowSettings) { this.change("Set Up Slide Show", (p) => { p.showSettings = clone(s); }); }
  setProperties(title: string, author: string) { this.change("Properties", (p) => { p.title = title; p.author = author; }); }

  // MARK: Text formatting

  /** Run formatting at the insertion point (editing) or of the first target. */
  get currentRunStyle(): RunStyle {
    if (this.textEditor) return this.textEditor.currentRunStyle();
    const e = this.primary;
    const t = e ? textOf(e) ?? (tableOf(e) ? tableOf(e)!.rows[0]?.[0]?.text : null) : null;
    return t ? firstRunStyle(t) : plainRun();
  }

  get currentParagraphStyle(): ParagraphStyle {
    if (this.textEditor) return this.textEditor.currentParagraphStyle();
    const e = this.primary;
    const t = e ? textOf(e) : null;
    return t ? firstParagraphStyle(t) : firstParagraphStyle(emptyTextBody());
  }

  /** The text body of the first target (for box-level settings like anchor and autofit). */
  get currentBody(): TextBody | null {
    const e = this.primary;
    return e ? textOf(e) : null;
  }

  /** Changes every text body of the targets (including table cells and group children). */
  changeTextBodies(name: string, body: (t: TextBody, e: SlideElement) => void) {
    const theme = this.theme;
    const env = envOf(this.presentation);
    this.changeTargets(name, (e) => {
      const walk = (x: SlideElement) => {
        const c = x.content;
        if ("shape" in c) { body(c.shape._0.text, x); fitHeight(x, theme); }
        else if ("table" in c) {
          c.table._0.rows.flat().forEach((cell) => body(cell.text, x));
          c.table._0.rowHeights = fittedRowHeights(c.table._0, R(x.frame).w, env);
          x.frame = [x.frame[0], [x.frame[1][0], c.table._0.rowHeights.reduce((a, b) => a + b, 0)]];
        } else if ("group" in c) c.group._0.children.forEach(walk);
      };
      walk(e);
    });
  }

  applyRunStyle(name: string, change: (r: RunStyle) => void) {
    if (this.textEditor) { this.textEditor.applyRunStyle(change); this.emit("text"); return; }
    this.changeTextBodies(name, (t) => updateRuns(t, change));
  }

  applyParagraphStyle(name: string, change: (p: ParagraphStyle) => void) {
    if (this.textEditor) { this.textEditor.applyParagraphStyle(change); this.emit("text"); return; }
    this.changeTextBodies(name, (t) => updateParagraphs(t, change));
  }

  setFontFamily(family: string) { this.applyRunStyle("Font", (r) => { r.fontFamily = family; }); }
  setFontSize(size: number) { this.applyRunStyle("Font Size", (r) => { r.size = Math.max(1, Math.min(size, 400)); }); }

  growFont(larger: boolean) {
    const steps = [8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96];
    const bodies = this.targetElements.map(textOf).filter((t): t is TextBody => !!t);
    const base = this.currentRunStyle.size ?? bodies[0]?.defaultSize ?? 18;
    const next = larger ? steps.find((s) => s > base) ?? base + 8 : [...steps].reverse().find((s) => s < base) ?? Math.max(1, base - 1);
    this.applyRunStyle(larger ? "Increase Font Size" : "Decrease Font Size", (r) => { r.size = next; });
  }

  toggleBold() { const on = !(this.currentRunStyle.bold ?? false); this.applyRunStyle("Bold", (r) => { r.bold = on; }); }
  toggleItalic() { const on = !(this.currentRunStyle.italic ?? false); this.applyRunStyle("Italic", (r) => { r.italic = on; }); }
  toggleUnderline() { const on = !this.currentRunStyle.underline; this.applyRunStyle("Underline", (r) => { r.underline = on; }); }
  toggleStrikethrough() { const on = !this.currentRunStyle.strikethrough; this.applyRunStyle("Strikethrough", (r) => { r.strikethrough = on; }); }
  toggleShadow() { const on = !this.currentRunStyle.shadow; this.applyRunStyle("Text Shadow", (r) => { r.shadow = on; }); }
  setBaseline(value: number) { const v = this.currentRunStyle.baseline === value ? 0 : value; this.applyRunStyle(value > 0 ? "Superscript" : "Subscript", (r) => { r.baseline = v; }); }
  setTextColor(color: PaintColor | null) { this.applyRunStyle("Font Color", (r) => { if (color) r.color = clone(color); else delete r.color; }); }
  setHighlight(color: RGB | null) { this.applyRunStyle("Highlight", (r) => { if (color) r.highlight = { ...color }; else delete r.highlight; }); }
  setCharacterSpacing(v: number) { this.applyRunStyle("Character Spacing", (r) => { r.characterSpacing = v; }); }
  setTextOutline(color: PaintColor | null, width: number) {
    this.applyRunStyle("Text Outline", (r) => { if (color) { r.outlineColor = clone(color); r.outlineWidth = width; } else { delete r.outlineColor; r.outlineWidth = 0; } });
  }

  clearFormatting() {
    this.applyRunStyle("Clear Formatting", (r) => {
      const link = r.link;
      for (const k of Object.keys(r)) delete (r as unknown as Record<string, unknown>)[k];
      Object.assign(r, plainRun());
      if (link) r.link = link;
    });
  }

  changeCase(mode: "upper" | "lower" | "title" | "sentence" | "toggle") {
    const convert = (s: string) => {
      switch (mode) {
        case "upper": return s.toUpperCase();
        case "lower": return s.toLowerCase();
        case "title": return s.toLowerCase().replace(/(^|\s)(\p{L})/gu, (_, a, b) => a + b.toUpperCase());
        case "sentence": return s.toLowerCase().replace(/(^\s*|[.!?]\s+)(\p{L})/gu, (_, a, b) => a + b.toUpperCase());
        case "toggle": return [...s].map((ch) => (ch === ch.toUpperCase() ? ch.toLowerCase() : ch.toUpperCase())).join("");
      }
    };
    if (this.textEditor) {
      const sel = this.textEditor.selectedText();
      if (sel) this.textEditor.insertText(convert(sel));
      return;
    }
    this.changeTextBodies("Change Case", (t) => { for (const p of t.paragraphs) for (const r of p.runs) r.text = convert(r.text); });
  }

  setAlignment(a: TextAlignment) { this.applyParagraphStyle("Align Text", (p) => { p.alignment = a; }); }

  toggleBullets(symbol?: string) {
    const current = this.currentParagraphStyle.bullet;
    const off = !symbol && "symbol" in current;
    const s = symbol ?? this.theme.bulletSymbol;
    this.applyParagraphStyle("Bullets", (p) => { p.bullet = off ? NO_BULLET : symbolBullet(s); });
  }

  toggleNumbering(scheme?: NumberingScheme) {
    const current = this.currentParagraphStyle.bullet;
    const off = !scheme && "numbered" in current;
    this.applyParagraphStyle("Numbering", (p) => { p.bullet = off ? NO_BULLET : numberedBullet(scheme ?? "arabicPeriod"); });
  }

  changeIndent(delta: number) { this.applyParagraphStyle(delta > 0 ? "Increase List Level" : "Decrease List Level", (p) => { p.level = Math.max(0, Math.min(8, p.level + delta)); }); }
  setLineSpacing(v: number) { this.applyParagraphStyle("Line Spacing", (p) => { p.lineSpacing = v; }); }
  setParagraphSpacing(before: number | null, after: number | null) {
    this.applyParagraphStyle("Paragraph Spacing", (p) => { if (before !== null) p.spaceBefore = before; if (after !== null) p.spaceAfter = after; });
  }

  setTextBox(name: string, change: (t: TextBody) => void) {
    this.commitTextEditing();
    this.changeTextBodies(name, change);
  }

  setVerticalAnchor(a: VerticalAnchor) { this.setTextBox("Align Text", (t) => { t.anchor = a; }); }
  setTextDirection(d: TextDirection) { this.setTextBox("Text Direction", (t) => { t.direction = d; }); }
  setColumns(n: number) { this.setTextBox("Columns", (t) => { t.columns = Math.max(1, Math.min(Math.round(n), 6)); }); }
  setAutofit(fit: AutoFit) { this.setTextBox("Autofit", (t) => { t.autofit = fit; }); }
  setWrap(wrap: boolean) { this.setTextBox("Wrap Text", (t) => { t.wrap = wrap; }); }
  setInsets(insets: TextBody["insets"]) { this.setTextBox("Margins", (t) => { t.insets = { ...insets }; }); }

  setHyperlink(url: string | null) {
    if (this.textEditor) { this.applyRunStyle("Link", (r) => { if (url) r.link = url; else delete r.link; }); return; }
    const e = this.primary;
    if (!e) return;
    if (textOf(e) && !e.action) this.applyRunStyle("Link", (r) => { if (url) r.link = url; else delete r.link; });
    else this.setAction(url ? { url: { _0: url } } : null);
  }

  // MARK: Helpers for the interface

  /** True when every target is a text-bearing shape. */
  get canFormatText() { return this.targetElements.some((e) => textOf(e) || tableOf(e)) || !!this.textEditor; }
  get bulletOn() { return !bulletIsNone(this.currentParagraphStyle.bullet) && "symbol" in this.currentParagraphStyle.bullet; }
  get numberingOn() { return "numbered" in this.currentParagraphStyle.bullet; }

  /** A placeholder whose geometry PowerPoint resets (for the "Reset" button). */
  get hasPlaceholders() { return this.currentSlide.elements.some((e) => e.placeholder); }

  /** Adjusted shape values (for the yellow handle). */
  adjustmentsOf(e: SlideElement) { const s = shapeOf(e); return s ? resolvedAdjustments(s.kind, s.adjustments) : []; }

  /** Elements fully inside a rectangle (marquee selection). */
  elementsIn(r: Rect): UUID[] {
    return this.currentSlide.elements.filter((e) => !e.locked && !e.hidden && rectsIntersect(r, R(e.frame))
      && R(e.frame).x >= r.x && R(e.frame).y >= r.y && maxX(R(e.frame)) <= maxX(r) && maxY(R(e.frame)) <= maxY(r)).map((e) => e.id);
  }
}

// MARK: Free functions

function update(e: SlideElement, ids: Set<UUID>, body: (e: SlideElement) => void) {
  if (ids.has(e.id)) { body(e); return; }
  const g = groupOf(e);
  if (!g) return;
  for (const child of g.children) update(child, ids, body);
  let bounds: Rect | null = null;
  for (const c of g.children) bounds = unionRect(bounds, R(c.frame));
  if (bounds) e.frame = F(bounds);
}

/** Grows or shrinks "resize shape to fit text" boxes to their text. */
export function fitHeight(e: SlideElement, theme: PresentationTheme) {
  const body = textOf(e);
  if (!body || body.autofit !== "resizeShape") return;
  const r = R(e.frame);
  const needed = requiredHeight(body, r.w, theme);
  if (Math.abs(needed - r.h) <= 0.5) return;
  let y = r.y;
  if (body.anchor === "middle") y += (r.h - needed) / 2;
  else if (body.anchor === "bottom") y += r.h - needed;
  e.frame = [[r.x, y], [r.w, needed]];
}

function scaleText(e: SlideElement, s: number) {
  const scale = (t: TextBody) => { t.defaultSize *= s; updateRuns(t, (r) => { if (r.size) r.size *= s; }); };
  const c = e.content;
  if ("shape" in c) scale(c.shape._0.text);
  else if ("table" in c) c.table._0.rows.flat().forEach((cell) => scale(cell.text));
  else if ("group" in c) c.group._0.children.forEach((child) => scaleText(child, s));
  else if ("chart" in c) c.chart._0.fontSize *= s;
}

function appendText(into: TextBody, other: TextBody) {
  if (other.paragraphs.every((p) => !paragraphText(p))) return;
  if (into.paragraphs.every((p) => !paragraphText(p))) into.paragraphs = clone(other.paragraphs);
  else into.paragraphs.push(...clone(other.paragraphs));
}

/** Clears spans that point past the table after rows or columns are removed. */
function normalizeMerges(t: TableContent) {
  const rows = t.rows.length, columns = t.columnWidths.length;
  t.rows.forEach((row, r) => row.forEach((cell, c) => {
    cell.rowSpan = Math.max(1, Math.min(cell.rowSpan, rows - r));
    cell.columnSpan = Math.max(1, Math.min(cell.columnSpan, columns - c));
  }));
  // A covered cell whose host is gone becomes a normal cell again.
  const covered = new Set<string>();
  t.rows.forEach((row, r) => row.forEach((cell, c) => {
    if (cell.isMerged) return;
    for (let rr = r; rr < r + cell.rowSpan; rr++) for (let cc = c; cc < c + cell.columnSpan; cc++) if (rr !== r || cc !== c) covered.add(`${rr},${cc}`);
  }));
  t.rows.forEach((row, r) => row.forEach((cell, c) => { if (cell.isMerged && !covered.has(`${r},${c}`)) cell.isMerged = false; }));
}


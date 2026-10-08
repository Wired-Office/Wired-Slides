import type { Slide } from "../model/types";
import { isTitleRole, paragraph, plainParagraphStyle, setPlainText, symbolBullet, textOf } from "../model/core";
import { sectionRanges, slideTitle } from "../model/presentation";
import type { PresentationController } from "../engine/controller";
import { renderSlide, thumbnail } from "../render/slide";
import { showPopupMenu } from "./popup";
import type { Navigator } from "./navigator";

/** Slide Sorter, Outline and Notes Page views, shown in place of the slide editor. */
export class AlternateViews {
  constructor(private root: HTMLElement, private c: PresentationController, private navigator: Navigator) {}

  render() {
    const mode = this.c.viewMode;
    if (mode === "sorter") this.sorter();
    else if (mode === "outline") this.outline();
    else if (mode === "notesPage") this.notesPage();
  }

  // MARK: Sorter

  private sorter() {
    const c = this.c, p = c.presentation;
    const scroll = this.root.scrollTop;
    this.root.replaceChildren();
    const grid = document.createElement("div");
    grid.className = "sorter";
    const starts = new Map(sectionRanges(p).map((r) => [r.start, r.section.name]));
    let dragging: number[] | null = null;
    const width = 220;
    p.slides.forEach((slide, i) => {
      const section = starts.get(i);
      if (section) { const label = document.createElement("div"); label.className = "section-label"; label.textContent = section; grid.append(label); }
      const tile = document.createElement("div");
      tile.className = "tile" + (c.selectedSlides.has(i) ? " selected" : "") + (slide.hidden ? " hidden-slide" : "");
      tile.draggable = true;
      const canvas = thumbnail(slide, i + 1, p, width * 2);
      canvas.style.width = `${width}px`;
      const caption = document.createElement("div");
      caption.className = "caption";
      caption.innerHTML = `<span>${i + 1}</span><span>${slide.transition.kind !== "none" ? "★" : ""}${slide.transition.advanceAfter !== undefined ? ` ${slide.transition.advanceAfter.toFixed(1)}s` : ""}</span>`;
      tile.append(canvas, caption);
      tile.addEventListener("mousedown", (e) => {
        if (e.shiftKey) c.selectSlideRange(i);
        else if (e.ctrlKey || e.metaKey) c.toggleSlideSelection(i);
        else if (!c.selectedSlides.has(i)) c.setCurrentSlide(i);
      });
      tile.addEventListener("dblclick", () => { c.setCurrentSlide(i); c.setView({ viewMode: "normal" }); });
      tile.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (!c.selectedSlides.has(i)) c.setCurrentSlide(i);
        showPopupMenu({ x: e.clientX, y: e.clientY }, this.navigator.slideMenu());
      });
      tile.addEventListener("dragstart", () => { dragging = c.selectedSlides.has(i) ? [...c.selectedSlides] : [i]; });
      tile.addEventListener("dragover", (e) => { if (!dragging) return; e.preventDefault(); grid.querySelectorAll(".drop-before").forEach((x) => x.classList.remove("drop-before")); tile.classList.add("drop-before"); });
      tile.addEventListener("drop", (e) => { if (!dragging) return; e.preventDefault(); c.moveSlides(dragging, i); dragging = null; });
      grid.append(tile);
    });
    grid.addEventListener("dragend", () => { dragging = null; grid.querySelectorAll(".drop-before").forEach((x) => x.classList.remove("drop-before")); });
    this.root.append(grid);
    this.root.scrollTop = scroll;
  }

  // MARK: Outline

  private outline() {
    const c = this.c;
    if (this.root.contains(document.activeElement) && this.root.querySelector(".outline-view")) {
      // Keep editing in place; just update the current slide marker.
      this.root.querySelectorAll<HTMLElement>(".num").forEach((n, i) => n.classList.toggle("current", i === c.currentSlideIndex));
      return;
    }
    this.root.replaceChildren();
    const view = document.createElement("div");
    view.className = "outline-view";
    c.slides.forEach((slide, i) => {
      const row = document.createElement("div");
      row.className = "outline-slide";
      const num = document.createElement("div");
      num.className = "num" + (i === c.currentSlideIndex ? " current" : "");
      num.textContent = String(i + 1);
      num.addEventListener("click", () => c.setCurrentSlide(i));
      const body = document.createElement("div");
      body.className = "body";
      const title = document.createElement("input");
      title.className = "title";
      title.value = slideTitle(slide);
      title.placeholder = "Title";
      title.addEventListener("focus", () => c.setCurrentSlide(i, true));
      title.addEventListener("change", () => this.setTitle(slide, title.value));
      title.addEventListener("keydown", (e) => {
        if (e.key === "Enter") { e.preventDefault(); title.blur(); c.setCurrentSlide(i); c.addSlide(); requestAnimationFrame(() => this.focusTitle(i + 1)); }
      });
      const bodyText = document.createElement("textarea");
      bodyText.value = this.bodyLines(slide).join("\n");
      bodyText.placeholder = "Text";
      bodyText.rows = Math.max(1, bodyText.value.split("\n").length);
      bodyText.addEventListener("input", () => { bodyText.rows = Math.max(1, bodyText.value.split("\n").length); });
      bodyText.addEventListener("focus", () => c.setCurrentSlide(i, true));
      bodyText.addEventListener("change", () => this.setBody(slide, bodyText.value));
      bodyText.addEventListener("keydown", (e) => {
        if (e.key !== "Tab") return;
        e.preventDefault();
        // Tab and Shift+Tab change the outline level of the current line.
        const start = bodyText.value.lastIndexOf("\n", bodyText.selectionStart - 1) + 1;
        const before = bodyText.value;
        if (e.shiftKey) { if (before[start] === "\t") bodyText.value = before.slice(0, start) + before.slice(start + 1); }
        else bodyText.value = before.slice(0, start) + "\t" + before.slice(start);
      });
      body.append(title, bodyText);
      row.append(num, body);
      view.append(row);
    });
    this.root.append(view);
  }

  private focusTitle(index: number) {
    this.root.querySelectorAll<HTMLInputElement>(".outline-slide .title")[index]?.focus();
  }

  private bodyLines(slide: Slide): string[] {
    const body = slide.elements.find((e) => e.placeholder === "body" || e.placeholder === "subtitle");
    const t = body && textOf(body);
    if (!t) return [];
    return t.paragraphs.map((p) => "\t".repeat(p.style.level) + p.runs.map((r) => r.text).join(""));
  }

  private setTitle(slide: Slide, text: string) {
    const index = this.c.slides.indexOf(slide);
    if (index < 0) return;
    this.c.change("Edit Outline", (p) => {
      const s = p.slides[index];
      const title = s.elements.find((e) => isTitleRole(e.placeholder));
      if (title && textOf(title)) setPlainText(textOf(title)!, text);
    });
  }

  private setBody(slide: Slide, text: string) {
    const index = this.c.slides.indexOf(slide);
    if (index < 0) return;
    this.c.change("Edit Outline", (p) => {
      const s = p.slides[index];
      const body = s.elements.find((e) => e.placeholder === "body" || e.placeholder === "subtitle");
      const t = body && textOf(body);
      if (!t) return;
      const base = t.paragraphs[0] ?? paragraph("", { ...plainParagraphStyle(), bullet: symbolBullet(p.theme.bulletSymbol) });
      t.paragraphs = (text ? text.split("\n") : [""]).map((line) => {
        const level = line.length - line.replace(/^\t+/, "").length;
        return { runs: [{ text: line.slice(level), style: structuredClone(base.runs[0]?.style ?? {}) as typeof base.runs[0]["style"] }], style: { ...structuredClone(base.style), level } };
      });
    });
  }

  // MARK: Notes page

  private notesPage() {
    const c = this.c, p = c.presentation;
    if (this.root.contains(document.activeElement)) return;
    this.root.replaceChildren();
    const view = document.createElement("div");
    view.className = "notes-page";
    const slide = c.currentSlide;
    const page = document.createElement("div");
    page.className = "page";
    const canvas = renderSlide(slide, c.currentSlideIndex + 1, p, 1064);
    page.append(canvas);
    const notes = document.createElement("textarea");
    notes.value = slide.notes;
    notes.placeholder = "Click to add notes";
    notes.addEventListener("input", () => c.setNotes(notes.value));
    page.append(notes);
    const nav = document.createElement("div");
    nav.className = "field-row";
    const prev = document.createElement("button"), next = document.createElement("button");
    prev.textContent = "◀ Previous";
    next.textContent = "Next ▶";
    prev.disabled = c.currentSlideIndex === 0;
    next.disabled = c.currentSlideIndex === c.slides.length - 1;
    prev.addEventListener("click", () => c.previousSlide());
    next.addEventListener("click", () => c.nextSlide());
    nav.append(prev, document.createTextNode(` Slide ${c.currentSlideIndex + 1} of ${c.slides.length} `), next);
    view.append(page, nav);
    this.root.append(view);
  }
}

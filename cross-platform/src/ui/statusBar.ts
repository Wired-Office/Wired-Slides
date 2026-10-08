import type { PresentationController } from "../engine/controller";
import type { AppActions } from "./actions";
import { icon } from "./icons";

/** Slide count, notes and comments toggles, view buttons and the zoom slider. */
export class StatusBar {
  private label: HTMLSpanElement;
  private message: HTMLSpanElement;
  private zoomSlider: HTMLInputElement;
  private zoomValue: HTMLSpanElement;
  private toggles: [HTMLButtonElement, () => boolean][] = [];

  constructor(root: HTMLElement, private c: PresentationController, actions: AppActions) {
    const dot = document.createElement("span");
    dot.className = "dot";
    this.label = document.createElement("span");
    this.message = document.createElement("span");
    this.message.style.color = "var(--accent)";
    const spacer = document.createElement("span");
    spacer.className = "spacer";
    const button = (name: string, label: string, title: string, action: () => void, isOn?: () => boolean) => {
      const b = document.createElement("button");
      b.append(icon(name));
      if (label) b.append(label);
      b.title = title;
      b.addEventListener("click", action);
      if (isOn) this.toggles.push([b, isOn]);
      return b;
    };
    const notes = button("notes", "Notes", "Show or hide notes", () => c.setView({ showNotes: !c.showNotes }), () => c.showNotes);
    const comments = button("comment", "Comments", "Show comments", () => c.setView({ sidePane: c.sidePane === "comments" ? null : "comments" }), () => c.sidePane === "comments");
    const views = [
      button("normal", "", "Normal", () => c.setView({ viewMode: "normal" }), () => c.viewMode === "normal"),
      button("sorter", "", "Slide Sorter", () => c.setView({ viewMode: "sorter" }), () => c.viewMode === "sorter"),
      button("reading", "", "Reading View", () => actions.readingView()),
      button("play", "", "Slide Show", () => actions.startShow("current")),
    ];
    const minus = button("minus", "", "Zoom Out", () => c.setView({ fitToWindow: false, zoom: Math.max(0.1, c.zoom - 0.1) }));
    this.zoomSlider = document.createElement("input");
    this.zoomSlider.type = "range";
    this.zoomSlider.className = "zoom-slider";
    this.zoomSlider.min = "10";
    this.zoomSlider.max = "400";
    this.zoomSlider.addEventListener("input", () => c.setView({ fitToWindow: false, zoom: Number(this.zoomSlider.value) / 100 }));
    const plus = button("plus", "", "Zoom In", () => c.setView({ fitToWindow: false, zoom: Math.min(4, c.zoom + 0.1) }));
    this.zoomValue = document.createElement("span");
    this.zoomValue.className = "zoom-value";
    const fit = button("fit", "", "Fit slide to current window", () => c.setView({ fitToWindow: true }), () => c.fitToWindow);
    const left = document.createElement("span");
    left.append(dot, this.label);
    root.append(left, this.message, spacer, notes, comments, ...views, minus, this.zoomSlider, plus, this.zoomValue, fit);
  }

  render() {
    const c = this.c;
    this.label.textContent = c.viewMode === "sorter" && c.selectedSlides.size > 1
      ? `${c.selectedSlides.size} slides selected`
      : `Slide ${c.currentSlideIndex + 1} of ${c.slides.length}`;
    this.message.textContent = c.status ?? (c.pendingInsert ? "Click and drag on the slide to draw. Esc cancels." : c.formatPainter ? "Click an object to apply the formatting." : "");
    if (document.activeElement !== this.zoomSlider) this.zoomSlider.value = String(Math.round(c.zoom * 100));
    this.zoomValue.textContent = `${Math.round(c.zoom * 100)}%`;
    for (const [b, on] of this.toggles) b.classList.toggle("on", on());
  }
}

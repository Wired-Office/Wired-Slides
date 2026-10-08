import type { PresentationController } from "../engine/controller";
import { LAYOUTS, LAYOUT_TITLES } from "../model/catalog";
import { sectionRanges } from "../model/presentation";
import { thumbnail } from "../render/slide";
import type { AppActions } from "./actions";
import type { MenuEntry } from "./menubar";
import { showPopupMenu } from "./popup";
import { promptText } from "./dialogs";
import { modKey } from "../version";

/** The slide thumbnails on the left, with sections, multi-selection and drag-to-reorder. */
export class Navigator {
  private collapsed = new Set<string>();
  private dropIndex: number | null = null;
  private dragging: number[] | null = null;

  constructor(private root: HTMLElement, private c: PresentationController, private actions: AppActions) {
    root.tabIndex = 0;
    root.addEventListener("keydown", (e) => this.keydown(e));
    root.addEventListener("contextmenu", (e) => {
      if ((e.target as HTMLElement).closest(".nav-item, .nav-section")) return;
      e.preventDefault();
      showPopupMenu({ x: e.clientX, y: e.clientY }, [
        { label: "New Slide", action: () => c.addSlide() },
        { label: "Paste", action: () => actions.paste() },
        { label: "Add Section", action: () => this.addSection() },
      ]);
    });
    root.addEventListener("dragover", (e) => {
      if (!this.dragging) return;
      e.preventDefault();
      const items = [...root.querySelectorAll<HTMLElement>(".nav-item")];
      let index = items.length;
      for (const [i, item] of items.entries()) {
        const r = item.getBoundingClientRect();
        if (e.clientY < r.top + r.height / 2) { index = i; break; }
      }
      if (index !== this.dropIndex) { this.dropIndex = index; this.markDrop(); }
    });
    root.addEventListener("drop", (e) => {
      if (!this.dragging || this.dropIndex === null) return;
      e.preventDefault();
      c.moveSlides(this.dragging, this.dropIndex);
      this.dragging = null;
      this.dropIndex = null;
    });
    root.addEventListener("dragend", () => { this.dragging = null; this.dropIndex = null; this.markDrop(); });
  }

  private markDrop() {
    const items = [...this.root.querySelectorAll<HTMLElement>(".nav-item")];
    items.forEach((item, i) => {
      item.classList.toggle("drop-before", this.dropIndex === i);
      item.classList.toggle("drop-after", this.dropIndex === items.length && i === items.length - 1);
    });
  }

  render() {
    const c = this.c, p = c.presentation;
    const scroll = this.root.scrollTop;
    this.root.replaceChildren();
    const ranges = sectionRanges(p);
    const sectionAt = new Map(ranges.map((r) => [r.start, r]));
    let hiddenUntil = -1;
    p.slides.forEach((slide, i) => {
      const section = sectionAt.get(i);
      if (section) {
        const header = document.createElement("div");
        header.className = "nav-section";
        const collapsed = this.collapsed.has(section.section.id);
        header.innerHTML = `<span class="chevron">${collapsed ? "▶" : "▼"}</span><span class="name"></span><span class="count">(${section.end - section.start})</span>`;
        header.querySelector(".name")!.textContent = section.section.name;
        header.addEventListener("click", () => { if (collapsed) this.collapsed.delete(section.section.id); else this.collapsed.add(section.section.id); this.render(); });
        header.addEventListener("dblclick", () => this.renameSection(section.section.id, section.section.name));
        header.addEventListener("contextmenu", (e) => {
          e.preventDefault();
          showPopupMenu({ x: e.clientX, y: e.clientY }, [
            { label: "Rename Section…", action: () => this.renameSection(section.section.id, section.section.name) },
            { label: "Remove Section", action: () => c.removeSection(section.section.id) },
            { label: "Remove All Sections", action: () => c.removeAllSections() },
            "-",
            { label: "Collapse All", action: () => { ranges.forEach((r) => this.collapsed.add(r.section.id)); this.render(); } },
            { label: "Expand All", action: () => { this.collapsed.clear(); this.render(); } },
          ]);
        });
        this.root.append(header);
        hiddenUntil = collapsed ? section.end : -1;
      }
      if (i < hiddenUntil) return;
      const item = document.createElement("div");
      item.className = "nav-item";
      item.classList.toggle("selected", c.selectedSlides.has(i));
      item.classList.toggle("current", i === c.currentSlideIndex);
      item.classList.toggle("hidden-slide", slide.hidden);
      item.draggable = true;
      const number = document.createElement("div");
      number.className = "number";
      number.textContent = String(i + 1);
      const marks = document.createElement("div");
      marks.className = "marks";
      if (slide.transition.kind !== "none" || slide.animations.length) marks.innerHTML = '<span title="Has transition or animations">★</span>';
      if (slide.comments.length) marks.insertAdjacentHTML("beforeend", '<span title="Has comments">💬</span>');
      const canvas = thumbnail(slide, i + 1, p, 324);
      canvas.style.aspectRatio = `${p.slideSize[0]} / ${p.slideSize[1]}`;
      item.append(number, marks, canvas);
      item.addEventListener("mousedown", (e) => {
        if (e.button !== 0) return;
        if (e.shiftKey) c.selectSlideRange(i);
        else if (e.ctrlKey || e.metaKey) c.toggleSlideSelection(i);
        else if (!c.selectedSlides.has(i) || c.selectedSlides.size === 1) c.setCurrentSlide(i);
        else c.setCurrentSlide(i, false, true);
        this.root.focus({ preventScroll: true });
      });
      item.addEventListener("click", (e) => { if (!e.shiftKey && !e.ctrlKey && !e.metaKey && c.selectedSlides.size > 1) c.setCurrentSlide(i); });
      item.addEventListener("dblclick", () => this.actions.startShow(i));
      item.addEventListener("dragstart", (e) => {
        this.dragging = c.selectedSlides.has(i) ? [...c.selectedSlides] : [i];
        e.dataTransfer?.setData("text/plain", "slides");
        if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
      });
      item.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (!c.selectedSlides.has(i)) c.setCurrentSlide(i);
        showPopupMenu({ x: e.clientX, y: e.clientY }, this.slideMenu());
      });
      this.root.append(item);
    });
    this.root.scrollTop = scroll;
    const current = this.root.querySelector<HTMLElement>(".nav-item.current");
    if (current) {
      const r = current.getBoundingClientRect(), box = this.root.getBoundingClientRect();
      if (r.top < box.top) current.scrollIntoView({ block: "nearest" });
      else if (r.bottom > box.bottom) current.scrollIntoView({ block: "nearest" });
    }
  }

  slideMenu(): MenuEntry[] {
    const c = this.c, m = modKey();
    const hidden = [...c.selectedSlides].every((i) => c.slides[i].hidden);
    return [
      { label: "Cut", shortcut: `${m}X`, action: () => this.actions.cut() },
      { label: "Copy", shortcut: `${m}C`, action: () => this.actions.copy() },
      { label: "Paste", shortcut: `${m}V`, action: () => this.actions.paste() },
      "-",
      { label: "New Slide", shortcut: `${m}M`, action: () => c.addSlide() },
      { label: "Duplicate Slide", shortcut: `${m}D`, action: () => c.duplicateSlides() },
      { label: "Delete Slide", action: () => c.deleteSlides() },
      "-",
      { label: "Add Section", action: () => this.addSection() },
      { label: "Layout", submenu: LAYOUTS.map((l) => ({ label: LAYOUT_TITLES[l], checked: c.currentSlide.layout === l, action: () => c.setLayout(l) })) },
      { label: "Reset Slide", action: () => c.resetSlides() },
      { label: "Format Background…", action: () => this.actions.formatBackground() },
      { label: hidden ? "Show Slide" : "Hide Slide", action: () => c.toggleHideSlides() },
      "-",
      { label: "Present From This Slide", action: () => this.actions.startShow("current") },
    ];
  }

  async addSection() {
    const name = await promptText("Add Section", "Section name:", "Untitled Section");
    if (name) this.c.addSection(name);
  }

  private async renameSection(id: string, current: string) {
    const name = await promptText("Rename Section", "Section name:", current);
    if (name) this.c.renameSection(id, name);
  }

  private keydown(e: KeyboardEvent) {
    const c = this.c;
    const mod = e.ctrlKey || e.metaKey;
    switch (e.key) {
      case "ArrowUp": case "ArrowLeft":
        if (e.shiftKey) c.selectSlideRange(Math.max(0, Math.min(...c.selectedSlides) - 1));
        else if (mod) c.moveSlideUp();
        else c.previousSlide();
        break;
      case "ArrowDown": case "ArrowRight":
        if (e.shiftKey) c.selectSlideRange(Math.min(c.slides.length - 1, Math.max(...c.selectedSlides) + 1));
        else if (mod) c.moveSlideDown();
        else c.nextSlide();
        break;
      case "Home": c.setCurrentSlide(0); break;
      case "End": c.setCurrentSlide(c.slides.length - 1); break;
      case "Delete": case "Backspace": c.deleteSlides(); break;
      case "Enter": c.addSlide(); break;
      default: return;
    }
    e.preventDefault();
  }
}

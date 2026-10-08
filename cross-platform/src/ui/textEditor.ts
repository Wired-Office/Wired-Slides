import type { ParagraphStyle, PresentationTheme, RunStyle, TextBody, UUID } from "../model/types";
import type { Rect } from "../model/core";
import { bulletIsNone, clone, cssColor, numberLabel, plainParagraphStyle, plainRun, resolve, themePaint } from "../model/core";
import type { PresentationController, TextEditing } from "../engine/controller";
import { fontStack } from "../render/fonts";
import { fittedScale } from "../render/text";

const ZWSP = "​";

/**
 * Edits a text body in place with a contenteditable overlay laid out like the
 * canvas text. Each run is a span pointing at a RunStyle and each paragraph a
 * div pointing at a ParagraphStyle, so formatting round-trips exactly
 * (theme colors and fonts stay references) instead of being parsed back from CSS.
 */
export class TextEditor implements TextEditing {
  readonly box: HTMLDivElement;
  readonly root: HTMLDivElement;
  private runStyles: RunStyle[] = [];
  private paragraphStyles: ParagraphStyle[] = [];
  private original: string;
  private finished = false;
  private scale: number;

  constructor(
    private c: PresentationController,
    readonly elementID: UUID,
    readonly cell: [number, number] | null,
    private body: TextBody,
    area: Rect,
    rotation: number,
    private theme: PresentationTheme,
    layer: HTMLElement,
    private onEnd: () => void,
  ) {
    this.original = JSON.stringify(body);
    this.scale = fittedScale(body, area.w, area.h, theme);
    this.box = document.createElement("div");
    this.box.className = "text-editor-box";
    Object.assign(this.box.style, {
      left: `${area.x}px`, top: `${area.y}px`, width: `${area.w}px`, height: `${area.h}px`,
      padding: `${body.insets.top}px ${body.insets.right}px ${body.insets.bottom}px ${body.insets.left}px`,
      justifyContent: body.anchor === "middle" ? "center" : body.anchor === "bottom" ? "flex-end" : "flex-start",
      transform: `rotate(${rotation + (body.direction === "rotated90" ? 90 : body.direction === "rotated270" ? -90 : 0)}deg)`,
    });
    if (body.direction !== "horizontal") {
      Object.assign(this.box.style, { left: `${area.x + area.w / 2 - area.h / 2}px`, top: `${area.y + area.h / 2 - area.w / 2}px`, width: `${area.h}px`, height: `${area.w}px` });
    }
    this.root = document.createElement("div");
    this.root.className = "text-editor" + (body.wrap ? "" : " nowrap");
    this.root.contentEditable = "true";
    this.root.spellcheck = true;
    this.root.style.pointerEvents = "auto";
    if (body.columns > 1) { this.root.style.columnCount = String(body.columns); this.root.style.columnGap = "14px"; this.root.style.height = "100%"; }
    this.box.append(this.root);
    layer.append(this.box);
    this.render();

    this.root.addEventListener("input", () => this.normalize());
    this.root.addEventListener("keydown", (e) => this.keydown(e));
    this.root.addEventListener("paste", (e) => {
      e.preventDefault();
      const text = e.clipboardData?.getData("text/plain") ?? "";
      this.insertText(text);
    });
    this.root.addEventListener("blur", (e) => {
      // Clicks on the ribbon keep editing; anything else on the page commits.
      const next = e.relatedTarget as HTMLElement | null;
      if (next && (next.closest("#ribbon") || next.closest(".palette") || next.closest(".gallery") || next.closest("#menubar"))) return;
      setTimeout(() => { if (!this.finished && document.activeElement !== this.root && !document.activeElement?.closest("#ribbon, .palette, .gallery, #menubar, dialog")) this.commit(); }, 0);
    });
    document.addEventListener("selectionchange", this.selectionChanged);
    this.root.focus();
    this.placeCaretAtEnd();
  }

  private selectionChanged = () => { if (!this.finished && this.root.contains(document.getSelection()?.anchorNode ?? null)) this.c.emit("text"); };

  // MARK: Rendering

  private styleIndex(style: RunStyle) {
    const key = JSON.stringify(style);
    const i = this.runStyles.findIndex((s) => JSON.stringify(s) === key);
    if (i >= 0) return i;
    this.runStyles.push(clone(style));
    return this.runStyles.length - 1;
  }

  private paragraphIndex(style: ParagraphStyle) {
    const key = JSON.stringify(style);
    const i = this.paragraphStyles.findIndex((s) => JSON.stringify(s) === key);
    if (i >= 0) return i;
    this.paragraphStyles.push(clone(style));
    return this.paragraphStyles.length - 1;
  }

  private render() {
    this.root.replaceChildren();
    for (const p of this.body.paragraphs) {
      const div = document.createElement("div");
      div.className = "p";
      div.dataset.p = String(this.paragraphIndex(p.style));
      const runs = p.runs.length ? p.runs : [{ text: "", style: plainRun() }];
      for (const run of runs) {
        const span = document.createElement("span");
        span.dataset.r = String(this.styleIndex(run.style));
        const pieces = run.text.split("\u2028");
        pieces.forEach((piece, i) => {
          if (i) span.append(document.createElement("br"));
          if (piece) span.append(piece);
        });
        div.append(span);
      }
      if (!div.textContent) div.append(document.createElement("br"));
      this.root.append(div);
    }
    this.restyle();
  }

  /** Applies CSS to every paragraph and span from their model styles. */
  private restyle() {
    const unit = Math.max((this.body.defaultSize * this.scale) / 24, 0.6);
    const counters = new Map<number, number>();
    for (const div of this.paragraphs()) {
      const st = this.paragraphStyles[Number(div.dataset.p)] ?? plainParagraphStyle();
      const hasBullet = !bulletIsNone(st.bullet);
      const indent = (st.level * 28 + (hasBullet ? 24 : 0)) * unit;
      const first = this.runStyles[Number((div.querySelector("[data-r]") as HTMLElement | null)?.dataset.r ?? 0)] ?? plainRun();
      const size = this.fontSize(first);
      Object.assign(div.style, {
        textAlign: st.alignment === "justify" ? "justify" : st.alignment,
        paddingLeft: `${indent}px`,
        marginTop: `${st.spaceBefore * this.scale}px`,
        marginBottom: `${st.spaceAfter * this.scale}px`,
        lineHeight: String(1.18 * st.lineSpacing),
        fontSize: `${size}px`,
        fontFamily: fontStack(this.family(first)),
      });
      for (const level of [...counters.keys()]) if (level > st.level) counters.delete(level);
      let label = "";
      if ("symbol" in st.bullet) label = st.bullet.symbol._0;
      else if ("numbered" in st.bullet) {
        const n = (counters.get(st.level) ?? st.bullet.numbered.start - 1) + 1;
        counters.set(st.level, n);
        label = numberLabel(st.bullet.numbered._0, n);
      } else counters.delete(st.level);
      if (label) {
        div.dataset.marker = label;
        div.style.setProperty("--marker-x", `${st.level * 28 * unit}px`);
        div.style.setProperty("--marker-color", st.bulletColor ? cssColor(resolve(st.bulletColor, this.theme.colors)) : this.color(first));
      } else delete div.dataset.marker;
    }
    for (const span of this.root.querySelectorAll<HTMLElement>("span[data-r]")) this.styleSpan(span);
  }

  private family(r: RunStyle) { return r.fontFamily ?? (this.body.fontRole === "heading" ? this.theme.headingFont : this.theme.bodyFont); }
  private fontSize(r: RunStyle) { return (r.size ?? this.body.defaultSize) * this.scale * (r.baseline ? 0.66 : 1); }
  private color(r: RunStyle) { return cssColor(resolve(r.color ?? (r.link ? themePaint("hyperlink") : this.body.defaultColor), this.theme.colors)); }

  private styleSpan(span: HTMLElement) {
    const r = this.runStyles[Number(span.dataset.r)] ?? plainRun();
    const decorations = [r.underline || r.link ? "underline" : "", r.strikethrough ? "line-through" : ""].filter(Boolean).join(" ");
    Object.assign(span.style, {
      fontFamily: fontStack(this.family(r)),
      fontSize: `${this.fontSize(r)}px`,
      fontWeight: r.bold ? "700" : "400",
      fontStyle: r.italic ? "italic" : "normal",
      fontVariant: r.smallCaps ? "small-caps" : "normal",
      color: this.color(r),
      textDecoration: decorations || "none",
      backgroundColor: r.highlight ? cssColor(r.highlight) : "",
      verticalAlign: r.baseline > 0 ? "super" : r.baseline < 0 ? "sub" : "",
      letterSpacing: r.characterSpacing ? `${r.characterSpacing * this.scale}px` : "",
      textShadow: r.shadow ? "0.04em 0.04em 0.08em rgba(0,0,0,0.45)" : "",
      webkitTextStroke: r.outlineColor && r.outlineWidth > 0 ? `${r.outlineWidth}px ${cssColor(resolve(r.outlineColor, this.theme.colors))}` : "",
    });
  }

  private paragraphs(): HTMLElement[] {
    return [...this.root.children].filter((n): n is HTMLElement => n instanceof HTMLElement);
  }

  /** Keeps the DOM in the expected shape after the browser edits it. */
  private normalize() {
    let lastP = "0";
    let lastR = String(this.styleIndex(this.body.paragraphs[0]?.runs[0]?.style ?? plainRun()));
    for (const node of [...this.root.childNodes]) {
      if (node instanceof HTMLElement && node.classList.contains("p")) continue;
      // Stray text or elements at the top level go into a paragraph.
      const div = document.createElement("div");
      div.className = "p";
      this.root.insertBefore(div, node);
      div.append(node);
    }
    for (const div of this.paragraphs()) {
      div.className = "p";
      if (div.dataset.p === undefined) div.dataset.p = lastP;
      lastP = div.dataset.p;
      for (const node of [...div.childNodes]) {
        if (node.nodeType === Node.TEXT_NODE) {
          const span = document.createElement("span");
          span.dataset.r = lastR;
          div.insertBefore(span, node);
          span.append(node);
        } else if (node instanceof HTMLElement && node.tagName !== "BR" && !node.dataset.r) {
          node.dataset.r = lastR;
        }
        const el = div.lastChild as HTMLElement | null;
        if (el?.dataset?.r) lastR = el.dataset.r;
      }
      for (const font of div.querySelectorAll("font, b, i, u, strike")) font.replaceWith(...font.childNodes);
    }
    this.restyle();
    this.c.emit("text");
  }

  // MARK: Keyboard

  private keydown(e: KeyboardEvent) {
    const mod = e.ctrlKey || e.metaKey;
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); this.commit(); return; }
    if (e.key === "Tab") {
      e.preventDefault();
      e.stopPropagation();
      if (this.cell) { this.commit(); this.c.emit("view"); this.tabToCell?.(e.shiftKey ? -1 : 1); return; }
      this.applyParagraphStyle((p) => { p.level = Math.max(0, Math.min(8, p.level + (e.shiftKey ? -1 : 1))); });
      return;
    }
    if (e.key === "Enter" && e.shiftKey) { e.preventDefault(); this.insertLineBreak(); return; }
    if (mod && !e.altKey) {
      const key = e.key.toLowerCase();
      const handled = ({ b: () => this.c.toggleBold(), i: () => this.c.toggleItalic(), u: () => this.c.toggleUnderline() } as Record<string, () => void>)[key];
      if (handled) { e.preventDefault(); e.stopPropagation(); handled(); return; }
      if (key === "z" || key === "y") {
        // Undo inside the editor uses the browser's own typing undo.
        e.stopPropagation();
        return;
      }
      if (["a", "c", "x", "v"].includes(key)) { e.stopPropagation(); return; }
    }
    e.stopPropagation();
  }

  /** Moves to the next or previous table cell (set by the canvas). */
  tabToCell?: (delta: number) => void;

  private insertLineBreak() {
    const sel = document.getSelection();
    if (!sel?.rangeCount) return;
    const range = sel.getRangeAt(0);
    range.deleteContents();
    const br = document.createElement("br");
    range.insertNode(br);
    // A break at the end of a paragraph needs a second one to show the new line.
    const after = document.createTextNode(ZWSP);
    br.after(after);
    range.setStart(after, 1);
    range.collapse(true);
    sel.removeAllRanges();
    sel.addRange(range);
    this.normalize();
  }

  // MARK: Selection helpers

  private range(): Range | null {
    const sel = document.getSelection();
    if (!sel?.rangeCount) return null;
    const r = sel.getRangeAt(0);
    return this.root.contains(r.commonAncestorContainer) ? r : null;
  }

  private placeCaretAtEnd() {
    const range = document.createRange();
    range.selectNodeContents(this.root);
    range.collapse(false);
    const sel = document.getSelection();
    sel?.removeAllRanges();
    sel?.addRange(range);
  }

  selectAll() {
    const range = document.createRange();
    range.selectNodeContents(this.root);
    const sel = document.getSelection();
    sel?.removeAllRanges();
    sel?.addRange(range);
  }

  /** Text nodes touched by the selection, split so they lie wholly inside it. */
  private selectedTextNodes(range: Range): Text[] {
    const nodes: Text[] = [];
    const walker = document.createTreeWalker(this.root, NodeFilter.SHOW_TEXT);
    let n: Node | null;
    while ((n = walker.nextNode())) if (range.intersectsNode(n)) nodes.push(n as Text);
    const result: Text[] = [];
    for (let t of nodes) {
      const startOffset = t === range.startContainer ? range.startOffset : 0;
      const endOffset = t === range.endContainer ? range.endOffset : t.length;
      if (startOffset >= endOffset) continue;
      if (endOffset < t.length) t.splitText(endOffset);
      if (startOffset > 0) t = t.splitText(startOffset);
      result.push(t);
    }
    return result;
  }

  private spanOf(node: Node): HTMLElement | null {
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : (node as HTMLElement);
    return el?.closest<HTMLElement>("span[data-r]") ?? null;
  }

  private paragraphOf(node: Node): HTMLElement | null {
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : (node as HTMLElement);
    return el?.closest<HTMLElement>(".p") ?? null;
  }

  // MARK: TextEditing

  currentRunStyle(): RunStyle {
    const range = this.range();
    const node = range?.startContainer;
    let span = node ? this.spanOf(node) : null;
    if (!span && node instanceof HTMLElement) span = node.querySelector("span[data-r]");
    if (!span && range && node) {
      const p = this.paragraphOf(node);
      span = p?.querySelector("span[data-r]") ?? null;
    }
    return clone(this.runStyles[Number(span?.dataset.r ?? 0)] ?? plainRun());
  }

  currentParagraphStyle(): ParagraphStyle {
    const range = this.range();
    const p = range ? this.paragraphOf(range.startContainer) : this.paragraphs()[0];
    return clone(this.paragraphStyles[Number(p?.dataset.p ?? 0)] ?? plainParagraphStyle());
  }

  applyRunStyle(change: (r: RunStyle) => void) {
    const range = this.range();
    if (!range) { this.root.focus(); return; }
    if (range.collapsed) {
      // Typing after this uses the new formatting: a fresh span holding a zero-width space.
      const span = this.spanOf(range.startContainer);
      const style = clone(this.runStyles[Number(span?.dataset.r ?? 0)] ?? plainRun());
      change(style);
      const fresh = document.createElement("span");
      fresh.dataset.r = String(this.styleIndex(style));
      const text = document.createTextNode(ZWSP);
      fresh.append(text);
      if (span && range.startContainer.nodeType === Node.TEXT_NODE) {
        const t = range.startContainer as Text;
        const rest = t.splitText(range.startOffset);
        const tail = document.createElement("span");
        tail.dataset.r = span.dataset.r!;
        let next: Node | null = rest;
        while (next) { const following: Node | null = next.nextSibling; tail.append(next); next = following; }
        span.after(fresh, tail);
        if (!tail.textContent) tail.remove();
      } else range.insertNode(fresh);
      const sel = document.getSelection()!;
      const caret = document.createRange();
      caret.setStart(text, 1);
      caret.collapse(true);
      sel.removeAllRanges();
      sel.addRange(caret);
      this.restyle();
      return;
    }
    const nodes = this.selectedTextNodes(range);
    for (const t of nodes) {
      const span = this.spanOf(t);
      const style = clone(this.runStyles[Number(span?.dataset.r ?? 0)] ?? plainRun());
      change(style);
      const index = String(this.styleIndex(style));
      if (span && span.childNodes.length === 1) { span.dataset.r = index; continue; }
      // Split the span around this text.
      const fresh = document.createElement("span");
      fresh.dataset.r = index;
      if (span) {
        const before = document.createElement("span");
        before.dataset.r = span.dataset.r!;
        const after = document.createElement("span");
        after.dataset.r = span.dataset.r!;
        let seen = false;
        for (const child of [...span.childNodes]) {
          if (child === t) { seen = true; continue; }
          (seen ? after : before).append(child);
        }
        fresh.append(t);
        span.replaceWith(...[before, fresh, after].filter((s) => s === fresh || s.childNodes.length));
      } else {
        t.replaceWith(fresh);
        fresh.append(t);
      }
    }
    if (nodes.length) {
      const sel = document.getSelection()!;
      const r = document.createRange();
      r.setStart(nodes[0], 0);
      r.setEnd(nodes[nodes.length - 1], nodes[nodes.length - 1].length);
      sel.removeAllRanges();
      sel.addRange(r);
    }
    this.restyle();
  }

  applyParagraphStyle(change: (p: ParagraphStyle) => void) {
    const range = this.range();
    const all = this.paragraphs();
    let chosen = all;
    if (range) {
      const start = this.paragraphOf(range.startContainer) ?? all[0];
      const end = this.paragraphOf(range.endContainer) ?? start;
      const a = all.indexOf(start), b = all.indexOf(end);
      chosen = all.slice(Math.max(0, Math.min(a, b)), Math.max(a, b) + 1);
    }
    for (const div of chosen) {
      const style = clone(this.paragraphStyles[Number(div.dataset.p)] ?? plainParagraphStyle());
      change(style);
      div.dataset.p = String(this.paragraphIndex(style));
    }
    this.restyle();
  }

  insertText(text: string) {
    this.root.focus();
    const range = this.range();
    if (!range) return;
    range.deleteContents();
    const lines = text.replace(/\r\n?/g, "\n").split("\n");
    const node = document.createTextNode(lines[0]);
    range.insertNode(node);
    let last: Node = node;
    // Extra lines become new paragraphs with the same formatting.
    if (lines.length > 1) {
      const p = this.paragraphOf(node);
      const span = this.spanOf(node);
      if (p) {
        let after: Node | null = (span ?? node).nextSibling;
        const tail: Node[] = [];
        while (after) { tail.push(after); after = after.nextSibling; }
        let current = p;
        lines.slice(1).forEach((line, i) => {
          const div = document.createElement("div");
          div.className = "p";
          div.dataset.p = p.dataset.p!;
          const s = document.createElement("span");
          s.dataset.r = span?.dataset.r ?? "0";
          s.append(line);
          div.append(s);
          if (i === lines.length - 2) div.append(...tail);
          current.after(div);
          current = div;
          last = s.firstChild ?? s;
        });
      }
    }
    const sel = document.getSelection()!;
    const caret = document.createRange();
    if (last.nodeType === Node.TEXT_NODE) caret.setStart(last, (last as Text).length); else caret.setStartAfter(last);
    caret.collapse(true);
    sel.removeAllRanges();
    sel.addRange(caret);
    this.normalize();
  }

  selectedText(): string {
    return this.range()?.toString().replace(/​/g, "") ?? "";
  }

  // MARK: Reading back

  textBody(): TextBody {
    const body = clone(this.body);
    body.paragraphs = this.paragraphs().map((div) => {
      const style = clone(this.paragraphStyles[Number(div.dataset.p)] ?? plainParagraphStyle());
      const runs: { text: string; style: RunStyle }[] = [];
      let lastStyle = Number((div.querySelector("[data-r]") as HTMLElement | null)?.dataset.r ?? 0);
      const push = (text: string, index: number) => {
        lastStyle = index;
        const prev = runs[runs.length - 1];
        const s = this.runStyles[index] ?? plainRun();
        if (prev && JSON.stringify(prev.style) === JSON.stringify(s)) prev.text += text;
        else runs.push({ text, style: clone(s) });
      };
      const walker = document.createTreeWalker(div, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
      let n: Node | null;
      while ((n = walker.nextNode())) {
        if (n.nodeType === Node.TEXT_NODE) {
          const text = (n as Text).data.replace(/​/g, "");
          if (text) push(text, Number(this.spanOf(n)?.dataset.r ?? lastStyle));
        } else if ((n as HTMLElement).tagName === "BR") {
          // A trailing <br> only keeps an empty line open; others are line breaks.
          const isLast = !nextContent(n, div);
          if (!isLast) push("\u2028", Number(this.spanOf(n)?.dataset.r ?? lastStyle));
        }
      }
      if (!runs.length) runs.push({ text: "", style: clone(this.runStyles[lastStyle] ?? plainRun()) });
      return { runs, style };
    });
    if (!body.paragraphs.length) body.paragraphs = [{ runs: [{ text: "", style: plainRun() }], style: plainParagraphStyle() }];
    return body;
  }

  commit() {
    if (this.finished) return;
    this.finished = true;
    const body = this.textBody();
    const changed = JSON.stringify(body) !== this.original;
    this.teardown();
    this.c.finishTextEditing(this.elementID, this.cell, body, changed);
  }

  cancel() {
    if (this.finished) return;
    this.finished = true;
    this.teardown();
  }

  private teardown() {
    document.removeEventListener("selectionchange", this.selectionChanged);
    this.box.remove();
    this.onEnd();
  }
}

function nextContent(node: Node, root: Node): boolean {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
  walker.currentNode = node;
  let n: Node | null;
  while ((n = walker.nextNode())) {
    if (n.nodeType === Node.TEXT_NODE && (n as Text).data.replace(/​/g, "")) return true;
    if ((n as HTMLElement).tagName === "BR") return true;
  }
  return false;
}

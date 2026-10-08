import type { Presentation } from "./model/types";
import { plainText, textOf } from "./model/core";
import { slideTitle, visibleSlideIndices } from "./model/presentation";
import { preloadPictures } from "./render/paint";
import { renderSlide } from "./render/slide";

export type PrintKind = "slides" | "handouts" | "notes" | "outline";

const escapeHTML = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

/**
 * Lays the presentation out as print pages and opens the system print
 * dialog, which also offers Save as PDF (Microsoft Print to PDF on Windows,
 * Print to File on Linux).
 */
export async function printPresentation(p: Presentation, kind: PrintKind, includeHidden = false): Promise<void> {
  await preloadPictures(p.media);
  const root = document.getElementById("print-root")!;
  root.replaceChildren();
  const indices = includeHidden ? p.slides.map((_, i) => i) : visibleSlideIndices(p);
  const [w, h] = p.slideSize;
  const image = (i: number, width: number) => renderSlide(p.slides[i], i + 1, p, width).toDataURL("image/png");
  let pageCSS: string;
  if (kind === "slides") {
    pageCSS = `@page { size: ${w}pt ${h}pt; margin: 0; }`;
    for (const i of indices) {
      const page = document.createElement("div");
      page.className = "print-page";
      page.style.cssText = `width:${w}pt;height:${h}pt`;
      page.innerHTML = `<img src="${image(i, 2000)}" style="width:${w}pt;height:${h}pt">`;
      root.append(page);
    }
  } else if (kind === "handouts") {
    pageCSS = "@page { size: letter portrait; margin: 0.5in; }";
    for (let n = 0; n < indices.length; n += 3) {
      const page = document.createElement("div");
      page.className = "print-page";
      page.style.cssText = "width:7.5in;height:10in;justify-content:flex-start";
      const rows = indices.slice(n, n + 3).map((i) => `<div class="handout-row"><img src="${image(i, 900)}" style="border:0.5pt solid #999;width:100%"><div class="handout-lines" style="height:${(3.4 * 72 * h) / w}pt"></div></div>`).join("");
      page.innerHTML = `<div class="handouts" style="grid-template-columns:1fr">${rows}</div><div class="footer">${Math.floor(n / 3) + 1}</div>`;
      root.append(page);
    }
  } else if (kind === "notes") {
    pageCSS = "@page { size: letter portrait; margin: 0.6in; }";
    for (const i of indices) {
      const page = document.createElement("div");
      page.className = "print-page";
      page.style.cssText = "width:7.3in;height:9.8in;justify-content:flex-start";
      page.innerHTML = `<img src="${image(i, 1400)}" style="width:6.5in;border:0.5pt solid #999"><div class="notes-text">${escapeHTML(p.slides[i].notes)}</div><div class="footer">${i + 1}</div>`;
      root.append(page);
    }
  } else {
    pageCSS = "@page { size: letter portrait; margin: 0.75in; }";
    const page = document.createElement("div");
    page.className = "print-page";
    page.style.alignItems = "stretch";
    page.innerHTML = `<div class="outline">${indices.map((i) => {
      const s = p.slides[i];
      const body = s.elements.filter((e) => !e.placeholder || e.placeholder === "body" || e.placeholder === "subtitle").flatMap((e) => (textOf(e) ? textOf(e)!.paragraphs : []));
      return `<h3>${i + 1}. ${escapeHTML(slideTitle(s) || "Untitled")}</h3>${body.filter((x) => x.runs.some((r) => r.text)).map((x) => `<p style="margin-left:${x.style.level * 18 + 12}pt">• ${escapeHTML(x.runs.map((r) => r.text).join(""))}</p>`).join("")}`;
    }).join("")}</div>`;
    root.append(page);
  }
  let style = document.getElementById("print-page-style");
  if (!style) { style = document.createElement("style"); style.id = "print-page-style"; document.head.append(style); }
  style.textContent = `@media print { ${pageCSS} }`;
  // Give the browser a moment to decode the page images.
  await Promise.all([...root.querySelectorAll("img")].map((img) => img.decode().catch(() => undefined)));
  window.print();
  setTimeout(() => root.replaceChildren(), 1000);
}

/** The outline as Rich Text (titles bold, bullets indented by level). */
export function outlineRTF(p: Presentation): string {
  const rtf = (s: string) => s.replace(/[\\{}]/g, (c) => "\\" + c).replace(/[^\x00-\x7f]/g, (c) => `\\u${c.charCodeAt(0) > 32767 ? c.charCodeAt(0) - 65536 : c.charCodeAt(0)}?`).replace(/\n/g, "\\line ");
  let out = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\fs24\n";
  p.slides.forEach((s, i) => {
    out += `\\pard\\sb240\\b ${i + 1}. ${rtf(slideTitle(s) || "Untitled")}\\b0\\par\n`;
    for (const e of s.elements) {
      if (e.placeholder && e.placeholder !== "body" && e.placeholder !== "subtitle") continue;
      const t = textOf(e);
      if (!t || !plainText(t)) continue;
      for (const para of t.paragraphs) {
        const text = para.runs.map((r) => r.text).join("");
        if (text) out += `\\pard\\li${360 + para.style.level * 360} ${rtf(text)}\\par\n`;
      }
    }
  });
  return out + "}";
}

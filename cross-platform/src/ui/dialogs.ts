import type { ChartContent, ChartKind, ElementAction, Fill, HeaderFooter, LegendPosition, PatternKind, SlideShowSettings, UUID } from "../model/types";
import {
  CHART_TITLES, chartOf, clone, fillSolid, imageOf, isRoundChart, parseHex, solidFill, themePaint, twoTone,
  gradientFill, hexString, findElement, R, elementTexts, textOf, tableOf, plainText,
} from "../model/core";
import { SLIDE_SIZES } from "../model/catalog";
import { ICON_CATEGORIES, SMARTART, smartArtSample, type PresentationTemplate, type SmartArtKind } from "../model/templates";
import { slideTitle } from "../model/presentation";
import type { FindOptions, PresentationController } from "../engine/controller";
import { renderSlide } from "../render/slide";
import { symbolSVG } from "../render/symbols";
import { installedFonts } from "../render/fonts";
import { picture, pictureSize } from "../render/paint";
import { basename, openURL } from "../platform";
import { settings, updateSettings } from "../settings";
import { THEMES } from "../model/themes";
import { APP_VERSION, platformName } from "../version";
import { showPalette, swatchCSS } from "./colors";

interface DialogButton { label: string; value: string; primary?: boolean; left?: boolean }

const dialog = () => document.getElementById("dialog") as HTMLDialogElement;
let queue: Promise<unknown> = Promise.resolve();

/** Shows a modal dialog; resolves with the clicked button's value, or null when dismissed. */
export function showDialog(title: string, body: HTMLElement | string, buttons: DialogButton[], options: { onOpen?: (root: HTMLElement) => void; width?: "wide" | "xwide" } = {}): Promise<string | null> {
  const run = () => new Promise<string | null>((resolve) => {
    const el = dialog();
    el.replaceChildren();
    el.className = options.width ?? "";
    const content = document.createElement("form");
    content.method = "dialog";
    const main = document.createElement("div");
    main.className = "dialog-body";
    const heading = document.createElement("h2");
    heading.textContent = title;
    main.append(heading);
    if (typeof body === "string") {
      const p = document.createElement("p");
      p.textContent = body;
      main.append(p);
    } else main.append(body);
    const actions = document.createElement("div");
    actions.className = "dialog-actions";
    for (const b of buttons) {
      const button = document.createElement("button");
      button.textContent = b.label;
      button.value = b.value;
      if (b.primary) button.className = "primary";
      if (b.left) button.classList.add("left");
      actions.append(button);
    }
    content.append(main, actions);
    el.append(content);
    el.onclose = () => resolve(el.returnValue && el.returnValue !== "cancel" ? el.returnValue : null);
    el.returnValue = "";
    content.addEventListener("submit", (event) => {
      const submitter = (event as SubmitEvent).submitter as HTMLButtonElement | null;
      if (!submitter) {
        event.preventDefault();
        el.close(buttons.find((b) => b.primary)?.value ?? "");
      }
    });
    el.showModal();
    options.onOpen?.(main);
  });
  const next = queue.then(run, run);
  queue = next.catch(() => undefined);
  return next;
}

export const html = (markup: string) => {
  const div = document.createElement("div");
  div.innerHTML = markup;
  return div;
};

export const escape = (text: string) => text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
const OK_CANCEL = (ok = "OK"): DialogButton[] => [{ label: "Cancel", value: "cancel" }, { label: ok, value: "ok", primary: true }];
const q = <T extends HTMLElement>(root: HTMLElement, selector: string) => root.querySelector<T>(selector)!;
const focusFirst = (selector: string) => (root: HTMLElement) => { const el = root.querySelector<HTMLInputElement>(selector); el?.focus(); el?.select?.(); };

export async function alertDialog(message: string, info?: string) {
  await showDialog(message, html(info ? `<p>${escape(info)}</p>` : ""), [{ label: "OK", value: "ok", primary: true }]);
}

export async function promptText(title: string, label: string, value = "", placeholder = ""): Promise<string | null> {
  const body = html(`<div class="field"><label for="p-text">${escape(label)}</label><input id="p-text" type="text" value="${escape(value)}" placeholder="${escape(placeholder)}"></div>`);
  if ((await showDialog(title, body, OK_CANCEL(), { onOpen: focusFirst("#p-text") })) !== "ok") return null;
  return q<HTMLInputElement>(body, "#p-text").value;
}

// MARK: Templates

export async function templateChooser(content: PresentationTemplate[], themes: PresentationTemplate[], recent: string[], openRecent: (path: string) => void, openOther: () => void): Promise<PresentationTemplate | null> {
  let chosen: PresentationTemplate | null = null;
  const all = [...themes, ...content];
  const card = (t: PresentationTemplate, i: number) => `<button type="button" class="template-card" data-i="${i}"><canvas></canvas><div class="meta"><b>${escape(t.name)}</b><span>${escape(t.subtitle)}</span></div></button>`;
  const body = html(`
    <div class="section-title" style="margin-top:0">Themes</div>
    <div class="template-grid">${themes.map((t, i) => card(t, i)).join("")}</div>
    <div class="section-title">Templates</div>
    <div class="template-grid">${content.map((t, i) => card(t, themes.length + i)).join("")}</div>
    ${recent.length ? `<div class="section-title">Recent</div><div class="recent-list">${recent.slice(0, 6).map((p) => `<button type="button" data-path="${escape(p)}">${escape(basename(p))}<span>${escape(p)}</span></button>`).join("")}</div>` : ""}`);
  body.addEventListener("click", (e) => {
    const cardEl = (e.target as HTMLElement).closest<HTMLElement>("[data-i]");
    if (cardEl) { chosen = all[Number(cardEl.dataset.i)]; dialog().close("ok"); return; }
    const recentButton = (e.target as HTMLElement).closest<HTMLElement>("[data-path]");
    if (recentButton) { dialog().close("cancel"); openRecent(recentButton.dataset.path!); }
  });
  const result = await showDialog("New Presentation", body, [{ label: "Open…", value: "open", left: true }, { label: "Cancel", value: "cancel" }], {
    width: "xwide",
    onOpen: (root) => {
      requestAnimationFrame(() => root.querySelectorAll<HTMLElement>(".template-card").forEach((el) => {
        try {
          const p = all[Number(el.dataset.i)].build();
          const preview = renderSlide(p.slides[0], 1, p, 360);
          const canvas = el.querySelector("canvas")!;
          canvas.width = preview.width;
          canvas.height = preview.height;
          canvas.getContext("2d")!.drawImage(preview, 0, 0);
          canvas.style.height = "auto";
          canvas.style.aspectRatio = `${p.slideSize[0]} / ${p.slideSize[1]}`;
        } catch {
          // A preview is decoration only.
        }
      }));
      root.querySelector<HTMLElement>(".template-card")?.focus();
    },
  });
  if (result === "open") openOther();
  return chosen;
}

// MARK: Insert

export async function insertTableDialog(): Promise<[number, number] | null> {
  const body = html(`
    <div class="field"><label for="t-cols">Number of columns</label><input id="t-cols" type="number" min="1" max="30" value="4"></div>
    <div class="field"><label for="t-rows">Number of rows</label><input id="t-rows" type="number" min="1" max="60" value="3"></div>`);
  if ((await showDialog("Insert Table", body, OK_CANCEL("Insert"), { onOpen: focusFirst("#t-cols") })) !== "ok") return null;
  const n = (id: string, max: number) => Math.max(1, Math.min(max, Math.round(Number(q<HTMLInputElement>(body, id).value) || 1)));
  return [n("#t-rows", 60), n("#t-cols", 30)];
}

export async function iconDialog(): Promise<string | null> {
  let chosen: string | null = null;
  const body = html(`<input id="i-search" type="search" placeholder="Search icons" style="margin-bottom:10px"><div id="i-list" style="max-height:380px;overflow:auto"></div>`);
  const render = (filter: string) => {
    const list = q(body, "#i-list");
    list.innerHTML = ICON_CATEGORIES.map(([name, symbols]) => {
      const shown = symbols.filter((s) => !filter || s.includes(filter) || name.toLowerCase().includes(filter));
      if (!shown.length) return "";
      return `<div class="section-title">${escape(name)}</div><div style="display:grid;grid-template-columns:repeat(auto-fill,44px);gap:6px">${shown.map((s) => `<button type="button" data-symbol="${s}" title="${s}" style="width:44px;height:44px;border:1px solid var(--bar-border);border-radius:8px;background:var(--field)">${symbolSVG(s, 26)}</button>`).join("")}</div>`;
    }).join("");
  };
  render("");
  q<HTMLInputElement>(body, "#i-search").addEventListener("input", (e) => render((e.target as HTMLInputElement).value.trim().toLowerCase()));
  body.addEventListener("click", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("[data-symbol]");
    if (!b) return;
    body.querySelectorAll("[data-symbol]").forEach((x) => ((x as HTMLElement).style.outline = ""));
    b.style.outline = "2px solid var(--accent)";
    chosen = b.dataset.symbol!;
  });
  body.addEventListener("dblclick", (e) => { if ((e.target as HTMLElement).closest("[data-symbol]")) dialog().close("ok"); });
  const result = await showDialog("Insert Icons", body, OK_CANCEL("Insert"), { width: "wide", onOpen: focusFirst("#i-search") });
  return result === "ok" ? chosen : null;
}

export async function smartArtDialog(): Promise<{ kind: SmartArtKind; items: string[] } | null> {
  let kind: SmartArtKind = "process";
  const body = html(`
    <div style="display:grid;grid-template-columns:200px 1fr;gap:14px">
      <div class="list-box" style="max-height:300px">${SMARTART.map(([k, title, cat]) => `<div class="item" data-kind="${k}"><span class="grow">${escape(title)}</span><span class="muted">${cat}</span></div>`).join("")}</div>
      <div><label class="note">Text, one item per line</label><textarea id="sa-items" rows="10" style="margin-top:6px"></textarea></div>
    </div>`);
  const select = (k: SmartArtKind) => {
    kind = k;
    body.querySelectorAll<HTMLElement>("[data-kind]").forEach((el) => el.classList.toggle("selected", el.dataset.kind === k));
    q<HTMLTextAreaElement>(body, "#sa-items").value = smartArtSample(k).join("\n");
  };
  select(kind);
  body.addEventListener("click", (e) => { const el = (e.target as HTMLElement).closest<HTMLElement>("[data-kind]"); if (el) select(el.dataset.kind as SmartArtKind); });
  if ((await showDialog("Choose a SmartArt Graphic", body, OK_CANCEL("Insert"), { width: "wide" })) !== "ok") return null;
  return { kind, items: q<HTMLTextAreaElement>(body, "#sa-items").value.split("\n").map((s) => s.trim()).filter(Boolean) };
}

export async function symbolDialog(): Promise<string | null> {
  const symbols = "©®™§¶†‡•…–—‘’“”«»€£¥¢$¤°±×÷≠≈≤≥∞√∑∏∫∂∆πΩµαβγδεθλσφψω←→↑↓↔⇒⇔✓✗★☆♥♦♣♠☺☻☼♪♫✉✈☎⌘⌥⇧⏎";
  let chosen: string | null = null;
  const body = html(`<div style="display:grid;grid-template-columns:repeat(12,34px);gap:4px">${[...symbols].map((s) => `<button type="button" data-s="${escape(s)}" style="height:34px;border:1px solid var(--bar-border);border-radius:6px;background:var(--field);font-size:18px">${escape(s)}</button>`).join("")}</div>`);
  body.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest<HTMLElement>("[data-s]"); if (b) { chosen = b.dataset.s!; dialog().close("ok"); } });
  await showDialog("Symbol", body, [{ label: "Cancel", value: "cancel" }], { width: "wide" });
  return chosen;
}

export async function dateTimeDialog(): Promise<string | null> {
  const now = new Date();
  const formats = [
    now.toLocaleDateString(), now.toLocaleDateString(undefined, { dateStyle: "medium" }), now.toLocaleDateString(undefined, { dateStyle: "long" }),
    now.toLocaleDateString(undefined, { dateStyle: "full" }), now.toISOString().slice(0, 10), now.toLocaleTimeString(undefined, { timeStyle: "short" }),
    now.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }),
  ];
  let chosen = 0;
  const body = html(`<div class="list-box">${formats.map((f, i) => `<div class="item ${i === 0 ? "selected" : ""}" data-i="${i}">${escape(f)}</div>`).join("")}</div>`);
  body.addEventListener("click", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>("[data-i]");
    if (!el) return;
    chosen = Number(el.dataset.i);
    body.querySelectorAll(".item").forEach((x) => x.classList.toggle("selected", x === el));
  });
  return (await showDialog("Date & Time", body, OK_CANCEL("Insert"))) === "ok" ? formats[chosen] : null;
}

// MARK: Charts

export async function chartDataDialog(c: PresentationController, id: UUID): Promise<void> {
  const e = findElement(c.currentSlide.elements, id);
  const chart = e && chartOf(e);
  if (!chart) return;
  const draft: ChartContent = clone(chart);
  const kinds = Object.keys(CHART_TITLES) as ChartKind[];
  const body = html(`
    <div class="columns-2">
      <div class="field"><label>Chart type</label><select id="c-kind">${kinds.map((k) => `<option value="${k}">${CHART_TITLES[k]}</option>`).join("")}</select></div>
      <div class="field"><label>Legend</label><select id="c-legend">${(["none", "bottom", "right", "top", "left"] as LegendPosition[]).map((l) => `<option value="${l}">${l[0].toUpperCase() + l.slice(1)}</option>`).join("")}</select></div>
    </div>
    <div class="field"><label for="c-title">Title</label><input id="c-title" type="text"></div>
    <div class="field-row" style="margin-bottom:10px">
      <label class="toggle" style="margin:0"><input id="c-labels" type="checkbox"> Data labels</label>
      <label class="toggle" style="margin:0"><input id="c-grid" type="checkbox"> Gridlines</label>
      <span style="flex:1"></span><label class="note">Font size</label><input id="c-font" type="number" min="6" max="48" style="width:64px">
    </div>
    <div style="overflow:auto;max-height:300px;border:1px solid var(--bar-border);border-radius:8px"><table id="c-table" style="border-collapse:collapse;width:100%"></table></div>
    <div class="field-row" style="margin-top:8px">
      <button type="button" id="c-addrow">+ Category</button><button type="button" id="c-delrow">− Category</button>
      <button type="button" id="c-addcol">+ Series</button><button type="button" id="c-delcol">− Series</button>
    </div>`);
  q<HTMLSelectElement>(body, "#c-kind").value = draft.kind;
  q<HTMLSelectElement>(body, "#c-legend").value = draft.legend;
  q<HTMLInputElement>(body, "#c-title").value = draft.title ?? "";
  q<HTMLInputElement>(body, "#c-labels").checked = draft.showDataLabels;
  q<HTMLInputElement>(body, "#c-grid").checked = draft.showGridlines;
  q<HTMLInputElement>(body, "#c-font").value = String(draft.fontSize);
  const cellStyle = "border:1px solid var(--bar-border);padding:0;";
  const inputStyle = "width:100%;border:0;height:26px;padding:0 6px;background:transparent;";
  const renderTable = () => {
    const t = q<HTMLTableElement>(body, "#c-table");
    const series = isRoundChart(draft.kind) ? draft.series.slice(0, 1) : draft.series;
    t.innerHTML = `<tr><th style="${cellStyle}"></th>${series.map((s, j) => `<th style="${cellStyle}"><input data-series="${j}" style="${inputStyle}font-weight:600" value="${escape(s.name)}"></th>`).join("")}</tr>`
      + draft.categories.map((cat, i) => `<tr><td style="${cellStyle}"><input data-cat="${i}" style="${inputStyle}" value="${escape(cat)}"></td>${series.map((s, j) => `<td style="${cellStyle}"><input data-v="${i},${j}" style="${inputStyle}text-align:right" value="${s.values[i] ?? ""}"></td>`).join("")}</tr>`).join("");
  };
  renderTable();
  body.addEventListener("input", (ev) => {
    const el = ev.target as HTMLInputElement;
    if (el.dataset.series) draft.series[Number(el.dataset.series)].name = el.value;
    if (el.dataset.cat) draft.categories[Number(el.dataset.cat)] = el.value;
    if (el.dataset.v) {
      const [i, j] = el.dataset.v.split(",").map(Number);
      const v = Number(el.value.replace(/,/g, ""));
      draft.series[j].values[i] = Number.isFinite(v) ? v : 0;
    }
  });
  q<HTMLSelectElement>(body, "#c-kind").addEventListener("change", (ev) => { draft.kind = (ev.target as HTMLSelectElement).value as ChartKind; renderTable(); });
  q(body, "#c-addrow").addEventListener("click", () => { draft.categories.push(`Category ${draft.categories.length + 1}`); draft.series.forEach((s) => s.values.push(0)); renderTable(); });
  q(body, "#c-delrow").addEventListener("click", () => { if (draft.categories.length > 1) { draft.categories.pop(); draft.series.forEach((s) => s.values.splice(draft.categories.length)); renderTable(); } });
  q(body, "#c-addcol").addEventListener("click", () => { draft.series.push({ name: `Series ${draft.series.length + 1}`, values: draft.categories.map(() => 0) }); renderTable(); });
  q(body, "#c-delcol").addEventListener("click", () => { if (draft.series.length > 1) { draft.series.pop(); renderTable(); } });
  if ((await showDialog("Edit Chart Data", body, OK_CANCEL(), { width: "wide" })) !== "ok") return;
  c.setChart(id, (target) => {
    Object.assign(target, draft);
    const title = q<HTMLInputElement>(body, "#c-title").value;
    if (title) target.title = title; else delete target.title;
    target.legend = q<HTMLSelectElement>(body, "#c-legend").value as LegendPosition;
    target.showDataLabels = q<HTMLInputElement>(body, "#c-labels").checked;
    target.showGridlines = q<HTMLInputElement>(body, "#c-grid").checked;
    target.fontSize = Math.max(6, Math.min(48, Number(q<HTMLInputElement>(body, "#c-font").value) || 12));
  });
}

// MARK: Links and actions

export async function hyperlinkDialog(current: string, slides: string[]): Promise<{ url: string } | "remove" | null> {
  const body = html(`
    <div class="field"><label for="l-url">Address</label><input id="l-url" type="text" placeholder="https://example.com or name@example.com" value="${escape(current.startsWith("#slide") ? "" : current)}"></div>
    <div class="field"><label for="l-slide">Or a slide</label><select id="l-slide"><option value="">—</option>${slides.map((s, i) => `<option value="${i}" ${current === `#slide${i + 1}` ? "selected" : ""}>${i + 1}. ${escape(s || "Untitled")}</option>`).join("")}</select></div>`);
  const buttons = OK_CANCEL(current ? "Update" : "Insert");
  if (current) buttons.unshift({ label: "Remove Link", value: "remove", left: true });
  const result = await showDialog(current ? "Edit Link" : "Insert Link", body, buttons, { onOpen: focusFirst("#l-url") });
  if (result === "remove") return "remove";
  if (result !== "ok") return null;
  const slide = q<HTMLSelectElement>(body, "#l-slide").value;
  if (slide) return { url: `#slide${Number(slide) + 1}` };
  let url = q<HTMLInputElement>(body, "#l-url").value.trim();
  if (!url) return null;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) url = url.includes("@") && !url.includes("/") ? `mailto:${url}` : `https://${url}`;
  return { url };
}

export async function actionDialog(current: ElementAction | undefined, slides: { id: UUID; title: string }[]): Promise<ElementAction | null | "cancel"> {
  const kind = !current ? "none" : Object.keys(current)[0];
  const body = html(`
    <div class="pane-radio" id="a-kind">
      ${[["none", "None"], ["nextSlide", "Next Slide"], ["previousSlide", "Previous Slide"], ["firstSlide", "First Slide"], ["lastSlide", "Last Slide"], ["endShow", "End Show"], ["slide", "Slide…"], ["url", "URL…"]]
        .map(([v, l]) => `<label><input type="radio" name="a" value="${v}" ${v === kind ? "checked" : ""}> ${l}</label>`).join("")}
    </div>
    <div class="field" style="margin-top:10px"><label>Slide</label><select id="a-slide">${slides.map((s, i) => `<option value="${s.id}" ${current && "slide" in current && current.slide._0 === s.id ? "selected" : ""}>${i + 1}. ${escape(s.title || "Untitled")}</option>`).join("")}</select></div>
    <div class="field"><label>URL</label><input id="a-url" type="text" value="${current && "url" in current ? escape(current.url._0) : ""}" placeholder="https://"></div>
    <p class="note">Actions run when the object is clicked during a slide show.</p>`);
  if ((await showDialog("Action Settings", body, OK_CANCEL())) !== "ok") return "cancel";
  const v = body.querySelector<HTMLInputElement>("input[name=a]:checked")?.value ?? "none";
  switch (v) {
    case "none": return null;
    case "slide": return { slide: { _0: q<HTMLSelectElement>(body, "#a-slide").value } };
    case "url": { const url = q<HTMLInputElement>(body, "#a-url").value.trim(); return url ? { url: { _0: /^[a-z]+:/i.test(url) ? url : `https://${url}` } } : null; }
    default: return { [v]: {} } as ElementAction;
  }
}

export async function altTextDialog(current: string): Promise<string | null> {
  const body = html(`<p class="note">Describe the object for people who use screen readers.</p><textarea id="alt" rows="4">${escape(current)}</textarea>`);
  return (await showDialog("Alt Text", body, OK_CANCEL(), { onOpen: () => q<HTMLTextAreaElement>(body, "#alt").focus() })) === "ok" ? q<HTMLTextAreaElement>(body, "#alt").value : null;
}

// MARK: Find

let lastFind: FindOptions = { text: "", replacement: "", matchCase: false, wholeWords: false };

export async function findReplaceDialog(c: PresentationController, replace: boolean): Promise<void> {
  const body = html(`
    <div class="field"><label for="f-text">Find what</label><input id="f-text" type="text" value="${escape(lastFind.text)}"></div>
    <div class="field" ${replace ? "" : "hidden"}><label for="f-rep">Replace with</label><input id="f-rep" type="text" value="${escape(lastFind.replacement)}"></div>
    <label class="toggle"><input id="f-case" type="checkbox" ${lastFind.matchCase ? "checked" : ""}> Match case</label>
    <label class="toggle"><input id="f-whole" type="checkbox" ${lastFind.wholeWords ? "checked" : ""}> Find whole words only</label>
    <p class="note" id="f-status"></p>`);
  const read = (): FindOptions => (lastFind = {
    text: q<HTMLInputElement>(body, "#f-text").value, replacement: q<HTMLInputElement>(body, "#f-rep").value,
    matchCase: q<HTMLInputElement>(body, "#f-case").checked, wholeWords: q<HTMLInputElement>(body, "#f-whole").checked,
  });
  const status = (text: string) => { q(body, "#f-status").textContent = text; };
  const buttons: DialogButton[] = replace
    ? [{ label: "Close", value: "cancel", left: true }, { label: "Replace All", value: "all" }, { label: "Replace", value: "one" }, { label: "Find Next", value: "next", primary: true }]
    : [{ label: "Close", value: "cancel" }, { label: "Find Next", value: "next", primary: true }];
  // The dialog stays open between searches.
  for (;;) {
    const result = await showDialog(replace ? "Replace" : "Find", body, buttons, { onOpen: focusFirst("#f-text") });
    if (!result) return;
    const o = read();
    if (result === "next") status(c.findNext(o) ? `Found on slide ${c.currentSlideIndex + 1}.` : "Not found.");
    else if (result === "one") { c.replaceCurrent(o); status(c.findNext(o) ? `Next match on slide ${c.currentSlideIndex + 1}.` : "No more matches."); }
    else if (result === "all") { const n = c.replaceAll(o); status(`Replaced ${n} ${n === 1 ? "occurrence" : "occurrences"}.`); }
  }
}

export async function replaceFontsDialog(c: PresentationController): Promise<void> {
  const used = c.usedFonts();
  const fonts = [...new Set([...installedFonts(), ...used])].sort();
  const body = html(`
    <div class="field"><label>Replace</label><select id="rf-old">${used.map((f) => `<option>${escape(f)}</option>`).join("")}</select></div>
    <div class="field"><label>With</label><select id="rf-new">${fonts.map((f) => `<option>${escape(f)}</option>`).join("")}</select></div>`);
  if ((await showDialog("Replace Font", body, OK_CANCEL("Replace"))) !== "ok") return;
  c.replaceFont(q<HTMLSelectElement>(body, "#rf-old").value, q<HTMLSelectElement>(body, "#rf-new").value);
}

// MARK: Design

export async function headerFooterDialog(current: HeaderFooter): Promise<HeaderFooter | null> {
  const body = html(`
    <label class="toggle"><input id="hf-date" type="checkbox" ${current.showDate ? "checked" : ""}> Date and time</label>
    <div class="pane-radio" style="margin:0 0 10px 24px">
      <label><input type="radio" name="hf-mode" value="auto" ${current.fixedDate === undefined ? "checked" : ""}> Update automatically</label>
      <label><input type="radio" name="hf-mode" value="fixed" ${current.fixedDate !== undefined ? "checked" : ""}> Fixed: <input id="hf-fixed" type="text" style="width:200px;height:24px" value="${escape(current.fixedDate ?? new Date().toLocaleDateString())}"></label>
    </div>
    <label class="toggle"><input id="hf-num" type="checkbox" ${current.showSlideNumber ? "checked" : ""}> Slide number</label>
    <label class="toggle"><input id="hf-footer" type="checkbox" ${current.showFooter ? "checked" : ""}> Footer</label>
    <input id="hf-text" type="text" style="margin:-4px 0 12px 24px;width:calc(100% - 24px)" value="${escape(current.footerText)}">
    <label class="toggle"><input id="hf-title" type="checkbox" ${current.hideOnTitleSlide ? "checked" : ""}> Don't show on title slide</label>`);
  if ((await showDialog("Header & Footer", body, OK_CANCEL("Apply to All"))) !== "ok") return null;
  const hf: HeaderFooter = {
    showDate: q<HTMLInputElement>(body, "#hf-date").checked, showSlideNumber: q<HTMLInputElement>(body, "#hf-num").checked,
    showFooter: q<HTMLInputElement>(body, "#hf-footer").checked, footerText: q<HTMLInputElement>(body, "#hf-text").value,
    hideOnTitleSlide: q<HTMLInputElement>(body, "#hf-title").checked,
  };
  if (body.querySelector<HTMLInputElement>("input[name=hf-mode]:checked")?.value === "fixed") hf.fixedDate = q<HTMLInputElement>(body, "#hf-fixed").value;
  return hf;
}

export async function slideSizeDialog(current: [number, number]): Promise<{ size: [number, number]; scale: boolean } | null> {
  const body = html(`
    <div class="field"><label>Slides sized for</label><select id="ss-preset">${SLIDE_SIZES.map(([name, s], i) => `<option value="${i}" ${s[0] === current[0] && s[1] === current[1] ? "selected" : ""}>${escape(name)}</option>`).join("")}<option value="custom">Custom</option></select></div>
    <div class="field"><label>Width (in)</label><input id="ss-w" type="number" step="0.01" value="${(current[0] / 72).toFixed(2)}"></div>
    <div class="field"><label>Height (in)</label><input id="ss-h" type="number" step="0.01" value="${(current[1] / 72).toFixed(2)}"></div>
    <div class="pane-radio"><label><input type="radio" name="ss-scale" value="scale" checked> Scale content to fit</label><label><input type="radio" name="ss-scale" value="keep"> Keep content size</label></div>`);
  q<HTMLSelectElement>(body, "#ss-preset").addEventListener("change", (e) => {
    const v = (e.target as HTMLSelectElement).value;
    if (v === "custom") return;
    const [, s] = SLIDE_SIZES[Number(v)];
    q<HTMLInputElement>(body, "#ss-w").value = (s[0] / 72).toFixed(2);
    q<HTMLInputElement>(body, "#ss-h").value = (s[1] / 72).toFixed(2);
  });
  if ((await showDialog("Slide Size", body, OK_CANCEL())) !== "ok") return null;
  const w = Math.max(72, Math.min(4032, Number(q<HTMLInputElement>(body, "#ss-w").value) * 72 || current[0]));
  const h = Math.max(72, Math.min(4032, Number(q<HTMLInputElement>(body, "#ss-h").value) * 72 || current[1]));
  return { size: [Math.round(w), Math.round(h)], scale: body.querySelector<HTMLInputElement>("input[name=ss-scale]:checked")?.value === "scale" };
}

/** Format Background: solid, gradient, picture or pattern, for this slide or all. */
export async function formatBackgroundDialog(c: PresentationController, pickPicture: () => Promise<string | null>): Promise<void> {
  const slide = c.currentSlide;
  const colors = c.theme.colors;
  let fill: Fill = clone(slide.background ?? c.theme.background);
  const kindOf = (f: Fill) => Object.keys(f)[0];
  const body = html(`
    <div class="segmented" id="bg-kind">${[["solid", "Solid"], ["gradient", "Gradient"], ["image", "Picture"], ["pattern", "Pattern"]].map(([v, l]) => `<button type="button" data-k="${v}">${l}</button>`).join("")}</div>
    <div id="bg-options"></div>
    <label class="toggle"><input id="bg-hide" type="checkbox" ${slide.hideBackgroundGraphics ? "checked" : ""}> Hide background graphics</label>`);
  const render = () => {
    body.querySelectorAll<HTMLElement>("[data-k]").forEach((b) => b.classList.toggle("selected", b.dataset.k === kindOf(fill)));
    const opts = q(body, "#bg-options");
    opts.replaceChildren();
    const colorRow = (label: string, get: () => Parameters<typeof swatchCSS>[0], set: (p: ReturnType<typeof themePaint>) => void) => {
      const row = html(`<div class="field"><label>${label}</label><button type="button" class="swatch-button" style="width:60px;height:26px;border:1px solid var(--bar-border);border-radius:5px;padding:3px;background:var(--field)"><span style="display:block;height:100%;border-radius:3px;background:${swatchCSS(get(), colors)}"></span></button></div>`);
      const button = q<HTMLButtonElement>(row, "button");
      button.addEventListener("click", () => showPalette(button, colors, (p) => { if (p) { set(p); render(); } }));
      opts.append(row.firstElementChild!);
    };
    if ("solid" in fill) { const f = fill; colorRow("Color", () => f.solid._0, (p) => { f.solid._0 = p; }); }
    else if ("gradient" in fill) {
      const g = fill.gradient._0;
      colorRow("From", () => g.stops[0]?.color, (p) => { g.stops[0].color = p; });
      colorRow("To", () => g.stops[g.stops.length - 1]?.color, (p) => { g.stops[g.stops.length - 1].color = p; });
      const row = html(`<div class="field"><label>Type</label><select><option value="linear">Linear</option><option value="radial">Radial</option></select></div><div class="field"><label>Angle</label><input type="number" min="0" max="359" value="${Math.round(g.angle)}"></div>`);
      q<HTMLSelectElement>(row, "select").value = g.kind;
      q<HTMLSelectElement>(row, "select").addEventListener("change", (e) => { g.kind = (e.target as HTMLSelectElement).value as "linear" | "radial"; });
      q<HTMLInputElement>(row, "input").addEventListener("input", (e) => { g.angle = Number((e.target as HTMLInputElement).value) || 0; });
      opts.append(...row.children);
    } else if ("image" in fill) {
      const f = fill.image._0;
      const row = html(`<div class="field"><label>Picture</label><button type="button">Choose…</button></div><div class="field"><label>Mode</label><select><option value="stretch">Stretch</option><option value="fit">Fill</option><option value="tile">Tile</option></select></div><div class="field"><label>Transparency</label><input type="range" min="0" max="100" value="${Math.round(f.transparency * 100)}"></div>`);
      q(row, "button").addEventListener("click", async () => { const id = await pickPicture(); if (id) { f.mediaID = id; render(); } });
      q<HTMLSelectElement>(row, "select").value = f.mode;
      q<HTMLSelectElement>(row, "select").addEventListener("change", (e) => { f.mode = (e.target as HTMLSelectElement).value as "stretch" | "fit" | "tile"; });
      q<HTMLInputElement>(row, "input[type=range]").addEventListener("input", (e) => { f.transparency = Number((e.target as HTMLInputElement).value) / 100; });
      opts.append(...row.children);
    } else if ("pattern" in fill) {
      const f = fill.pattern._0;
      const kinds: PatternKind[] = ["horizontal", "vertical", "diagonalUp", "diagonalDown", "grid", "dots", "checker"];
      const row = html(`<div class="field"><label>Pattern</label><select>${kinds.map((k) => `<option value="${k}">${k.replace(/([A-Z])/g, " $1").replace(/^./, (x) => x.toUpperCase())}</option>`).join("")}</select></div>`);
      q<HTMLSelectElement>(row, "select").value = f.kind;
      q<HTMLSelectElement>(row, "select").addEventListener("change", (e) => { f.kind = (e.target as HTMLSelectElement).value as PatternKind; });
      opts.append(...row.children);
      colorRow("Foreground", () => f.foreground, (p) => { f.foreground = p; });
      colorRow("Background", () => f.background, (p) => { f.background = p; });
    }
  };
  q(body, "#bg-kind").addEventListener("click", (e) => {
    const k = (e.target as HTMLElement).closest<HTMLElement>("[data-k]")?.dataset.k;
    if (!k || k === kindOf(fill)) return;
    const base = fillSolid(fill) ?? themePaint("light1");
    if (k === "solid") fill = solidFill(base);
    else if (k === "gradient") fill = gradientFill(twoTone(base, themePaint("light2")));
    else if (k === "image") fill = { image: { _0: { mediaID: "", mode: "stretch", transparency: 0 } } };
    else fill = { pattern: { _0: { kind: "dots", foreground: themePaint("dark1", 0.6), background: base } } };
    render();
  });
  render();
  const result = await showDialog("Format Background", body, [{ label: "Reset Background", value: "reset", left: true }, { label: "Apply to All", value: "all" }, ...OK_CANCEL("Apply")]);
  if (!result) return;
  const valid = !("image" in fill) || !!fill.image._0.mediaID;
  if (result === "reset") c.setBackground(null, false);
  else if (valid) c.setBackground(fill, result === "all");
  const hide = q<HTMLInputElement>(body, "#bg-hide").checked;
  if (hide !== slide.hideBackgroundGraphics) c.setHideBackgroundGraphics(hide);
}

// MARK: Slide show

export async function setUpShowDialog(current: SlideShowSettings): Promise<SlideShowSettings | null> {
  const body = html(`
    <label class="toggle"><input id="su-loop" type="checkbox" ${current.loopUntilEscape ? "checked" : ""}> Loop continuously until Esc</label>
    <label class="toggle"><input id="su-noanim" type="checkbox" ${current.showWithoutAnimation ? "checked" : ""}> Show without animation</label>
    <label class="toggle"><input id="su-timings" type="checkbox" ${current.useTimings ? "checked" : ""}> Use timings, if present</label>
    <label class="toggle"><input id="su-presenter" type="checkbox" ${current.usePresenterView ? "checked" : ""}> Use Presenter View</label>
    <div class="field"><label>Pen color</label><input id="su-pen" type="color" value="#${hexString(current.penColor).toLowerCase()}"></div>
    <div class="field"><label>Laser pointer color</label><input id="su-laser" type="color" value="#${hexString(current.laserColor).toLowerCase()}"></div>`);
  if ((await showDialog("Set Up Slide Show", body, OK_CANCEL())) !== "ok") return null;
  return {
    loopUntilEscape: q<HTMLInputElement>(body, "#su-loop").checked, showWithoutAnimation: q<HTMLInputElement>(body, "#su-noanim").checked,
    useTimings: q<HTMLInputElement>(body, "#su-timings").checked, usePresenterView: q<HTMLInputElement>(body, "#su-presenter").checked,
    penColor: parseHex(q<HTMLInputElement>(body, "#su-pen").value) ?? current.penColor, laserColor: parseHex(q<HTMLInputElement>(body, "#su-laser").value) ?? current.laserColor,
  };
}

// MARK: Pictures

export async function cropDialog(c: PresentationController): Promise<void> {
  const e = c.primary;
  const image = e && imageOf(e);
  if (!e || !image) return;
  const crop = clone(image.crop);
  const pct = (v: number) => Math.round(v * 1000) / 10;
  const body = html(`
    <p class="note">Crop each side as a percentage of the picture. Negative values add space.</p>
    ${(["left", "top", "right", "bottom"] as const).map((side) => `<div class="field"><label>${side[0].toUpperCase() + side.slice(1)} (%)</label><input data-side="${side}" type="number" step="0.5" min="-50" max="95" value="${pct(crop[side])}"></div>`).join("")}
    <div class="field"><label>Aspect ratio</label><select id="cr-aspect"><option value="">Keep</option><option value="1">1:1</option><option value="1.3333">4:3</option><option value="1.7778">16:9</option><option value="0.75">3:4</option></select></div>`);
  const result = await showDialog("Crop Picture", body, [{ label: "Reset", value: "reset", left: true }, ...OK_CANCEL("Crop")]);
  if (!result) return;
  if (result === "reset") { c.setCrop({ left: 0, top: 0, right: 0, bottom: 0 }); return; }
  body.querySelectorAll<HTMLInputElement>("[data-side]").forEach((input) => { crop[input.dataset.side as keyof typeof crop] = (Number(input.value) || 0) / 100; });
  const aspect = Number(q<HTMLSelectElement>(body, "#cr-aspect").value);
  const p = picture(image.mediaID, c.presentation.media);
  if (aspect && p) {
    // Crop evenly to the chosen aspect ratio and size the frame to match.
    const [iw, ih] = pictureSize(p);
    const current = iw / ih;
    if (current > aspect) { const excess = (1 - aspect / current) / 2; crop.left = excess; crop.right = excess; crop.top = 0; crop.bottom = 0; }
    else { const excess = (1 - current / aspect) / 2; crop.top = excess; crop.bottom = excess; crop.left = 0; crop.right = 0; }
    const r = R(e.frame);
    c.setElementRect(e.id, { x: r.x, y: r.y, w: r.w, h: r.w / aspect }, "Crop");
  }
  c.setCrop(crop);
}

// MARK: Review

export async function accessibilityDialog(c: PresentationController): Promise<void> {
  const issues: string[] = [];
  c.slides.forEach((s, i) => {
    if (!slideTitle(s) && !s.elements.some((e) => e.placeholder === "title" || e.placeholder === "centeredTitle")) issues.push(`Slide ${i + 1}: Missing slide title`);
    for (const e of s.elements) {
      if ((imageOf(e) || chartOf(e) || "icon" in e.content || "media" in e.content) && !e.altText) issues.push(`Slide ${i + 1}: “${e.name}” has no alt text`);
      const t = tableOf(e);
      if (t && !t.style.headerRow) issues.push(`Slide ${i + 1}: Table “${e.name}” has no header row`);
    }
  });
  const body = html(issues.length
    ? `<p>${issues.length} ${issues.length === 1 ? "issue" : "issues"} found.</p><div class="list-box">${issues.map((x) => `<div class="item">${escape(x)}</div>`).join("")}</div>`
    : "<p>No accessibility issues found.</p>");
  await showDialog("Accessibility Checker", body, [{ label: "OK", value: "ok", primary: true }]);
}

export async function wordCountDialog(c: PresentationController): Promise<void> {
  const text = c.slides.flatMap((s) => s.elements.flatMap(elementTexts)).join(" ");
  const notes = c.slides.map((s) => s.notes).join(" ");
  const words = (t: string) => (t.match(/\S+/g) ?? []).length;
  const rows: [string, string][] = [
    ["Slides", String(c.slides.length)], ["Hidden slides", String(c.slides.filter((s) => s.hidden).length)], ["Words on slides", String(words(text))],
    ["Words in notes", String(words(notes))], ["Characters (no spaces)", String(text.replace(/\s/g, "").length)],
    ["Pictures", String(c.slides.reduce((n, s) => n + s.elements.filter((e) => imageOf(e)).length, 0))],
  ];
  await showDialog("Word Count", html(`<div class="list-box">${rows.map(([l, v]) => `<div class="item"><span class="grow">${l}</span><b>${v}</b></div>`).join("")}</div>`), [{ label: "OK", value: "ok", primary: true }]);
}

export async function propertiesDialog(c: PresentationController): Promise<void> {
  const p = c.presentation;
  const body = html(`
    <div class="field"><label>Title</label><input id="pr-title" type="text" value="${escape(p.title)}"></div>
    <div class="field"><label>Author</label><input id="pr-author" type="text" value="${escape(p.author)}"></div>
    <p class="note">Created ${escape(new Date(p.created).toLocaleString())} · ${p.slides.length} slides</p>`);
  if ((await showDialog("Properties", body, OK_CANCEL())) !== "ok") return;
  c.setProperties(q<HTMLInputElement>(body, "#pr-title").value, q<HTMLInputElement>(body, "#pr-author").value);
}

/** Slides from Outline: each unindented line starts a slide; indented lines are bullets. */
export async function outlineDialog(): Promise<string | null> {
  const body = html(`<p class="note">Paste or type an outline. Each line without indentation becomes a slide title; lines indented with a tab or spaces become its bullets.</p><textarea id="ol" rows="14" placeholder="Introduction\n\tWhy this matters\n\tWhat we'll cover\nNext steps"></textarea>`);
  return (await showDialog("Slides from Outline", body, OK_CANCEL("Insert Slides"), { width: "wide", onOpen: () => q<HTMLTextAreaElement>(body, "#ol").focus() })) === "ok" ? q<HTMLTextAreaElement>(body, "#ol").value : null;
}

// MARK: Settings, about, updates

export async function settingsDialog(checkNow: () => void): Promise<void> {
  const s = settings();
  const body = html(`
    <div class="section-title" style="margin-top:0">General</div>
    <label class="toggle"><input id="s-chooser" type="checkbox" ${s.showTemplateChooserOnLaunch ? "checked" : ""}> Show the template chooser when Wired Slides opens</label>
    <div class="field"><label for="s-theme">Default theme</label><select id="s-theme">${THEMES.map((t) => `<option value="${t.id}" ${t.id === s.defaultThemeID ? "selected" : ""}>${escape(t.name)}</option>`).join("")}</select></div>
    <div class="field"><label for="s-format">Save new presentations as</label><select id="s-format"><option value="wslides">Wired Slides (.wslides)</option><option value="pptx">PowerPoint (.pptx)</option></select></div>
    <div class="field"><label for="s-author">Author name</label><input id="s-author" type="text" value="${escape(s.authorName)}"></div>
    <div class="section-title">Editing</div>
    <label class="toggle"><input id="s-guides" type="checkbox" ${s.smartGuides ? "checked" : ""}> Smart guides while moving objects</label>
    <label class="toggle"><input id="s-grid" type="checkbox" ${s.snapToGrid ? "checked" : ""}> Snap objects to the grid</label>
    <div class="section-title">Updates</div>
    <label class="toggle"><input id="s-updates" type="checkbox" ${s.checkForUpdates ? "checked" : ""}> Check for new versions automatically</label>
    <p class="note">Wired Slides ${APP_VERSION} for ${platformName()} · <a href="#" id="s-check">Check now</a></p>`);
  q<HTMLSelectElement>(body, "#s-format").value = s.defaultFormat;
  q(body, "#s-check").addEventListener("click", (e) => { e.preventDefault(); checkNow(); });
  await showDialog("Settings", body, [{ label: "Done", value: "ok", primary: true }]);
  const checked = (id: string) => q<HTMLInputElement>(body, id).checked;
  updateSettings({
    showTemplateChooserOnLaunch: checked("#s-chooser"), defaultThemeID: q<HTMLSelectElement>(body, "#s-theme").value,
    defaultFormat: q<HTMLSelectElement>(body, "#s-format").value as "wslides" | "pptx", authorName: q<HTMLInputElement>(body, "#s-author").value.trim(),
    smartGuides: checked("#s-guides"), snapToGrid: checked("#s-grid"), checkForUpdates: checked("#s-updates"),
  });
}

export async function aboutDialog(): Promise<void> {
  const body = html(`
    <p>Version ${APP_VERSION} for ${platformName()}</p>
    <p>Presentations with a familiar PowerPoint workflow: layouts, themes, shapes, pictures, tables, charts, SmartArt, transitions, animations and a full-screen slide show with Presenter View. Presentations are saved as <b>.wslides</b> files that open in Wired Slides on Mac, Windows and Linux, and it opens and saves PowerPoint <b>.pptx</b> files too.</p>
    <p class="note"><a href="#" id="about-site">github.com/999david7/Wired-Slides</a></p>`);
  q(body, "#about-site").addEventListener("click", (e) => { e.preventDefault(); openURL("https://github.com/999david7/Wired-Slides"); });
  await showDialog("Wired Slides", body, [{ label: "OK", value: "ok", primary: true }]);
}

export function plainNotes(body: string): string {
  return body.replace(/\r\n/g, "\n").split("\n")
    .filter((line) => !line.includes("Generated with [Claude Code]"))
    .map((line) => line.replace(/^[#>]+\s*/, "").replace(/^[-*]\s+/, "• ").replace(/\*\*(.+?)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1"))
    .join("\n").trim();
}

export async function updateDialog(version: string, notes: string): Promise<"download" | "later" | "skip"> {
  const body = html(`<p>You have version ${APP_VERSION}. Download the new version and run the installer to update.</p><div class="notes"></div>`);
  q(body, ".notes").textContent = plainNotes(notes);
  const result = await showDialog(`Wired Slides ${version} is available`, body, [
    { label: "Skip This Version", value: "skip", left: true }, { label: "Remind Me Later", value: "later" }, { label: "Download", value: "download", primary: true },
  ]);
  return (result as "download" | "skip") ?? "later";
}

/** Plain text of every slide (for the outline export and Reuse Slides list). */
export function slideSummary(c: PresentationController) {
  return c.slides.map((s) => ({ title: slideTitle(s), body: s.elements.filter((e) => !e.placeholder || e.placeholder === "body").map((e) => (textOf(e) ? plainText(textOf(e)!) : "")).filter(Boolean) }));
}


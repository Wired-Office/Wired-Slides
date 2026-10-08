import "./styles.css";
import type { Presentation, Slide, SlideElement, UUID } from "./model/types";
import {
  R, clone, duplicateElement, elementMediaIDs, findElement, groupOf, imageOf, isTitleRole, offsetElement, setPlainText, textOf, uuid,
} from "./model/core";
import { makeSlide, newPresentation, slideTitle, bodyLines, addMedia } from "./model/presentation";
import { themeById, THEMES } from "./model/themes";
import { contentTemplates, themeTemplates } from "./model/templates";
import { PresentationController } from "./engine/controller";
import { FileFormatError, formatForName, readPresentation, writePresentation, type FormatID } from "./formats";
import { preloadPictures, picture, pictureSize, setImageReadyHandler, mimeType } from "./render/paint";
import { drawElement, visualBounds } from "./render/elements";
import { envOf, invalidateThumbnails, renderSlide, slidePNG } from "./render/slide";
import { printPresentation, outlineRTF, type PrintKind } from "./print";
import {
  askToSave, basename, chooseFileToOpen, chooseFiles, chooseSaveLocation, initialFile, isDesktop, onWindowClose, openURL, readFile, setWindowTitle,
  showMessage, writeFile,
} from "./platform";
import { addRecentFile, settings, updateSettings } from "./settings";
import { checkForUpdate, isCheckDue } from "./updates";
import { modKey } from "./version";
import type { AppActions } from "./ui/actions";
import { buildMenubar, type MenuEntry, type MenuSpec } from "./ui/menubar";
import { closePopupMenu } from "./ui/popup";
import { Ribbon } from "./ui/ribbon";
import { Navigator } from "./ui/navigator";
import { SlideEditor } from "./ui/editor";
import { SidePane } from "./ui/panes";
import { AlternateViews } from "./ui/views";
import { StatusBar } from "./ui/statusBar";
import { SlideShow } from "./slideshow/show";
import {
  aboutDialog, accessibilityDialog, actionDialog, alertDialog, altTextDialog, chartDataDialog, cropDialog, dateTimeDialog, escape, findReplaceDialog,
  formatBackgroundDialog, headerFooterDialog, html, hyperlinkDialog, iconDialog, insertTableDialog, outlineDialog, propertiesDialog, replaceFontsDialog,
  setUpShowDialog, settingsDialog, showDialog, slideSizeDialog, smartArtDialog, symbolDialog, templateChooser, updateDialog, wordCountDialog,
} from "./ui/dialogs";

// MARK: Document state

const doc = {
  path: null as string | null,
  name: "Presentation1",
  format: "wslides" as FormatID,
};

const initialTheme = THEMES.some((t) => t.id === settings().defaultThemeID) ? settings().defaultThemeID : "wired";
const c = new PresentationController(newPresentation(themeById(initialTheme)));
c.presentation.author = settings().authorName;

// MARK: Clipboard

interface ClipboardPayload {
  kind: "elements" | "slides";
  elements?: SlideElement[];
  slides?: Slide[];
  media: Presentation["media"];
  theme: string;
  text: string;
}

let clipboard: ClipboardPayload | null = null;

function payloadText(elements: SlideElement[]): string {
  return elements.map((e) => (textOf(e) ? textOf(e)!.paragraphs.map((p) => p.runs.map((r) => r.text).join("")).join("\n") : "")).filter(Boolean).join("\n") || " ";
}

function copySelection(cut: boolean): ClipboardPayload | null {
  const p = c.presentation;
  if (c.selection.length && document.activeElement?.closest("#stage")) {
    const elements = c.selectedElements.map(clone);
    const media = Object.fromEntries(elements.flatMap(elementMediaIDs).filter((id) => p.media[id]).map((id) => [id, p.media[id]]));
    clipboard = { kind: "elements", elements, media, theme: p.theme.id, text: payloadText(elements) };
    if (cut) c.deleteSelection();
    return clipboard;
  }
  if (document.activeElement?.closest("#navigator") || c.viewMode === "sorter") {
    const indices = [...c.selectedSlides].sort((a, b) => a - b);
    const slides = indices.map((i) => clone(p.slides[i]));
    const media = Object.fromEntries(slides.flatMap((s) => s.elements.flatMap(elementMediaIDs)).filter((id) => p.media[id]).map((id) => [id, p.media[id]]));
    clipboard = { kind: "slides", slides, media, theme: p.theme.id, text: slides.map(slideTitle).join("\n") || " " };
    if (cut) c.deleteSlides();
    return clipboard;
  }
  return null;
}

function pasteInternal(payload: ClipboardPayload) {
  if (payload.kind === "slides" && payload.slides) {
    const at = c.currentSlideIndex + 1;
    c.change("Paste Slides", (p) => {
      const copies = payload.slides!.map((s) => {
        const copy = clone(s);
        copy.id = uuid();
        const remap = new Map<UUID, UUID>();
        const refresh = (e: SlideElement) => { const old = e.id; e.id = uuid(); remap.set(old, e.id); groupOf(e)?.children.forEach(refresh); };
        copy.elements.forEach(refresh);
        copy.animations = copy.animations.map((a) => ({ ...a, id: uuid(), elementID: remap.get(a.elementID) ?? a.elementID }));
        return copy;
      });
      for (const [id, item] of Object.entries(payload.media)) if (!p.media[id]) p.media[id] = item;
      p.slides.splice(at, 0, ...copies);
    });
    c.setCurrentSlide(at);
    return;
  }
  const elements = (payload.elements ?? []).map((e) => {
    const copy = duplicateElement(e);
    delete copy.placeholder;
    // Pasting onto the same slide offsets the copies so they don't hide the originals.
    if (c.currentSlide.elements.some((x) => JSON.stringify(x.frame) === JSON.stringify(e.frame))) offsetElement(copy, 18, 18);
    return copy;
  });
  const index = c.currentSlideIndex;
  c.change("Paste", (p) => {
    for (const [id, item] of Object.entries(payload.media)) if (!p.media[id]) p.media[id] = item;
    p.slides[index].elements.push(...elements);
  });
  c.select(elements.map((e) => e.id));
}

async function insertImageFiles(files: { name: string; bytes: Uint8Array }[], at?: [number, number], replacing?: UUID) {
  for (const file of files) {
    const type = mimeType(file.name);
    if (type.startsWith("video/") || type.startsWith("audio/")) { c.insertMedia(file.bytes, file.name, type.startsWith("video/") ? "video" : "audio"); continue; }
    try {
      const bitmap = await createImageBitmap(new Blob([file.bytes as BlobPart], { type }));
      c.insertPicture(file.bytes, file.name, [bitmap.width, bitmap.height], at, replacing);
      bitmap.close();
    } catch {
      await showMessage(`“${file.name}” isn't a picture Wired Slides can show.`, "warning");
    }
    replacing = undefined;
  }
}

function pasteText(text: string) {
  if (c.textEditor) { c.textEditor.insertText(text); return; }
  const lines = text.replace(/\r\n?/g, "\n").trim();
  if (!lines) return;
  c.insertTextBox(undefined, lines);
  c.commitTextEditing();
}

document.addEventListener("copy", (e) => {
  if (c.textEditor || isTyping()) return;
  const payload = copySelection(false);
  if (payload) { e.preventDefault(); e.clipboardData?.setData("text/plain", payload.text); }
});
document.addEventListener("cut", (e) => {
  if (c.textEditor || isTyping()) return;
  const payload = copySelection(true);
  if (payload) { e.preventDefault(); e.clipboardData?.setData("text/plain", payload.text); }
});
document.addEventListener("paste", (e) => {
  if (c.textEditor || isTyping()) return;
  e.preventDefault();
  const files = [...(e.clipboardData?.files ?? [])];
  if (files.length) { void Promise.all(files.map(async (f) => ({ name: f.name || "Pasted Image.png", bytes: new Uint8Array(await f.arrayBuffer()) }))).then((list) => insertImageFiles(list)); return; }
  const text = e.clipboardData?.getData("text/plain") ?? "";
  if (clipboard && text === clipboard.text) pasteInternal(clipboard);
  else if (text) pasteText(text);
  else if (clipboard) pasteInternal(clipboard);
});

/** True when focus is in a form field (the notes, a dialog, the ribbon), where shortcuts belong to the field. */
function isTyping() {
  const el = document.activeElement as HTMLElement | null;
  return !!el && (el.matches("input, textarea, select") || el.isContentEditable);
}

async function pasteFromMenu(asText = false) {
  if (c.textEditor) {
    try { c.textEditor.insertText(await navigator.clipboard.readText()); } catch { /* the keyboard shortcut still works */ }
    return;
  }
  try {
    if (!asText && navigator.clipboard.read) {
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const type = item.types.find((t) => t.startsWith("image/"));
        if (type) { const blob = await item.getType(type); await insertImageFiles([{ name: `Pasted Image.${type.split("/")[1]}`, bytes: new Uint8Array(await blob.arrayBuffer()) }]); return; }
      }
    }
    const text = await navigator.clipboard.readText();
    if (!asText && clipboard && text === clipboard.text) { pasteInternal(clipboard); return; }
    if (text) { pasteText(text); return; }
  } catch {
    // The system clipboard isn't readable here; fall back to what Wired Slides copied.
  }
  if (clipboard) pasteInternal(clipboard);
}

// MARK: Files

function setDocument(p: Presentation, path: string | null, format: FormatID, name: string) {
  c.load(p);
  doc.path = path;
  doc.format = format;
  doc.name = name.replace(/\.(wslides|pptx)$/i, "");
  invalidateThumbnails();
  void preloadPictures(p.media);
  updateTitle();
}

async function confirmDiscard(): Promise<boolean> {
  c.commitTextEditing();
  if (!c.dirty) return true;
  const answer = await askToSave(doc.name);
  if (answer === "cancel") return false;
  if (answer === "save") return save();
  return true;
}

async function openPath(path: string) {
  try {
    const bytes = await readFile(path);
    const { presentation, format } = readPresentation(basename(path), bytes);
    setDocument(presentation, path, format, basename(path));
    addRecentFile(path);
  } catch (error) {
    await showMessage(error instanceof FileFormatError ? error.message : `“${basename(path)}” couldn't be opened. ${(error as Error).message ?? ""}`, "error");
  }
}

async function openDocument() {
  if (!(await confirmDiscard())) return;
  const file = await chooseFileToOpen();
  if (!file) return;
  try {
    const { presentation, format } = readPresentation(file.name, file.bytes);
    setDocument(presentation, file.path, format, file.name);
    if (file.path) addRecentFile(file.path);
  } catch (error) {
    await showMessage(error instanceof FileFormatError ? error.message : `“${file.name}” couldn't be opened.`, "error");
  }
}

/** Charts, icons and media without posters become pictures in .pptx files. */
function rasterize(e: SlideElement): { png: Uint8Array; bounds: ReturnType<typeof visualBounds> } | null {
  const bounds = visualBounds(e);
  const scale = 3;
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.ceil(bounds.w * scale));
  canvas.height = Math.max(1, Math.ceil(bounds.h * scale));
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;
  ctx.scale(scale, scale);
  ctx.translate(-bounds.x, -bounds.y);
  drawElement(ctx, e, envOf(c.presentation));
  return { png: dataURLBytes(canvas.toDataURL("image/png")), bounds };
}

function toPNG(id: string): Uint8Array | null {
  const pic = picture(id, c.presentation.media);
  if (!pic) return null;
  const [w, h] = pictureSize(pic);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, w);
  canvas.height = Math.max(1, h);
  canvas.getContext("2d")!.drawImage(pic, 0, 0);
  return dataURLBytes(canvas.toDataURL("image/png"));
}

function dataURLBytes(url: string): Uint8Array {
  const binary = atob(url.slice(url.indexOf(",") + 1));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function encode(format: FormatID): Promise<Uint8Array> {
  c.commitTextEditing();
  const p = c.presentation;
  await preloadPictures(p.media);
  if (format === "wslides") {
    const preview = await slidePNG(p.slides[0], 1, p, 512).catch(() => undefined);
    return writePresentation(p, "wslides", { preview });
  }
  return writePresentation(p, "pptx", { pptx: { rasterize, toPNG } });
}

async function writeTo(path: string, format: FormatID): Promise<boolean> {
  try {
    await writeFile(path, await encode(format));
    doc.path = isDesktop ? path : null;
    doc.format = format;
    doc.name = basename(path).replace(/\.(wslides|pptx)$/i, "");
    c.markSaved();
    if (isDesktop) addRecentFile(path);
    updateTitle();
    return true;
  } catch (error) {
    await showMessage(`The presentation couldn't be saved. ${(error as Error).message ?? error}`, "error");
    return false;
  }
}

async function save(): Promise<boolean> {
  if (!doc.path || !isDesktop) return saveAs();
  return writeTo(doc.path, doc.format);
}

async function saveAs(): Promise<boolean> {
  const preferred: FormatID = doc.path ? doc.format : settings().defaultFormat;
  const order: FormatID[] = preferred === "pptx" ? ["pptx", "wslides"] : ["wslides", "pptx"];
  const path = await chooseSaveLocation(`${doc.name}.${preferred}`, order);
  if (!path) return false;
  const format = formatForName(path)?.id ?? preferred;
  const finalPath = formatForName(path) ? path : `${path}.${format}`;
  return writeTo(finalPath, format);
}

async function exportAs(kind: "pdf" | "png" | "jpeg" | "outline") {
  const p = c.presentation;
  c.commitTextEditing();
  if (kind === "pdf") {
    await alertDialog("Export to PDF", isDesktop
      ? "In the print dialog that opens next, choose “Save as PDF” (or “Microsoft Print to PDF” on Windows, “Print to File” on Linux) as the printer."
      : "In the print dialog that opens next, choose “Save as PDF” as the destination.");
    await printPresentation(p, "slides");
    return;
  }
  if (kind === "outline") {
    const path = await chooseSaveLocation(`${doc.name}.rtf`, [{ name: "Rich Text", extensions: ["rtf"] }]);
    if (path) await writeFile(path, new TextEncoder().encode(outlineRTF(p)));
    return;
  }
  const ext = kind === "png" ? "png" : "jpg";
  const path = await chooseSaveLocation(`${doc.name}.${ext}`, [{ name: kind.toUpperCase(), extensions: [ext] }]);
  if (!path) return;
  await preloadPictures(p.media);
  const base = path.replace(/\.(png|jpe?g)$/i, "");
  for (let i = 0; i < p.slides.length; i++) {
    const bytes = await slidePNG(p.slides[i], i + 1, p, 1920, kind === "png" ? "image/png" : "image/jpeg");
    await writeFile(p.slides.length === 1 ? `${base}.${ext}` : `${base} ${i + 1}.${ext}`, bytes);
  }
  c.flash(`Exported ${p.slides.length} ${p.slides.length === 1 ? "slide" : "slides"}.`);
}

async function newDocument(fromChooser = true) {
  if (!(await confirmDiscard())) return;
  if (fromChooser) {
    const template = await templateChooser(contentTemplates(), themeTemplates(), settings().recentFiles, (path) => void openPath(path), () => void openDocument());
    if (!template) return;
    const p = template.build();
    p.author = settings().authorName;
    setDocument(p, null, settings().defaultFormat, "Presentation1");
    return;
  }
  const p = newPresentation(themeById(initialTheme));
  p.author = settings().authorName;
  setDocument(p, null, settings().defaultFormat, "Presentation1");
}

function updateTitle() {
  void setWindowTitle(`${doc.name}${c.dirty ? " — Edited" : ""} — Wired Slides`);
}

// MARK: Insert helpers

const IMAGE_FILTER = { name: "Pictures", extensions: ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg", "avif", "tif", "tiff"] };

async function insertPictures(replacing?: UUID) {
  const files = await chooseFiles(IMAGE_FILTER, !replacing);
  if (!files.length) return;
  if (replacing && c.primary && imageOf(c.primary) && !c.primary.placeholder) {
    // Change Picture: keep the frame and formatting, swap the image.
    const file = files[0];
    const id = replacing;
    c.change("Change Picture", (p) => {
      const media = addMedia(p, file.bytes, file.name);
      const e = findElement(p.slides[c.currentSlideIndex].elements, id);
      const img = e && imageOf(e);
      if (img) { img.mediaID = media; img.crop = { left: 0, top: 0, right: 0, bottom: 0 }; }
    });
    return;
  }
  await insertImageFiles(files, undefined, replacing);
}

async function insertMedia(kind: "video" | "audio") {
  const filter = kind === "video" ? { name: "Video", extensions: ["mp4", "m4v", "mov", "webm"] } : { name: "Audio", extensions: ["mp3", "m4a", "wav", "aac", "ogg"] };
  const [file] = await chooseFiles(filter, false);
  if (file) c.insertMedia(file.bytes, file.name, kind);
}

async function photoAlbum() {
  const files = await chooseFiles(IMAGE_FILTER, true);
  if (!files.length) return;
  for (const file of files) {
    c.addSlide("blank");
    await insertImageFiles([file]);
    const e = c.primary;
    if (e) {
      // Fit each picture to the slide.
      const r = R(e.frame), [w, h] = c.slideSize;
      const s = Math.min((w - 60) / r.w, (h - 60) / r.h);
      c.setElementRect(e.id, { x: (w - r.w * s) / 2, y: (h - r.h * s) / 2, w: r.w * s, h: r.h * s }, "Photo Album");
    }
  }
}

async function slidesFromOutline() {
  const text = await outlineDialog();
  if (!text) return;
  const groups: { title: string; lines: string[] }[] = [];
  for (const raw of text.replace(/\r\n?/g, "\n").split("\n")) {
    if (!raw.trim()) continue;
    const indented = /^(\t| {2,})/.test(raw);
    const line = raw.replace(/^ {2}/g, "\t").replace(/ {2}/g, "\t");
    if (!indented || !groups.length) groups.push({ title: raw.trim(), lines: [] });
    else groups[groups.length - 1].lines.push(line.replace(/^\t/, ""));
  }
  if (!groups.length) return;
  const at = c.currentSlideIndex + 1;
  c.change("Slides from Outline", (p) => {
    const slides = groups.map((g) => {
      const slide = makeSlide(g.lines.length ? "titleContent" : "titleOnly", p.theme, p.slideSize);
      for (const e of slide.elements) {
        const t = textOf(e);
        if (!t) continue;
        if (isTitleRole(e.placeholder)) setPlainText(t, g.title);
        else if (e.placeholder === "body" && g.lines.length) t.paragraphs = bodyLines(g.lines, clone(t.paragraphs[0]));
      }
      return slide;
    });
    p.slides.splice(at, 0, ...slides);
  });
  c.setCurrentSlide(at);
}

async function reuseSlides() {
  const file = await chooseFileToOpen();
  if (!file) return;
  let source: Presentation;
  try { source = readPresentation(file.name, file.bytes).presentation; } catch (error) { await showMessage((error as Error).message, "error"); return; }
  const chosen = new Set<number>();
  const body = html(`<p class="note">Click slides to choose them. They're inserted after the current slide and take on this presentation's theme.</p><div class="template-grid" style="grid-template-columns:repeat(auto-fill,minmax(150px,1fr))"></div>`);
  const grid = body.querySelector(".template-grid")!;
  await preloadPictures(source.media);
  source.slides.forEach((s, i) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "template-card";
    const canvas = renderSlide(s, i + 1, source, 300);
    canvas.style.cssText = "width:100%;height:auto";
    const meta = document.createElement("div");
    meta.className = "meta";
    meta.innerHTML = `<b>${i + 1}</b><span>${escape(slideTitle(s) || "Untitled")}</span>`;
    card.append(canvas, meta);
    card.addEventListener("click", () => { if (chosen.has(i)) chosen.delete(i); else chosen.add(i); card.style.outline = chosen.has(i) ? "3px solid var(--accent)" : ""; });
    grid.append(card);
  });
  if ((await showDialog("Reuse Slides", body, [{ label: "Cancel", value: "cancel" }, { label: "Insert", value: "ok", primary: true }], { width: "xwide" })) !== "ok" || !chosen.size) return;
  const slides = [...chosen].sort((a, b) => a - b).map((i) => source.slides[i]);
  const media = Object.fromEntries(slides.flatMap((s) => s.elements.flatMap(elementMediaIDs)).filter((id) => source.media[id]).map((id) => [id, source.media[id]]));
  pasteInternal({ kind: "slides", slides, media, theme: source.theme.id, text: "" });
}

async function designIdeas() {
  const p = c.presentation;
  const slide = c.currentSlide;
  const body = html(`<p class="note">The current slide in each design. Click one to apply it to the presentation.</p><div class="template-grid"></div>`);
  const grid = body.querySelector(".template-grid")!;
  let picked: string | null = null;
  for (const t of THEMES) {
    const theme = themeById(t.id);
    const card = document.createElement("button");
    card.type = "button";
    card.className = "template-card";
    const canvas = renderSlide(slide, c.currentSlideIndex + 1, { ...p, theme }, 360);
    canvas.style.cssText = "width:100%;height:auto";
    const meta = document.createElement("div");
    meta.className = "meta";
    meta.innerHTML = `<b>${escape(t.name)}</b>`;
    card.append(canvas, meta);
    card.addEventListener("click", () => { picked = t.id; (document.getElementById("dialog") as HTMLDialogElement).close("ok"); });
    grid.append(card);
  }
  await showDialog("Design Ideas", body, [{ label: "Close", value: "cancel" }], { width: "xwide" });
  if (picked) c.applyTheme(themeById(picked));
}

// MARK: Slide show

let activeShow: SlideShow | null = null;

function startShow(from: number | "current", presenter = false, rehearse = false, windowed = false) {
  c.commitTextEditing();
  if (activeShow) return;
  const start = from === "current" ? c.currentSlideIndex : from;
  const usePresenter = presenter || (c.presentation.showSettings.usePresenterView && presenter);
  void preloadPictures(c.presentation.media).then(() => {
    activeShow = new SlideShow(c.presentation, start, {
      presenter: usePresenter, rehearse, windowed,
      onExit: async ({ timings, lastSlide }) => {
        activeShow = null;
        c.setCurrentSlide(Math.min(lastSlide, c.slides.length - 1));
        document.getElementById("stage")?.focus();
        if (timings?.size) {
          const total = [...timings.values()].reduce((a, b) => a + b, 0);
          const body = html(`<p>The total time for the slide show was ${Math.floor(total / 60)}:${String(Math.round(total % 60)).padStart(2, "0")}. Do you want to keep the new slide timings?</p>`);
          if ((await showDialog("Rehearse Timings", body, [{ label: "No", value: "cancel" }, { label: "Yes", value: "ok", primary: true }])) === "ok") {
            c.change("Rehearse Timings", (p) => { for (const s of p.slides) { const t = timings.get(s.id); if (t !== undefined) s.transition.advanceAfter = t; } p.showSettings.useTimings = true; });
          }
        }
      },
    });
  });
}

document.addEventListener("ws-preview-animations", () => {
  if (activeShow) return;
  void preloadPictures(c.presentation.media).then(() => {
    activeShow = new SlideShow(c.presentation, c.currentSlideIndex, { windowed: true, previewOnly: true, onExit: () => { activeShow = null; } });
  });
});

// MARK: Actions

async function checkUpdates(userInitiated: boolean) {
  try {
    const offer = await checkForUpdate(userInitiated);
    if (!offer) { if (userInitiated) await showMessage("Wired Slides is up to date."); return; }
    const answer = await updateDialog(offer.version, offer.release.body ?? "");
    if (answer === "download") await openURL(offer.url);
    if (answer === "skip") updateSettings({ skippedVersion: offer.release.tag_name });
  } catch (error) {
    if (userInitiated) await showMessage(`Couldn't check for updates. ${(error as Error).message}`, "warning");
  }
}

const actions: AppActions = {
  newPresentation: () => void newDocument(true),
  open: () => void openDocument(),
  openRecent: (path) => void confirmDiscard().then(async (ok) => { if (ok) await openPath(path); }),
  save,
  saveAs,
  exportAs: (kind) => void exportAs(kind),
  print: (kind: PrintKind = "slides") => { c.commitTextEditing(); void printPresentation(c.presentation, kind); },
  close: () => void confirmDiscard().then((ok) => { if (ok) void newDocument(false); }),
  cut: () => { if (c.textEditor) document.execCommand("cut"); else copySelection(true); },
  copy: () => {
    if (c.textEditor) { document.execCommand("copy"); return; }
    const payload = copySelection(false);
    if (payload) void navigator.clipboard?.writeText(payload.text).catch(() => {});
  },
  paste: (asText) => void pasteFromMenu(asText),
  duplicate: () => (c.selection.length ? c.duplicateSelection() : c.duplicateSlides()),
  insertPictures: (replacing) => void insertPictures(replacing),
  insertMedia: (kind) => void insertMedia(kind),
  insertTable: () => void insertTableDialog().then((r) => { if (r) c.insertTable(r[0], r[1]); }),
  insertSmartArt: () => void smartArtDialog().then((r) => { if (r) c.insertSmartArt(r.kind, r.items); }),
  insertIcon: () => void iconDialog().then((s) => { if (s) c.insertIcon(s); }),
  insertSymbol: () => void symbolDialog().then((s) => { if (s) c.insertText(s); }),
  insertDateTime: () => void dateTimeDialog().then((s) => { if (s) c.insertText(s); }),
  insertSlidesFromOutline: () => void slidesFromOutline(),
  reuseSlides: () => void reuseSlides(),
  photoAlbum: () => void photoAlbum(),
  editChart: (id) => void chartDataDialog(c, id),
  hyperlink: async () => {
    const current = c.textEditor ? c.currentRunStyle.link ?? "" : (c.primary?.action && "url" in c.primary.action ? c.primary.action.url._0 : c.currentRunStyle.link ?? "");
    const result = await hyperlinkDialog(current, c.slides.map(slideTitle));
    if (result === "remove") c.setHyperlink(null);
    else if (result) {
      const m = /^#slide(\d+)$/.exec(result.url);
      if (m && !c.textEditor && c.primary) c.setAction({ slide: { _0: c.slides[Number(m[1]) - 1].id } });
      else c.setHyperlink(result.url);
    }
  },
  action: async () => {
    const e = c.primary;
    if (!e) return;
    const result = await actionDialog(e.action, c.slides.map((s) => ({ id: s.id, title: slideTitle(s) })));
    if (result !== "cancel") c.setAction(result);
  },
  altText: async () => { const e = c.primary; if (!e) return; const t = await altTextDialog(e.altText); if (t !== null) c.setAltText(t); },
  findReplace: (replace) => void findReplaceDialog(c, replace),
  replaceFonts: () => void replaceFontsDialog(c),
  headerFooter: async () => { const hf = await headerFooterDialog(c.presentation.headerFooter); if (hf) c.setHeaderFooter(hf); },
  slideSize: async () => { const r = await slideSizeDialog(c.slideSize); if (r) c.setSlideSize(r.size, r.scale); },
  formatBackground: () => void formatBackgroundDialog(c, async () => {
    const [file] = await chooseFiles(IMAGE_FILTER, false);
    if (!file) return null;
    let id = "";
    c.change("Insert Picture", (p) => { id = addMedia(p, file.bytes, file.name); });
    return id;
  }),
  setUpShow: async () => { const s = await setUpShowDialog(c.presentation.showSettings); if (s) c.setShowSettings(s); },
  startShow: (from, presenter = false, rehearse = false) => startShow(from, presenter, rehearse),
  readingView: () => startShow("current", false, false, true),
  accessibility: () => void accessibilityDialog(c),
  wordCount: () => void wordCountDialog(c),
  spelling: () => void alertDialog("Spelling", "Spelling is checked as you type: misspelled words are underlined while you edit text. Right-click an underlined word for suggestions."),
  properties: () => void propertiesDialog(c),
  preferences: () => void settingsDialog(() => void checkUpdates(true)),
  about: () => void aboutDialog(),
  checkForUpdates: () => void checkUpdates(true),
  openURL: (url) => void openURL(url),
  designIdeas: () => void designIdeas(),
  cropPicture: () => void cropDialog(c),
};

// MARK: Interface

const ribbon = new Ribbon(document.getElementById("ribbon")!, c, actions);
const navigator_ = new Navigator(document.getElementById("navigator")!, c, actions);
const stage = document.getElementById("stage")!;
const editor = new SlideEditor(stage, c, actions);
const sidePane = new SidePane(document.getElementById("sidepane")!, c);
const alternate = document.createElement("div");
alternate.style.cssText = "position:absolute;inset:0;overflow:auto;background:var(--workspace)";
alternate.hidden = true;
stage.append(alternate);
const views = new AlternateViews(alternate, c, navigator_);
const statusBar = new StatusBar(document.getElementById("statusbar")!, c, actions);
const notes = document.getElementById("notes-text") as HTMLTextAreaElement;
const main = document.getElementById("main")!;

notes.addEventListener("input", () => c.setNotes(notes.value));

// Dragging the splitter resizes the notes pane.
document.getElementById("notes-splitter")!.addEventListener("pointerdown", (e) => {
  const pane = document.getElementById("notes")!;
  const startY = e.clientY, startH = pane.offsetHeight;
  const move = (ev: PointerEvent) => { pane.style.height = `${Math.max(40, Math.min(innerHeight * 0.6, startH - (ev.clientY - startY)))}px`; };
  const up = () => { document.removeEventListener("pointermove", move); document.removeEventListener("pointerup", up); };
  document.addEventListener("pointermove", move);
  document.addEventListener("pointerup", up);
});

let lastSlideID = "";
function sync(kind: string) {
  const normal = c.viewMode === "normal";
  editor.host.hidden = !normal;
  alternate.hidden = normal;
  main.classList.toggle("no-notes", !c.showNotes || !normal);
  if (normal) editor.redraw();
  else views.render();
  if (kind === "model" || kind === "slide") navigator_.render();
  if (c.currentSlide.id !== lastSlideID || kind === "model") {
    lastSlideID = c.currentSlide.id;
    if (document.activeElement !== notes) notes.value = c.currentSlide.notes;
  }
  if (kind === "view") editor.layout();
  ribbon.refresh();
  sidePane.render();
  statusBar.render();
  updateTitle();
  stage.classList.toggle("inserting", !!c.pendingInsert);
}
c.onChange(sync);
setImageReadyHandler(() => { invalidateThumbnails(); editor.redraw(); navigator_.render(); });
c.presenter = {
  insertTable: actions.insertTable, editChart: actions.editChart, hyperlink: actions.hyperlink, findReplace: actions.findReplace, headerFooter: actions.headerFooter,
  slideSize: actions.slideSize, insertIcon: actions.insertIcon, smartArt: actions.insertSmartArt, action: actions.action, setUpShow: actions.setUpShow,
  startShow: (from, presenter, rehearse) => startShow(from, presenter, rehearse), insertPictures: () => actions.insertPictures(), insertMedia: () => actions.insertMedia("video"),
};

// MARK: Menus

const m = modKey();
const menus: MenuSpec[] = [
  { label: "File", items: () => [
    { label: "New…", shortcut: `${m}N`, action: actions.newPresentation },
    { label: "New Blank Presentation", action: () => void newDocument(false) },
    { label: "Open…", shortcut: `${m}O`, action: actions.open },
    { label: "Open Recent", submenu: settings().recentFiles.map((path) => ({ label: basename(path), action: () => actions.openRecent(path) })) },
    "-",
    { label: "Save", shortcut: `${m}S`, action: () => void save() },
    { label: "Save As…", shortcut: `${m}⇧S`, action: () => void saveAs() },
    { label: "Export", submenu: [
      { label: "PDF…", action: () => actions.exportAs("pdf") },
      { label: "PNG Images…", action: () => actions.exportAs("png") },
      { label: "JPEG Images…", action: () => actions.exportAs("jpeg") },
      { label: "Outline (RTF)…", action: () => actions.exportAs("outline") },
    ] },
    "-",
    { label: "Print…", shortcut: `${m}P`, action: () => actions.print("slides") },
    { label: "Print Handouts…", action: () => actions.print("handouts") },
    { label: "Print Notes Pages…", action: () => actions.print("notes") },
    { label: "Print Outline…", action: () => actions.print("outline") },
    "-",
    { label: "Properties…", action: actions.properties },
    { label: "Settings…", shortcut: `${m},`, action: actions.preferences },
  ] },
  { label: "Edit", items: () => [
    { label: c.canUndo ? `Undo ${c.undoName}` : "Undo", shortcut: `${m}Z`, enabled: c.canUndo || !!c.textEditor, action: () => undo() },
    { label: c.canRedo ? `Redo ${c.redoName}` : "Redo", shortcut: `${m}Y`, enabled: c.canRedo, action: () => c.redo() },
    "-",
    { label: "Cut", shortcut: `${m}X`, action: actions.cut },
    { label: "Copy", shortcut: `${m}C`, action: actions.copy },
    { label: "Paste", shortcut: `${m}V`, action: () => actions.paste() },
    { label: "Paste as Text", shortcut: `${m}⇧V`, action: () => actions.paste(true) },
    { label: "Duplicate", shortcut: `${m}D`, action: actions.duplicate },
    { label: "Delete", action: () => (c.selection.length ? c.deleteSelection() : c.deleteSlides()) },
    "-",
    { label: "Select All", shortcut: `${m}A`, action: () => (c.textEditor ? editor.selectAllText() : c.selectAll()) },
    "-",
    { label: "Find…", shortcut: `${m}F`, action: () => actions.findReplace(false) },
    { label: "Replace…", shortcut: `${m}H`, action: () => actions.findReplace(true) },
    { label: "Replace Fonts…", action: actions.replaceFonts },
  ] },
  { label: "View", items: () => [
    { label: "Normal", checked: c.viewMode === "normal", action: () => c.setView({ viewMode: "normal" }) },
    { label: "Outline View", checked: c.viewMode === "outline", action: () => c.setView({ viewMode: "outline" }) },
    { label: "Slide Sorter", checked: c.viewMode === "sorter", action: () => c.setView({ viewMode: "sorter" }) },
    { label: "Notes Page", checked: c.viewMode === "notesPage", action: () => c.setView({ viewMode: "notesPage" }) },
    { label: "Reading View", action: actions.readingView },
    "-",
    { label: "Notes", checked: c.showNotes, action: () => c.setView({ showNotes: !c.showNotes }) },
    { label: "Gridlines", checked: c.showGridlines, action: () => c.setView({ showGridlines: !c.showGridlines }) },
    { label: "Guides", checked: c.showGuides, action: () => c.setView({ showGuides: !c.showGuides }) },
    "-",
    { label: "Format Pane", checked: c.sidePane === "format", action: () => c.setView({ sidePane: c.sidePane === "format" ? null : "format" }) },
    { label: "Animation Pane", checked: c.sidePane === "animations", action: () => c.setView({ sidePane: c.sidePane === "animations" ? null : "animations" }) },
    { label: "Selection Pane", checked: c.sidePane === "selection", action: () => c.setView({ sidePane: c.sidePane === "selection" ? null : "selection" }) },
    { label: "Comments", checked: c.sidePane === "comments", action: () => c.setView({ sidePane: c.sidePane === "comments" ? null : "comments" }) },
    "-",
    { label: "Zoom In", shortcut: `${m}+`, action: () => c.setView({ fitToWindow: false, zoom: Math.min(4, c.zoom * 1.2) }) },
    { label: "Zoom Out", shortcut: `${m}−`, action: () => c.setView({ fitToWindow: false, zoom: Math.max(0.1, c.zoom / 1.2) }) },
    { label: "Fit to Window", shortcut: `${m}0`, checked: c.fitToWindow, action: () => c.setView({ fitToWindow: true }) },
  ] },
  { label: "Insert", items: () => [
    { label: "New Slide", shortcut: `${m}M`, action: () => c.addSlide() },
    { label: "Duplicate Slide", action: () => c.duplicateSlides() },
    { label: "Slides from Outline…", action: actions.insertSlidesFromOutline },
    { label: "Reuse Slides…", action: actions.reuseSlides },
    "-",
    { label: "Text Box", action: () => c.setPendingInsert({ textBox: false }) },
    { label: "Pictures…", action: () => actions.insertPictures() },
    { label: "Photo Album…", action: actions.photoAlbum },
    { label: "Table…", action: actions.insertTable },
    { label: "Chart", action: () => c.insertChart("column") },
    { label: "SmartArt…", action: actions.insertSmartArt },
    { label: "Icons…", action: actions.insertIcon },
    { label: "Video…", action: () => actions.insertMedia("video") },
    { label: "Audio…", action: () => actions.insertMedia("audio") },
    "-",
    { label: "Link…", shortcut: `${m}K`, action: () => void actions.hyperlink() },
    { label: "Comment", action: () => c.setView({ sidePane: "comments" }) },
    { label: "Header & Footer…", action: () => void actions.headerFooter() },
    { label: "Date & Time…", action: actions.insertDateTime },
    { label: "Symbol…", action: actions.insertSymbol },
  ] },
  { label: "Format", items: () => [
    { label: "Bold", shortcut: `${m}B`, action: () => c.toggleBold() },
    { label: "Italic", shortcut: `${m}I`, action: () => c.toggleItalic() },
    { label: "Underline", shortcut: `${m}U`, action: () => c.toggleUnderline() },
    { label: "Increase Font Size", shortcut: `${m}]`, action: () => c.growFont(true) },
    { label: "Decrease Font Size", shortcut: `${m}[`, action: () => c.growFont(false) },
    "-",
    { label: "Align Left", shortcut: `${m}L`, action: () => c.setAlignment("left") },
    { label: "Center", shortcut: `${m}E`, action: () => c.setAlignment("center") },
    { label: "Align Right", shortcut: `${m}R`, action: () => c.setAlignment("right") },
    { label: "Justify", shortcut: `${m}J`, action: () => c.setAlignment("justify") },
    "-",
    { label: "Format Pane…", action: () => c.setView({ sidePane: "format" }) },
    { label: "Format Background…", action: actions.formatBackground },
    { label: "Slide Size…", action: () => void actions.slideSize() },
    { label: "Theme", submenu: THEMES.map((t) => ({ label: t.name, checked: c.theme.id === t.id, action: () => c.applyTheme(themeById(t.id)) })) },
  ] },
  { label: "Arrange", items: () => {
    const has = c.selection.length > 0;
    const entries: MenuEntry[] = [
      { label: "Bring to Front", shortcut: `${m}⇧]`, enabled: has, action: () => c.arrange("front") },
      { label: "Bring Forward", enabled: has, action: () => c.arrange("forward") },
      { label: "Send Backward", enabled: has, action: () => c.arrange("backward") },
      { label: "Send to Back", shortcut: `${m}⇧[`, enabled: has, action: () => c.arrange("back") },
      "-",
      { label: "Group", shortcut: `${m}G`, enabled: c.selection.length > 1, action: () => c.group() },
      { label: "Ungroup", shortcut: `${m}⇧G`, enabled: c.selectedElements.some((e) => groupOf(e)), action: () => c.ungroup() },
      "-",
      { label: "Align Left", enabled: has, action: () => c.align("left") }, { label: "Align Center", enabled: has, action: () => c.align("center") },
      { label: "Align Right", enabled: has, action: () => c.align("right") }, { label: "Align Top", enabled: has, action: () => c.align("top") },
      { label: "Align Middle", enabled: has, action: () => c.align("middle") }, { label: "Align Bottom", enabled: has, action: () => c.align("bottom") },
      { label: "Distribute Horizontally", enabled: c.selection.length > 2, action: () => c.distribute(true) },
      { label: "Distribute Vertically", enabled: c.selection.length > 2, action: () => c.distribute(false) },
      "-",
      { label: "Rotate Right 90°", enabled: has, action: () => c.rotate(90) }, { label: "Rotate Left 90°", enabled: has, action: () => c.rotate(-90) },
      { label: "Flip Horizontal", enabled: has, action: () => c.flip(true) }, { label: "Flip Vertical", enabled: has, action: () => c.flip(false) },
      "-",
      { label: "Lock / Unlock", enabled: has, action: () => c.toggleLock() },
    ];
    return entries;
  } },
  { label: "Slide Show", items: () => [
    { label: "From Beginning", shortcut: "F5", action: () => startShow(0) },
    { label: "From Current Slide", shortcut: "⇧F5", action: () => startShow("current") },
    { label: "Presenter View", action: () => startShow("current", true) },
    { label: "Rehearse Timings", action: () => startShow(0, false, true) },
    "-",
    { label: "Set Up Slide Show…", action: () => void actions.setUpShow() },
    { label: c.currentSlide.hidden ? "Show Slide" : "Hide Slide", action: () => c.toggleHideSlides() },
  ] },
  { label: "Help", items: () => [
    { label: "Wired Slides on GitHub", action: () => actions.openURL("https://github.com/999david7/Wired-Slides") },
    { label: "Keyboard Shortcuts", action: () => void shortcutsDialog() },
    { label: "Check for Updates…", action: actions.checkForUpdates },
    "-",
    { label: "About Wired Slides", action: actions.about },
  ] },
];
buildMenubar(document.getElementById("menubar")!, menus, () => {});

async function shortcutsDialog() {
  const rows: [string, string][] = [
    [`${m}N / ${m}O / ${m}S`, "New, Open, Save"], [`${m}M`, "New slide"], [`${m}D`, "Duplicate"], [`${m}G / ${m}⇧G`, "Group / Ungroup"],
    ["F5 / ⇧F5", "Slide show from beginning / current slide"], ["Enter or F2", "Edit the selected object's text"], ["Esc", "Stop editing, deselect"],
    ["Arrow keys", "Nudge (⇧ for 10 pt, Alt for fine)"], [`${m}← / ${m}→`, "Rotate 15°"], ["Tab", "Select the next object"],
    [`${m}B / I / U`, "Bold, italic, underline"], [`${m}] / ${m}[`, "Larger / smaller text"], [`${m}L / E / R / J`, "Align text"],
    ["In a slide show", "B black screen, W white screen, number + Enter go to slide, G all slides, L laser, Ctrl+P pen, E erase ink"],
  ];
  await showDialog("Keyboard Shortcuts", html(`<div class="list-box" style="max-height:none">${rows.map(([k, v]) => `<div class="item"><b style="min-width:150px">${escape(k)}</b><span class="grow">${escape(v)}</span></div>`).join("")}</div>`), [{ label: "OK", value: "ok", primary: true }], { width: "wide" });
}

function undo() {
  if (c.textEditor) { c.commitTextEditing(); }
  c.undo();
}

// MARK: Keyboard

document.addEventListener("keydown", (e) => {
  if (activeShow || (document.getElementById("dialog") as HTMLDialogElement).open) return;
  const mod = e.ctrlKey || e.metaKey;
  const key = e.key.toLowerCase();
  if (e.key === "F5") { e.preventDefault(); startShow(e.shiftKey ? "current" : 0); return; }
  if (!mod) return;
  const typing = isTyping() && !c.textEditor;
  const run = (fn: () => void) => { e.preventDefault(); closePopupMenu(); fn(); };
  // These work everywhere.
  switch (key) {
    case "n": return run(() => (e.shiftKey ? void newDocument(false) : actions.newPresentation()));
    case "o": return run(actions.open);
    case "s": return run(() => void (e.shiftKey ? saveAs() : save()));
    case "p": return run(() => actions.print("slides"));
    case ",": return run(actions.preferences);
    case "f": return run(() => actions.findReplace(false));
    case "h": return run(() => actions.findReplace(true));
  }
  if (typing) return;
  if (c.textEditor) {
    // The text editor handles typing shortcuts itself; formatting ones come here.
    switch (key) {
      case "l": return run(() => c.setAlignment("left"));
      case "e": return run(() => c.setAlignment("center"));
      case "r": return run(() => c.setAlignment("right"));
      case "j": return run(() => c.setAlignment("justify"));
      case "]": return run(() => c.growFont(true));
      case "[": return run(() => c.growFont(false));
      case "k": return run(() => void actions.hyperlink());
    }
    return;
  }
  switch (key) {
    case "z": return run(() => (e.shiftKey ? c.redo() : undo()));
    case "y": return run(() => c.redo());
    case "a": return run(() => c.selectAll());
    case "d": return run(actions.duplicate);
    case "m": return run(() => c.addSlide());
    case "g": return run(() => (e.shiftKey ? c.ungroup() : c.group()));
    case "k": return run(() => void actions.hyperlink());
    case "b": return run(() => c.toggleBold());
    case "i": return run(() => c.toggleItalic());
    case "u": return run(() => c.toggleUnderline());
    case "l": return run(() => c.setAlignment("left"));
    case "e": return run(() => c.setAlignment("center"));
    case "r": return run(() => c.setAlignment("right"));
    case "j": return run(() => c.setAlignment("justify"));
    case "]": return run(() => (e.shiftKey ? c.arrange("front") : c.growFont(true)));
    case "[": return run(() => (e.shiftKey ? c.arrange("back") : c.growFont(false)));
    case "=": case "+": return run(() => c.setView({ fitToWindow: false, zoom: Math.min(4, c.zoom * 1.2) }));
    case "-": return run(() => c.setView({ fitToWindow: false, zoom: Math.max(0.1, c.zoom / 1.2) }));
    case "0": return run(() => c.setView({ fitToWindow: true }));
    case "v": if (e.shiftKey) return run(() => actions.paste(true)); return;
  }
});

// MARK: Drag and drop

document.addEventListener("dragover", (e) => { if (e.dataTransfer?.types.includes("Files")) e.preventDefault(); });
document.addEventListener("drop", async (e) => {
  const files = [...(e.dataTransfer?.files ?? [])];
  if (!files.length) return;
  e.preventDefault();
  const presentationFile = files.find((f) => formatForName(f.name));
  if (presentationFile) {
    if (!(await confirmDiscard())) return;
    try {
      const { presentation, format } = readPresentation(presentationFile.name, new Uint8Array(await presentationFile.arrayBuffer()));
      setDocument(presentation, null, format, presentationFile.name);
    } catch (error) { await showMessage((error as Error).message, "error"); }
    return;
  }
  const list = await Promise.all(files.map(async (f) => ({ name: f.name, bytes: new Uint8Array(await f.arrayBuffer()) })));
  const at = (e.target as HTMLElement).closest("#stage") ? editor.slidePoint(e.clientX, e.clientY) : undefined;
  await insertImageFiles(list, at);
});

// MARK: Startup

void onWindowClose(async () => confirmDiscard());
window.addEventListener("beforeunload", () => { (window as unknown as { __dirty?: boolean }).__dirty = c.dirty; });

async function start() {
  editor.layout();
  sync("model");
  stage.focus();
  const path = await initialFile();
  if (path) await openPath(path);
  else if (settings().showTemplateChooserOnLaunch) await newDocument(true);
  if (settings().checkForUpdates && isCheckDue()) setTimeout(() => void checkUpdates(false), 4000);
}

void start();


// Development builds expose the controller for debugging from the console.
if (import.meta.env.DEV) Object.assign(window, { __wiredSlides: { c, editor, actions } });

import type { Presentation } from "../model/types";
import { isoNow } from "../model/core";
import { makeSlide, pruneMedia } from "../model/presentation";
import { readZip, text, writeZip } from "./zip";

export class FileFormatError extends Error {}

export const WSLIDES_MIME = "application/vnd.wiredslides.wslides";
const FORMAT_VERSION = 1;

interface Envelope {
  formatVersion: number;
  application: string;
  presentation: Presentation;
  /** Media ids → original file names. */
  mediaNames: Record<string, string>;
}

/** JSON with keys sorted, like the Mac app's encoder. */
function sortedJSON(value: unknown): string {
  return JSON.stringify(value, (_key, v) => {
    if (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Uint8Array)) {
      return Object.fromEntries(Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => [k, v[k]]));
    }
    // The Mac app can't decode NaN or infinity (JSON has no way to write them).
    if (typeof v === "number" && !Number.isFinite(v)) return 0;
    return v;
  });
}

/** Writes the native format: a ZIP of `presentation.json`, the media files and a preview. */
export function writeWSlides(p: Presentation, preview?: Uint8Array): Uint8Array {
  const stripped: Presentation = { ...p, media: { ...p.media } };
  pruneMedia(stripped);
  const media = stripped.media;
  const envelope: Envelope = {
    formatVersion: FORMAT_VERSION,
    application: "Wired Slides",
    presentation: { ...stripped, media: {} },
    mediaNames: Object.fromEntries(Object.entries(media).map(([id, item]) => [id, item.filename])),
  };
  const entries: [string, Uint8Array | string][] = [["mimetype", WSLIDES_MIME], ["presentation.json", sortedJSON(envelope)]];
  for (const id of Object.keys(media).sort()) entries.push([`media/${id}`, media[id].data]);
  if (preview) entries.push(["preview.png", preview]);
  return writeZip(entries);
}

export function readWSlides(bytes: Uint8Array): Presentation {
  let entries: Record<string, Uint8Array>;
  try {
    entries = readZip(bytes);
  } catch {
    throw new FileFormatError("The presentation couldn't be read because it isn't a valid Wired Slides file.");
  }
  const json = entries["presentation.json"];
  if (!json) throw new FileFormatError("The presentation is missing its contents (presentation.json).");
  let envelope: Envelope;
  try {
    envelope = JSON.parse(text(json));
  } catch (error) {
    throw new FileFormatError(`The presentation couldn't be read: ${(error as Error).message}`);
  }
  if (envelope.formatVersion > FORMAT_VERSION) throw new FileFormatError("This presentation was made with a newer version of Wired Slides.");
  const p = envelope.presentation;
  if (!p || !Array.isArray(p.slides) || !p.theme) throw new FileFormatError("The presentation couldn't be read: its contents are incomplete.");
  p.media = {};
  for (const [id, name] of Object.entries(envelope.mediaNames ?? {})) {
    const data = entries[`media/${id}`];
    if (data) p.media[id] = { filename: name, data };
  }
  p.created ??= isoNow();
  if (!p.slides.length) p.slides = [makeSlide("title", p.theme, p.slideSize)];
  return p;
}

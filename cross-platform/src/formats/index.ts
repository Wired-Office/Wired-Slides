import type { Presentation } from "../model/types";
import { readPPTX } from "./pptx-read";
import { writePPTX, type PPTXHelpers } from "./pptx-write";
import { FileFormatError, readWSlides, writeWSlides } from "./wslides";
import { isZip, readZip } from "./zip";

export type FormatID = "wslides" | "pptx";

export interface FileFormat { id: FormatID; name: string; shortName: string; extensions: string[] }

/** The file types Wired Slides opens and saves. */
export const FORMATS: FileFormat[] = [
  { id: "wslides", name: "Wired Slides Presentation", shortName: "Wired Slides", extensions: ["wslides"] },
  { id: "pptx", name: "PowerPoint Presentation", shortName: "PowerPoint", extensions: ["pptx"] },
];

export const formatById = (id: FormatID) => FORMATS.find((f) => f.id === id)!;

export function formatForName(name: string): FileFormat | null {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  return FORMATS.find((f) => f.extensions.includes(ext)) ?? null;
}

/** Reads a file, picking the format from its name (or its contents when the name doesn't say). */
export function readPresentation(name: string, bytes: Uint8Array): { presentation: Presentation; format: FormatID } {
  let format = formatForName(name)?.id;
  if (!isZip(bytes)) throw new FileFormatError(`“${name}” isn't a presentation Wired Slides can open.`);
  if (!format) format = readZip(bytes)["presentation.json"] ? "wslides" : "pptx";
  return { presentation: format === "wslides" ? readWSlides(bytes) : readPPTX(bytes), format };
}

export function writePresentation(p: Presentation, format: FormatID, o: { preview?: Uint8Array; pptx?: PPTXHelpers } = {}): Uint8Array {
  return format === "wslides" ? writeWSlides(p, o.preview) : writePPTX(p, o.pptx);
}

export { FileFormatError };

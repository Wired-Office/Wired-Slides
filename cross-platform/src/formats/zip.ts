import { strFromU8, strToU8, unzipSync, zipSync, type Zippable } from "fflate";

export const isZip = (bytes: Uint8Array) => bytes.length > 3 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04;

export function readZip(bytes: Uint8Array): Record<string, Uint8Array> {
  return unzipSync(bytes);
}

const COMPRESSED = /\.(png|jpe?g|gif|webp|heic|avif|mp4|mov|m4v|m4a|mp3|aac|zip)$/i;

/** Writes entries in order; text is deflated, media and `mimetype` are stored. */
export function writeZip(entries: [string, Uint8Array | string][]): Uint8Array {
  const files: Zippable = {};
  for (const [path, data] of entries) {
    const bytes = typeof data === "string" ? strToU8(data) : data;
    files[path] = [bytes, { level: path === "mimetype" || COMPRESSED.test(path) ? 0 : 6 }];
  }
  return zipSync(files);
}

export const text = (bytes: Uint8Array | undefined) => (bytes ? strFromU8(bytes) : "");

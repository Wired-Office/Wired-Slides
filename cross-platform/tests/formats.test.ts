import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { readPresentation, writePresentation } from "../src/formats";
import { readZip, text } from "../src/formats/zip";
import { contentTemplates, themeTemplates } from "../src/model/templates";
import { slideTitle } from "../src/model/presentation";
import { buildPlan, initiallyHidden } from "../src/model/catalog";

const fixture = (name: string) => new Uint8Array(readFileSync(join(process.cwd(), "tests/fixtures", name)));
const json = (bytes: Uint8Array) => JSON.parse(text(readZip(bytes)["presentation.json"]));

/** Keys present in every object at each path of a JSON tree (array indices collapse to []). */
function alwaysPresentKeys(root: unknown) {
  const result = new Map<string, Set<string>>();
  const walk = (value: unknown, path: string) => {
    if (Array.isArray(value)) { value.forEach((v) => walk(v, path + "[]")); return; }
    if (!value || typeof value !== "object") return;
    const keys = new Set(Object.keys(value));
    // Enum wrappers ({ "solid": { … } }) hold one case each; only structs have required keys.
    if (keys.size > 1) {
      const known = result.get(path);
      result.set(path, known ? new Set([...known].filter((k) => keys.has(k))) : keys);
    }
    for (const [k, v] of Object.entries(value)) walk(v, `${path}.${k}`);
  };
  walk(root, "");
  return result;
}

/** Swift optionals: the Mac app leaves them out when unset. */
const OPTIONAL = new Set([
  "fontFamily", "size", "bold", "italic", "color", "highlight", "link", "outlineColor", "bulletColor", "prompt", "fill", "placeholder", "action",
  "shadow", "glow", "reflection", "maskShape", "startElement", "endElement", "borderColor", "title", "posterID", "background", "titleBackground",
  "fixedDate", "advanceAfter",
]);

function missingKeys(reference: Map<string, Set<string>>, candidate: unknown): string[] {
  const missing: string[] = [];
  const walk = (value: unknown, path: string) => {
    if (Array.isArray(value)) { value.forEach((v) => walk(v, path + "[]")); return; }
    if (!value || typeof value !== "object") return;
    const required = Object.keys(value).length > 1 ? reference.get(path) : undefined;
    if (required) for (const k of required) if (!(k in value) && !OPTIONAL.has(k)) missing.push(`${path}.${k}`);
    for (const [k, v] of Object.entries(value)) walk(v, `${path}.${k}`);
  };
  walk(candidate, "");
  return [...new Set(missing)];
}

describe(".wslides", () => {
  it("reads a presentation saved by the Mac app", () => {
    const { presentation, format } = readPresentation("mac-pitch.wslides", fixture("mac-pitch.wslides"));
    expect(format).toBe("wslides");
    expect(presentation.slides).toHaveLength(7);
    expect(slideTitle(presentation.slides[1])).toBe("The Problem");
    expect(presentation.theme.id).toBe("midnight");
  });

  it("writes the Mac app's JSON back unchanged", () => {
    const original = fixture("mac-pitch.wslides");
    const { presentation } = readPresentation("a.wslides", original);
    const written = writePresentation(presentation, "wslides");
    expect(json(written).presentation).toEqual(json(original).presentation);
    expect(text(readZip(written).mimetype)).toBe("application/vnd.wiredslides.wslides");
  });

  it("writes every field the Mac app requires", () => {
    const reference = alwaysPresentKeys(json(fixture("mac-pitch.wslides")));
    for (const template of [...contentTemplates(), ...themeTemplates()]) {
      const written = json(writePresentation(template.build(), "wslides"));
      expect(missingKeys(reference, written), template.name).toEqual([]);
      expect(written.presentation.created).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    }
  });
});

describe(".pptx", () => {
  it("reads a PowerPoint file written by the Mac app", () => {
    const { presentation, format } = readPresentation("mac-pitch.pptx", fixture("mac-pitch.pptx"));
    expect(format).toBe("pptx");
    expect(presentation.slides).toHaveLength(7);
    expect(presentation.slides.map(slideTitle).slice(1, 4)).toEqual(["The Problem", "Our Solution", "Market Opportunity"]);
    expect(presentation.slides[0].notes).toBe("Introduce yourself and the company in one breath.");
    expect(presentation.slides[1].transition.kind).toBe("push");
  });

  it("round-trips its own PowerPoint files", () => {
    for (const template of contentTemplates()) {
      const p = template.build();
      const back = readPresentation("x.pptx", writePresentation(p, "pptx")).presentation;
      expect(back.slides.map(slideTitle), template.name).toEqual(p.slides.map(slideTitle));
      expect(back.slides.map((s) => s.notes)).toEqual(p.slides.map((s) => s.notes));
    }
  });
});

describe("animations", () => {
  it("groups effects into click steps like the Mac app", () => {
    const deck = contentTemplates().find((t) => t.id === "pitch")!.build();
    const steps = buildPlan(deck.slides[1]);
    expect(steps).toHaveLength(2);
    expect(steps[1].map((s) => s.start)).toEqual([0]);
    expect(initiallyHidden(steps).size).toBe(1);
  });
});

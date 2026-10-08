import type {
  AnimationEffect, AnimationTrigger, LayoutKind, MotionDirection, ShapeKind, Slide, SlideAnimation, TransitionKind, Transition, UUID,
  ThemeColors, ConnectorKind, PlaceholderRole,
} from "./types";
import { findElement, rgbHex, setShapeTitleLookup, themeColors, uuid, WHITE, BLACK } from "./core";

// MARK: Shapes

export const SHAPE_TITLES: Record<ShapeKind, string> = {
  rect: "Rectangle", roundRect: "Rounded Rectangle", snip1Rect: "Snip Single Corner", snip2SameRect: "Snip Same Side Corners",
  round2SameRect: "Round Same Side Corners", ellipse: "Oval", triangle: "Isosceles Triangle", rtTriangle: "Right Triangle",
  parallelogram: "Parallelogram", trapezoid: "Trapezoid", diamond: "Diamond", pentagon: "Pentagon", hexagon: "Hexagon", octagon: "Octagon",
  decagon: "Decagon", pie: "Pie", chord: "Chord", teardrop: "Teardrop", frame: "Frame", donut: "Donut", can: "Cylinder", cube: "Cube",
  heart: "Heart", lightningBolt: "Lightning Bolt", sun: "Sun", moon: "Moon", cloud: "Cloud", smileyFace: "Smiley Face", plaque: "Plaque",
  noSmoking: "\"Not Allowed\" Symbol", rightArrow: "Right Arrow", leftArrow: "Left Arrow", upArrow: "Up Arrow", downArrow: "Down Arrow",
  leftRightArrow: "Left-Right Arrow", upDownArrow: "Up-Down Arrow", chevron: "Chevron", homePlate: "Pentagon Arrow",
  notchedRightArrow: "Notched Right Arrow", quadArrow: "Quad Arrow", mathPlus: "Plus", mathMinus: "Minus", mathMultiply: "Multiply",
  mathDivide: "Division", mathEqual: "Equal", mathNotEqual: "Not Equal", flowChartProcess: "Process", flowChartAlternateProcess: "Alternate Process",
  flowChartDecision: "Decision", flowChartInputOutput: "Data", flowChartPredefinedProcess: "Predefined Process", flowChartDocument: "Document",
  flowChartTerminator: "Terminator", flowChartPreparation: "Preparation", flowChartManualInput: "Manual Input", flowChartConnector: "Connector",
  flowChartDelay: "Delay", star4: "Star: 4 Points", star5: "Star: 5 Points", star6: "Star: 6 Points", star8: "Star: 8 Points",
  star12: "Star: 12 Points", star24: "Star: 24 Points", irregularSeal1: "Explosion", wedgeRectCallout: "Speech Bubble: Rectangle",
  wedgeRoundRectCallout: "Speech Bubble: Rounded Rectangle", wedgeEllipseCallout: "Speech Bubble: Oval", cloudCallout: "Thought Bubble: Cloud",
};
setShapeTitleLookup((k) => SHAPE_TITLES[k] ?? k);

export const SHAPE_KINDS = Object.keys(SHAPE_TITLES) as ShapeKind[];

export const SHAPE_CATEGORIES: [string, ShapeKind[]][] = [
  ["Rectangles", ["rect", "roundRect", "snip1Rect", "snip2SameRect", "round2SameRect"]],
  ["Basic Shapes", ["ellipse", "triangle", "rtTriangle", "parallelogram", "trapezoid", "diamond", "pentagon", "hexagon", "octagon", "decagon",
    "pie", "chord", "teardrop", "frame", "donut", "can", "cube", "heart", "lightningBolt", "sun", "moon", "cloud", "smileyFace", "plaque", "noSmoking"]],
  ["Block Arrows", ["rightArrow", "leftArrow", "upArrow", "downArrow", "leftRightArrow", "upDownArrow", "chevron", "homePlate", "notchedRightArrow", "quadArrow"]],
  ["Equation Shapes", ["mathPlus", "mathMinus", "mathMultiply", "mathDivide", "mathEqual", "mathNotEqual"]],
  ["Flowchart", ["flowChartProcess", "flowChartAlternateProcess", "flowChartDecision", "flowChartInputOutput", "flowChartPredefinedProcess",
    "flowChartDocument", "flowChartTerminator", "flowChartPreparation", "flowChartManualInput", "flowChartConnector", "flowChartDelay"]],
  ["Stars and Banners", ["star4", "star5", "star6", "star8", "star12", "star24", "irregularSeal1"]],
  ["Callouts", ["wedgeRectCallout", "wedgeRoundRectCallout", "wedgeEllipseCallout", "cloudCallout"]],
];

export function shapeFromOOXML(name: string): ShapeKind | null {
  if ((SHAPE_KINDS as string[]).includes(name)) return name as ShapeKind;
  switch (name) {
    case "flowChartOnlineStorage": case "flowChartMagneticDisk": return "can";
    case "star7": case "star10": case "star16": case "star32": return "star8";
    case "irregularSeal2": return "irregularSeal1";
    case "plus": return "mathPlus";
    case "round1Rect": case "round2DiagRect": return "roundRect";
    case "snip2DiagRect": case "snipRoundRect": return "snip2SameRect";
    case "ribbon": case "ribbon2": case "wave": case "doubleWave": return "rect";
    case "flowChartMerge": case "flowChartExtract": return "triangle";
  }
  return null;
}

/** Default adjustment values (fractions of the shape's smaller side, unless noted). */
export function defaultAdjustments(kind: ShapeKind): number[] {
  switch (kind) {
    case "roundRect": case "round2SameRect": case "wedgeRoundRectCallout": case "flowChartAlternateProcess": return [0.1667];
    case "snip1Rect": case "snip2SameRect": case "plaque": return [0.1667];
    case "parallelogram": case "trapezoid": case "flowChartInputOutput": case "hexagon": return [0.25];
    case "octagon": return [0.2929];
    case "rightArrow": case "leftArrow": case "upArrow": case "downArrow": case "leftRightArrow": case "upDownArrow": case "notchedRightArrow": return [0.5, 0.5];
    case "quadArrow": return [0.22];
    case "chevron": case "homePlate": return [0.5];
    case "frame": return [0.125];
    case "donut": case "noSmoking": case "can": case "cube": return [0.25];
    case "moon": return [0.5];
    case "pie": return [0, 270];
    case "chord": return [45, 270];
    case "star4": return [0.25];
    case "star5": return [0.38];
    case "star6": return [0.5];
    case "star8": return [0.62];
    case "star12": case "star24": return [0.75];
    case "mathPlus": case "mathMinus": case "mathMultiply": case "mathDivide": case "mathEqual": case "mathNotEqual": return [0.235];
    case "wedgeRectCallout": case "wedgeEllipseCallout": case "cloudCallout": return [0.2, 1.4];
  }
  return [];
}

export function resolvedAdjustments(kind: ShapeKind, adjustments: number[]): number[] {
  return defaultAdjustments(kind).map((d, i) => (i < adjustments.length ? adjustments[i] : d));
}

const HANDLES = new Set<ShapeKind>([
  "roundRect", "round2SameRect", "snip1Rect", "snip2SameRect", "plaque", "parallelogram", "trapezoid", "hexagon", "octagon",
  "chevron", "homePlate", "frame", "donut", "noSmoking", "can", "cube", "moon", "star4", "star5", "star6", "star8", "star12", "star24",
  "rightArrow", "leftArrow", "upArrow", "downArrow", "leftRightArrow", "upDownArrow", "notchedRightArrow",
  "wedgeRectCallout", "wedgeRoundRectCallout", "wedgeEllipseCallout", "cloudCallout", "flowChartInputOutput",
]);
export const hasAdjustHandle = (k: ShapeKind) => HANDLES.has(k);
export const isCallout = (k: ShapeKind) => k === "wedgeRectCallout" || k === "wedgeRoundRectCallout" || k === "wedgeEllipseCallout" || k === "cloudCallout";
export const isStar = (k: ShapeKind) => /^star\d+$/.test(k);

export const CONNECTOR_TITLES: Record<ConnectorKind, string> = { straight: "Straight", elbow: "Elbow", curved: "Curved" };
export const CONNECTOR_OOXML: Record<ConnectorKind, string> = { straight: "line", elbow: "bentConnector3", curved: "curvedConnector3" };

// MARK: Placeholders and layouts

export const PLACEHOLDER_OOXML: Record<PlaceholderRole, string> = {
  title: "title", centeredTitle: "ctrTitle", subtitle: "subTitle", body: "body", picture: "pic", date: "dt", footer: "ftr", slideNumber: "sldNum",
};
export function placeholderFromOOXML(v: string | null): PlaceholderRole {
  switch (v) {
    case "title": return "title";
    case "ctrTitle": return "centeredTitle";
    case "subTitle": return "subtitle";
    case "pic": return "picture";
    case "dt": return "date";
    case "ftr": return "footer";
    case "sldNum": return "slideNumber";
  }
  return "body";
}

export const LAYOUTS: LayoutKind[] = ["title", "titleContent", "sectionHeader", "twoContent", "comparison", "titleOnly", "blank", "contentCaption", "pictureCaption", "quote", "bigNumber"];
export const LAYOUT_TITLES: Record<LayoutKind, string> = {
  title: "Title Slide", titleContent: "Title and Content", sectionHeader: "Section Header", twoContent: "Two Content", comparison: "Comparison",
  titleOnly: "Title Only", blank: "Blank", contentCaption: "Content with Caption", pictureCaption: "Picture with Caption", quote: "Quote", bigNumber: "Big Number",
};
export const LAYOUT_OOXML: Record<LayoutKind, string> = {
  title: "title", titleContent: "obj", sectionHeader: "secHead", twoContent: "twoObj", comparison: "twoTxTwoObj", titleOnly: "titleOnly",
  blank: "blank", contentCaption: "objTx", pictureCaption: "picTx", quote: "obj", bigNumber: "obj",
};
export const layoutFromOOXML = (t: string | null): LayoutKind => LAYOUTS.find((l) => LAYOUT_OOXML[l] === t) ?? "titleContent";
export const isTitleStyleLayout = (l: LayoutKind) => l === "title" || l === "sectionHeader";

// MARK: Transitions

export const TRANSITIONS: TransitionKind[] = ["none", "morph", "fade", "fadeThroughBlack", "push", "wipe", "split", "reveal", "cover", "uncover", "zoom", "flip", "cube", "circle", "dissolve", "blinds"];
export const TRANSITION_TITLES: Record<TransitionKind, string> = {
  none: "None", morph: "Morph", fade: "Fade", fadeThroughBlack: "Fade Through Black", push: "Push", wipe: "Wipe", split: "Split", reveal: "Reveal",
  cover: "Cover", uncover: "Uncover", zoom: "Zoom", flip: "Flip", cube: "Cube", circle: "Shape", dissolve: "Dissolve", blinds: "Blinds",
};
export const transitionHasDirection = (k: TransitionKind) => ["push", "wipe", "reveal", "cover", "uncover", "flip", "cube", "split"].includes(k);
export const DIRECTIONS: MotionDirection[] = ["fromRight", "fromLeft", "fromTop", "fromBottom"];
export const DIRECTION_TITLES: Record<MotionDirection, string> = { fromRight: "From Right", fromLeft: "From Left", fromTop: "From Top", fromBottom: "From Bottom" };
export const DIRECTION_OOXML: Record<MotionDirection, string> = { fromRight: "l", fromLeft: "r", fromTop: "d", fromBottom: "u" };

export const newTransition = (): Transition => ({ kind: "none", direction: "fromRight", duration: 0.7, advanceOnClick: true });

// MARK: Animations

export type AnimationCategory = "entrance" | "emphasis" | "exit" | "motionPath";
export const ANIMATION_CATEGORIES: [AnimationCategory, string][] = [["entrance", "Entrance"], ["emphasis", "Emphasis"], ["exit", "Exit"], ["motionPath", "Motion Paths"]];

export const ANIMATION_TITLES: Record<AnimationEffect, string> = {
  appear: "Appear", fadeIn: "Fade", flyIn: "Fly In", floatIn: "Float In", wipeIn: "Wipe", splitIn: "Split", zoomIn: "Zoom", growTurnIn: "Grow & Turn",
  swivelIn: "Swivel", bounceIn: "Bounce", spinIn: "Spinner", pulse: "Pulse", spin: "Spin", growShrink: "Grow/Shrink", teeter: "Teeter",
  transparency: "Transparency", colorPulse: "Color Pulse", wave: "Wave", disappear: "Disappear", fadeOut: "Fade", flyOut: "Fly Out",
  floatOut: "Float Out", wipeOut: "Wipe", splitOut: "Split", zoomOut: "Zoom", shrinkTurnOut: "Shrink & Turn", swivelOut: "Swivel",
  bounceOut: "Bounce", pathLine: "Lines", pathArc: "Arcs", pathCircle: "Shapes", pathZigzag: "Zigzag",
};
export const ANIMATION_EFFECTS = Object.keys(ANIMATION_TITLES) as AnimationEffect[];

export function animationCategory(e: AnimationEffect): AnimationCategory {
  if (["appear", "fadeIn", "flyIn", "floatIn", "wipeIn", "splitIn", "zoomIn", "growTurnIn", "swivelIn", "bounceIn", "spinIn"].includes(e)) return "entrance";
  if (["pulse", "spin", "growShrink", "teeter", "transparency", "colorPulse", "wave"].includes(e)) return "emphasis";
  if (e.startsWith("path")) return "motionPath";
  return "exit";
}

export const effectsIn = (c: AnimationCategory) => ANIMATION_EFFECTS.filter((e) => animationCategory(e) === c);
export const effectHasDirection = (e: AnimationEffect) => ["flyIn", "flyOut", "floatIn", "floatOut", "wipeIn", "wipeOut", "pathLine", "pathArc"].includes(e);

export function defaultDuration(e: AnimationEffect): number {
  if (e === "appear" || e === "disappear") return 0;
  if (["flyIn", "flyOut", "floatIn", "floatOut", "wipeIn", "wipeOut", "fadeIn", "fadeOut"].includes(e)) return 0.5;
  if (["spin", "pathLine", "pathArc", "pathCircle", "pathZigzag", "spinIn"].includes(e)) return 2;
  return 1;
}

export const TRIGGER_TITLES: Record<AnimationTrigger, string> = { onClick: "On Click", withPrevious: "With Previous", afterPrevious: "After Previous" };

export function newAnimation(elementID: UUID, effect: AnimationEffect, trigger: AnimationTrigger = "onClick"): SlideAnimation {
  return { id: uuid(), elementID, effect, trigger, duration: defaultDuration(effect), delay: 0, direction: "fromBottom", repeatCount: 1, amount: 1 };
}

export const validAnimations = (slide: Slide) => slide.animations.filter((a) => findElement(slide.elements, a.elementID));

export interface BuildItem { animation: SlideAnimation; start: number; end: number }

/** A slide's animations split into click steps with start times; step 0 runs when the slide appears. */
export function buildPlan(slide: Slide, animated = true): BuildItem[][] {
  const animations = animated ? validAnimations(slide) : [];
  const steps: BuildItem[][] = [[]];
  let stepStart = true, lastStart = 0, lastEnd = 0;
  animations.forEach((a, i) => {
    if (a.trigger === "onClick") {
      steps.push([]);
      lastStart = 0;
      lastEnd = 0;
      stepStart = true;
    } else if (i === 0) {
      stepStart = true;
    }
    let start: number;
    switch (a.trigger) {
      case "onClick": start = a.delay; break;
      case "withPrevious": start = (stepStart ? 0 : lastStart) + a.delay; break;
      case "afterPrevious": start = lastEnd + a.delay; break;
    }
    const end = start + a.duration * Math.max(a.repeatCount, 1);
    steps[steps.length - 1].push({ animation: a, start, end });
    lastStart = start;
    lastEnd = Math.max(lastEnd, end);
    stepStart = false;
  });
  return steps;
}

/** Elements hidden before any animation runs (their first effect is an entrance). */
export function initiallyHidden(steps: BuildItem[][]): Set<UUID> {
  const seen = new Set<UUID>(), hidden = new Set<UUID>();
  for (const item of steps.flat()) {
    const id = item.animation.elementID;
    if (seen.has(id)) continue;
    seen.add(id);
    if (animationCategory(item.animation.effect) === "entrance") hidden.add(id);
  }
  return hidden;
}

// MARK: Fonts and color schemes

export const FONT_PAIRS: { name: string; heading: string; body: string }[] = [
  { name: "Helvetica Neue", heading: "Helvetica Neue", body: "Helvetica Neue" },
  { name: "Avenir", heading: "Avenir Next", body: "Avenir Next" },
  { name: "Georgia", heading: "Georgia", body: "Georgia" },
  { name: "Classic", heading: "Baskerville", body: "Gill Sans" },
  { name: "Futura", heading: "Futura", body: "Avenir" },
  { name: "Didot", heading: "Didot", body: "Helvetica Neue" },
  { name: "Rockwell", heading: "Rockwell", body: "Gill Sans" },
  { name: "Optima", heading: "Optima", body: "Optima" },
  { name: "Palatino", heading: "Palatino", body: "Palatino" },
  { name: "Menlo", heading: "Menlo", body: "Menlo" },
  { name: "American Typewriter", heading: "American Typewriter", body: "Courier New" },
  { name: "Calibri", heading: "Calibri Light", body: "Calibri" },
  { name: "Arial", heading: "Arial", body: "Arial" },
  { name: "Segoe UI", heading: "Segoe UI Light", body: "Segoe UI" },
  { name: "Times New Roman", heading: "Times New Roman", body: "Times New Roman" },
  { name: "Verdana", heading: "Verdana", body: "Verdana" },
];

const c = (h: number) => rgbHex(h);
const scheme = (d1: number | typeof BLACK, l1: number | typeof WHITE, d2: number, l2: number, a: number[]): ThemeColors =>
  themeColors(typeof d1 === "number" ? c(d1) : d1, typeof l1 === "number" ? c(l1) : l1, c(d2), c(l2), a.map(c));

export const COLOR_SCHEMES: [string, ThemeColors][] = [
  ["Wired", scheme(0x1c1c1e, WHITE, 0x3a3a3c, 0xf2f0ec, [0xf57a1b, 0x2f6fdb, 0x1e9a5f, 0xd64545, 0x8e5cd9, 0x13a3a3])],
  ["Office", scheme(BLACK, WHITE, 0x44546a, 0xe7e6e6, [0x4472c4, 0xed7d31, 0xa5a5a5, 0xffc000, 0x5b9bd5, 0x70ad47])],
  ["Blue", scheme(0x17406d, WHITE, 0x0f6fc6, 0xdbeff9, [0x0f6fc6, 0x009dd9, 0x0bd0d9, 0x10cf9b, 0x7cca62, 0xa5c249])],
  ["Green", scheme(0x1d3a26, WHITE, 0x455f51, 0xe3ded1, [0x549e39, 0x8ab833, 0xc0cf3a, 0x029676, 0x4ab5c4, 0x0989b1])],
  ["Red Orange", scheme(0x3b1e12, WHITE, 0x505046, 0xeeece1, [0xe84c22, 0xffbd47, 0xb64926, 0xff8427, 0xcc9900, 0xb22600])],
  ["Violet", scheme(0x2e1a47, WHITE, 0x373545, 0xdcd8dc, [0xad84c6, 0x8784c7, 0x5d739a, 0x6997af, 0x84acb6, 0x6f8183])],
  ["Paper", scheme(0x3d3226, 0xfbf7f0, 0x5c4b37, 0xede4d3, [0xa5644e, 0xb58b80, 0xc3986d, 0xa19574, 0xc17529, 0x7a6a55])],
  ["Grayscale", scheme(BLACK, WHITE, 0x000000, 0xf8f8f8, [0xdddddd, 0xb2b2b2, 0x969696, 0x808080, 0x5f5f5f, 0x4d4d4d])],
  ["Midnight", scheme(0xf2f2f7, 0x111827, 0xc7cbd6, 0x1f2937, [0xf59e0b, 0x60a5fa, 0x34d399, 0xf87171, 0xa78bfa, 0x22d3ee])],
  ["Marquee", scheme(0x1f2a33, WHITE, 0x5e5e5e, 0xdddddd, [0x418ab3, 0xa6b727, 0xf69200, 0x838383, 0xfec306, 0xdf5327])],
];

export const SLIDE_SIZES: [string, [number, number]][] = [
  ["Widescreen (16:9)", [960, 540]], ["Standard (4:3)", [720, 540]], ["16:10", [960, 600]], ["Letter Paper (8.5×11 in)", [720, 540]],
  ["A4 Paper (210×297 mm)", [780, 540]], ["Square (1:1)", [720, 720]], ["Portrait (9:16)", [540, 960]], ["Banner", [576, 72]],
];

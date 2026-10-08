import type { ShapeKind } from "../model/types";
import type { Rect } from "../model/core";
import { clamp, inset, maxX, maxY, midX, midY } from "../model/core";
import { defaultAdjustments, hasAdjustHandle } from "../model/catalog";

/**
 * The outline of a preset shape inside a rectangle (y grows downward), plus
 * shaded accent faces (cube sides, cylinder top) and the area text flows into.
 * Shapes made of overlapping pieces set `union`: they fill with the nonzero
 * rule and stroke only their outer edge.
 */
export interface ShapeGeometry {
  path: Path2D;
  evenOdd: boolean;
  union: boolean;
  accents: { path: Path2D; shade: number }[];
  details: Path2D[];
  textRect: Rect;
}

type P = [number, number];

export function shapeGeometry(kind: ShapeKind, r: Rect, adj: number[]): ShapeGeometry {
  const defaults = defaultAdjustments(kind);
  const a = (i: number) => (i < adj.length ? adj[i] : i < defaults.length ? defaults[i] : 0);
  const w = r.w, h = r.h, ss = Math.min(w, h);
  const x0 = r.x, y0 = r.y, x1 = maxX(r), y1 = maxY(r), cx = midX(r), cy = midY(r);
  const poly = (points: P[], into = new Path2D()) => {
    // Every piece winds clockwise so overlapping pieces merge under the nonzero rule.
    let area = 0;
    points.forEach(([x, y], i) => { const [nx, ny] = points[(i + 1) % points.length]; area += x * ny - nx * y; });
    if (area < 0) points = [...points].reverse();
    points.forEach(([x, y], i) => (i ? into.lineTo(x, y) : into.moveTo(x, y)));
    into.closePath();
    return into;
  };
  const npoly = (points: P[]) => poly(points.map(([fx, fy]) => [x0 + w * fx, y0 + h * fy]));
  const regular = (n: number, rotation = -Math.PI / 2) =>
    poly(Array.from({ length: n }, (_, i) => { const t = rotation + (i * 2 * Math.PI) / n; return [cx + (w / 2) * Math.cos(t), cy + (h / 2) * Math.sin(t)] as P; }));
  const star = (n: number, inner: number) =>
    poly(Array.from({ length: 2 * n }, (_, i) => {
      const t = -Math.PI / 2 + (i * Math.PI) / n, k = i % 2 === 0 ? 1 : inner;
      return [cx + (w / 2) * k * Math.cos(t), cy + (h / 2) * k * Math.sin(t)] as P;
    }));
  const ellipse = (rx: number, ry: number, rw: number, rh: number, into = new Path2D()) => {
    into.moveTo(rx + rw, ry + rh / 2);
    into.ellipse(rx + rw / 2, ry + rh / 2, Math.max(rw / 2, 0), Math.max(rh / 2, 0), 0, 0, Math.PI * 2);
    into.closePath();
    return into;
  };
  const rect = (rx: number, ry: number, rw: number, rh: number, into = new Path2D()) => { into.rect(rx, ry, rw, rh); return into; };
  const roundRect = (rr: Rect, radius: number, into = new Path2D()) => {
    const rad = Math.max(0, Math.min(radius, rr.w / 2, rr.h / 2));
    into.moveTo(rr.x + rad, rr.y);
    into.arcTo(maxX(rr), rr.y, maxX(rr), maxY(rr), rad);
    into.arcTo(maxX(rr), maxY(rr), rr.x, maxY(rr), rad);
    into.arcTo(rr.x, maxY(rr), rr.x, rr.y, rad);
    into.arcTo(rr.x, rr.y, maxX(rr), rr.y, rad);
    into.closePath();
    return into;
  };

  let text: Rect = r;
  let path: Path2D;
  let evenOdd = false, union = false;
  const accents: { path: Path2D; shade: number }[] = [];
  const details: Path2D[] = [];

  switch (kind) {
    case "rect": case "flowChartProcess":
      path = rect(x0, y0, w, h);
      break;
    case "roundRect": case "flowChartAlternateProcess": {
      const radius = Math.min(a(0) * ss, ss / 2);
      path = roundRect(r, radius);
      text = inset(r, radius * 0.29, radius * 0.29);
      break;
    }
    case "snip1Rect": {
      const s = a(0) * ss;
      path = poly([[x0, y0], [x1 - s, y0], [x1, y0 + s], [x1, y1], [x0, y1]]);
      break;
    }
    case "snip2SameRect": {
      const s = a(0) * ss;
      path = poly([[x0 + s, y0], [x1 - s, y0], [x1, y0 + s], [x1, y1], [x0, y1], [x0, y0 + s]]);
      break;
    }
    case "round2SameRect": {
      const s = Math.min(a(0) * ss, ss / 2);
      path = new Path2D();
      path.moveTo(x0, y1);
      path.arcTo(x0, y0, x1, y0, s);
      path.arcTo(x1, y0, x1, y1, s);
      path.lineTo(x1, y1);
      path.closePath();
      break;
    }
    case "ellipse": case "flowChartConnector":
      path = ellipse(x0, y0, w, h);
      text = inset(r, w * 0.146, h * 0.146);
      break;
    case "triangle":
      path = poly([[cx, y0], [x1, y1], [x0, y1]]);
      text = { x: x0 + w * 0.25, y: y0 + h * 0.5, w: w * 0.5, h: h * 0.5 };
      break;
    case "rtTriangle":
      path = poly([[x0, y0], [x1, y1], [x0, y1]]);
      text = { x: x0 + w * 0.08, y: y0 + h * 0.5, w: w * 0.5, h: h * 0.45 };
      break;
    case "parallelogram": case "flowChartInputOutput": {
      const s = Math.min(a(0) * ss, w * 0.9);
      path = poly([[x0 + s, y0], [x1, y0], [x1 - s, y1], [x0, y1]]);
      text = inset(r, s * 0.6, 0);
      break;
    }
    case "trapezoid": {
      const s = Math.min(a(0) * ss, w / 2);
      path = poly([[x0 + s, y0], [x1 - s, y0], [x1, y1], [x0, y1]]);
      text = inset(r, s * 0.6, 0);
      break;
    }
    case "flowChartManualInput":
      path = poly([[x0, y0 + h * 0.2], [x1, y0], [x1, y1], [x0, y1]]);
      text = { x: x0, y: y0 + h * 0.2, w, h: h * 0.8 };
      break;
    case "diamond": case "flowChartDecision":
      path = poly([[cx, y0], [x1, cy], [cx, y1], [x0, cy]]);
      text = inset(r, w / 4, h / 4);
      break;
    case "pentagon":
      path = npoly([[0.5, 0], [1, 0.382], [0.809, 1], [0.191, 1], [0, 0.382]]);
      text = { ...inset(r, w * 0.2, h * 0.2), y: y0 + h * 0.3 };
      break;
    case "hexagon": {
      const s = Math.min(a(0) * ss, w / 2);
      path = poly([[x0 + s, y0], [x1 - s, y0], [x1, cy], [x1 - s, y1], [x0 + s, y1], [x0, cy]]);
      text = inset(r, s * 0.6, 0);
      break;
    }
    case "octagon": {
      const s = a(0) * ss;
      path = poly([[x0 + s, y0], [x1 - s, y0], [x1, y0 + s], [x1, y1 - s], [x1 - s, y1], [x0 + s, y1], [x0, y1 - s], [x0, y0 + s]]);
      text = inset(r, s * 0.5, s * 0.5);
      break;
    }
    case "decagon":
      path = regular(10, 0);
      text = inset(r, w * 0.12, h * 0.12);
      break;
    case "pie": case "chord": {
      const start = (a(0) * Math.PI) / 180, end = (a(1) * Math.PI) / 180;
      path = new Path2D();
      if (kind === "pie") path.moveTo(cx, cy);
      else path.moveTo(cx + (w / 2) * Math.cos(start), cy + (h / 2) * Math.sin(start));
      path.ellipse(cx, cy, w / 2, h / 2, 0, start, end, false);
      path.closePath();
      text = inset(r, w * 0.15, h * 0.15);
      break;
    }
    case "teardrop":
      path = ellipse(x0, y0, w, h);
      poly([[cx, y0], [x1, y0], [x1, cy], [cx, cy]], path);
      union = true;
      text = inset(r, w * 0.146, h * 0.146);
      break;
    case "frame": {
      const t = a(0) * ss;
      path = rect(x0, y0, w, h);
      rect(x0 + t, y0 + t, w - t * 2, h - t * 2, path);
      evenOdd = true;
      text = inset(r, t, t);
      break;
    }
    case "donut": {
      const t = a(0) * ss;
      path = ellipse(x0, y0, w, h);
      ellipse(x0 + t, y0 + t, w - t * 2, h - t * 2, path);
      evenOdd = true;
      break;
    }
    case "noSmoking": {
      // A ring with a diagonal bar inside: drawn as the ring plus the bar clipped to the inner circle.
      const t = a(0) * ss, half = t / 2;
      path = ellipse(x0, y0, w, h);
      ellipse(x0 + t, y0 + t, w - t * 2, h - t * 2, path);
      evenOdd = true;
      const bar = poly([[x0 + w * 0.15 - half, y0 + h * 0.15 + half], [x0 + w * 0.15 + half, y0 + h * 0.15 - half],
        [x1 - w * 0.15 + half, y1 - h * 0.15 - half], [x1 - w * 0.15 - half, y1 - h * 0.15 + half]]);
      accents.push({ path: bar, shade: 0 });
      break;
    }
    case "can": {
      const e = a(0) * ss;
      path = new Path2D();
      path.moveTo(x0, y0 + e / 2);
      path.lineTo(x0, y1 - e / 2);
      path.bezierCurveTo(x0, y1 + e / 6, x1, y1 + e / 6, x1, y1 - e / 2);
      path.lineTo(x1, y0 + e / 2);
      path.bezierCurveTo(x1, y0 - e / 6, x0, y0 - e / 6, x0, y0 + e / 2);
      path.closePath();
      accents.push({ path: ellipse(x0, y0, w, e), shade: 0.25 });
      text = { x: x0, y: y0 + e, w, h: h - e * 1.5 };
      break;
    }
    case "cube": {
      const d = a(0) * ss;
      path = poly([[x0, y0 + d], [x0 + d, y0], [x1, y0], [x1, y1 - d], [x1 - d, y1], [x0, y1]]);
      accents.push({ path: poly([[x0, y0 + d], [x0 + d, y0], [x1, y0], [x1 - d, y0 + d]]), shade: 0.25 });
      accents.push({ path: poly([[x1 - d, y0 + d], [x1, y0], [x1, y1 - d], [x1 - d, y1]]), shade: -0.2 });
      text = { x: x0, y: y0 + d, w: w - d, h: h - d };
      break;
    }
    case "heart":
      path = new Path2D();
      path.moveTo(cx, y0 + h * 0.25);
      path.bezierCurveTo(cx + w * 0.55, y0 - h * 0.25, x1 + w * 0.3, y0 + h * 0.45, cx, y1);
      path.bezierCurveTo(x0 - w * 0.3, y0 + h * 0.45, cx - w * 0.55, y0 - h * 0.25, cx, y0 + h * 0.25);
      path.closePath();
      text = inset(r, w * 0.2, h * 0.2);
      break;
    case "lightningBolt":
      path = npoly([[0.39, 0], [0.62, 0.32], [0.55, 0.35], [0.79, 0.6], [0.72, 0.63], [1, 1], [0.42, 0.7], [0.5, 0.67], [0.17, 0.48], [0.26, 0.44], [0, 0.2]]);
      text = inset(r, w * 0.3, h * 0.3);
      break;
    case "sun": {
      const core = inset(r, w * 0.25, h * 0.25);
      path = ellipse(core.x, core.y, core.w, core.h);
      for (let i = 0; i < 8; i++) {
        const t = (i * Math.PI) / 4;
        poly([[cx + w * 0.34 * Math.cos(t - 0.18), cy + h * 0.34 * Math.sin(t - 0.18)], [cx + (w / 2) * Math.cos(t), cy + (h / 2) * Math.sin(t)],
          [cx + w * 0.34 * Math.cos(t + 0.18), cy + h * 0.34 * Math.sin(t + 0.18)]], path);
      }
      union = true;
      text = inset(core, core.w * 0.15, core.h * 0.15);
      break;
    }
    case "moon": {
      const k = a(0);
      path = new Path2D();
      path.moveTo(x1, y0);
      path.bezierCurveTo(x0 - w * 0.33, y0, x0 - w * 0.33, y1, x1, y1);
      path.bezierCurveTo(x1 - w * k * 1.33, y1 - h * 0.1, x1 - w * k * 1.33, y0 + h * 0.1, x1, y0);
      path.closePath();
      text = { x: x0 + w * 0.1, y: y0 + h * 0.3, w: w * 0.4, h: h * 0.4 };
      break;
    }
    case "cloud": case "cloudCallout": {
      const body = inset(r, w * 0.12, h * 0.16);
      path = ellipse(body.x, body.y, body.w, body.h);
      const bumps: [number, number, number][] = [[0.2, 0.3, 0.42], [0.42, 0.2, 0.46], [0.66, 0.22, 0.42], [0.84, 0.42, 0.36], [0.75, 0.72, 0.4], [0.5, 0.8, 0.42], [0.24, 0.72, 0.4], [0.12, 0.5, 0.32]];
      for (const [bx, by, size] of bumps) {
        const bw = w * size, bh = h * size;
        ellipse(x0 + w * bx - bw / 2, y0 + h * by - bh / 2, bw, bh, path);
      }
      if (kind === "cloudCallout") {
        const tip: P = [x0 + w * a(0), y0 + h * a(1)];
        [0.07, 0.045, 0.03].forEach((s, i) => {
          const t = 0.55 + i * 0.18;
          const px = cx + (tip[0] - cx) * t, py = cy + (tip[1] - cy) * t;
          ellipse(px - ss * s, py - ss * s, ss * s * 2, ss * s * 2, path);
        });
      }
      union = true;
      text = inset(r, w * 0.2, h * 0.22);
      break;
    }
    case "smileyFace": {
      path = ellipse(x0, y0, w, h);
      const eyes = ellipse(x0 + w * 0.3, y0 + h * 0.3, w * 0.1, h * 0.1);
      ellipse(x0 + w * 0.6, y0 + h * 0.3, w * 0.1, h * 0.1, eyes);
      accents.push({ path: eyes, shade: -0.35 });
      const mouth = new Path2D();
      mouth.moveTo(x0 + w * 0.27, y0 + h * 0.65);
      mouth.quadraticCurveTo(cx, y0 + h * 0.85, x0 + w * 0.73, y0 + h * 0.65);
      details.push(mouth);
      text = inset(r, w * 0.2, h * 0.2);
      break;
    }
    case "plaque": {
      const s = a(0) * ss;
      path = new Path2D();
      path.moveTo(x0 + s, y0);
      path.lineTo(x1 - s, y0);
      path.arc(x1, y0, s, Math.PI, Math.PI / 2, true);
      path.lineTo(x1, y1 - s);
      path.arc(x1, y1, s, -Math.PI / 2, Math.PI, true);
      path.lineTo(x0 + s, y1);
      path.arc(x0, y1, s, 0, -Math.PI / 2, true);
      path.lineTo(x0, y0 + s);
      path.arc(x0, y0, s, Math.PI / 2, 0, true);
      path.closePath();
      text = inset(r, s * 0.7, s * 0.7);
      break;
    }
    case "rightArrow": case "leftArrow": case "notchedRightArrow": {
      const shaft = a(0) * h, head = Math.min(a(1) * ss, w);
      const top = cy - shaft / 2, bottom = cy + shaft / 2;
      let pts: P[] = [[x0, top], [x1 - head, top], [x1 - head, y0], [x1, cy], [x1 - head, y1], [x1 - head, bottom], [x0, bottom]];
      if (kind === "notchedRightArrow") pts.push([x0 + shaft / 2, cy]);
      if (kind === "leftArrow") pts = pts.map(([x, y]) => [x0 + x1 - x, y]);
      path = poly(pts);
      text = { x: kind === "leftArrow" ? x0 + head * 0.5 : x0, y: top, w: w - head * 0.5, h: shaft };
      break;
    }
    case "upArrow": case "downArrow": {
      const shaft = a(0) * w, head = Math.min(a(1) * ss, h);
      const left = cx - shaft / 2, right = cx + shaft / 2;
      let pts: P[] = [[left, y1], [left, y0 + head], [x0, y0 + head], [cx, y0], [x1, y0 + head], [right, y0 + head], [right, y1]];
      if (kind === "downArrow") pts = pts.map(([x, y]) => [x, y0 + y1 - y]);
      path = poly(pts);
      text = { x: left, y: kind === "upArrow" ? y0 + head * 0.5 : y0, w: shaft, h: h - head * 0.5 };
      break;
    }
    case "leftRightArrow": {
      const shaft = a(0) * h, head = Math.min(a(1) * ss, w / 2);
      const top = cy - shaft / 2, bottom = cy + shaft / 2;
      path = poly([[x0, cy], [x0 + head, y0], [x0 + head, top], [x1 - head, top], [x1 - head, y0], [x1, cy], [x1 - head, y1], [x1 - head, bottom], [x0 + head, bottom], [x0 + head, y1]]);
      text = { x: x0 + head * 0.5, y: top, w: w - head, h: shaft };
      break;
    }
    case "upDownArrow": {
      const shaft = a(0) * w, head = Math.min(a(1) * ss, h / 2);
      const left = cx - shaft / 2, right = cx + shaft / 2;
      path = poly([[cx, y0], [x1, y0 + head], [right, y0 + head], [right, y1 - head], [x1, y1 - head], [cx, y1], [x0, y1 - head], [left, y1 - head], [left, y0 + head], [x0, y0 + head]]);
      text = { x: left, y: y0 + head * 0.5, w: shaft, h: h - head };
      break;
    }
    case "quadArrow": {
      const s = (a(0) * ss) / 2, head = ss * 0.22;
      path = poly([
        [cx, y0], [cx + head, y0 + head], [cx + s, y0 + head], [cx + s, cy - s], [x1 - head, cy - s], [x1 - head, cy - head],
        [x1, cy], [x1 - head, cy + head], [x1 - head, cy + s], [cx + s, cy + s], [cx + s, y1 - head], [cx + head, y1 - head],
        [cx, y1], [cx - head, y1 - head], [cx - s, y1 - head], [cx - s, cy + s], [x0 + head, cy + s], [x0 + head, cy + head],
        [x0, cy], [x0 + head, cy - head], [x0 + head, cy - s], [cx - s, cy - s], [cx - s, y0 + head], [cx - head, y0 + head],
      ]);
      text = { x: cx - s, y: cy - s, w: s * 2, h: s * 2 };
      break;
    }
    case "chevron": {
      const d = Math.min(a(0) * ss, w);
      path = poly([[x0, y0], [x1 - d, y0], [x1, cy], [x1 - d, y1], [x0, y1], [x0 + d, cy]]);
      text = inset(r, d, 0);
      break;
    }
    case "homePlate": {
      const d = Math.min(a(0) * ss, w);
      path = poly([[x0, y0], [x1 - d, y0], [x1, cy], [x1 - d, y1], [x0, y1]]);
      text = { x: x0, y: y0, w: w - d * 0.5, h };
      break;
    }
    case "mathPlus": case "mathMultiply": {
      const t = (a(0) * ss) / 2;
      const plus = poly([[cx - t, y0], [cx + t, y0], [cx + t, cy - t], [x1, cy - t], [x1, cy + t], [cx + t, cy + t],
        [cx + t, y1], [cx - t, y1], [cx - t, cy + t], [x0, cy + t], [x0, cy - t], [cx - t, cy - t]]);
      if (kind === "mathMultiply") {
        path = new Path2D();
        path.addPath(plus, new DOMMatrix().translate(cx, cy).rotate(45).scale(0.75, 0.75).translate(-cx, -cy));
      } else {
        path = plus;
      }
      text = { x: cx - t, y: cy - t, w: t * 2, h: t * 2 };
      break;
    }
    case "mathMinus": {
      const t = (a(0) * h) / 2;
      path = rect(x0, cy - t, w, t * 2);
      break;
    }
    case "mathDivide": {
      const t = (a(0) * h) / 2;
      path = rect(x0, cy - t / 2, w, t);
      const d = Math.min(t * 1.6, h * 0.2);
      ellipse(cx - d / 2, y0 + h * 0.12, d, d, path);
      ellipse(cx - d / 2, y1 - h * 0.12 - d, d, d, path);
      break;
    }
    case "mathEqual": case "mathNotEqual": {
      const t = (a(0) * h) / 3;
      path = rect(x0, cy - t * 1.5, w, t);
      rect(x0, cy + t * 0.5, w, t, path);
      if (kind === "mathNotEqual") {
        poly([[cx + w * 0.12, y0], [cx + w * 0.12 + t, y0], [cx - w * 0.12 + t, y1], [cx - w * 0.12, y1]], path);
        union = true;
      }
      break;
    }
    case "flowChartPredefinedProcess": {
      path = rect(x0, y0, w, h);
      const lines = new Path2D();
      lines.moveTo(x0 + w * 0.1, y0); lines.lineTo(x0 + w * 0.1, y1);
      lines.moveTo(x1 - w * 0.1, y0); lines.lineTo(x1 - w * 0.1, y1);
      details.push(lines);
      text = inset(r, w * 0.1, 0);
      break;
    }
    case "flowChartDocument":
      path = new Path2D();
      path.moveTo(x0, y0);
      path.lineTo(x1, y0);
      path.lineTo(x1, y1 - h * 0.17);
      path.bezierCurveTo(x0 + w * 0.7, y1 - h * 0.4, x0 + w * 0.3, y1 + h * 0.2, x0, y1 - h * 0.08);
      path.closePath();
      text = { x: x0, y: y0, w, h: h * 0.8 };
      break;
    case "flowChartTerminator": {
      const radius = Math.min(h / 2, w / 2);
      path = roundRect(r, radius);
      text = inset(r, radius * 0.3, 0);
      break;
    }
    case "flowChartPreparation": {
      const s = Math.min(w * 0.2, h);
      path = poly([[x0 + s, y0], [x1 - s, y0], [x1, cy], [x1 - s, y1], [x0 + s, y1], [x0, cy]]);
      text = inset(r, s, 0);
      break;
    }
    case "flowChartDelay":
      path = new Path2D();
      path.moveTo(x0, y0);
      path.lineTo(cx, y0);
      path.ellipse(cx, cy, w / 2, h / 2, 0, -Math.PI / 2, Math.PI / 2, false);
      path.lineTo(x0, y1);
      path.closePath();
      text = inset(r, w * 0.05, h * 0.15);
      break;
    case "star4": case "star5": case "star6": case "star8": case "star12": case "star24": {
      const n = Number(kind.slice(4));
      path = star(n, a(0));
      const k = Math.max(a(0), 0.3);
      text = inset(r, (w * (1 - k * 0.8)) / 2, (h * (1 - k * 0.8)) / 2);
      break;
    }
    case "irregularSeal1":
      path = npoly([[0.5, 0.18], [0.6, 0], [0.64, 0.2], [0.86, 0.08], [0.78, 0.3], [1, 0.34], [0.82, 0.5], [0.98, 0.7], [0.76, 0.66],
        [0.8, 0.94], [0.6, 0.76], [0.5, 1], [0.42, 0.78], [0.2, 0.92], [0.26, 0.68], [0, 0.66], [0.18, 0.5], [0.02, 0.28], [0.26, 0.32], [0.22, 0.06], [0.4, 0.24]]);
      text = inset(r, w * 0.28, h * 0.28);
      break;
    case "wedgeRectCallout": case "wedgeRoundRectCallout": case "wedgeEllipseCallout": {
      const tip: P = [x0 + w * a(0), y0 + h * a(1)];
      path = kind === "wedgeEllipseCallout" ? ellipse(x0, y0, w, h) : kind === "wedgeRoundRectCallout" ? roundRect(r, ss * 0.1667) : rect(x0, y0, w, h);
      const dx = tip[0] - cx, dy = tip[1] - cy, len = Math.max(Math.hypot(dx, dy), 1);
      const nx = -dy / len, ny = dx / len, base = ss * 0.12;
      const sx = cx + dx * 0.2, sy = cy + dy * 0.2;
      poly([[sx + nx * base, sy + ny * base], tip, [sx - nx * base, sy - ny * base]], path);
      union = true;
      text = kind === "wedgeEllipseCallout" ? inset(r, w * 0.146, h * 0.146) : r;
      break;
    }
    default:
      path = rect(x0, y0, w, h);
  }
  return { path, evenOdd, union, accents, details, textRect: text };
}

/** Where the yellow adjustment handle sits. */
export function adjustHandle(kind: ShapeKind, r: Rect, adj: number[]): [number, number] | null {
  if (!hasAdjustHandle(kind)) return null;
  const defaults = defaultAdjustments(kind);
  const a = (i: number) => (i < adj.length ? adj[i] : i < defaults.length ? defaults[i] : 0);
  const ss = Math.min(r.w, r.h);
  switch (kind) {
    case "roundRect": case "round2SameRect": case "plaque": return [r.x + a(0) * ss, r.y];
    case "snip1Rect": case "snip2SameRect": return [maxX(r) - a(0) * ss, r.y];
    case "parallelogram": case "trapezoid": case "hexagon": case "flowChartInputOutput": case "octagon": case "frame": return [r.x + a(0) * ss, r.y];
    case "chevron": case "homePlate": return [maxX(r) - a(0) * ss, r.y];
    case "donut": case "noSmoking": return [r.x + a(0) * ss, midY(r)];
    case "can": case "cube": return [midX(r), r.y + a(0) * ss];
    case "moon": return [maxX(r) - a(0) * r.w, midY(r)];
    case "star4": case "star5": case "star6": case "star8": case "star12": case "star24": return [midX(r), midY(r) - (a(0) * r.h) / 2];
    case "rightArrow": case "notchedRightArrow": case "leftRightArrow": return [maxX(r) - a(1) * ss, r.y];
    case "leftArrow": return [r.x + a(1) * ss, r.y];
    case "upArrow": case "upDownArrow": return [r.x, r.y + a(1) * ss];
    case "downArrow": return [r.x, maxY(r) - a(1) * ss];
    case "wedgeRectCallout": case "wedgeRoundRectCallout": case "wedgeEllipseCallout": case "cloudCallout": return [r.x + a(0) * r.w, r.y + a(1) * r.h];
  }
  return null;
}

/** The adjustments after dragging the handle to a point. */
export function adjustTo(kind: ShapeKind, r: Rect, adj: number[], [px, py]: [number, number]): number[] {
  const defaults = defaultAdjustments(kind);
  const values = defaults.map((d, i) => (i < adj.length ? adj[i] : d));
  const ss = Math.max(Math.min(r.w, r.h), 1);
  switch (kind) {
    case "roundRect": case "round2SameRect": case "plaque": values[0] = clamp((px - r.x) / ss, 0, 0.5); break;
    case "snip1Rect": case "snip2SameRect": values[0] = clamp((maxX(r) - px) / ss, 0, 0.5); break;
    case "parallelogram": case "trapezoid": case "hexagon": case "flowChartInputOutput": values[0] = clamp((px - r.x) / ss, 0, (r.w / ss) * 0.5); break;
    case "octagon": case "frame": values[0] = clamp((px - r.x) / ss, 0, 0.5); break;
    case "chevron": case "homePlate": values[0] = clamp((maxX(r) - px) / ss, 0, r.w / ss); break;
    case "donut": case "noSmoking": values[0] = clamp((px - r.x) / ss, 0.02, 0.5); break;
    case "can": case "cube": values[0] = clamp((py - r.y) / ss, 0, 1); break;
    case "moon": values[0] = clamp((maxX(r) - px) / Math.max(r.w, 1), 0.05, 0.9); break;
    case "star4": case "star5": case "star6": case "star8": case "star12": case "star24": values[0] = clamp((midY(r) - py) / Math.max(r.h / 2, 1), 0.05, 0.95); break;
    case "rightArrow": case "notchedRightArrow": case "leftRightArrow": values[1] = clamp((maxX(r) - px) / ss, 0, r.w / ss); break;
    case "leftArrow": values[1] = clamp((px - r.x) / ss, 0, r.w / ss); break;
    case "upArrow": case "upDownArrow": values[1] = clamp((py - r.y) / ss, 0, r.h / ss); break;
    case "downArrow": values[1] = clamp((maxY(r) - py) / ss, 0, r.h / ss); break;
    case "wedgeRectCallout": case "wedgeRoundRectCallout": case "wedgeEllipseCallout": case "cloudCallout":
      values[0] = (px - r.x) / Math.max(r.w, 1);
      values[1] = (py - r.y) / Math.max(r.h, 1);
      break;
  }
  return values;
}

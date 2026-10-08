import type { ChartContent, LegendPosition, RGB, ThemeColors } from "../model/types";
import type { Rect } from "../model/core";
import { accents, cssColor, isDark, isRoundChart, resolve, shaded, withAlpha } from "../model/core";
import { fontString } from "./fonts";
import { fillPath, type Ctx, type RenderEnv } from "./paint";

export function seriesColor(chart: ChartContent, index: number, colors: ThemeColors): RGB {
  const series = chart.series[index];
  if (!isRoundChart(chart.kind) && series?.color) return resolve(series.color, colors);
  const list = accents(colors);
  const base = list[index % list.length];
  const round = Math.floor(index / list.length);
  return round === 0 ? base : shaded(base, round % 2 === 1 ? -0.3 : 0.35);
}

/** A rounded axis range and step. */
export function niceScale(lo: number, hi: number, ticks = 5): { min: number; max: number; step: number } {
  if (lo === hi) { hi = lo + 1; if (lo > 0) lo = 0; }
  const rough = (hi - lo) / ticks;
  const magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
  const residual = rough / magnitude;
  const step = (residual > 5 ? 10 : residual > 2 ? 5 : residual > 1 ? 2 : 1) * magnitude;
  return { min: Math.floor(lo / step) * step, max: Math.ceil(hi / step) * step, step };
}

export function formatValue(v: number): string {
  const g = (n: number) => String(Number(n.toPrecision(6)));
  if (Math.abs(v) >= 1_000_000) return g(v / 1_000_000) + "M";
  if (Math.abs(v) >= 10_000) return g(v / 1000) + "K";
  if (v === Math.round(v)) return String(v);
  return g(Math.round(v * 1000) / 1000);
}

export function drawChart(ctx: Ctx, chart: ChartContent, rect: Rect, env: RenderEnv) {
  const colors = env.theme.colors;
  const bg = new Path2D();
  bg.rect(rect.x, rect.y, rect.w, rect.h);
  fillPath(ctx, bg, chart.background, rect, env);
  const textColor = resolve(chart.textColor, colors);
  const fs = chart.fontSize;
  const family = env.theme.bodyFont;
  const font = (size: number) => fontString(family, size, false, false);
  ctx.save();
  ctx.textBaseline = "top";
  ctx.textAlign = "left";
  ctx.font = font(fs);
  let plot = { x: rect.x + 8, y: rect.y + 8, w: rect.w - 16, h: rect.h - 16 };

  if (chart.title) {
    ctx.font = font(fs * 1.5);
    ctx.fillStyle = cssColor(textColor);
    const w = ctx.measureText(chart.title).width;
    ctx.fillText(chart.title, rect.x + rect.w / 2 - w / 2, plot.y);
    const h = fs * 1.5 * 1.2;
    plot = { ...plot, y: plot.y + h + 6, h: plot.h - h - 6 };
    ctx.font = font(fs);
  }

  const items: [string, RGB][] = isRoundChart(chart.kind)
    ? chart.categories.map((c, i) => [c, seriesColor(chart, i, colors)])
    : chart.series.map((s, i) => [s.name, seriesColor(chart, i, colors)]);
  if (chart.legend !== "none" && items.length) plot = drawLegend(ctx, items, chart.legend, plot, fs, textColor);
  if (plot.w > 20 && plot.h > 20) {
    if (isRoundChart(chart.kind)) drawPie(ctx, chart, plot, colors, fs, font(fs));
    else drawCartesian(ctx, chart, plot, colors, fs, textColor);
  }
  ctx.restore();
}

function drawLegend(ctx: Ctx, items: [string, RGB][], position: LegendPosition, plot: Rect, fs: number, textColor: RGB): Rect {
  const swatch = fs * 0.75, spacing = fs, lineHeight = fs * 1.4;
  const widths = items.map(([label]) => ctx.measureText(label).width + swatch + 5);
  const drawItem = (i: number, x: number, y: number) => {
    ctx.fillStyle = cssColor(items[i][1]);
    ctx.fillRect(x, y + (lineHeight - swatch) / 2, swatch, swatch);
    ctx.fillStyle = cssColor(textColor);
    ctx.fillText(items[i][0], x + swatch + 5, y + (lineHeight - fs * 1.15) / 2);
  };
  if (position === "top" || position === "bottom") {
    const rows: number[][] = [[]];
    let x = 0;
    widths.forEach((w, i) => {
      if (x + w > plot.w && rows[rows.length - 1].length) { rows.push([]); x = 0; }
      rows[rows.length - 1].push(i);
      x += w + spacing;
    });
    const total = rows.length * lineHeight;
    let y = position === "top" ? plot.y : plot.y + plot.h - total;
    for (const row of rows) {
      const rowWidth = row.reduce((a, i) => a + widths[i], 0) + spacing * (row.length - 1);
      let rx = plot.x + plot.w / 2 - rowWidth / 2;
      for (const i of row) { drawItem(i, rx, y); rx += widths[i] + spacing; }
      y += lineHeight;
    }
    return { x: plot.x, y: position === "top" ? plot.y + total + 6 : plot.y, w: plot.w, h: plot.h - total - 6 };
  }
  const column = Math.max(...widths) + 8;
  const total = items.length * lineHeight;
  const x = position === "left" ? plot.x : plot.x + plot.w - column + 8;
  let y = plot.y + plot.h / 2 - total / 2;
  items.forEach((_, i) => { drawItem(i, x, y); y += lineHeight; });
  return { x: position === "left" ? plot.x + column : plot.x, y: plot.y, w: plot.w - column - 4, h: plot.h };
}

function drawPie(ctx: Ctx, chart: ChartContent, plot: Rect, colors: ThemeColors, fs: number, font: string) {
  const series = chart.series[0];
  if (!series) return;
  const values = series.values.map((v) => Math.max(v, 0));
  const total = values.reduce((a, b) => a + b, 0);
  if (total <= 0) return;
  const d = Math.min(plot.w, plot.h);
  const cx = plot.x + plot.w / 2, cy = plot.y + plot.h / 2;
  let angle = -Math.PI / 2;
  values.forEach((v, i) => {
    if (v <= 0) return;
    const sweep = (v / total) * Math.PI * 2;
    ctx.beginPath();
    if (chart.kind === "doughnut") {
      ctx.arc(cx, cy, d / 2, angle, angle + sweep);
      ctx.arc(cx, cy, d / 4, angle + sweep, angle, true);
    } else {
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, d / 2, angle, angle + sweep);
    }
    ctx.closePath();
    const color = seriesColor(chart, i, colors);
    ctx.fillStyle = cssColor(color);
    ctx.fill();
    ctx.strokeStyle = cssColor(colors.light1);
    ctx.lineWidth = 1.5;
    ctx.stroke();
    if (chart.showDataLabels) {
      const mid = angle + sweep / 2, r = chart.kind === "doughnut" ? d * 0.38 : d * 0.32;
      const label = `${Math.round((v / total) * 100)}%`;
      ctx.font = font;
      ctx.fillStyle = isDark(color) ? "white" : "black";
      const w = ctx.measureText(label).width;
      ctx.fillText(label, cx + Math.cos(mid) * r - w / 2, cy + Math.sin(mid) * r - fs * 0.6);
    }
    angle += sweep;
  });
}

function drawCartesian(ctx: Ctx, chart: ChartContent, plotRect: Rect, colors: ThemeColors, fs: number, textColor: RGB) {
  const kind = chart.kind;
  const horizontal = kind === "bar" || kind === "stackedBar";
  const stacked = kind === "stackedColumn" || kind === "stackedBar";
  const n = Math.max(chart.categories.length, ...chart.series.map((s) => s.values.length), 0);
  if (!n || !chart.series.length) return;
  const value = (s: number, i: number) => chart.series[s].values[i] ?? 0;

  let lo = 0, hi = 0;
  if (stacked) {
    for (let i = 0; i < n; i++) {
      let pos = 0, neg = 0;
      chart.series.forEach((_, s) => { const v = value(s, i); if (v >= 0) pos += v; else neg += v; });
      hi = Math.max(hi, pos); lo = Math.min(lo, neg);
    }
  } else {
    chart.series.forEach((_, s) => { for (let i = 0; i < n; i++) { lo = Math.min(lo, value(s, i)); hi = Math.max(hi, value(s, i)); } });
  }
  const scale = niceScale(lo, hi);
  const ticks: number[] = [];
  for (let t = scale.min; t <= scale.max + scale.step / 2; t += scale.step) ticks.push(Number(t.toPrecision(12)));
  const tickWidth = Math.max(...ticks.map((t) => ctx.measureText(formatValue(t)).width));
  const categoryHeight = fs * 1.4;
  const categoryWidth = Math.max(0, ...chart.categories.map((c) => ctx.measureText(c).width));
  const plot = { ...plotRect };
  if (horizontal) { plot.x += categoryWidth + 8; plot.w -= categoryWidth + 8; plot.h -= categoryHeight; }
  else { plot.x += tickWidth + 8; plot.w -= tickWidth + 8; plot.h -= categoryHeight; }
  if (plot.w <= 10 || plot.h <= 10) return;
  const pos = (v: number) => {
    const f = (v - scale.min) / (scale.max - scale.min);
    return horizontal ? plot.x + f * plot.w : plot.y + plot.h - f * plot.h;
  };
  const ink = cssColor(textColor);

  ctx.lineWidth = 0.75;
  for (const tick of ticks) {
    const p = pos(tick);
    if (chart.showGridlines) {
      ctx.strokeStyle = cssColor(withAlpha(textColor, 0.15));
      ctx.beginPath();
      if (horizontal) { ctx.moveTo(p, plot.y); ctx.lineTo(p, plot.y + plot.h); }
      else { ctx.moveTo(plot.x, p); ctx.lineTo(plot.x + plot.w, p); }
      ctx.stroke();
    }
    const label = formatValue(tick);
    const w = ctx.measureText(label).width;
    ctx.fillStyle = ink;
    if (horizontal) ctx.fillText(label, p - w / 2, plot.y + plot.h + 3);
    else ctx.fillText(label, plot.x - w - 6, p - fs * 0.6);
  }
  ctx.strokeStyle = cssColor(withAlpha(textColor, 0.45));
  ctx.lineWidth = 1;
  const zero = pos(Math.max(scale.min, Math.min(0, scale.max)));
  ctx.beginPath();
  if (horizontal) { ctx.moveTo(zero, plot.y); ctx.lineTo(zero, plot.y + plot.h); }
  else { ctx.moveTo(plot.x, zero); ctx.lineTo(plot.x + plot.w, zero); }
  ctx.stroke();

  const band = (horizontal ? plot.h : plot.w) / n;
  ctx.fillStyle = ink;
  for (let i = 0; i < Math.min(n, chart.categories.length); i++) {
    let label = chart.categories[i];
    if (horizontal) {
      const w = ctx.measureText(label).width;
      ctx.fillText(label, plot.x - w - 6, plot.y + band * (i + 0.5) - fs * 0.6);
    } else if (kind !== "scatter") {
      const maxWidth = band - 4;
      if (ctx.measureText(label).width > maxWidth) {
        while (label.length > 1 && ctx.measureText(label + "…").width > maxWidth) label = label.slice(0, -1);
        label += "…";
      }
      const w = ctx.measureText(label).width;
      ctx.fillText(label, plot.x + band * (i + 0.5) - w / 2, plot.y + plot.h + 3);
    }
  }

  const count = chart.series.length;
  if (kind === "column" || kind === "bar" || kind === "stackedColumn" || kind === "stackedBar") {
    const groupWidth = band * 0.7;
    const barWidth = stacked ? groupWidth : groupWidth / count;
    for (let i = 0; i < n; i++) {
      let posBase = 0, negBase = 0;
      for (let s = 0; s < count; s++) {
        const v = value(s, i);
        let from = 0, to = v;
        if (stacked) {
          if (v >= 0) { from = posBase; to = posBase + v; posBase = to; } else { from = negBase; to = negBase + v; negBase = to; }
        }
        const start = (horizontal ? plot.y : plot.x) + band * i + (band - groupWidth) / 2 + (stacked ? 0 : barWidth * s);
        const a = pos(from), b = pos(to);
        const r = horizontal
          ? { x: Math.min(a, b), y: start, w: Math.abs(b - a), h: barWidth * 0.92 }
          : { x: start, y: Math.min(a, b), w: barWidth * 0.92, h: Math.abs(b - a) };
        ctx.fillStyle = cssColor(seriesColor(chart, s, colors));
        ctx.fillRect(r.x, r.y, r.w, r.h);
        if (chart.showDataLabels) {
          const label = formatValue(v), w = ctx.measureText(label).width;
          ctx.fillStyle = ink;
          if (horizontal) ctx.fillText(label, r.x + r.w + 3, r.y + r.h / 2 - fs * 0.6);
          else ctx.fillText(label, r.x + r.w / 2 - w / 2, stacked ? r.y + r.h / 2 - fs * 0.6 : r.y - fs * 1.25);
        }
      }
    }
  } else if (kind === "line" || kind === "lineMarkers" || kind === "area") {
    for (let s = count - 1; s >= 0; s--) {
      const color = seriesColor(chart, s, colors);
      const points = Array.from({ length: n }, (_, i) => [plot.x + band * (i + 0.5), pos(value(s, i))] as [number, number]);
      ctx.beginPath();
      if (kind === "area") {
        ctx.moveTo(points[0][0], zero);
        for (const [x, y] of points) ctx.lineTo(x, y);
        ctx.lineTo(points[points.length - 1][0], zero);
        ctx.closePath();
        ctx.fillStyle = cssColor(withAlpha(color, 0.75));
        ctx.fill();
      } else {
        points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
        ctx.strokeStyle = cssColor(color);
        ctx.lineWidth = Math.max(2, fs / 5);
        ctx.lineJoin = "round";
        ctx.stroke();
        if (kind === "lineMarkers") {
          ctx.fillStyle = cssColor(color);
          for (const [x, y] of points) { ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill(); }
        }
      }
      if (chart.showDataLabels) {
        ctx.fillStyle = ink;
        points.forEach(([x, y], i) => {
          const label = formatValue(value(s, i)), w = ctx.measureText(label).width;
          ctx.fillText(label, x - w / 2, y - fs * 1.2 - 4);
        });
      }
    }
  } else if (kind === "scatter") {
    for (let s = 0; s < count; s++) {
      ctx.fillStyle = cssColor(seriesColor(chart, s, colors));
      for (let i = 0; i < n; i++) {
        ctx.beginPath();
        ctx.arc(plot.x + (plot.w * (i + 1)) / (n + 1), pos(value(s, i)), 4.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }
}

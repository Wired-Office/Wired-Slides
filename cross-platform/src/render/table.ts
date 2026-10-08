import type { PaintColor, RGB, TableContent, ThemeColors, UUID } from "../model/types";
import type { Rect } from "../model/core";
import { clone, cssColor, isDark, maxX, maxY, resolve, shaded, themePaint, updateRuns, withAlpha } from "../model/core";
import { fillPath, type Ctx, type RenderEnv } from "./paint";
import { drawText, requiredHeight } from "./text";
import type { DrawOptions } from "./elements";

/** Column and row edges of a table placed in a frame. */
export class TableGeometry {
  xs: number[];
  ys: number[];

  constructor(t: TableContent, f: Rect) {
    const totalW = Math.max(t.columnWidths.reduce((a, b) => a + b, 0), 1);
    let x = f.x;
    this.xs = [x];
    for (const w of t.columnWidths) { x += (w / totalW) * f.w; this.xs.push(x); }
    let y = f.y;
    this.ys = [y];
    for (const h of t.rowHeights) { y += h; this.ys.push(y); }
  }

  rect(row: number, column: number, rowSpan = 1, columnSpan = 1): Rect {
    const r2 = Math.min(row + rowSpan, this.ys.length - 1), c2 = Math.min(column + columnSpan, this.xs.length - 1);
    return { x: this.xs[column], y: this.ys[row], w: this.xs[c2] - this.xs[column], h: this.ys[r2] - this.ys[row] };
  }

  cellAt(x: number, y: number): [number, number] | null {
    let column = -1, row = -1;
    for (let i = 0; i < this.xs.length - 1; i++) if (x >= this.xs[i] && x < this.xs[i + 1]) column = i;
    for (let i = 0; i < this.ys.length - 1; i++) if (y >= this.ys[i] && y < this.ys[i + 1]) row = i;
    return row >= 0 && column >= 0 ? [row, column] : null;
  }
}

/** The look a cell gets from the table's style options. */
export function cellAppearance(t: TableContent, row: number, column: number, colors: ThemeColors): { fill: RGB | null; text: PaintColor | null; bold: boolean } {
  const s = t.style;
  const base = resolve(s.color, colors);
  const isHeader = s.headerRow && row === 0;
  const isTotal = s.totalRow && row === t.rows.length - 1;
  const isEdgeColumn = (s.firstColumn && column === 0) || (s.lastColumn && column === t.columnWidths.length - 1);
  const bodyRow = row - (s.headerRow ? 1 : 0);
  const banded = (s.bandedRows && bodyRow % 2 === 0) || (s.bandedColumns && column % 2 === 0);
  switch (s.intensity) {
    case 1:
      if (isHeader) return { fill: null, text: { rgb: { _0: shaded(base, -0.25) } }, bold: true };
      if (isTotal) return { fill: null, text: null, bold: true };
      return { fill: banded ? shaded(base, 0.85) : null, text: null, bold: isEdgeColumn };
    case 2:
      if (isHeader || isTotal) return { fill: isDark(colors.dark1) ? colors.dark1 : colors.light1, text: themePaint("light1"), bold: true };
      if (isEdgeColumn) return { fill: shaded(base, -0.3), text: themePaint("light1"), bold: true };
      return { fill: banded ? shaded(base, -0.15) : base, text: themePaint("light1"), bold: false };
    default:
      if (isHeader) return { fill: base, text: themePaint("light1"), bold: true };
      if (isTotal || isEdgeColumn) return { fill: shaded(base, 0.6), text: null, bold: true };
      return { fill: banded ? shaded(base, 0.75) : shaded(base, 0.88), text: null, bold: false };
  }
}

export function drawTable(ctx: Ctx, t: TableContent, f: Rect, elementID: UUID, env: RenderEnv, options: DrawOptions) {
  const geo = new TableGeometry(t, f);
  const colors = env.theme.colors;
  const base = resolve(t.style.color, colors);
  const columns = t.columnWidths.length;
  for (let row = 0; row < t.rows.length; row++) {
    for (let column = 0; column < columns; column++) {
      const cell = t.rows[row]?.[column];
      if (!cell || cell.isMerged) continue;
      const r = geo.rect(row, column, cell.rowSpan, cell.columnSpan);
      const look = cellAppearance(t, row, column, colors);
      if (cell.fill) {
        const p = new Path2D();
        p.rect(r.x, r.y, r.w, r.h);
        fillPath(ctx, p, cell.fill, r, env);
      } else if (look.fill) {
        ctx.fillStyle = cssColor(look.fill);
        ctx.fillRect(r.x, r.y, r.w, r.h);
      }
      if (options.editingTextElement === elementID && options.editingCell?.[0] === row && options.editingCell?.[1] === column) continue;
      if (cell.text.paragraphs.every((p) => p.runs.every((x) => !x.text))) continue;
      drawText(ctx, styledCellBody(t, row, column, colors), r, env.theme);
    }
  }
  ctx.save();
  ctx.setLineDash([]);
  if (t.style.borderColor) {
    ctx.strokeStyle = cssColor(resolve(t.style.borderColor, colors));
    ctx.lineWidth = t.style.borderWidth;
    for (let row = 0; row < t.rows.length; row++) for (let column = 0; column < columns; column++) {
      const cell = t.rows[row]?.[column];
      if (!cell || cell.isMerged) continue;
      const r = geo.rect(row, column, cell.rowSpan, cell.columnSpan);
      ctx.strokeRect(r.x, r.y, r.w, r.h);
    }
  } else if (t.style.intensity === 1) {
    ctx.strokeStyle = cssColor(base);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(f.x, f.y); ctx.lineTo(maxX(f), f.y);
    ctx.moveTo(f.x, maxY(f)); ctx.lineTo(maxX(f), maxY(f));
    ctx.stroke();
    if (t.style.headerRow && geo.ys.length > 1) {
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(f.x, geo.ys[1]); ctx.lineTo(maxX(f), geo.ys[1]);
      ctx.stroke();
    }
  } else {
    ctx.strokeStyle = t.style.intensity === 2 ? cssColor(withAlpha(colors.light1, 0.35)) : "white";
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (const y of geo.ys.slice(1, -1)) { ctx.moveTo(f.x, y); ctx.lineTo(maxX(f), y); }
    for (const x of geo.xs.slice(1, -1)) { ctx.moveTo(x, f.y); ctx.lineTo(x, maxY(f)); }
    ctx.stroke();
    if (t.style.totalRow && geo.ys.length > 2) {
      ctx.strokeStyle = cssColor(base);
      ctx.lineWidth = 2;
      const y = geo.ys[geo.ys.length - 2];
      ctx.beginPath();
      ctx.moveTo(f.x, y); ctx.lineTo(maxX(f), y);
      ctx.stroke();
    }
  }
  ctx.restore();
}

/** A cell's text with the table style's color and weight applied (as drawn and exported). */
export function styledCellBody(t: TableContent, row: number, column: number, colors: ThemeColors) {
  const cell = t.rows[row][column];
  const look = cellAppearance(t, row, column, colors);
  if (!look.text && !look.bold) return cell.text;
  const body = clone(cell.text);
  if (look.text) body.defaultColor = look.text;
  if (look.bold) updateRuns(body, (s) => { if (s.bold === undefined) s.bold = true; });
  return body;
}

/** Row heights after growing rows whose text no longer fits. */
export function fittedRowHeights(t: TableContent, width: number, env: RenderEnv): number[] {
  const heights = [...t.rowHeights];
  const totalW = Math.max(t.columnWidths.reduce((a, b) => a + b, 0), 1);
  t.rows.forEach((row, r) => {
    let needed = 0;
    row.forEach((cell, c) => {
      if (cell.isMerged || cell.rowSpan !== 1) return;
      let span = 0;
      for (let i = c; i < Math.min(c + cell.columnSpan, t.columnWidths.length); i++) span += t.columnWidths[i];
      needed = Math.max(needed, requiredHeight(cell.text, (span / totalW) * width, env.theme));
    });
    heights[r] = Math.max(heights[r], needed);
  });
  return heights;
}

import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {SceneGraph} from '@open-pencil/scene-graph';
import {IORegistry, BUILTIN_IO_FORMATS} from '@open-pencil/core/io';
import {meta, schemes, modeNames, variables, colors, components, rgba, show, sources, pageIndex, coverFields, fontFaces, theme, gradients} from './tokens.mjs';
import {drawComponent} from './components.mjs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const venv = path.join(dir, '.venv', 'bin', 'python');
const python = process.env.PYTHON || (fs.existsSync(venv) ? venv : 'python3');
const faces = JSON.parse(execFileSync(python, [path.join(dir, 'font-outlines.py'), JSON.stringify(fontFaces)], {maxBuffer: 32 * 1024 * 1024}));
for (const face of Object.values(faces)) for (const glyph of Object.values(face)) glyph[1] = Uint8Array.from(Buffer.from(glyph[1], 'base64'));

const g = new SceneGraph();
const cover = g.getPages()[0];
cover.name = 'Cover';
const [tokensPage, componentsPage] = ['Tokens', 'Components'].map((name) => g.addPage(name));

const collection = g.createCollection(meta.name);
collection.modes[0].name = modeNames[0];
for (const name of modeNames.slice(1)) g.createMode(collection.id, name);
const modeIds = collection.modes.map((m) => m.modeId);
const vars = {};
for (const v of variables) {
  const value = (i) => (v.type === 'COLOR' ? rgba(v.values[i]) : v.values[i]);
  vars[v.name] = g.createVariable(v.name, v.type, collection.id, value(0));
  modeIds.slice(1).forEach((id, i) => { vars[v.name].valuesByMode[id] = value(i + 1); });
}

const documentColor = (h) => ({r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255, a: 1});
// A bound paint takes its alpha from the variable, so a view-level opacity goes on the node (alpha below).
function ink(node, field, color, {weight = 1} = {}) {
  if (!color) return;
  const token = vars[color];
  if (!token && !color.startsWith('#')) throw new Error('Unknown color token ' + color);
  const c = token ? token.valuesByMode[modeIds[0]] : documentColor(color);
  node[field] = [{type: 'SOLID', color: {...c, a: 1}, opacity: c.a, visible: true}];
  if (field === 'strokes') { node.strokeWeight = weight; node.strokeAlign = 'INSIDE'; Object.assign(node.strokes[0], {weight, align: 'INSIDE'}); }
  if (token) g.bindVariable(node.id, field + '/0/color', token.id);
}
// OpenPencil 0.16.0 binds only solid paint colors, so a CSS linear-gradient copies its stop values from the
// variables named in tokens.mjs `gradients`; the verifier checks the stops against those variables.
// Transform: top to bottom, as CSS linear-gradient(a, b) without a direction (scene-graph DEFAULT_GRADIENT_TRANSFORM).
function gradient(node, key) {
  const stops = gradients[key];
  if (!stops) throw new Error('Unknown gradient ' + key);
  const value = (name) => ({...vars[name].valuesByMode[modeIds[0]]});
  node.fills = [{type: 'GRADIENT_LINEAR', color: value(stops[0]), opacity: 1, visible: true,
    gradientStops: stops.map((name, i) => ({color: value(name), position: i / (stops.length - 1)})),
    gradientTransform: {m00: 0, m01: 1, m02: 0, m10: -1, m11: 0, m12: 1}}];
  node.name = 'Gradient / ' + key + ' / ' + node.name;
}
function box(parent, name, x, y, w, h, fill = null, type = 'FRAME', alpha = 1) {
  const n = g.createNode(type, parent.id, {name, x, y, width: Math.max(0.01, w), height: Math.max(0.01, h), fills: [], clipsContent: false});
  ink(n, 'fills', fill);
  if (alpha !== 1) n.opacity = alpha;
  return n;
}
const WEIGHTS = [400, 500, 600, 700];
const faceOf = (font, weight) => {
  const near = WEIGHTS.filter((w) => faces[font + w]).reduce((a, b) => (Math.abs(weight - b) < Math.abs(weight - a) ? b : a), 400);
  return faces[font + near] ?? faces[font + 400];
};
function measure(s, font, size, weight = 400, tracking = 0) {
  const face = faceOf(font, weight);
  return (face ? [...s].reduce((w, ch) => w + (face[ch]?.[0] ?? 0.5) * size, 0) : s.length * size * 0.56) + tracking * [...s].length;
}
const baselineOf = (size, lh) => lh / 2 + size * 0.34;
// Left, center or right aligned text; with o.w and o.wrap it wraps at word boundaries, one glyph run per line.
function text(parent, s, x, y, o = {}) {
  const {size = 13, weight = 400, font = 'Inter', color, alpha = 1, align = 'LEFT', tracking = 0, lh = Math.round(size * 1.2 + 0.5)} = o;
  const lines = [];
  if (o.w && o.wrap) {
    let line = '';
    for (const word of s.split(' ')) {
      const next = line ? line + ' ' + word : word;
      if (line && measure(next, font, size, weight, tracking) > o.w) { lines.push(line); line = word; } else line = next;
    }
    lines.push(line);
  } else lines.push(s);
  const natural = Math.ceil(measure(s, font, size, weight, tracking)) + 1;
  const w = o.w ?? natural;
  const n = box(parent, o.name ?? s, x, y, w, lh * lines.length, null, 'TEXT');
  Object.assign(n, {text: s, fontSize: size, fontFamily: font, fontWeight: weight, lineHeight: lh, textAlignHorizontal: align, textAutoResize: o.w ? 'HEIGHT' : 'WIDTH_AND_HEIGHT'});
  if (tracking) n.letterSpacing = tracking;
  if (o.strike) n.textDecoration = 'STRIKETHROUGH';
  ink(n, 'fills', color);
  if (alpha !== 1) n.opacity = alpha;
  const face = faceOf(font, weight);
  if (face) {
    const glyphs = [];
    let i = 0;
    lines.forEach((line, row) => {
      const lw = measure(line, font, size, weight, tracking);
      let gx = align === 'CENTER' ? (w - lw) / 2 : align === 'RIGHT' ? w - lw : 0;
      for (const ch of line) {
        const glyph = face[ch];
        if (glyph) glyphs.push({commandsBlob: glyph[1], x: gx, y: row * lh + baselineOf(size, lh), firstCharacter: i, fontSize: size, advance: glyph[0] * size});
        gx += (glyph?.[0] ?? 0.5) * size + tracking; i += ch.length;
      }
      i += 1;
    });
    n.derivedTextGlyphs = glyphs;
  }
  return n;
}
const link = (n, id) => { n.styleRuns = [{start: 0, length: n.text.length, style: {hyperlink: {type: 'NODE', value: id}}}]; };
const COVER_FONT = theme.font;

// Cover: plain document colors, values copied from the DESIGN.md frontmatter.
const card = box(cover, 'Cover', 0, 0, 960, 0, '#ffffff');
const INK = '#1b1f24', MUTED = '#5b6470';
text(card, meta.name, 48, 48, {font: COVER_FONT, size: 32, weight: 700, color: INK, lh: 44});
let y = 120;
for (const [label, value] of coverFields()) {
  text(card, label, 48, y, {font: COVER_FONT, color: MUTED});
  text(card, value, 240, y, {font: COVER_FONT, color: INK, weight: 600});
  y += 28;
}
y += 20;
text(card, 'Page index', 48, y, {font: COVER_FONT, size: 15, weight: 700, color: INK}); y += 28;
for (const [page, summary] of pageIndex) {
  const p = g.getPages().find((x) => x.name === page);
  link(text(card, page, 48, y, {font: COVER_FONT, color: '#0b57d0', weight: 600}), p.id);
  text(card, summary, 240, y, {font: COVER_FONT, color: MUTED}); y += 26;
}
y += 20;
text(card, 'Source files', 48, y, {font: COVER_FONT, size: 15, weight: 700, color: INK}); y += 28;
for (const file of sources) { text(card, file, 48, y, {font: COVER_FONT, color: INK, size: 12}); y += 22; }
card.height = y + 40;

const {surface: SURFACE, line: LINE, text: TEXT, sub: SUB, band: BAND} = theme;
const T = (parent, s, x, y, o) => text(parent, s, x, y, {font: COVER_FONT, ...o});
function versionLabel(page) {
  const band = box(page, 'Version label', 0, -64, 900, 36, BAND);
  ink(band, 'strokes', LINE);
  T(band, `${meta.name} · design ${meta.design_version} · product ${meta.product_version} · ${page.name}`, 14, 9, {color: TEXT, size: 13});
  band.variableModes = {[collection.id]: modeIds[0]};
}

// Tokens page: color swatches per mode, then non-color tokens grouped by prefix.
let tx = 0;
modeIds.forEach((modeId, mode) => {
  const lane = box(tokensPage, 'Colors / ' + modeNames[mode], tx, 0, 900, 80 + colors.length * 34, SURFACE);
  lane.variableModes = {[collection.id]: modeId};
  T(lane, 'Colors / ' + modeNames[mode], 20, 16, {size: 20, weight: 700, color: TEXT});
  colors.forEach((c, i) => {
    const ry = 64 + i * 34;
    const chip = box(lane, c.name, 20, ry, 48, 24, c.name, 'RECTANGLE');
    ink(chip, 'strokes', LINE);
    T(lane, c.name, 84, ry + 4, {color: TEXT, size: 12});
    T(lane, show(c, mode), 300, ry + 4, {color: SUB, size: 12});
    T(lane, c.sources[mode], 560, ry + 4, {color: SUB, size: 11});
  });
  tx += 940;
});
const groups = Map.groupBy(variables.filter((v) => v.type !== 'COLOR'), (v) => v.name.split(' / ')[0]);
let gx = tx, gy = 0;
for (const [group, entries] of groups) {
  const board = box(tokensPage, group, gx, gy, 760, 72 + entries.length * 26, SURFACE);
  board.variableModes = {[collection.id]: modeIds[0]};
  T(board, group, 20, 16, {size: 20, weight: 700, color: TEXT});
  entries.forEach((v, i) => {
    const ry = 60 + i * 26;
    T(board, v.name.split(' / ').slice(1).join(' / '), 20, ry, {color: TEXT, size: 12});
    T(board, String(v.values[0]), 300, ry, {color: SUB, size: 12});
    T(board, v.sources[0], 420, ry, {color: SUB, size: 11});
  });
  gy += board.height + 24;
  if (gy > 1100) { gx += 800; gy = 0; }
}

// Components page: one board per component or state; the main component in the first mode,
// and for every further mode an instance inside a lane switched to that mode.
let cy = 0, cx = 0, rowHeight = 0;
for (const [name, source, note] of components) {
  const board = box(componentsPage, name, cx, cy, 10, 10, SURFACE);
  board.variableModes = {[collection.id]: modeIds[0]};
  T(board, name, 20, 16, {size: 16, weight: 700, color: TEXT});
  const caption = T(board, source + ' · ' + note, 20, 42, {color: SUB, size: 11});
  const master = box(board, name, 20, 76, 10, 10, null, 'COMPONENT');
  drawComponent(name, master, {g, box, text, ink, gradient, measure, baselineOf});
  let right = master.x + master.width, bottom = master.y + master.height;
  modeIds.slice(1).forEach((modeId, i) => {
    const lane = box(board, 'Mode / ' + modeNames[i + 1], right + 20, 56, master.width + 40, master.height + 40, SURFACE);
    lane.variableModes = {[collection.id]: modeId};
    T(lane, modeNames[i + 1], 20, 2, {color: SUB, size: 11});
    const inst = g.createInstance(master.id, lane.id, {name: name + ' / ' + modeNames[i + 1], x: 20, y: 20});
    if (!inst) throw new Error('No instance for ' + name);
    inst.variableModes = {[collection.id]: modeId};
    right = lane.x + lane.width; bottom = Math.max(bottom, lane.y + lane.height);
  });
  board.width = Math.max(right + 20, caption.width + 40, 360);
  board.height = bottom + 24;
  rowHeight = Math.max(rowHeight, board.height);
  cx += board.width + 40;
  if (cx > 1800) { cx = 0; cy += rowHeight + 40; rowHeight = 0; }
}

for (const page of g.getPages().slice(1)) versionLabel(page);

const saved = await new IORegistry(BUILTIN_IO_FORMATS).writeDocument('fig', g);
const destination = path.resolve(process.argv[2] || path.join(dir, 'template.fig'));
const pending = fs.mkdtempSync(path.join(path.dirname(destination), '.template-'));
try { const next = path.join(pending, 'template.fig'); fs.writeFileSync(next, saved.data); fs.renameSync(next, destination); } finally { fs.rmdirSync(pending); }
console.log(JSON.stringify({file: path.relative(process.cwd(), destination), pages: g.getPages().map((p) => p.name), schemes, variables: g.variables.size, components: components.length, instances: components.length * (modeIds.length - 1), nodes: g.nodes.size, bytes: saved.data.length}));

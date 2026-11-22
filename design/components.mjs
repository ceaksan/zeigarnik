// Main components drawn from Sources/ZeigarnikUI/Theme/Components.swift in points (1pt = 1px), in Light; the
// generator puts a Dark instance beside each. Copy comes from the in-app DesignGallery (DesignGallery.swift).
// Widths follow the gallery column (440pt minus inspectorPadding on both sides). Text uses SF Pro Text outlines;
// ◷ and ✎ are not in SF Pro (macOS substitutes a fallback font) and are left blank. SF Symbols are
// color-bound placeholder squares named after the symbol. SpecBar's track is Theme.specTrack, which equals Theme.line since 2026-11-22.
import {num, gallery} from './tokens.mjs';

const SF = 'SF Pro Text';
const sp = (k) => num('Spacing / ' + k), ty = (k) => num('Type / ' + k), sz = (k) => num('Size / ' + k), op = (k) => num('Opacity / ' + k), rad = (k) => num('Radius / ' + k);
const COLUMN = () => sz('gallery column') - 2 * sp('inspectorPadding');

function symbol(h, parent, name, x, y, size, color) {
  const n = h.box(parent, 'SF Symbol ' + name, x, y, size, size, color, 'RECTANGLE');
  n.cornerRadius = 2;
  return n;
}
// Text with padding on a rounded fill (Tag, ProjectChip, ScheduledChip).
function pill(h, m, label, fg, bg, px, py, radius) {
  const t = h.text(m, label, px, py, {font: SF, size: ty('chip'), color: fg});
  m.width = t.width + 2 * px; m.height = t.height + 2 * py; m.cornerRadius = radius;
  if (bg) h.ink(m, 'fills', bg);
  return t;
}
const tag = (h, m, label, tone) => pill(h, m, label, {neutral: 'text', warn: 'warn', ok: 'ok'}[tone], {neutral: 'line', warn: 'warnSoft', ok: 'okSoft'}[tone],
  sp('tag horizontal'), sp('tag vertical'), rad('tagCorner'));

function noteCard(h, m, {date, text, scheduled, badge, hover = false}) {
  const w = COLUMN(), pad = sp('note card padding'), r = rad('corner');
  m.width = w; m.cornerRadius = r;
  const layers = [];
  if (scheduled) layers.push(h.box(m, 'Scheduled fill', 0, 0, w, 10, 'accentSoft', 'RECTANGLE'));
  if (hover) layers.push(h.box(m, 'Hover tint', 0, 0, w, 10, 'text', 'RECTANGLE', op('hover tint')));
  const body = h.text(m, text, pad, pad, {font: SF, size: ty('body'), color: 'text', w: w - 2 * pad, wrap: true});
  const fy = pad + body.height + sp('note card footer gap');
  const footer = h.box(m, 'Footer', pad, fy, w - 2 * pad, 10);
  const d = h.text(footer, (scheduled ? '◷ ' : '') + date, 0, 0, {font: SF, size: ty('chip'), color: 'muted'});
  let fh = d.height;
  if (badge) {
    const holder = h.box(footer, 'Tag', d.width + sp('note card footer stack'), 0, 10, 10);
    tag(h, holder, badge, 'neutral');
    fh = Math.max(fh, holder.height);
  }
  if (hover) {
    fh = sz('note card footer height');
    const s = ty('small');
    symbol(h, footer, 'trash', footer.width - s, (fh - s) / 2, s, 'muted');
    symbol(h, footer, 'pencil', footer.width - 2 * s - sp('card actions gap'), (fh - s) / 2, s, 'muted');
  }
  for (const c of h.g.getChildren(footer.id)) c.y = (fh - c.height) / 2;
  footer.height = fh;
  m.height = fy + fh + pad;
  for (const l of layers) { l.height = m.height; l.cornerRadius = r; }
  const border = h.box(m, 'Border', 0, 0, w, m.height, null, 'RECTANGLE');
  border.cornerRadius = r;
  h.ink(border, 'strokes', scheduled ? 'accent' : 'line', {weight: sz('card border')});
}

const draw = {
  ...Object.fromEntries(gallery.tags.map(([label, tone]) => [`Tag / ${tone}`, (h, m) => tag(h, m, label, tone)])),
  ...Object.fromEntries([0, 1, 2, 3, 4, 5].map((i) => [`Project chip / color ${i}`,
    (h, m) => pill(h, m, gallery.chip, 'text', `chip-${i}`, sp('chip horizontal'), sp('chip vertical'), rad('chipCorner'))])),
  'Scheduled chip': (h, m) => pill(h, m, '◷ ' + gallery.scheduled, 'onAccent', 'accent', sp('chip horizontal'), sp('chip vertical'), rad('chipCorner')),
  'Note marker'(h, m) {
    const t = h.text(m, '✎ ' + gallery.marker, sp('note marker leading'), sp('chip vertical'), {font: SF, size: ty('chip'), color: 'muted'});
    m.width = t.x + t.width + sp('note marker trailing'); m.height = t.height + 2 * sp('chip vertical');
  },
  'Live dot'(h, m) {
    const d = sz('live dot');
    h.box(m, 'Circle', 0, 0, d, d, 'live', 'ELLIPSE');
    m.width = m.height = d;
  },
  'Section header'(h, m) {
    const t = h.text(m, gallery.section.toUpperCase(), 0, sp('section header top'), {font: SF, size: ty('caption'), weight: 600, color: 'muted', tracking: ty('caption tracking')});
    m.width = t.width; m.height = t.y + t.height + sp('section header bottom');
  },
  'Key value grid'(h, m) {
    const w = COLUMN(), key = sz('keyColumnWidth'), gx = sp('key value horizontal'), gy = sp('key value vertical');
    let y = 0;
    for (const [k, v] of gallery.rows) {
      const a = h.text(m, k, 0, y, {font: SF, size: ty('keyValue'), color: 'muted', w: key, wrap: true});
      const b = h.text(m, v, key + gx, y, {font: SF, size: ty('keyValue'), color: 'text', w: w - key - gx, wrap: true});
      y += Math.max(a.height, b.height) + gy;
    }
    m.width = w; m.height = y - gy;
  },
  'Note card / scheduled with badge': (h, m) => noteCard(h, m, {date: gallery.scheduledCard[0], text: gallery.scheduledCard[1], badge: gallery.scheduledCard[2], scheduled: true}),
  'Note card / plain': (h, m) => noteCard(h, m, {date: gallery.plainCard[0], text: gallery.plainCard[1], scheduled: false}),
  'Note card / interactive hover': (h, m) => noteCard(h, m, {date: gallery.plainCard[0], text: gallery.plainCard[1], scheduled: false, hover: true}),
  Sparkline(h, m) {
    const w = COLUMN(), gap = sp('sparkline bar gap'), height = sz('sparkline height'), values = gallery.sparkline;
    const max = Math.max(...values.filter((x) => x > 0)), bw = (w - gap * (values.length - 1)) / values.length;
    values.forEach((value, i) => {
      const bh = height * Math.max(sz('sparkline min fraction'), value / max);
      const bar = h.box(m, `Bar ${i + 1} (${value})`, i * (bw + gap), height - bh, bw, bh, 'accent', 'RECTANGLE', op('sparkline bar'));
      bar.independentCorners = true; bar.topLeftRadius = bar.topRightRadius = Math.min(rad('sparkline bar top'), bh / 2);
    });
    m.width = w; m.height = height;
  },
  ...Object.fromEntries(gallery.specBars.map(([done, total]) => [`Spec bar / ${done} of ${total}`, (h, m) => {
    const w = sz('spec bar width'), ht = sz('spec bar height'), r = rad('spec bar');
    const track = h.box(m, 'Track (specTrack = line)', 0, 0, w, ht, 'line', 'RECTANGLE');
    track.cornerRadius = r;
    if (total > 0) {
      const fw = w * Math.min(1, Math.max(0, done / total));
      const fill = h.box(m, 'Fill', 0, 0, fw, ht, 'accent', 'RECTANGLE');
      fill.independentCorners = true;
      fill.topLeftRadius = fill.bottomLeftRadius = r;
      fill.topRightRadius = fill.bottomRightRadius = fw >= w ? r : 0;
    }
    m.width = w; m.height = ht;
  }])),
  'Banner / warn'(h, m) {
    const w = COLUMN(), px = sp('banner horizontal'), py = sp('banner vertical'), s = ty('body');
    m.width = w;
    h.ink(m, 'fills', 'warnSoft');
    symbol(h, m, 'exclamationmark.triangle', px, py + 1.5, s, 'warn');
    const t = h.text(m, gallery.banner, px + s + sp('banner icon gap'), py, {font: SF, size: s, color: 'warn', w: w - 2 * px - s - sp('banner icon gap'), wrap: true});
    m.height = t.height + 2 * py;
  },
  'Banner / neutral'(h, m) {
    const w = COLUMN(), px = sp('banner horizontal'), py = sp('banner vertical');
    m.width = w;
    h.ink(m, 'fills', 'side');
    const t = h.text(m, gallery.neutralBanner, px, py, {font: SF, size: ty('body'), color: 'text', w: w - 2 * px, wrap: true});
    m.height = t.height + 2 * py;
  },
};

export function drawComponent(name, master, helpers) {
  if (!draw[name]) throw new Error('No drawing for component ' + name);
  draw[name](helpers, master);
}

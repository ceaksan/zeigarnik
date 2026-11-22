import fs from 'node:fs';

const root = new URL('../', import.meta.url);
export const read = (file) => fs.readFileSync(new URL(file, root), 'utf8');
export const lineOf = (file, line) => read(file).split('\n')[line - 1] ?? '';

const front = read('DESIGN.md').split('\n---\n')[0];
export const meta = Object.fromEntries(
  [...front.matchAll(/^(\w+): (.+)$/gm)].map(([, k, v]) => [k, v.split(' #')[0].trim().replace(/^"(.*)"$/, '$1')]),
);
// Frontmatter colors with literal light and dark hex values, plus the chips arrays.
export const designColors = Object.fromEntries([...front.matchAll(/^  (\w+): \{ light: "(#[0-9a-f]{6})", dark: "(#[0-9a-f]{6})" \}/gm)].map(([, k, l, d]) => [k, [l, d]]));
const chipArray = (mode) => JSON.parse(front.match(new RegExp(`^    ${mode}: (\\[.*\\])$`, 'm'))[1]);
chipArray('light').forEach((l, i) => { designColors[`chip-${i}`] = [l, chipArray('dark')[i]]; });
export const schemes = meta.schemes.replace(/[[\]]/g, '').split(',').map((s) => s.trim());
export const modeNames = schemes.map((s) => s[0].toUpperCase() + s.slice(1));

const hexRgba = (h) => ({r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255, a: 1});
export const rgba = (c) => c;
export const hexOf = (c) => '#' + ['r', 'g', 'b'].map((k) => Math.round(c[k] * 255).toString(16).padStart(2, '0')).join('') + (c.a < 1 ? Math.round(c.a * 255).toString(16).padStart(2, '0') : '');

const UI = 'Sources/ZeigarnikUI/', TH = UI + 'Theme/Theme.swift', CO = UI + 'Theme/Components.swift', GA = UI + 'Theme/DesignGallery.swift';

// A token is read from one source line per mode (Light, Dark): the regex must match that line, and parse turns the match into the value.
function token(name, type, at, parse, note = '') {
  return {name, type, at, parse, note};
}
export function evaluate(spec) {
  return spec.at.map(([file, line, regex]) => {
    const m = lineOf(file, line).match(regex);
    if (!m) throw new Error(`${spec.name}: ${regex} not found at ${file}:${line}`);
    return {value: spec.parse(m), literal: m[0], source: `${file}:${line}`};
  });
}
const both = (file, line, regex) => [[file, line, regex], [file, line, regex]];

// Theme.color(light:dark:): light for aqua, dark for darkAqua (Theme.swift:48-57).
const dynamic = (name, line) => token(name, 'COLOR', [
  [TH, line, /color\(light: 0x([0-9a-f]{6}), dark: 0x[0-9a-f]{6}\)/],
  [TH, line, /color\(light: 0x[0-9a-f]{6}, dark: 0x([0-9a-f]{6})\)/],
], (m) => hexRgba('#' + m[1]));
const colorSpecs = [
  ...[['bg', 6], ['window', 7], ['side', 8], ['line', 9], ['text', 10], ['muted', 11], ['accent', 12], ['accentSoft', 13], ['warn', 14], ['danger', 15],
    ['warnSoft', 16], ['ok', 17], ['okSoft', 18]].map(([n, l]) => dynamic(n, l)),
  ...[20, 21, 22, 23, 24, 25].map((l, i) => dynamic(`chip-${i}`, l)),
  dynamic('live', 27), dynamic('star', 28), dynamic('today', 29),
  token('onAccent', 'COLOR', both(TH, 30, /onAccent = (Color\.white)/), () => hexRgba('#ffffff'), 'SwiftUI Color.white'),
];

const n1 = (m) => Number(m[1]);
const f = (name, file, line, regex) => token(name, 'FLOAT', both(file, line, regex), n1);
const size = /size: ([\d.]+)/, cg = /CGFloat = ([\d.]+)/, v = /\.padding\(\.vertical, (\d+)\)/, h = /\.padding\(\.horizontal, (\d+)\)/, gap = /spacing: (\d+)/;
const numberSpecs = [
  f('Opacity / hover tint', CO, 245, /opacity\(([\d.]+)\)/),
  f('Opacity / sparkline bar', CO, 310, /opacity\(([\d.]+)\)/),
  f('Type / body', TH, 33, size), f('Type / small', TH, 34, size), f('Type / caption', TH, 35, size), f('Type / title', TH, 36, size),
  f('Type / chip', TH, 37, size), f('Type / dayTotal', TH, 38, size), f('Type / keyValue', TH, 39, size),
  f('Type / caption tracking', CO, 154, /tracking\(([\d.]+)\)/),
  f('Radius / corner', TH, 44, cg), f('Radius / tagCorner', TH, 45, cg), f('Radius / chipCorner', TH, 46, cg),
  f('Radius / sparkline bar top', CO, 309, /topLeadingRadius: (\d+)/),
  f('Spacing / inspectorPadding', TH, 42, cg),
  f('Spacing / tag vertical', CO, 21, v), f('Spacing / tag horizontal', CO, 22, h),
  f('Spacing / chip gap', CO, 56, gap), f('Spacing / chip vertical', CO, 62, v), f('Spacing / chip horizontal', CO, 63, h),
  f('Spacing / note marker leading', CO, 101, /\.padding\(\.leading, (\d+)\)/), f('Spacing / note marker trailing', CO, 102, /\.padding\(\.trailing, (\d+)\)/),
  f('Spacing / section header top', CO, 156, /\.padding\(\.top, (\d+)\)/), f('Spacing / section header bottom', CO, 157, /\.padding\(\.bottom, (\d+)\)/),
  f('Spacing / key value horizontal', CO, 169, /horizontalSpacing: (\d+)/), f('Spacing / key value vertical', CO, 169, /verticalSpacing: (\d+)/),
  f('Spacing / note card padding', CO, 226, /\.padding\((\d+)\)/), f('Spacing / note card footer gap', CO, 244, cg),
  f('Spacing / note card footer stack', CO, 216, gap), f('Spacing / card actions gap', CO, 267, gap),
  f('Spacing / sparkline bar gap', CO, 305, gap), f('Spacing / banner icon gap', CO, 329, gap),
  f('Spacing / banner vertical', CO, 338, v), f('Spacing / banner horizontal', CO, 339, h),
  f('Size / keyColumnWidth', TH, 43, cg), f('Size / note card footer height', CO, 243, cg), f('Size / card border', CO, 234, /lineWidth: (\d+)/),
  f('Size / live dot', CO, 112, /width: (\d+)/), f('Size / sparkline height', CO, 315, /height: (\d+)/),
  f('Size / sparkline min fraction', CO, 308, /max\(([\d.]+), value/), f('Size / gallery column', GA, 12, /width: (\d+)/),
  f('Size / spec bar width', CO, 130, /width: (\d+)/), f('Size / spec bar height', CO, 130, /height: (\d+)/),
  f('Radius / spec bar', CO, 128, /cornerRadius: (\d+)/),
];

const resolve = (spec) => {
  const hits = evaluate(spec);
  return {...spec, values: hits.map((x) => x.value), literals: hits.map((x) => x.literal), sources: hits.map((x) => x.source)};
};
export const colors = colorSpecs.map(resolve);
export const numbers = numberSpecs.map(resolve);
export const variables = [...colors, ...numbers];
export const num = (name) => numbers.find((n) => n.name === name).values[0];
export const show = (c, mode) => `${c.literals[mode]} = ${hexOf(c.values[mode])}`;

// Sample copy from the in-app DesignGallery (DesignGallery.swift), read from its lines.
const galleryString = (line, index = 0) => [...lineOf(GA, line).matchAll(/"([^"]*)"/g)][index][1];
export const gallery = {
  tags: [[43, 'neutral'], [45, 'warn'], [46, 'ok']].map(([l, tone]) => [galleryString(l), tone]),
  chip: galleryString(99), scheduled: galleryString(103), marker: galleryString(104), section: galleryString(75),
  rows: [65, 66, 67, 68, 69, 70, 71, 72].map((l) => [galleryString(l, 0), galleryString(l, 1)]),
  scheduledCard: [galleryString(77, 0), galleryString(77, 1), galleryString(77, 2)],
  plainCard: [galleryString(78, 0), galleryString(78, 1)],
  sparkline: JSON.parse(lineOf(GA, 82).match(/values: (\[[\d, ]+\])/)[1]),
  banner: galleryString(85),
  specBars: [54, 56, 58].map((l) => lineOf(GA, l).match(/SpecBar\(done: (\d+), total: (\d+)\)/).slice(1, 3).map(Number)),
  neutralBanner: lineOf(UI + 'Window/RootView.swift', 89).match(/Banner\("([^"(]+)\(/)[1] + '(1): orbit',
};

export const fontFaces = {
  'SF Pro Text': [400, 500, 600, 700].map((wt) => [wt, 'SFNS.ttf', {opsz: 17, wght: wt}]),
};
export const theme = {font: 'SF Pro Text', surface: 'window', band: 'side', line: 'line', text: 'text', sub: 'muted'};

export const components = [
  ['Tag / neutral', `${CO}:4`, 'chip 11pt text on line, padding 1 x 6, radius 5; DesignGallery copy'],
  ['Tag / warn', `${CO}:4`, 'warn on warnSoft'],
  ['Tag / ok', `${CO}:4`, 'ok on okSoft'],
  ...[0, 1, 2, 3, 4, 5].map((i) => [`Project chip / color ${i}`, `${CO}:43`, `text on chips[${i}], padding 1 x 5, radius 4`]),
  ['Scheduled chip', `${CO}:68`, '"◷ " + text in onAccent on accent, radius 4; ◷ is not in SF Pro and is left blank'],
  ['Note marker', `${CO}:87`, '"✎ " + text, 11pt muted, no fill; ✎ is not in SF Pro and is left blank'],
  ['Live dot', `${CO}:106`, '7pt circle in live'],
  ['Section header', `${CO}:144`, 'uppercased, 11pt semibold, tracking 0.44, muted, padding top 14 bottom 6'],
  ['Key value grid', `${CO}:161`, '12.5pt, muted keys in a 110pt column, text values, spacing 8 x 5; DesignGallery rows in a 440pt column'],
  ['Note card / scheduled with badge', `${CO}:193`, 'accentSoft fill, accent 1pt border, radius 8, padding 8, "◷ " date, neutral Tag'],
  ['Note card / plain', `${CO}:193`, 'no fill, line 1pt border'],
  ['Note card / interactive hover', `${CO}:230`, 'text at 0.05 hover tint, footer 24pt with CardActions pencil and trash (SF Symbol placeholders, 11.5pt muted, gap 10)'],
  ['Sparkline', `${CO}:296`, 'bars accent at 0.75, gap 3, height 46, top radius 2, minimum fraction 0.02; DesignGallery values'],
  ['Banner / warn', `${CO}:319`, 'exclamationmark.triangle placeholder and 13pt text in warn on warnSoft, padding 8 x 14'],
  ...[[9, 11], [12, 12], [0, 0]].map(([d, t]) => [`Spec bar / ${d} of ${t}`, `${CO}:118`, t ? `track Theme.specTrack (= line, Theme.swift:31) 60 x 5, radius 3, accent fill ${d}/${t} of the width; DesignGallery value` : 'total 0: track only, no fill; DesignGallery value']),
  ['Banner / neutral', `${UI}Window/RootView.swift:89`, 'no icon, 13pt text on side; copy follows RootView.swift:89 with a sample project name'],
];
export const componentNames = components.map((c) => c[0]);

export const sources = ['DESIGN.md', TH, CO, GA + ' (sample copy)', 'design/tokens.mjs', 'design/components.mjs'];
export const pageIndex = [
  ['Cover', 'Release metadata, page index and source files'],
  ['Tokens', 'Light and Dark colors from Theme.color, project chip palette, fonts, radii, spacing and sizes'],
  ['Components', 'Theme components (Tag, chips, markers, cards, sparkline, spec bars, banners) in Light, with Dark instances'],
];
export const coverFields = () => [
  ['Company', meta.company], ['Brand', meta.brand], ['Design version', meta.design_version],
  ['Product version', meta.product_version], ['Source commit', meta.source_commit], ['Updated', meta.updated],
  ['Status', meta.status], ['Color schemes', modeNames.join(', ')], ['Template', meta.template],
  ['Template level', '1 (Cover, Tokens, Components)'],
];

export const designColorPairs = () => Object.entries(designColors).flatMap(([k, pair]) => {
  const c = colors.find((x) => x.name === k);
  if (!c) throw new Error('DESIGN.md color without token: ' + k);
  return pair.map((value, i) => [`${k} ${modeNames[i]}`, value, hexOf(c.values[i])]);
});
export const extraChecks = () => [
  ['Theme.color picks dark for darkAqua', lineOf(TH, 50).trim() === 'let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light'],
  ['Theme.specTrack is Theme.line (decided 2026-11-22)', lineOf(TH, 31).trim() === 'public static let specTrack = line'],
  ['gallery spec bars match the drawn states', JSON.stringify(gallery.specBars) === '[[9,11],[12,12],[0,0]]'],
  ['every Theme color(light:dark:) has a token', [...read(TH).matchAll(/color\(light: 0x/g)].length === colors.length - 1],
];

// No CSS-style gradients in this app; the generator and verifier share this shape with HTML projects.
export const gradients = {};

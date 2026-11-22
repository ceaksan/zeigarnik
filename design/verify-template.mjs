import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {IORegistry, BUILTIN_IO_FORMATS} from '@open-pencil/core/io';
import {populateAllFigPages} from '@open-pencil/core/io/formats/fig';
import {meta, modeNames, variables, colors, componentNames, coverFields, pageIndex, evaluate, designColorPairs, extraChecks, gradients} from './tokens.mjs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const file = path.resolve(process.argv[2] || path.join(dir, 'template.fig'));
for (const name of ['cli', 'core', 'scene-graph']) {
  const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'node_modules', '@open-pencil', name, 'package.json'), 'utf8'));
  assert.equal(pkg.version, '0.16.0', `pinned @open-pencil/${name}`);
}
const cliPkgPath = fileURLToPath(import.meta.resolve('@open-pencil/cli/package.json'));
const cliBin = path.join(path.dirname(cliPkgPath), JSON.parse(fs.readFileSync(cliPkgPath, 'utf8')).bin.openpencil);
const cli = (...args) => JSON.parse(execFileSync(process.execPath, [cliBin, ...args, file, '--json'], {encoding: 'utf8'}));
const near = (a, b) => ['r', 'g', 'b', 'a'].every((k) => Math.abs(a[k] - b[k]) <= 1 / 255 + 1e-5);

// Source side: every token is re-read from the line it cites, and DESIGN.md agrees with the source.
const fromSource = new Map(variables.map((v) => [v.name, evaluate(v)]));
for (const [label, documented, actual] of designColorPairs()) assert.equal(documented.toLowerCase(), actual.toLowerCase(), 'DESIGN.md color ' + label);
for (const [label, ok] of extraChecks()) assert(ok, label);

const bytes = fs.readFileSync(file);
const {graph: g} = await new IORegistry(BUILTIN_IO_FORMATS).readDocument({name: 'template.fig', data: new Uint8Array(bytes)});
populateAllFigPages(g);
const pages = g.getPages(), pageNames = pages.map((p) => p.name);
assert.deepEqual(pageNames, pageIndex.map((p) => p[0]), 'page order');
assert.equal(cli('info').pages, pages.length, 'CLI page count');
const [cover, tokensPage, componentsPage] = pages;
const children = (n) => g.getChildren(n.id), desc = (n) => [n, ...children(n).flatMap(desc)];
const child = (n, name) => { const c = children(n).find((x) => x.name === name); assert(c, `${n.name} / ${name}`); return c; };
const texts = (n) => desc(n).filter((x) => x.type === 'TEXT');

const card = child(cover, 'Cover'), coverTexts = texts(card);
assert(coverTexts.some((t) => t.text === meta.name), 'cover title');
for (const [label, value] of coverFields()) {
  const k = coverTexts.find((t) => t.text === label);
  assert(k, 'cover field ' + label);
  assert(coverTexts.some((t) => t.y === k.y && t.x === 240 && t.text === value), `cover ${label} = ${value}`);
}
for (const p of pages) assert(coverTexts.some((t) => t.text === p.name && t.styleRuns?.[0]?.style.hyperlink?.value === p.id), 'page index link ' + p.name);

assert.equal(g.variableCollections.size, 1, 'one collection');
const [collection] = g.variableCollections.values();
assert.equal(collection.name, meta.name, 'collection name');
assert.deepEqual(collection.modes.map((m) => m.name), modeNames, 'modes');
const cliVars = cli('variables').collections;
assert.deepEqual(cliVars.map((c) => [c.name, c.modes, c.variables.length]), [[meta.name, modeNames, variables.length]], 'CLI variables');
const byName = new Map([...g.variables.values()].map((v) => [v.name, v]));
assert.equal(byName.size, variables.length, 'variable count');
for (const spec of variables) {
  const v = byName.get(spec.name), hits = fromSource.get(spec.name);
  assert(v, 'variable ' + spec.name);
  assert.equal(v.type, spec.type, spec.name);
  assert.equal(hits.length, modeNames.length, spec.name + ' has one source per mode');
  collection.modes.forEach((m, i) => {
    const actual = v.valuesByMode[m.modeId], expected = hits[i].value;
    if (spec.type === 'COLOR') assert(near(actual, expected), `${spec.name} ${m.name}: ${JSON.stringify(actual)} vs ${hits[i].literal} at ${hits[i].source}`);
    else if (spec.type === 'FLOAT') assert(Math.abs(actual - expected) <= 1e-5 * Math.max(1, Math.abs(expected)), `${spec.name} ${m.name}: ${actual} vs ${hits[i].literal} at ${hits[i].source}`);
    else assert.equal(actual, expected, `${spec.name} ${m.name}`);
  });
}
const tokensTexts = texts(tokensPage).map((t) => t.text);
collection.modes.forEach((m, i) => {
  const lane = child(tokensPage, 'Colors / ' + m.name);
  assert.equal(lane.variableModes[collection.id], m.modeId, 'lane mode ' + m.name);
  for (const c of colors) {
    assert.equal(child(lane, c.name).boundVariables['fills/0/color'], byName.get(c.name).id, 'swatch ' + c.name);
    assert(texts(lane).some((t) => t.text === c.name), 'swatch name ' + c.name);
    assert(texts(lane).some((t) => t.text.startsWith(fromSource.get(c.name)[i].literal)), 'swatch value ' + c.name);
  }
});
for (const v of variables.filter((x) => x.type !== 'COLOR')) assert(tokensTexts.includes(v.sources[0]), 'token source shown ' + v.name);

for (const p of pages.slice(1)) {
  const band = child(p, 'Version label'), [t] = texts(band);
  assert.equal(t.text, `${meta.name} · design ${meta.design_version} · product ${meta.product_version} · ${p.name}`, 'label on ' + p.name);
  for (const n of [band, t]) assert(g.variables.has(n.boundVariables['fills/0/color']), 'label bound on ' + p.name);
}

const masters = desc(componentsPage).filter((n) => n.type === 'COMPONENT');
assert.deepEqual(masters.map((m) => m.name).sort(), [...componentNames].sort(), 'components');
const ids = new Set([...g.variables.keys()]);
const opacities = [1, ...variables.filter((v) => v.name.startsWith('Opacity / ')).map((v) => v.values[0])];
let bindings = 0, glyphTexts = 0, gradientPaints = 0;
for (const master of masters) {
  const paints = desc(master).flatMap((n) => ['fills', 'strokes'].flatMap((f) => (n[f] || []).map((paint, i) => [n, f, i, paint])));
  const solid = paints.filter(([, , , p]) => p.type === 'SOLID');
  assert(solid.length, 'no paint in ' + master.name);
  for (const [n, f, i, paint] of solid) {
    const id = n.boundVariables[`${f}/${i}/color`];
    assert(id && ids.has(id), `unbound ${f} on ${master.name} / ${n.name}`);
    const value = g.variables.get(id).valuesByMode[collection.modes[0].modeId];
    assert(near({...paint.color, a: value.a}, value), `${master.name} / ${n.name} paint differs from ${g.variables.get(id).name}`);
    assert(Math.abs(paint.opacity - value.a) < 1e-4, `${master.name} / ${n.name} paint opacity ${paint.opacity}`);
    bindings++;
  }
  // Gradient paints cannot be bound in 0.16.0: the node names its gradient and every stop equals that gradient's variables.
  for (const [n, f, , paint] of paints.filter(([, , , p]) => p.type.startsWith('GRADIENT_'))) {
    const key = n.name.match(/^Gradient \/ ([\w-]+) \//)?.[1], stops = gradients[key];
    assert(stops, `${master.name} / ${n.name} ${f} gradient names no tokens.mjs gradient`);
    assert.equal(paint.gradientStops.length, stops.length, `${master.name} / ${n.name} stop count`);
    paint.gradientStops.forEach((s, i) => assert(near(s.color, byName.get(stops[i]).valuesByMode[collection.modes[0].modeId]), `${master.name} / ${n.name} stop ${i} is not ${stops[i]}`));
    gradientPaints++;
  }
  assert(paints.every(([, , , p]) => p.type === 'SOLID' || p.type.startsWith('GRADIENT_')), `${master.name} has a paint that is neither solid nor gradient`);
  for (const n of desc(master)) assert(opacities.some((o) => Math.abs(n.opacity - o) < 1e-4), `${master.name} / ${n.name} opacity ${n.opacity} is not a token opacity`);
  for (const t of texts(master)) assert(t.derivedTextGlyphs?.length, `${master.name} / ${t.name} has no glyph outlines`);
  glyphTexts += texts(master).length;
}

// Every further mode: one instance per main component, switched to that mode, whose bound paints resolve to that mode's values.
const instances = desc(componentsPage).filter((n) => n.type === 'INSTANCE');
assert.equal(instances.length, masters.length * (modeNames.length - 1), 'one instance per component and extra mode');
let recolored = 0;
for (const inst of instances) {
  const main = masters.find((m) => m.id === inst.componentId);
  assert(main, 'instance without main ' + inst.name);
  // OpenPencil 0.16.0 does not save variableModes on an INSTANCE, so the mode comes from its lane (inherited).
  const modeId = g.getNodeVariableModeId(inst.id, collection.id), mode = collection.modes.find((m) => m.modeId === modeId);
  assert(mode && mode.modeId !== collection.modes[0].modeId, 'instance mode ' + inst.name);
  assert.equal(inst.name, `${main.name} / ${mode.name}`, 'instance name');
  for (const n of desc(inst)) {
    for (const f of ['fills', 'strokes']) (n[f] || []).forEach((p, i) => {
      const id = n.boundVariables?.[`${f}/${i}/color`];
      if (!id) return;
      const resolved = g.resolveColorVariableForNode(n.id, id), expected = g.variables.get(id).valuesByMode[modeId];
      assert(resolved && near(resolved, expected), `${inst.name} / ${n.name} does not resolve to ${mode.name}`);
      if (!near(expected, g.variables.get(id).valuesByMode[collection.modes[0].modeId])) recolored++;
    });
  }
}
if (modeNames.length > 1) assert(recolored > 0, 'mode switch recolors no instance paint');

console.log(JSON.stringify({file: path.basename(file), pages: pageNames, collection: collection.name, modes: modeNames, variables: byName.size, colors: colors.length, components: masters.length, componentColorBindings: bindings, componentGradients: gradientPaints, componentTextsWithGlyphs: glyphTexts, modeInstances: instances.length, recoloredInstancePaints: recolored, bytes: bytes.length}));

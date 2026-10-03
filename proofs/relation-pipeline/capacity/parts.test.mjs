import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { hash } from '../inventory.mjs';
import { recordCapacityOwner, validateCapacityOwners, unionCapacityParts, resolveCapacityUnion, assembleCapacityParts } from './parts.mjs';

// Synthetic transport only. Real source/artifact/semantic audits remain required.
function fixture() {
  const source = { digest: 'source', sources: {} };
  const make = (part, phase, count) => Array.from({ length: count }, (_, i) => ({ path: `${part}/${phase}/${i}.json`,
    receipt: { boundary: { workspace: `${part}-${phase}`, root: `/checkout/${part}`, role: 'normal' } } }));
  const normal = make('L-C0', 'instrumented', 12), mutated = make('L-C1', 'instrumented', 45), restored = make('L-C1', 'post-restore', 15);
  const owner0 = recordCapacityOwner(normal, 'instrumented'), owner1 = recordCapacityOwner(mutated, 'instrumented');
  const owner2 = recordCapacityOwner(restored, 'post-restore', owner1.id);
  const common = { version: 'structure', revision: 'sha', source, toolchain: {}, claim: {}, overlays: {}, corpus: [], seed: 148256,
    search: [], shrinkMeaning: 'minimum', mutationTimingMeaning: 'wall time', targets: ['js', 'wasm', 'native'], kind: 'capacity-part', complete: true };
  const reports = [{ ...structuredClone(common), part: 'L-C0', normal: {}, boundaries: {}, backingCore: {}, backingModel: {}, model: {}, custody: {}, parentStartup: {},
    executions: normal, executionOwners: { [owner0.id]: owner0 }, timings: {} },
  { ...structuredClone(common), part: 'L-C1', mutations: [], postRestore: { owner: owner2.id, predecessor: owner1.id, sourceDigest: source.digest, records: [] },
    executions: [...mutated, ...restored], executionOwners: { [owner1.id]: owner1, [owner2.id]: owner2 }, timings: {} }];
  const parts = reports.map(report => ({ path: `.artifacts/relation-pipeline/capacity/parts/${report.part}.json`, report }));
  const files = new Map(parts.map(({ path, report }) => [path, JSON.stringify(report, null, 2) + '\n']));
  return { parts, files, read: path => { assert(files.has(path)); return files.get(path); } };
}
test('capacity union retains immutable originals and three distinct owner inventories', () => {
  const { parts, files, read } = fixture(), originals = structuredClone(parts);
  const union = unionCapacityParts(parts, read);
  assert.equal(union.kind, 'capacity-union'); assert.equal(union.part, undefined);
  assert.equal(union.executions.length, 72); assert.equal(Object.keys(union.executionOwners).length, 3);
  assert.deepEqual(parts, originals);
  assert.deepEqual(resolveCapacityUnion(union, read), parts);
  for (const ref of union.parts) assert.equal(ref.digest, hash(files.get(ref.path)));
  assert.deepEqual(union.executionOwners['L-C1-post-restore'].paths, parts[1].report.executionOwners['L-C1-post-restore'].paths);
});
for (const [name, corrupt] of [
  ['missing part', f => f.parts.pop()],
  ['duplicate part', f => { f.parts[1] = f.parts[0]; }],
  ['stale source', f => { f.parts[1].report.source.digest = 'stale'; }],
  ['incomplete fragment', f => { f.parts[1].report.complete = false; }],
  ['cross-part claim', f => { f.parts[1].report.normal = {}; }],
  ['missing close', f => { f.parts[1].report.executionOwners['L-C1-post-restore'].closed = false; }],
  ['missing restored receipt', f => { f.parts[1].report.executions.pop(); }],
  ['wrong predecessor', f => { f.parts[1].report.postRestore.predecessor = 'other-owner'; }],
  ['wrong restored checkout', f => { f.parts[1].report.executionOwners['L-C1-post-restore'].root = '/elsewhere'; }],
  ['duplicated receipt', f => { f.parts[1].report.executions.push(f.parts[1].report.executions[0]); }],
  ['changed original bytes', f => { f.files.set(f.parts[0].path, '{}'); }],
]) test(`capacity union rejects ${name}`, () => {
  const f = fixture(); corrupt(f); assert.throws(() => unionCapacityParts(f.parts, f.read));
});
test('derived-field tampering cannot mask immutable original or target substitution', () => {
  const f = fixture(), union = unionCapacityParts(f.parts, f.read);
  union.normal = { js: ['foreign target observation'] };
  assert.throws(() => resolveCapacityUnion(union, f.read), /differs from immutable original/);
  const good = unionCapacityParts(f.parts, f.read);
  f.files.set(f.parts[1].path, `${f.files.get(f.parts[1].path)} `);
  assert.throws(() => resolveCapacityUnion(good, f.read), /original report digest differs/);
});
test('union writes a new report once without rewriting either original', () => {
  const f = fixture(), root = mkdtempSync(join(tmpdir(), 'actql-capacity-union-'));
  try {
    mkdirSync(join(root, '.artifacts/relation-pipeline/capacity/parts'), { recursive: true });
    for (const [path, bytes] of f.files) writeFileSync(join(root, path), bytes);
    const union = assembleCapacityParts(root);
    assert.equal(JSON.parse(readFileSync(join(root, '.artifacts/relation-pipeline/capacity/all.json'))).kind, 'capacity-union');
    for (const [path, bytes] of f.files) assert.equal(readFileSync(join(root, path), 'utf8'), bytes);
    assert.throws(() => assembleCapacityParts(root), /Refusing to overwrite/);
    assert.deepEqual(resolveCapacityUnion(union, f.read), f.parts);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('fragment cannot hide an execution behind an unrepresented owner', () => {
  const { parts } = fixture(), report = parts[1].report;
  report.executions[0].receipt.boundary.workspace = 'foreign-owner';
  assert.throws(() => validateCapacityOwners(report));
});

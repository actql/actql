import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { hash } from '../inventory.mjs';
import { recordCapacityOwner, validateCapacityOwners, unionCapacityParts, resolveCapacityUnion, assembleCapacityParts } from './parts.mjs';
import { prepareCapacityRegressionInputs, substituteCapacityRegressionParts } from './regression-inputs.mjs';
import { capacityPartIds, capacityObligationsByPart, capacityMutationNames, partRole } from '../proof-parts.mjs';
import { capacityRegressionDescriptor, retainCapacityRegressionText } from './regression-fixtures.mjs';
import { runCapacityRegressionWorkers } from './regression-workers.mjs';

// Synthetic transport only. Real source/artifact/semantic audits remain required.
function fixture() {
  const source = { digest: 'source', sources: {} };
  const make = (part, phase, count) => Array.from({ length: count }, (_, i) => ({ path: `${part}/${phase}/${i}.json`,
    receipt: { boundary: { workspace: `${part}-${phase}`, root: `/checkout/${part}`, role: 'normal' } } }));
  const common = { version: 'structure', revision: 'sha', source, toolchain: {}, claim: {}, overlays: {}, corpus: [], seed: 148256,
    search: [], shrinkMeaning: 'minimum', mutationTimingMeaning: 'wall time', targets: ['js', 'wasm', 'native'], kind: 'capacity-part', complete: true };
  const reports = capacityPartIds.map(part => {
    const role = partRole(part), obligations = capacityObligationsByPart[part];
    const report = { ...structuredClone(common), part, executions: [], executionOwners: {}, timings: {} };
    if (role === 'capacity-support') return Object.assign(report,
      { backingCore: {}, backingModel: {}, model: {}, custody: {}, parentStartup: {} });
    const normal = role === 'capacity-normal';
    const primary = make(part, 'instrumented', normal
      ? obligations.normal.targets.length * (1 + obligations.boundaries.values.length)
      : obligations.mutations.length * (3 + 2 * report.targets.length));
    const owner = recordCapacityOwner(primary, 'instrumented');
    report.executions = primary; report.executionOwners[owner.id] = owner;
    if (normal) return Object.assign(report, { normal: {}, boundaries: {} });
    const restored = make(part, 'post-restore', obligations.ownerLocalRestoration.caseCount * report.targets.length);
    const successor = recordCapacityOwner(restored, 'post-restore', owner.id);
    report.executions.push(...restored); report.executionOwners[successor.id] = successor;
    report.mutations = obligations.mutations.map(name => ({ name, minimal: { id: name }, history: [{ accepted: 0 }] }));
    report.postRestore = { owner: successor.id, predecessor: owner.id, sourceDigest: source.digest,
      records: report.mutations.map(m => ({ name: m.name, minimal: m.minimal, observations: {} })) };
    return report;
  });
  const parts = reports.map(report => ({ path: `.artifacts/relation-pipeline/capacity/parts/${report.part}.json`, report }));
  const files = new Map(parts.map(({ path, report }) => [path, JSON.stringify(report, null, 2) + '\n']));
  return { parts, files, reports, mutants: reports.filter(r => partRole(r.part) === 'capacity-mutants'),
    support: reports.find(r => partRole(r.part) === 'capacity-support'),
    read: path => { assert(files.has(path)); return files.get(path); } };
}
test('regression preparation reads each original once and freezes a detached source snapshot', () => {
  const f = fixture(), original = unionCapacityParts(f.parts, f.read);
  const current = { digest: 'source', sources: { 'src/example.mbt': 'original' } }, reads = [];
  const prepared = prepareCapacityRegressionInputs(original, current, path => { reads.push(path); return f.read(path); });
  current.sources['src/example.mbt'] = 'caller mutation';
  assert.equal(prepared.current.sources['src/example.mbt'], 'original');
  assert.throws(() => { prepared.current.sources['src/example.mbt'] = 'case mutation'; }, TypeError);
  assert.throws(() => { prepared.current = current; }, TypeError);
  for (let i = 0; i < 10; i++) assert.deepEqual(prepared.parts(), f.parts);
  assert.deepEqual(reads, original.parts.map(ref => ref.path));
});
for (const order of [[...capacityPartIds].filter(id => partRole(id) !== 'capacity-support'),
  [...capacityPartIds].filter(id => partRole(id) !== 'capacity-support').reverse()]) {
  test(`regression cases cannot leak dirty nested state in ${order.join('/')} order`, () => {
    const f = fixture(), original = unionCapacityParts(f.parts, f.read), before = structuredClone(original);
    const prepared = prepareCapacityRegressionInputs(original, original.source, f.read);
    for (const id of order) {
      const parts = prepared.parts(), selected = parts.find(({ report }) => report.part === id);
      selected.report.executions[0].receipt.boundary.workspace = 'foreign-owner';
      selected.report.source.sources['extra.mbt'] = 'case mutation';
      // Dirty cases still run the real union validator and must reject.
      assert.throws(() => unionCapacityParts(parts, f.read));
      const clean = prepared.parts();
      assert.deepEqual(clean, f.parts);
      assert.deepEqual(unionCapacityParts(clean, f.read), original);
    }
    assert.deepEqual(original, before);
    assert.deepEqual(prepared.current, before.source);
  });
}
test('prepared originals never bypass changed-input validation or become a cached pass', () => {
  const f = fixture(), original = unionCapacityParts(f.parts, f.read);
  const prepared = prepareCapacityRegressionInputs(original, original.source, f.read);
  assert.deepEqual(unionCapacityParts(prepared.parts(), f.read), original);
  const path = original.parts[0].path, bytes = f.files.get(path);
  f.files.set(path, '{}');
  assert.throws(() => unionCapacityParts(prepared.parts(), f.read), /original report differs/);
  f.files.set(path, bytes);
  assert.deepEqual(unionCapacityParts(prepared.parts(), f.read), original);
  const altered = prepared.parts();
  altered[0].report.complete = false;
  const overrides = new Map(altered.map(({ path, report }) => [path, JSON.stringify(report)]));
  assert.throws(() => unionCapacityParts(altered, path => overrides.get(path)), /Incomplete capacity fragment/);
  assert.deepEqual(unionCapacityParts(prepared.parts(), f.read), original);
});
test('regression preparation does not hide missing or malformed original inputs', () => {
  const f = fixture(), original = unionCapacityParts(f.parts, f.read);
  assert.throws(() => prepareCapacityRegressionInputs(original, original.source, () => { throw new Error('missing original'); }), /missing original/);
  assert.throws(() => prepareCapacityRegressionInputs(original, original.source, () => '{'), SyntaxError);
});
test('capacity union retains all original fields and both distinct restored owner pairs without inventing support owners', () => {
  const { parts, files, read } = fixture(), originals = structuredClone(parts);
  const union = unionCapacityParts(parts, read);
  assert.equal(union.kind, 'capacity-union'); assert.equal(union.part, undefined);
  assert.equal(union.executions.length, 72); assert.equal(Object.keys(union.executionOwners).length, 5);
  assert.deepEqual(parts, originals);
  assert.deepEqual(resolveCapacityUnion(union, read), parts);
  for (const ref of union.parts) assert.equal(ref.digest, hash(files.get(ref.path)));
  const mutants = parts.filter(({ report }) => partRole(report.part) === 'capacity-mutants');
  assert.deepEqual(union.mutations.map(m => m.name), capacityMutationNames);
  assert.deepEqual(union.postRestore.parts, mutants.map(({ report: r }) => ({ part: r.part, ...r.postRestore })));
  assert.deepEqual(union.postRestore.records, mutants.flatMap(({ report }) => report.postRestore.records));
  for (const { report } of mutants) assert.deepEqual(union.executionOwners[report.postRestore.owner].paths,
    report.executionOwners[report.postRestore.owner].paths);
  const support = parts.find(({ report }) => partRole(report.part) === 'capacity-support').report;
  assert.deepEqual(support.executions, []); assert.deepEqual(support.executionOwners, {});
});
for (const [name, corrupt] of [
  ['missing part', f => f.parts.pop()],
  ['duplicate part', f => { f.parts[1] = f.parts[0]; }],
  ['stale source', f => { f.parts[1].report.source.digest = 'stale'; }],
  ['incomplete fragment', f => { f.parts[1].report.complete = false; }],
  ['cross-part claim', f => { f.parts[1].report.normal = {}; }],
  ['missing close', f => { const r = f.mutants[0]; r.executionOwners[r.postRestore.owner].closed = false; }],
  ['missing restored receipt', f => { f.mutants[0].executions.pop(); }],
  ['wrong predecessor', f => { f.mutants[0].postRestore.predecessor = 'other-owner'; }],
  ['wrong restored checkout', f => { const r = f.mutants[0]; r.executionOwners[r.postRestore.owner].root = '/elsewhere'; }],
  ['duplicated receipt', f => { f.parts[0].report.executions.push(f.parts[0].report.executions[0]); }],
  ['changed original bytes', f => { f.files.set(f.parts[0].path, '{}'); }],
  ['support claims a pipeline owner', f => { f.support.executionOwners = structuredClone(f.reports[0].executionOwners); }],
  ['support claims pipeline executions', f => { f.support.executions = structuredClone(f.reports[0].executions); }],
  ['missing support field', f => { delete f.support.backingModel; }],
  ['mutant from another subset', f => { f.mutants[0].mutations[0] = f.mutants[1].mutations[0]; }],
  ['missing subset minimum', f => { f.mutants[1].postRestore.records.pop(); }],
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
  const { mutants } = fixture(), report = mutants[0];
  report.executions[0].receipt.boundary.workspace = 'foreign-owner';
  assert.throws(() => validateCapacityOwners(report));
});

test('negative union substitutions retain each exact mutant subset and its real restoration pair', () => {
  const f = fixture(), original = unionCapacityParts(f.parts, f.read), before = structuredClone(f.parts);
  const changed = structuredClone(original);
  changed.mutations.at(-1).history[0].accepted = -2;
  const prepared = prepareCapacityRegressionInputs(original, original.source, f.read);
  const substituted = substituteCapacityRegressionParts(prepared.parts(), changed);
  const overrides = new Map(substituted.map(({ path, report }) => [path, JSON.stringify(report)]));
  const rebuilt = unionCapacityParts(substituted, path => overrides.get(path));
  assert.deepEqual(rebuilt.mutations, changed.mutations);
  assert.deepEqual(rebuilt.postRestore, original.postRestore);
  for (const { report } of substituted.filter(p => partRole(p.report.part) === 'capacity-mutants')) {
    assert.deepEqual(report.mutations.map(m => m.name), capacityObligationsByPart[report.part].mutations);
    assert.deepEqual(report.postRestore.records.map(r => r.name), capacityObligationsByPart[report.part].mutations);
  }
  assert.deepEqual(prepared.parts(), before);
  assert.deepEqual(f.parts, before);
});

for (const [name, change] of [
  ['foreign restored owner', r => { r.postRestore.parts[0].owner = 'foreign'; }],
  ['omitted mutant', r => { r.mutations.pop(); }],
]) test(`substituted union still rejects ${name} before semantic audit`, () => {
  const f = fixture(), report = unionCapacityParts(f.parts, f.read); change(report);
  const parts = substituteCapacityRegressionParts(structuredClone(f.parts), report);
  const overrides = new Map(parts.map(({ path, report }) => [path, JSON.stringify(report)]));
  assert.throws(() => unionCapacityParts(parts, path => overrides.get(path)), { code: 'ERR_ASSERTION' });
});

test('actual worker reconstructs independent full union and reaches the original compiler validator', async t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-capacity-worker-validator-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, 'toolchain.json'), JSON.stringify({ version: 'pinned' }));
  const current = { digest: 'source', sources: {} }, cases = [];
  for (const slot of ['compiler', 'source', 'owner']) {
    const f = fixture(), parts = [];
    for (const { path, report } of f.parts) {
      report.version = 'actql-relation-pipeline-structure/0.1';
      report.toolchain = { version: 'unreviewed' };
      if (slot === 'owner' && Object.keys(report.executionOwners).length)
        report.executionOwners[Object.keys(report.executionOwners)[0]].closed = false;
      const retained = await retainCapacityRegressionText(join(root, `${slot}-${report.part}.json`),
        JSON.stringify(report, null, 2) + '\n');
      parts.push({ path, archive: capacityRegressionDescriptor(retained) });
    }
    cases.push({ slot, parts, current: slot === 'source' ? { digest: 'changed', sources: {} } : current, root });
  }
  const records = await runCapacityRegressionWorkers(cases);
  assert(records.every(record => record.state === 'closed' && record.exitCode === 0 && !record.error));
  assert(records.every(record => record.result.status === 1));
  assert.match(records[0].result.stderr, /Unpinned compiler declaration/);
  assert.match(records[1].result.stderr, /Stale capacity source/);
  assert.match(records[2].result.stderr, /Unclosed capacity execution owner/);
});

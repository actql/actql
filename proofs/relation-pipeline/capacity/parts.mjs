// Capacity fragments retain their original receipt owners. The union is a
// deterministic view over immutable, byte-addressed producer reports.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { capacityObligationsByPart } from '../proof-parts.mjs';
import { hash } from '../inventory.mjs';
export { validateCapacityPart } from './audit.mjs';
export const capacityPartIds = Object.freeze(Object.keys(capacityObligationsByPart));
const prefix = '.artifacts/relation-pipeline/capacity/parts/';
const common = ['version', 'revision', 'source', 'toolchain', 'claim', 'overlays', 'corpus', 'seed', 'search', 'shrinkMeaning', 'mutationTimingMeaning'];
const fields = {
  'L-C0': ['normal', 'boundaries', 'backingCore', 'backingModel', 'model', 'custody', 'parentStartup'],
  'L-C1': ['mutations', 'postRestore'],
};
export function recordCapacityOwner(executions, phase, predecessor = null) {
  assert(executions.length, 'Empty capacity execution owner');
  const { workspace: id, root, role } = executions[0].receipt.boundary;
  for (const execution of executions) assert.deepEqual(
    { id: execution.receipt.boundary.workspace, root: execution.receipt.boundary.root, role: execution.receipt.boundary.role },
    { id, root, role }, 'Capacity execution owner changed');
  return { id, root, role, phase, predecessor, closed: true, paths: executions.map(e => e.path) };
}
export function validateCapacityOwners(report) {
  assert.equal(report.kind, 'capacity-part', 'Capacity producer must be a fragment');
  assert(capacityPartIds.includes(report.part), 'Unknown capacity fragment');
  assert.equal(report.complete, true, 'Incomplete capacity fragment');
  assert.deepEqual(report.targets, ['js', 'wasm', 'native']);
  for (const field of fields[report.part]) assert(Object.hasOwn(report, field), `Missing capacity obligation ${field}`);
  for (const field of fields[capacityPartIds.find(id => id !== report.part)]) assert(!Object.hasOwn(report, field), 'Fragment claims another capacity part');
  const owners = Object.values(report.executionOwners);
  assert.equal(owners.length, report.part === 'L-C0' ? 1 : 2, 'Missing capacity execution owner');
  const seen = new Set();
  for (const owner of owners) {
    assert.equal(report.executionOwners[owner.id], owner);
    assert.equal(owner.closed, true, 'Unclosed capacity execution owner');
    assert.equal(owner.role, 'normal');
    const executions = report.executions.filter(e => e.receipt.boundary.workspace === owner.id);
    assert(executions.length, 'Unrepresented capacity execution owner');
    assert.deepEqual(owner.paths, executions.map(e => e.path), 'Capacity owner receipt inventory differs');
    assert.deepEqual(owner, recordCapacityOwner(executions, owner.phase, owner.predecessor));
    for (const path of owner.paths) { assert(!seen.has(path), 'Capacity receipt has multiple owners'); seen.add(path); }
  }
  assert.equal(seen.size, report.executions.length, 'Capacity receipt has no owner');
  const primary = owners.find(owner => owner.phase === 'instrumented');
  assert(primary && primary.predecessor === null, 'Missing instrumented capacity owner');
  if (report.part === 'L-C1') {
    const restored = owners.find(owner => owner.phase === 'post-restore');
    assert(restored, 'Missing post-restore capacity owner');
    assert.notEqual(restored.id, primary.id, 'Reused post-restore owner');
    assert.equal(restored.root, primary.root, 'Post-restore replay changed checkout');
    assert.equal(restored.predecessor, primary.id, 'Wrong post-restore predecessor');
    assert.equal(report.postRestore.predecessor, primary.id);
    assert.equal(report.postRestore.owner, restored.id);
    assert.equal(report.postRestore.sourceDigest, report.source.digest);
    assert.deepEqual(report.executions.map(e => e.path), [...primary.paths, ...restored.paths], 'Capacity owner handoff reordered');
    assert.equal(restored.paths.length, capacityObligationsByPart['L-C1'].ownerLocalRestoration.caseCount * report.targets.length, 'Missing post-restore minimum execution');
  }
  return owners;
}
export function unionCapacityParts(parts, read) {
  assert.deepEqual(parts.map(entry => entry.report.part), capacityPartIds, 'Capacity union requires exactly L-C0 and L-C1');
  const [normal, mutation] = parts.map(({ report }) => report);
  parts.forEach(({ report }) => validateCapacityOwners(report));
  for (const key of common) assert.deepEqual(normal[key], mutation[key], `Capacity part ${key} differs`);
  const references = parts.map(({ path, report }) => {
    assert.equal(path, `${prefix}${report.part}.json`, 'Capacity original report path differs');
    const bytes = read(path);
    assert.deepEqual(JSON.parse(bytes), report, 'Capacity original report differs');
    return { part: report.part, path, digest: hash(bytes) };
  });
  const executionOwners = {};
  for (const { report } of parts) for (const [id, owner] of Object.entries(report.executionOwners)) {
    assert(!Object.hasOwn(executionOwners, id), 'Capacity parts reused an execution owner');
    executionOwners[id] = { ...owner, part: report.part };
  }
  const executions = parts.flatMap(({ report }) => report.executions);
  assert.equal(new Set(executions.map(e => e.path)).size, executions.length, 'Capacity parts reused a receipt');
  return { ...Object.fromEntries(common.map(key => [key, normal[key]])),
    kind: 'capacity-union', complete: true, targets: normal.targets, parts: references,
    ...Object.fromEntries(fields['L-C0'].map(key => [key, normal[key]])),
    ...Object.fromEntries(fields['L-C1'].map(key => [key, mutation[key]])),
    executions, executionOwners, timings: Object.fromEntries(parts.map(({ report }) => [report.part, report.timings])) };
}
export function resolveCapacityUnion(report, read) {
  assert.equal(report.kind, 'capacity-union');
  assert.deepEqual(report.parts.map(ref => ref.part), capacityPartIds, 'Incomplete capacity union');
  const parts = report.parts.map(ref => {
    assert.equal(ref.path, `${prefix}${ref.part}.json`, 'Capacity original report path differs');
    const bytes = read(ref.path);
    assert.equal(hash(bytes), ref.digest, 'Capacity original report digest differs');
    return { path: ref.path, report: JSON.parse(bytes) };
  });
  assert.deepEqual(report, unionCapacityParts(parts, read), 'Capacity union differs from immutable original reports');
  return parts;
}
export function assembleCapacityParts(root) {
  const read = path => readFileSync(join(root, path));
  const parts = capacityPartIds.map(part => {
    const path = `${prefix}${part}.json`;
    return { path, report: JSON.parse(read(path)) };
  });
  const report = unionCapacityParts(parts, read);
  const path = join(root, '.artifacts/relation-pipeline/capacity/all.json');
  mkdirSync(join(root, '.artifacts/relation-pipeline/capacity'), { recursive: true });
  assert(!existsSync(path), 'Refusing to overwrite original capacity report');
  writeFileSync(path, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  return report;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv[2], 'union', 'Expected capacity parts union');
  assembleCapacityParts(fileURLToPath(new URL('../../../', import.meta.url)));
}

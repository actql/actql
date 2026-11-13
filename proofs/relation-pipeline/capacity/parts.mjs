// Capacity fragments retain their original receipt owners. The union is a
// deterministic view over immutable, byte-addressed producer reports.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { capacityObligationsByPart, capacityPartIds, capacityMutationNames, partRole } from '../proof-parts.mjs';
import { hash } from '../inventory.mjs';
export { validateCapacityPart } from './audit.mjs';
export { capacityPartIds } from '../proof-parts.mjs';
const prefix = '.artifacts/relation-pipeline/capacity/parts/';
const common = ['version', 'revision', 'source', 'toolchain', 'claim', 'overlays', 'corpus', 'seed', 'search', 'shrinkMeaning', 'mutationTimingMeaning'];
const fields = {
  'capacity-normal': ['normal', 'boundaries'],
  'capacity-support': ['backingCore', 'backingModel', 'model', 'custody', 'parentStartup'],
  'capacity-mutants': ['mutations', 'postRestore'],
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
  const role = partRole(report.part), obligations = capacityObligationsByPart[report.part];
  for (const field of fields[role]) assert(Object.hasOwn(report, field), `Missing capacity obligation ${field}`);
  for (const field of Object.entries(fields).filter(([other]) => other !== role).flatMap(([, names]) => names))
    assert(!Object.hasOwn(report, field), 'Fragment claims another capacity part');
  assert(Array.isArray(report.executions));
  const owners = Object.values(report.executionOwners);
  if (role === 'capacity-support') {
    // These existing schemas retain their real Core/custody/Native receipts.
    // They never used the pipeline executor; a generic owner would be invented.
    assert.equal(report.executions.length, 0, 'Support fragment claims pipeline executions');
    assert.equal(owners.length, 0, 'Support fragment claims a generic execution owner');
    return owners;
  }
  assert.equal(owners.length, role === 'capacity-normal' ? 1 : 2, 'Missing capacity execution owner');
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
  if (role === 'capacity-normal') assert.equal(primary.paths.length,
    obligations.normal.targets.length * (1 + obligations.boundaries.values.length), 'Missing normal/boundary execution');
  if (role === 'capacity-mutants') {
    assert.deepEqual(report.mutations.map(m => m.name), obligations.mutations, 'Capacity fragment mutation inventory differs');
    assert.deepEqual(report.postRestore.records.map(r => r.name), obligations.mutations, 'Missing post-restore minimum');
    const restored = owners.find(owner => owner.phase === 'post-restore');
    assert(restored, 'Missing post-restore capacity owner');
    assert.notEqual(restored.id, primary.id, 'Reused post-restore owner');
    assert.equal(restored.root, primary.root, 'Post-restore replay changed checkout');
    assert.equal(restored.predecessor, primary.id, 'Wrong post-restore predecessor');
    assert.equal(report.postRestore.predecessor, primary.id);
    assert.equal(report.postRestore.owner, restored.id);
    assert.equal(report.postRestore.sourceDigest, report.source.digest);
    assert.deepEqual(report.executions.map(e => e.path), [...primary.paths, ...restored.paths], 'Capacity owner handoff reordered');
    assert.equal(restored.paths.length, obligations.ownerLocalRestoration.caseCount * report.targets.length, 'Missing post-restore minimum execution');
  }
  return owners;
}
export function unionCapacityParts(parts, read) {
  assert.deepEqual(parts.map(entry => entry.report.part), capacityPartIds, 'Capacity union requires every canonical capacity part');
  const reports = parts.map(({ report }) => report), [first] = reports;
  parts.forEach(({ report }) => validateCapacityOwners(report));
  for (const report of reports.slice(1)) for (const key of common) assert.deepEqual(first[key], report[key], `Capacity part ${key} differs`);
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
  const single = reports.filter(r => partRole(r.part) !== 'capacity-mutants')
    .flatMap(r => fields[partRole(r.part)].map(key => [key, r[key]]));
  const mutantReports = reports.filter(r => partRole(r.part) === 'capacity-mutants');
  const mutations = mutantReports.flatMap(r => r.mutations);
  assert.deepEqual(mutations.map(m => m.name), capacityMutationNames, 'Capacity union mutation inventory differs');
  return { ...Object.fromEntries(common.map(key => [key, first[key]])),
    kind: 'capacity-union', complete: true, targets: first.targets, parts: references,
    ...Object.fromEntries(single), mutations,
    // Preserve each actual successor pair; no combined owner is fabricated.
    postRestore: { parts: mutantReports.map(r => ({ part: r.part, ...r.postRestore })),
      records: mutantReports.flatMap(r => r.postRestore.records) },
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

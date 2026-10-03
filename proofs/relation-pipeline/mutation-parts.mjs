// Structural admission and truthful union of immutable per-owner reports.
// Semantic/minimality auditing remains in audit.mjs; no receipt is rewritten.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mutationNamesByPart, planDigest, partFamily } from './proof-parts.mjs';
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const targets = ['js', 'wasm', 'native'];
const partIds = Object.keys(mutationNamesByPart);
export const mutationPartSchema = 'actql-relation-pipeline-mutation-part/0.1';
export function mutationPart(id) {
  assert.equal(partFamily(id), 'mutations');
  return { version: mutationPartSchema, id, planDigest, variants: [...mutationNamesByPart[id]] };
}
export function mutationReportPath(id, mode) {
  assert(partIds.includes(id), 'Unknown mutation part');
  assert(['fixed', 'explore'].includes(mode), 'Unknown mutation mode');
  return `.artifacts/relation-pipeline/${mode === 'fixed' ? 'fixed-mutations' : 'mutations'}-${id}.json`;
}
function exactTargets(value, message) {
  assert(value && typeof value === 'object' && !Array.isArray(value), message);
  assert.deepEqual(Object.keys(value).sort(), [...targets].sort(), message);
}
function workspacePair(pair) {
  assert(pair && typeof pair === 'object');
  assert.deepEqual(Object.keys(pair).sort(), ['mutable', 'pristine']);
  for (const owner of Object.values(pair)) {
    assert.deepEqual(Object.keys(owner).sort(), ['id', 'root']);
    assert(typeof owner.id === 'string' && owner.id && typeof owner.root === 'string' && owner.root);
  }
  assert.notEqual(pair.mutable.id, pair.pristine.id, 'Mutation owners share workspace identity');
  assert.notEqual(pair.mutable.root, pair.pristine.root, 'Mutation owners share workspace root');
}
function owner(execution, workspace, role, source) {
  assert(execution?.receipt?.boundary, 'Missing mutation execution boundary');
  const run = execution.receipt;
  assert.equal(source.digest, digest(source.sources), 'Wrong mutation execution source snapshot');
  assert.equal(run.boundary.workspace, workspace.id, 'Wrong mutation owner');
  assert.equal(run.boundary.root, workspace.root, 'Wrong mutation owner root');
  assert.equal(run.boundary.role, role, 'Wrong mutation owner role');
  assert.equal(run.sourceDigest, source.digest, 'Wrong mutation observation source');
  assert.equal(run.boundary.sourceDigest, source.digest, 'Wrong mutation boundary source');
  assert(targets.includes(run.target), 'Unexpected mutation observation target');
  assert(Array.isArray(run.cases) && run.cases.length > 0, 'Missing mutation observations');
}
function minimumExecutions(executions, observations, minimum, pair, role, source, correspondence = role === 'pristine') {
  assert.equal(executions?.length, 3, 'Missing or extra minimum executions');
  assert.deepEqual(executions.map(e => e.receipt.target), targets, 'Missing or duplicate minimum target');
  exactTargets(observations, 'Missing or extra minimum observations');
  for (const execution of executions) {
    owner(execution, pair[role], role, source);
    assert.equal(execution.receipt.correspondence, correspondence, 'Wrong minimum correspondence');
    assert.equal(execution.receipt.cases.length, 1, 'Missing or extra minimum observation');
    const entry = execution.receipt.cases[0];
    assert.deepEqual(entry.testCase, minimum, 'Wrong minimum replay input');
    assert.deepEqual(entry.observation, observations[execution.receipt.target], 'Wrong minimum replay observation');
  }
}
export function inspectMutationPart(report, { partId = report.part?.id, mode = report.mode, source, decision } = {}) {
  assert.deepEqual(Object.keys(report).sort(), ['version', 'part', 'closure', 'restorationOwner', 'source', 'workspaces',
    'revision', 'toolchain', 'mode', 'decision', 'seed', 'explorationTarget', 'searchDomain', 'meaning', 'results'].sort(),
    'Unknown mutation part fields');
  assert.deepEqual(report.part, mutationPart(partId), 'Wrong mutation part plan');
  assert.equal(report.source.digest, digest(report.source.sources), 'Wrong mutation source snapshot');
  assert.equal(report.version, 'actql-relation-pipeline-mutations/0.1');
  assert(['fixed', 'explore'].includes(mode), 'Unknown mutation mode');
  assert.equal(report.mode, mode, 'Wrong mutation report mode');
  if (source) assert.deepEqual(report.source, source, 'Wrong mutation part source');
  if (decision) assert.deepEqual(report.decision, decision, 'Wrong mutation exploration decision');
  assert.equal(report.revision, report.decision.revision, 'Wrong mutation revision');
  assert(mode !== 'explore' || report.decision.required, 'Unexpected fresh exploration report');
  assert.equal(report.seed, mode === 'explore' ? 105106 : null);
  assert.equal(report.explorationTarget, mode === 'explore' ? 'js' : null);
  assert.deepEqual(report.closure, { mutable: true, pristine: true, restoration: true, sourceRestored: true }, 'Unclosed mutation owners');
  workspacePair(report.workspaces);
  assert.deepEqual(Object.keys(report.restorationOwner ?? {}).sort(), ['id', 'root']);
  assert(typeof report.restorationOwner.id === 'string' && report.restorationOwner.id);
  assert.equal(report.restorationOwner.root, report.workspaces.mutable.root, 'Restoration changed mutable root');
  for (const previous of Object.values(report.workspaces)) {
    assert.notEqual(report.restorationOwner.id, previous.id, 'Restoration reused an old owner');
  }
  assert.deepEqual(report.results.map(r => r.name), mutationNamesByPart[partId], 'Missing, duplicate, extra or wrong-owner mutation variant');
  const refs = [], paths = new Set(), observations = new Set();
  for (const result of report.results) {
    assert.equal(result.owner, partId, 'Wrong mutation result owner');
    assert(result.killed, 'Mutation was not detected');
    assert.equal(result.localMinimal, mode === 'explore');
    assert(Array.isArray(result.executions), 'Missing mutation executions');
    if (mode === 'fixed') assert.equal(result.executions.length, 3, 'Missing or extra fixed mutation executions');
    else {
      assert(Array.isArray(result.history) && result.history.length > 0, 'Missing shrink history');
      assert.equal(result.executions.length, 4 + result.history.filter(h => h.attempted > 0).length,
        'Missing or extra fresh mutation executions');
      assert(result.executions.slice(0, -3).every(e => e.receipt.target === 'js'), 'Fresh search/shrink used wrong target');
    }
    result.executions.forEach(e => owner(e, report.workspaces.mutable, 'mutable', result.source));
    minimumExecutions(result.executions.slice(-3), result.replay, result.minimal, report.workspaces, 'mutable', result.source);
    minimumExecutions(result.healthyExecutions, result.healthy, result.minimal, report.workspaces, 'pristine', report.source);
    assert.deepEqual(Object.keys(result.postRestore ?? {}).sort(), ['executions', 'observations']);
    minimumExecutions(result.postRestore.executions, result.postRestore.observations, result.minimal,
      { mutable: report.restorationOwner }, 'mutable', report.source, true);
    for (const execution of [...result.executions, ...result.healthyExecutions, ...result.postRestore.executions]) {
      assert(!paths.has(execution.path), 'Mutation receipt reused across obligations'); paths.add(execution.path);
      for (const entry of execution.receipt.cases) {
        assert(typeof entry.id === 'string' && entry.id, 'Missing mutation observation identity');
        assert(!observations.has(entry.id), 'Mutation observation reused across obligations'); observations.add(entry.id);
      }
      refs.push(execution);
    }
  }
  return refs;
}
export function joinMutationParts(parts, { mode = parts[0]?.report.mode, source, decision } = {}) {
  assert.equal(parts.length, 2, 'Missing or extra mutation parts');
  assert.deepEqual(parts.map(p => p.report.part?.id).sort(), [...partIds].sort(), 'Missing or duplicate mutation part');
  const ordered = partIds.map(id => parts.find(p => p.report.part.id === id));
  const original = ordered[0].report;
  const paths = new Set(), observations = new Set(), ownerIds = new Set(), roots = new Set();
  for (const { path, report } of ordered) {
    assert.equal(path, mutationReportPath(report.part.id, mode), 'Wrong immutable mutation report slot');
    for (const key of ['version', 'source', 'revision', 'toolchain', 'mode', 'decision', 'seed', 'explorationTarget', 'searchDomain', 'meaning']) {
      assert.deepEqual(report[key], original[key], `Mutation part ${key} differs`);
    }
    const refs = inspectMutationPart(report, { mode, source, decision });
    for (const workspace of Object.values(report.workspaces)) {
      assert(!roots.has(workspace.root), 'Mutation parts share a source/build root'); roots.add(workspace.root);
    }
    for (const workspace of [...Object.values(report.workspaces), report.restorationOwner]) {
      assert(!ownerIds.has(workspace.id), 'Mutation parts share an owner'); ownerIds.add(workspace.id);
    }
    for (const ref of refs) {
      assert(!paths.has(ref.path), 'Mutation receipt shared across parts'); paths.add(ref.path);
      for (const entry of ref.receipt.cases) {
        assert(!observations.has(entry.id), 'Mutation observation shared across parts'); observations.add(entry.id);
      }
    }
  }
  const { part: _part, workspaces: _workspaces, restorationOwner: _restorationOwner, closure: _closure, results: _results, ...common } = original;
  return { ...common,
    partUnion: { planDigest, parts: ordered.map(({ path, report }) => ({ id: report.part.id, path, digest: digest(report) })),
      owners: Object.fromEntries(ordered.flatMap(({ report }) => report.results.map(result => [result.name, report.part.id]))) },
    workspaceOwners: Object.fromEntries(ordered.map(({ report }) => [report.part.id, report.workspaces])),
    restorationOwners: Object.fromEntries(ordered.map(({ report }) => [report.part.id, report.restorationOwner])),
    results: ordered.flatMap(({ report }) => report.results),
  };
}
export const unionMutationParts = joinMutationParts;
export function resolveMutationUnion(report, read) {
  assert(report.partUnion, 'Missing immutable mutation union');
  assert.equal(report.partUnion.planDigest, planDigest, 'Wrong mutation union plan');
  const parts = report.partUnion.parts.map(entry => {
    assert(partIds.includes(entry.id), 'Unknown mutation union owner');
    assert.equal(entry.path, mutationReportPath(entry.id, report.mode), 'Wrong mutation union report path');
    const original = read(entry.path);
    assert.equal(original.part.id, entry.id, 'Wrong mutation union report owner');
    assert.equal(digest(original), entry.digest, 'Immutable mutation report changed');
    return { path: entry.path, report: original };
  });
  const joined = joinMutationParts(parts, { mode: report.mode, source: report.source, decision: report.decision });
  assert.deepEqual(report, joined, 'Derived mutation union differs from immutable originals');
  return joined;
}

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { partIds, mutationNamesByPart, capacityObligationsByPart, plan, planDigest, partFamily } from './proof-parts.mjs';
import { mutationPart, mutationReportPath, inspectMutationPart, joinMutationParts, resolveMutationUnion } from './mutation-parts.mjs';
import { variants } from './mutation-registry.mjs';
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const targets = ['js', 'wasm', 'native'];
const snapshot = value => { const sources = { 'source.mbt': hash(value) }; return { sources, digest: hash(sources) }; };
function sample(id, mode = 'fixed') {
  const source = snapshot('healthy'), workspaces = {
    mutable: { id: `${id}-mutable`, root: `/owner/${id}/mutable` },
    pristine: { id: `${id}-pristine`, root: `/owner/${id}/pristine` },
  }, restorationOwner = { id: `${id}-restored`, root: workspaces.mutable.root };
  return {
    version: 'actql-relation-pipeline-mutations/0.1', part: mutationPart(id),
    closure: { mutable: true, pristine: true, restoration: true, sourceRestored: true },
    workspaces, restorationOwner, source, revision: 'a'.repeat(40), toolchain: { moonc: 'pinned compiler' },
    mode, decision: { required: true, revision: 'a'.repeat(40) }, seed: mode === 'fixed' ? null : 105106,
    explorationTarget: mode === 'fixed' ? null : 'js', searchDomain: 'reviewed cases', meaning: 'anchored minima',
    results: mutationNamesByPart[id].map(name => {
      const minimal = { id: name, rows: [{}], steps: [{}] }, changed = snapshot(name);
      const execution = (phase, target, workspace, source, correspondence = false) => {
        const label = `${id}-${mode}-${name}-${phase}-${target}`;
        const observation = { id: label, rows: [name] };
        const receipt = { target, sourceDigest: source.digest, correspondence,
          boundary: { workspace: workspace.id, root: workspace.root,
            role: workspace === workspaces.pristine ? 'pristine' : 'mutable', sourceDigest: source.digest },
          cases: [{ id: label, testCase: minimal, observation }] };
        return { path: `.artifacts/relation-pipeline/${label}.json`, receipt, digest: hash(receipt) };
      };
      const mutated = targets.map(t => execution('mutated', t, workspaces.mutable, changed));
      const healthy = targets.map(t => execution('healthy', t, workspaces.pristine, source, true));
      const restored = targets.map(t => execution('post-restore', t, restorationOwner, source, true));
      const observations = executions => Object.fromEntries(executions.map(e => [e.receipt.target, e.receipt.cases[0].observation]));
      return { name, owner: id, source: changed, minimal, original: minimal, killed: true,
        localMinimal: mode === 'explore', ...(mode === 'explore' ? { history: [{ attempted: 1, accepted: -1 }] } : {}),
        executions: [...(mode === 'explore' ? ['search', 'shrink'].map(p => execution(p, 'js', workspaces.mutable, changed)) : []), ...mutated],
        replay: observations(mutated), healthy: observations(healthy), healthyExecutions: healthy,
        postRestore: { observations: observations(restored), executions: restored } };
    }),
  };
}
function parts(mode = 'fixed') {
  return Object.keys(mutationNamesByPart).map(id => ({ path: mutationReportPath(id, mode), report: sample(id, mode) }));
}

test('the immutable canonical plan binds all four static parts and exact eight registry mutations', () => {
  assert.deepEqual(partIds, ['L-C0', 'L-C1', 'L-M0', 'L-M1']);
  assert.deepEqual(Object.values(mutationNamesByPart).flat(), variants.map(v => v.name));
  assert(Object.values(mutationNamesByPart).every(names => names.length === 4));
  assert.equal(planDigest, hash(plan));
  assert.equal(capacityObligationsByPart['L-C1'].mutations.length, 5);
  assert.equal(capacityObligationsByPart['L-C0'].finalNormal.caseCount, 86);
  assert.equal(partFamily('L-M0'), 'mutations');
  assert.equal(partFamily('L-C1'), 'capacity');
  assert.throws(() => partFamily('L-M2'), /Unknown proof part/);
  assert.throws(() => { plan.parts['L-M0'].variants.push('extra'); }, TypeError);
});
for (const mode of ['fixed', 'explore']) {
  test(`${mode} part admission includes fresh recovery and union preserves all receipt bytes and owners`, () => {
    const inputs = parts(mode), bytes = inputs.map(p => JSON.stringify(p.report));
    inputs.forEach(p => assert.equal(inspectMutationPart(p.report).length, 4 * (mode === 'fixed' ? 9 : 11)));
    const joined = joinMutationParts(inputs.reverse());
    assert.deepEqual(joined.results.map(r => r.name), variants.map(v => v.name));
    for (const result of joined.results) {
      const original = inputs.find(p => p.report.part.id === result.owner).report.results.find(r => r.name === result.name);
      assert.equal(result, original);
      assert.equal(joined.partUnion.owners[result.name], result.owner);
      assert.equal(joined.workspaceOwners[result.owner].mutable.id, result.executions[0].receipt.boundary.workspace);
      assert.equal(joined.restorationOwners[result.owner].id, result.postRestore.executions[0].receipt.boundary.workspace);
    }
    assert.deepEqual(resolveMutationUnion(joined, path => inputs.find(p => p.path === path).report), joined);
    assert.deepEqual(inputs.reverse().map(p => JSON.stringify(p.report)), bytes);
    assert.equal(Object.hasOwn(joined, 'workspaces'), false, 'Union cannot pretend all observations used one pair');
  });
}
const corruptions = [
  ['missing variant', r => r.results.pop(), /mutation variant/],
  ['duplicate variant', r => { r.results[1] = r.results[0]; }, /mutation variant/],
  ['extra variant', r => r.results.push(r.results[0]), /mutation variant/],
  ['wrong assigned variant', r => { r.results[0].name = mutationNamesByPart['L-M1'][0]; }, /mutation variant/],
  ['wrong result owner', r => { r.results[0].owner = 'L-M1'; }, /result owner/],
  ['wrong plan', r => { r.part.planDigest = 'f'.repeat(64); }, /part plan/],
  ['unknown part field', r => { r.unchecked = true; }, /Unknown mutation part fields/],
  ['unknown mode', r => { r.mode = 'arbitrary'; }, /Unknown mutation mode/],
  ['unclosed original owner', r => { r.closure.mutable = false; }, /Unclosed/],
  ['unclosed recovery owner', r => { r.closure.restoration = false; }, /Unclosed/],
  ['source not restored', r => { r.closure.sourceRestored = false; }, /Unclosed/],
  ['old recovery owner', r => { r.restorationOwner.id = r.workspaces.mutable.id; }, /reused an old owner/],
  ['different recovery root', r => { r.restorationOwner.root += '-other'; }, /changed mutable root/],
  ['missing recovery receipt', r => r.results[0].postRestore.executions.pop(), /minimum executions/],
  ['extra recovery receipt', r => r.results[0].postRestore.executions.push(r.results[0].postRestore.executions[0]), /minimum executions/],
  ['missing recovery observation', r => { delete r.results[0].postRestore.observations.wasm; }, /minimum observations/],
  ['extra recovery observation', r => { r.results[0].postRestore.observations.extra = {}; }, /minimum observations/],
  ['wrong recovery receipt owner', r => { r.results[0].postRestore.executions[0].receipt.boundary.workspace = r.workspaces.pristine.id; }, /Wrong mutation owner/],
  ['stale mutated recovery source', r => { r.results[0].postRestore.executions[0].receipt.sourceDigest = r.results[0].source.digest; }, /observation source/],
  ['wrong recovery target', r => { r.results[0].postRestore.executions[1].receipt.target = 'js'; }, /minimum target/],
  ['extra healthy observation', r => { r.results[0].healthyExecutions[0].receipt.cases.push(r.results[0].healthyExecutions[0].receipt.cases[0]); }, /minimum observation/],
  ['borrowed recovery input', r => { r.results[0].postRestore.executions[0].receipt.cases[0].testCase = { id: 'other' }; }, /replay input/],
  ['unchecked recovery', r => { r.results[0].postRestore.executions[0].receipt.correspondence = false; }, /correspondence/],
  ['duplicate receipt', r => { r.results[0].postRestore.executions[0].path = r.results[0].executions[0].path; }, /receipt reused/],
  ['duplicate observation', r => { r.results[0].postRestore.executions[0].receipt.cases[0].id = r.results[0].executions[0].receipt.cases[0].id; }, /observation reused/],
];
for (const [label, corrupt, expected] of corruptions) {
  test(`mutation admission rejects ${label}`, () => {
    const report = sample('L-M0'); corrupt(report);
    assert.throws(() => inspectMutationPart(report), expected);
  });
}
test('fresh evidence cannot omit search or shrinking or use another mode/target', () => {
  for (const corrupt of [r => r.results[0].executions.shift(), r => r.results[0].executions.splice(1, 1),
    r => { r.results[0].executions[0].receipt.target = 'wasm'; }, r => { r.decision.required = false; }]) {
    const report = sample('L-M0', 'explore'); corrupt(report);
    assert.throws(() => inspectMutationPart(report));
  }
  assert.throws(() => inspectMutationPart(sample('L-M0'), { mode: 'explore' }), /Wrong mutation report mode/);
});
test('union rejects incomplete, duplicate, cross-mode and shared owner inputs', () => {
  assert.throws(() => joinMutationParts(parts().slice(0, 1)), /Missing or extra/);
  const [one] = parts(); assert.throws(() => joinMutationParts([one, one]), /Missing or duplicate/);
  const mixed = parts(); mixed[1] = parts('explore')[1];
  assert.throws(() => joinMutationParts(mixed), /report slot|mode differs/);
  const owners = parts(); owners[1].report.workspaces.mutable.id = owners[0].report.workspaces.mutable.id;
  assert.throws(() => joinMutationParts(owners), /Wrong mutation owner|share an owner/);
  const wrongSource = parts(); wrongSource[1].report.source = snapshot('different');
  assert.throws(() => joinMutationParts(wrongSource), /source differs/);
});
test('derived full reports fail closed on rewritten, missing or reassigned observations and immutable originals', () => {
  const originals = parts();
  const read = path => originals.find(p => p.path === path).report;
  for (const corrupt of [r => r.results.pop(), r => { r.results[0].owner = 'L-M1'; },
    r => { r.partUnion.owners[r.results[0].name] = 'L-M1'; },
    r => { r.results[0].postRestore.executions[0].receipt.boundary.workspace = 'borrowed'; },
    r => { r.results[0].healthy.js.id = 'rewritten'; }]) {
    const report = structuredClone(joinMutationParts(originals)); corrupt(report);
    assert.throws(() => resolveMutationUnion(report, read), /Derived mutation union/);
  }
  const joined = joinMutationParts(originals);
  originals[0].report.results[0].killed = false;
  assert.throws(() => resolveMutationUnion(joined, read), /Immutable mutation report changed/);
});

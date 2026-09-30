import test from 'node:test';
import assert from 'node:assert/strict';
import { graph, premises, validate } from './evidence.mjs';

function fixture() {
  const nodes = graph([{ operation: 'intersect', variant: 'all', profile: 'nullable', premises, residual: ['kernel semantics and physical custody'] }], 'native');
  const current = { digest: 'current-source', builtArtifacts: { 'native.exe': 'current-binary' } };
  const result = { exit: 0, passed: true, count: 1, target: 'native', sourceDigest: current.digest,
    artifacts: { 'native.exe': 'current-binary' } };
  const report = { target: 'native', source: current, runs: {
    lean: { ...result, command: ['node', 'proofs/bounded-session/check.mjs'], artifacts: {} },
    'session-native': { ...result, command: ['moon', 'test', 'src/bounded_execution', '--target', 'native', '--deny-warn'] },
    'adapter-native': { ...result, command: ['moon', 'test', 'src/connectors/local', '--target', 'native', '--deny-warn'] },
    'connection-native': { ...result, command: ['moon', 'test', 'src/query_integration/local_managed_set_wbtest.mbt', '--target', 'native', '--deny-warn'] },
  } };
  return { nodes, report, current };
}

test('conditional derivation accepts matched evidence without upgrading refinement', () => {
  const { nodes, report, current } = fixture();
  const claims = validate(nodes, report, current, 'native');
  assert.equal(claims.length, 1);
  assert.equal(claims[0].kind, 'derived');
  assert.deepEqual(claims[0].premises, premises);
});

for (const [name, change, expected] of [
  ['wrong operation', ({ nodes }) => { nodes[3].scope.operation = 'except'; }, /Scope mismatch/],
  ['wrong duplicate variant', ({ nodes }) => { nodes[3].scope.variant = 'distinct'; }, /Scope mismatch/],
  ['nonnullable evidence for nullable scope', ({ nodes }) => { nodes[3].scope.profile = 'nonnull'; }, /Scope mismatch/],
  ['JS evidence for native', ({ report }) => { report.runs['adapter-native'].target = 'js'; }, /target mismatch/i],
  ['stale source', ({ report }) => { report.source = { digest: 'old' }; }, /Stale source/],
  ['stale package', ({ current }) => { current.builtArtifacts['native.exe'] = 'rebuilt'; }, /Stale built artifact/],
  ['missing premise', ({ nodes }) => { nodes[4].premises.pop(); }, /Missing premise/],
  ['missing connection', ({ nodes }) => { nodes[4].dependencies.pop(); }, /Missing dependency/],
  ['missing claim', ({ nodes }) => { nodes[4].dependencies.push('absent'); }, /Missing premise evidence/],
  ['cyclic evidence', ({ nodes }) => { nodes[0].dependencies.push('session'); }, /Cyclic/],
  ['empty execution', ({ report }) => { report.runs['adapter-native'].count = 0; }, /Unrelated execution/],
  ['unrelated passing suite', ({ report }) => { report.runs['adapter-native'].command[2] = 'src/relation_set'; }, /Unrelated execution/],
  ['proof-name-only evidence', ({ report }) => { report.runs.lean.command[1] = 'search-theorem-names.mjs'; }, /Wrong proof artifact/],
  ['unexecuted proof', ({ report }) => { delete report.runs.lean; }, /Missing or stale executed/],
  ['unsupported guarantee', ({ nodes }) => { nodes[4].guarantees.push('arbitrary DAG safety'); }, /Unsupported guarantee/],
  ['refinement upgrade', ({ nodes }) => { nodes[1].kind = 'verified-refinement'; }, /Unsupported evidence/],
]) {
  test(`rejects ${name}`, () => {
    const state = fixture();
    change(state);
    assert.throws(() => validate(state.nodes, state.report, state.current, 'native'), expected);
  });
}

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { checkBindings, checkNestObligations, executedConnectionCoverage, graph, nestLocalSuites, premises, validate } from './evidence.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const binding = JSON.parse(readFileSync(new URL('bindings.json', import.meta.url)))[0];
const nestBinding = JSON.parse(readFileSync(new URL('bindings.json', import.meta.url))).find(b => b.operation === 'nest');

test('connection evidence admits only the executed set fixture scopes', () => {
  checkBindings(root, [binding, { ...binding, operation: 'except', variant: 'distinct' }]);
});

test('copying the set binding cannot witness another adapter-using provider', () => {
  assert.throws(() => checkBindings(root, [{ ...binding, operation: 'nest',
    provider: 'src/connectors/local/nest_provider.mbt', entrypoint: 'nest_provider', kernel: 'start_bounded_nest',
  }]), /Unsupported connection scope/);
});

function nestFixture() {
  const { report, current } = fixture();
  const result = { exit: 0, passed: true, count: 4, target: 'native', sourceDigest: current.digest,
    artifacts: { 'native.exe': 'current-binary' } };
  report.runs['nest-connection-native'] = { ...result, coverage: executedConnectionCoverage('nest-connection'),
    command: ['moon', 'test', 'src/query_integration/local_managed_nest_wbtest.mbt', '--target', 'native', '--deny-warn'] };
  for (const suite of nestLocalSuites) report.runs[`${suite.id}-native`] = { ...result, count: suite.minimumTests,
    command: ['moon', 'test', suite.fixture, '--target', 'native', '--deny-warn', ...(suite.filter ? ['--filter', suite.filter] : [])] };
  return { nodes: graph([nestBinding], 'native'), report, current };
}

test('Nest admits its own registered witness and retains all local obligations without changing common proofs', () => {
  checkBindings(root, [nestBinding]);
  assert.equal(checkNestObligations(root).testRetirements.length, 0);
  const { nodes, report, current } = nestFixture();
  const [claim] = validate(nodes, report, current, 'native');
  assert.deepEqual(claim.premises, premises);
  assert.deepEqual(claim.residual, nestBinding.residual);
  assert.deepEqual(claim.dependencies, ['session', 'adapter', 'nest/correlated-parent-major:connection']);
});

test('existing set execution cannot be relabeled as the Nest witness', () => {
  const { nodes, report, current } = nestFixture();
  report.runs['nest-connection-native'] = report.runs['connection-native'];
  assert.throws(() => validate(nodes, report, current, 'native'), /Unrelated execution/);
});

test('Nest connection cannot select the set run even after forging its coverage label', () => {
  const { nodes, report, current } = nestFixture();
  nodes[3].run = 'connection-native';
  report.runs['connection-native'].coverage = executedConnectionCoverage('nest-connection');
  assert.throws(() => validate(nodes, report, current, 'native'), /Unrelated connection execution/);
});

test('operation-specific passing tests cannot replace common correspondence', () => {
  for (const index of [1, 2]) {
    const { nodes, report, current } = nestFixture();
    nodes[index].run = 'nest-kernel-native';
    assert.throws(() => validate(nodes, report, current, 'native'), /Invalid common correspondence/);
  }
});

test('Nest symmetric profile widening fails with unchanged execution and source/artifact receipts', () => {
  const { report, current } = nestFixture();
  const before = JSON.stringify({ report, current });
  const widened = { ...nestBinding, profile: 'UNCHECKED arbitrary parent and child fields' };
  assert.throws(() => checkBindings(root, [widened]), /Unverified connection profile/);
  assert.throws(() => validate(graph([widened], 'native'), report, current, 'native'), /independently executed connection coverage/);
  assert.equal(JSON.stringify({ report, current }), before);
});

test('Nest cannot substitute another provider while relabeling both claim scopes', () => {
  const { report, current } = nestFixture();
  const wrong = { ...nestBinding, provider: 'src/connectors/local/set_provider.mbt' };
  assert.throws(() => checkBindings(root, [wrong]), /Unsupported connection scope/);
  assert.throws(() => validate(graph([wrong], 'native'), report, current, 'native'), /independently executed connection coverage/);
});

test('Nest two-input and capacity obligations cannot disappear from a copied binding', () => {
  for (const index of [1, 2, 4]) {
    const { report, current } = nestFixture();
    const incomplete = { ...nestBinding, residual: nestBinding.residual.filter((_, i) => i !== index) };
    assert.throws(() => checkBindings(root, [incomplete]), /Missing Nest-specific residual/);
    assert.throws(() => validate(graph([incomplete], 'native'), report, current, 'native'), /Missing Nest-specific residual/);
  }
});

test('Nest rejects partial connection execution and missing operation-specific boundaries', () => {
  const partial = nestFixture();
  partial.report.runs['nest-connection-native'].count = 3;
  assert.throws(() => validate(partial.nodes, partial.report, partial.current, 'native'), /Unrelated execution/);
  for (const suite of nestLocalSuites) {
    const state = nestFixture();
    delete state.report.runs[`${suite.id}-native`];
    assert.throws(() => validate(state.nodes, state.report, state.current, 'native'), /Missing executed Nest-specific obligation/);
  }
});

test('Nest rejects an invented executed profile even when a binding matches it', () => {
  const { report, current } = nestFixture();
  const widened = { ...nestBinding, profile: 'arbitrary unchecked rows' };
  report.runs['nest-connection-native'].coverage.scopes[0].profile = widened.profile;
  assert.throws(() => validate(graph([widened], 'native'), report, current, 'native'), /independently executed connection coverage/);
});

test('connection profile cannot be replaced by an unexecuted one', () => {
  assert.throws(() => checkBindings(root, [{ ...binding, profile: 'nonnull-only' }]), /Unverified connection profile/);
});

function fixture() {
  const nodes = graph([{ ...binding, premises, residual: ['kernel semantics and physical custody'] }], 'native');
  const current = { digest: 'current-source', builtArtifacts: { 'native.exe': 'current-binary' } };
  const result = { exit: 0, passed: true, count: 1, target: 'native', sourceDigest: current.digest,
    artifacts: { 'native.exe': 'current-binary' } };
  const report = { target: 'native', source: current, runs: {
    lean: { ...result, command: ['node', 'proofs/bounded-session/check.mjs'], artifacts: {} },
    'session-native': { ...result, command: ['moon', 'test', 'src/bounded_execution', '--target', 'native', '--deny-warn'] },
    'adapter-native': { ...result, command: ['moon', 'test', 'src/connectors/local', '--target', 'native', '--deny-warn'] },
    'connection-native': { ...result, coverage: executedConnectionCoverage(),
      command: ['moon', 'test', 'src/query_integration/local_managed_set_wbtest.mbt', '--target', 'native', '--deny-warn'] },
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

test('copied binding cannot widen both claim scopes using unchanged execution and digests', () => {
  const { report, current } = fixture();
  const originalReport = JSON.stringify(report);
  const originalCurrent = JSON.stringify(current);
  const widened = { ...binding, profile: 'UNCHECKED rows with arbitrary field types' };
  const nodes = graph([widened], 'native');
  assert.equal(nodes[3].scope.profile, widened.profile);
  assert.equal(nodes[4].scope.profile, widened.profile);
  assert.throws(() => checkBindings(root, [widened]), /Unverified connection profile/);
  assert.throws(() => validate(nodes, report, current, 'native'), /independently executed connection coverage/);
  assert.equal(JSON.stringify(report), originalReport);
  assert.equal(JSON.stringify(current), originalCurrent);
});

test('copied binding cannot relabel both operation and variant to an unexecuted scope', () => {
  const { report, current } = fixture();
  for (const copied of [{ ...binding, operation: 'nest' }, { ...binding, variant: 'unchecked' }]) {
    assert.throws(() => checkBindings(root, [copied]), /Unsupported connection scope/);
    assert.throws(() => validate(graph([copied], 'native'), report, current, 'native'), /independently executed connection coverage/);
  }
});

test('execution coverage cannot be broadened together with the claim', () => {
  const { report, current } = fixture();
  const copied = { ...binding, profile: 'UNCHECKED rows with arbitrary field types' };
  report.runs['connection-native'].coverage.scopes[2].profile = copied.profile;
  assert.throws(() => validate(graph([copied], 'native'), report, current, 'native'), /independently executed connection coverage/);
});

test('missing independent execution coverage is rejected', () => {
  const { nodes, report, current } = fixture();
  delete report.runs['connection-native'].coverage;
  assert.throws(() => validate(nodes, report, current, 'native'), /Unverified executed connection coverage/);
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

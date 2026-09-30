import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { bindings, checkBindings, executedCoverage, fixture, graph, premises, snapshot, validate } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const clone = value => structuredClone(value);
function evidence(target = 'js') {
  const source = snapshot(root), artifact = { 'test.js': 'digest' };
  const runs = { lean: { command: [process.execPath, 'proofs/relation-chain/check.mjs'],
    passed: true, exit: 0, sourceDigest: source.digest } };
  for (const [id, suite] of [['session', 'src/bounded_execution'], ['connection', fixture]]) {
    runs[`${id}-${target}`] = { command: ['moon', 'test', suite, '--target', target, '--deny-warn'],
      target, passed: true, exit: 0, count: 4, sourceDigest: source.digest,
      artifacts: artifact, ...(id === 'connection' ? { coverage: executedCoverage() } : {}) };
  }
  return { nodes: graph(bindings(), target), report: { source, target, runs },
    current: { ...source, builtArtifacts: clone(artifact) } };
}
test('reviewed actual chain bindings and conditional derived claims', () => {
  checkBindings(root, bindings());
  for (const target of ['js', 'wasm', 'native']) {
    const e = evidence(target);
    assert.equal(validate(e.nodes, e.report, e.current, target).length, 3);
  }
});
for (const [label, change] of [
  ['profile', b => { b.profile = 'UNCHECKED rows with arbitrary field types'; }],
  ['provider', b => { b.children[0] = 'unverified/provider.mbt'; }],
  ['stop premise', b => { b.stopContract = 'eventual-stop'; }],
  ['length', b => { b.length = 100; }],
  ['operation', b => { b.operation = 'time_series/distinct'; }],
]) test(`same-source both-sided ${label} relabeling cannot reuse execution`, () => {
  const e = evidence(), requested = bindings();
  change(requested[0]);
  assert.throws(() => checkBindings(root, requested));
  // Neither the independent execution record nor source/artifact changes.
  assert.throws(() => validate(graph(requested, 'js'), e.report, e.current, 'js'));
});
for (const [label, corrupt] of [
  ['missing child premise', e => { e.nodes.at(-1).premises = premises.slice(1); }],
  ['missing connection', e => { e.nodes.at(-1).dependencies.pop(); }],
  ['stale source', e => { e.current.digest = 'changed'; }],
  ['stale artifact', e => { e.current.builtArtifacts['test.js'] = 'changed'; }],
  ['unexecuted fixture', e => { e.report.runs['connection-js'].count = 0; }],
  ['target substitution', e => { e.report.runs['connection-js'].target = 'native'; }],
  ['fixture substitution', e => { e.report.runs['connection-js'].command[2] = 'src/other'; }],
  ['coverage widened in record', e => { e.report.runs['connection-js'].coverage.scopes[0].profile = '*'; }],
  ['forged formal connection', e => { const n = e.nodes.find(n => n.id.endsWith(':connection')); n.kind = 'formal-model'; n.scope.target = 'model'; n.run = 'lean'; }],
  ['cycle', e => { e.nodes[0].dependencies = [e.nodes.at(-1).id]; }],
  ['capacity guarantee', e => { e.nodes.at(-1).guarantees.push('all memory bounded'); }],
]) test(`reject ${label}`, () => {
  const e = evidence(); corrupt(e);
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'));
});

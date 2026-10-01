import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { bindings, checkBindings, coverage, fixture, identityFixture, snapshot, validate } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
function evidence(target = 'js') {
  const source = snapshot(root), artifact = { 'test.js': 'digest' };
  const runs = { lean: { passed: true, exit: 0, sourceDigest: source.digest,
    command: [process.execPath, 'proofs/relation-capacity/check.mjs'] } };
  for (const [kind, path] of [['capacity', fixture], ['identity', identityFixture], ['ledger', 'src/physical_resources/ledger_wbtest.mbt']]) {
    runs[`${kind}-${target}`] = { passed: true, exit: 0, sourceDigest: source.digest, target,
      count: kind === 'capacity' ? 3 : 1, artifacts: artifact,
      command: ['moon', 'test', path, '--target', target, '--deny-warn'] };
  }
  return { requested: bindings(), report: { source, target, coverage: coverage(), runs },
    current: { ...source, builtArtifacts: artifact } };
}
test('reviewed inventory and conditional bounds accept all executed targets', () => {
  checkBindings(root, bindings());
  for (const target of ['js', 'wasm', 'native']) {
    const e = evidence(target);
    assert.equal(validate(e.requested, e.report, e.current, target).length, 3);
  }
});
for (const [name, change] of [
  ['profile', x => { x.profile = 'UNCHECKED arbitrary field types'; }],
  ['provider', x => { x.provider = 'delayed-stop/custom-provider'; }],
  ['child callback', x => { x.children[0] = 'delayed-stop/custom-provider'; }],
  ['length', x => { x.length = 100; }],
  ['physical observation', x => { x.observation = 'process heap/RSS'; }],
  ['removed parent premise', x => { x.premises.pop(); }],
  ['discharged parent assumption', x => { x.unresolved.splice(1, 1); }],
  ['unconditional guarantee', x => { x.guarantee = 'all chain live bytes proved bounded'; }],
]) test(`cannot relabel requested capacity ${name} while retaining source and execution`, () => {
  const e = evidence(); change(e.requested[0]);
  assert.throws(() => checkBindings(root, e.requested));
  assert.throws(() => validate(e.requested, e.report, e.current, 'js'));
});
for (const [name, change] of [
  ['stale source', e => { e.current.digest = 'changed'; }],
  ['stale artifact', e => { e.current.builtArtifacts = { 'test.js': 'changed' }; }],
  ['native substitution', e => { e.report.runs['capacity-js'].target = 'native'; }],
  ['wrong fixture', e => { e.report.runs['capacity-js'].command[2] = identityFixture; }],
  ['no executed capacity tests', e => { e.report.runs['capacity-js'].count = 0; }],
  ['missing identity proof', e => { delete e.report.runs['identity-js']; }],
  ['coverage relabeling', e => { e.report.coverage.scopes[0].profile = '*'; }],
  ['shrunk inventory', e => { e.report.source.sources['proofs/relation-capacity/allocations.json'] = 'narrowed'; }],
]) test(`reject ${name}`, () => {
  const e = evidence(); change(e);
  assert.throws(() => validate(e.requested, e.report, e.current, 'js'));
});

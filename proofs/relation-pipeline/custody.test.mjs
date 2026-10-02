import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { hash, snapshot } from './inventory.mjs';
import { generatedObservers } from './capacity/instrument.mjs';
import { auditCustody, custodyInput, custodyOverlay, custodyDirectory } from './capacity/parent-control/custody.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
function fixture(target = 'js', mode = 'normal') {
  const entries = new Map();
  const read = path => entries.get(path) ?? readFileSync(join(root, path));
  const current = snapshot(root);
  const { overlay, fixture: sourceFixture, variable } = custodyOverlay(read, mode);
  const overlays = Object.fromEntries(Object.entries({ ...generatedObservers, ...overlay }).map(([p, code]) => [p, hash(code)]));
  const sources = { ...current.sources, ...overlays };
  const exact = Object.fromEntries(Object.keys(sources).sort().map(p => [p, sources[p]]));
  const observation = { executionCapacity: 100, before: 100, after: mode === 'normal' ? 0 : 100, workBefore: 6, workAfter: 6 };
  const child = '"event":"before-cleanup"\n"event":"after-cleanup"\n';
  const stage = 'ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup\n';
  const log = 'ACTQL_CUSTODY_CHAIN:started\n' + (mode === 'normal' ? child + stage :
    'ACTQL_CUSTODY_RETRY:false\nACTQL_CUSTODY_RETRY:error\n' + stage + child) +
    `ACTQL_CUSTODY:${JSON.stringify(observation)}\nTotal tests: 1, passed: 1, failed: 0.\n`;
  const binary = Buffer.from(`synthetic audit-unit-test artifact for ${target}`), digest = hash(binary);
  const artifact = `_build/${target}/debug/test/query_integration/query_integration.whitebox_test.${{ js: 'js', wasm: 'wasm', native: 'exe' }[target]}`;
  const archive = `${custodyDirectory}/binaries/${digest}`;
  entries.set('test-input.json', Buffer.from(JSON.stringify(custodyInput())));
  entries.set('test-fixture.mbt', Buffer.from(overlay[sourceFixture]));
  entries.set('test.log', Buffer.from(log)); entries.set(archive, binary);
  const report = { version: 'actql-relation-custody/0.1', target, mode, source: current,
    toolchain: JSON.parse(read('toolchain.json')), overlays,
    executedSource: { sources: exact, digest: hash(JSON.stringify(exact)) },
    command: ['moon', 'test', sourceFixture, '--target', target, '--deny-warn'], exit: 0,
    inputVariable: variable, inputPath: 'test-input.json', fixturePath: 'test-fixture.mbt',
    inputDigest: hash(JSON.stringify(custodyInput().program)), logPath: 'test.log', logDigest: hash(log),
    artifacts: { [artifact]: digest }, archives: { [artifact]: archive }, observation,
    physicalGcCompletion: false, completeAllocationUpper: false, prematureReleaseCandidate: false };
  return { report, current, read, entries };
}
for (const target of ['js', 'wasm', 'native']) for (const mode of ['normal', 'pending']) {
  test(`custody auditor accepts internally bound ${target}/${mode} records`, () => {
    const f = fixture(target, mode);
    assert.equal(auditCustody(f.report, target, mode, f.current, f.read).target, target);
  });
}
for (const target of ['js', 'wasm']) {
  test(`custody auditor rejects a whole consistent native record requested as ${target}`, () => {
    const f = fixture('native');
    assert.throws(() => auditCustody(f.report, target, 'normal', f.current, f.read), /target differs/);
  });
}
test('custody auditor rejects a normal record requested for false/error cleanup', () => {
  const f = fixture();
  assert.throws(() => auditCustody(f.report, 'js', 'pending', f.current, f.read), /mode differs/);
});
for (const [name, mutate] of [
  ['unconditional byte claim', f => { f.report.completeAllocationUpper = true; }],
  ['missing actual chain', f => {
    const log = f.read('test.log').toString().replace('ACTQL_CUSTODY_CHAIN:started\n', '');
    f.entries.set('test.log', Buffer.from(log)); f.report.logDigest = hash(log);
  }],
  ['provider source drift', f => { f.report.executedSource.sources['src/connectors/local/selected_relation_provider.mbt'] = '0'.repeat(64); }],
  ['detached fixture', f => { f.entries.set('test-fixture.mbt', Buffer.from('test "unrelated" {}')); }],
  ['different operation domain', f => {
    const input = custodyInput(); input.case.steps[0].op = 'select';
    f.entries.set('test-input.json', Buffer.from(JSON.stringify(input)));
  }],
]) {
  test(`custody auditor rejects ${name}`, () => {
    const f = fixture(); mutate(f);
    assert.throws(() => auditCustody(f.report, 'js', 'normal', f.current, f.read));
  });
}

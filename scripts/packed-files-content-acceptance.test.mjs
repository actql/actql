// Synthetic observations test detector strength only. No product/Model/Effect
// execution is claimed by this file; the separate packed runner performs it.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {packedContentBytes, packedContentCases, packedPureContentCases, packedContentSelection, packedContentCid,
  verifyPackedContentProducerManifest,
  verifyPackedContentScenario} from './packed-files-content-acceptance.mjs';

function observations(scenario) {
  const content = {media_type: 'text/csv',
    metadata: {content_cid: packedContentCid, size_bytes: 20}};
  const row = {destination: {$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
    provider_namespace: 'file-fixture', resource_kind: 'file',
    provider_identity_cid: `sha256:${'a'.repeat(64)}`, authority_scope_cid: `sha256:${'b'.repeat(64)}`,
    boundary_cid: `sha256:${'c'.repeat(64)}`, identity_cid: `sha256:${'d'.repeat(64)}`},
  name: 'approved.csv', content};
  const names = scenario.model ? ['capture', 'approve-model', 'approve', 'read']
    : ['capture', 'approve', 'read'];
  const phases = names.map((phase, index) => ({phase, pid: 101 + index,
    ref: {run: 'synthetic-detector-only'},
    status: ['capture', 'approve-model'].includes(phase) ? 'waiting_checkpoint'
      : scenario.fault ? 'needs_reconciliation' : 'succeeded',
    reads: phase === 'capture' ? 1 : 0, generations: phase === 'capture' ? 1 : 0,
    modelCalls: phase === 'approve-model' ? 1 : 0,
    sends: phase === 'approve' ? 1 : 0, writeGrants: phase === 'approve' ? 1 : 0,
    ...(!['capture', 'approve-model'].includes(phase) && !scenario.fault ? {rows: [row],
      ...(scenario.attachment ? {attachmentRows: [{name: 'approved.csv', content,
        media_type: 'text/csv', size_bytes: 20, row_count: 1}]} : {})} : {}),
    ...(scenario.fault ? {result_available: false} : {}),
  }));
  return {scenario, phases, bytes: Buffer.from(packedContentBytes),
    receipt: {content_cid: packedContentCid, request_cid: `sha256:${'1'.repeat(64)}`}};
}
test('four synthetic observation shapes match the separately declared byte expectations', () => {
  for (const scenario of packedContentCases) verifyPackedContentScenario(observations(scenario));
});
test('Pure selection preserves both transports, intermediate rows, restart and Unknown without a Model case', () => {
  assert.strictEqual(packedContentSelection().cases, packedContentCases);
  assert.strictEqual(packedContentSelection(['--scope', 'full']).cases, packedContentCases);
  const selected = packedContentSelection(['--scope', 'pure']);
  assert.strictEqual(selected.cases, packedPureContentCases);
  assert.equal(selected.cases.length, 4);
  assert.deepEqual(selected.cases.map(value => [value.entrance, value.fault ?? null]),
    [['Local', null], ['HTTPS', null], ['Local', 'lost_reply'], ['HTTPS', 'lost_reply']]);
  assert.ok(selected.cases.every(value => value.model === undefined && value.attachment === true));
  assert.ok(Object.isFrozen(selected) && Object.isFrozen(selected.cases) &&
    selected.cases.every(Object.isFrozen));
  for (const scenario of selected.cases) verifyPackedContentScenario(observations(scenario));
  const replay = observations(selected.cases[3]);
  replay.phases.at(-1).sends = 1;
  assert.throws(() => verifyPackedContentScenario(replay));
});
test('unknown or widened packed selection is refused without a fallback', () => {
  for (const args of [['pure'], ['--scope'], ['--scope', 'typo'],
    ['--scope', 'pure', '--allow-model'], ['--scope=pure']]) {
    assert.throws(() => packedContentSelection(args), TypeError);
  }
});
test('producer manifest binds the exact revision and all five string digests before installation', () => {
  const original = {revision: 'a'.repeat(40), tarballs: Object.fromEntries(
    ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']
      .map((name, index) => [name, String(index + 1).repeat(64)]))};
  verifyPackedContentProducerManifest(original, original.revision);
  assert.throws(() => verifyPackedContentProducerManifest(original, 'b'.repeat(40)));
  for (const mutate of [
    body => { delete body.tarballs.sdk; },
    body => { body.tarballs.extra = '1'.repeat(64); },
    body => { body.tarballs.sdk = ['2'.repeat(64)]; },
    body => { body.tarballs.sdk = null; },
    body => { body.tarballs.sdk = '2'.repeat(63); },
    body => { body.tarballs = []; },
  ]) {
    const changed = structuredClone(original);
    mutate(changed);
    assert.throws(() => verifyPackedContentProducerManifest(changed, original.revision));
  }
});
test('Pure runner requires a verified producer before any scratch or packing', () => {
  const env = {...process.env};
  delete env.ACTQL_PACKED_CLIENT_PACKAGES;
  const result = spawnSync(process.execPath, [
    fileURLToPath(new URL('./test-packed-files-content.mjs', import.meta.url)), '--scope', 'pure'],
  {env, encoding: 'utf8'});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PackedPureContentRequiresVerifiedProducer/u);
  assert.doesNotMatch(result.stdout, /PACKED_CONTENT_CASE|Packed Client packages/u);
});
for (const [name, mutate] of [
  ['Source replay after restart', facts => { facts.phases.at(-1).reads = 1; }],
  ['generation replay after restart', facts => { facts.phases.at(-1).generations = 1; }],
  ['a second send after an unknown reply', facts => { facts.phases.at(-1).sends = 1; }],
  ['unknown converted to success', facts => { facts.phases.at(-1).status = 'succeeded'; }],
  ['Run replacement at restart', facts => { facts.phases.at(-1).ref = {run: 'another-run'}; }],
  ['fake process restart', facts => { facts.phases.at(-1).pid = facts.phases[0].pid; }],
]) test(`packed acceptance detects ${name}`, () => {
  const facts = observations(packedContentCases.at(-1));
  mutate(facts);
  assert.throws(() => verifyPackedContentScenario(facts));
});
test('packed acceptance detects changed Content bytes and a mismatched receipt', () => {
  const wrongBytes = observations(packedContentCases[0]);
  wrongBytes.bytes = Buffer.from('name\napproved.csv\n');
  assert.throws(() => verifyPackedContentScenario(wrongBytes));
  const wrongReceipt = observations(packedContentCases[0]);
  wrongReceipt.receipt.content_cid = `sha256:${'2'.repeat(64)}`;
  assert.throws(() => verifyPackedContentScenario(wrongReceipt));
});
test('Model approval cannot grant COMMAND or publish its Result', () => {
  const facts = observations(packedContentCases[0]);
  facts.phases[1].writeGrants = 1;
  assert.throws(() => verifyPackedContentScenario(facts));
});
test('intermediate SERIALIZE metadata cannot be lost or changed across processes', () => {
  const facts = observations(packedContentCases[2]);
  facts.phases.at(-1).attachmentRows = [{name: 'approved.csv'}];
  assert.throws(() => verifyPackedContentScenario(facts));
});
test('packed runner parses without starting a pack or public Run', () => {
  const result = spawnSync(process.execPath, ['--check',
    fileURLToPath(new URL('./test-packed-files-content.mjs', import.meta.url))], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
});

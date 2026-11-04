import assert from 'node:assert/strict';
import test from 'node:test';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';

// Execute the actual installed frame with explicit compiler/Resource ports.
// These counters are not an ordinary admission, byte loan or physical ACK.
function fixture({grow} = {}) {
  const program = {}, acquisition = {}, ledger = {}, reservation = {}, events = [];
  const constructorFailure = new Error('original candidate constructor');
  let execution, frame, available = true;
  const definition = {identity: 'same original Run', wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'};
  const control = {
    reserveWorkspace(original, maximum, count) {
      assert.equal(original, ledger); assert.equal(maximum, 4096); assert.equal(count, 0);
      events.push('reserve'); return reservation;
    },
    growWorkspace(original, value, maximum, count) {
      assert.equal(original, ledger); assert.equal(value, reservation); assert.equal(maximum, 4096);
      events.push(['grow', count]); grow?.({frame, count, revoke() {available = false;}});
    },
    releaseWorkspace(original, value) {
      assert.equal(original, ledger); assert.equal(value, reservation); events.push('release');
    },
    candidateForRun() {events.push('candidate'); throw constructorFailure;},
    recoveryCandidateForRun() {events.push('restore candidate'); throw constructorFailure;},
    reissuer(resolve) {assert.equal(typeof resolve, 'function'); return {};},
  };
  frame = installRunKeyedContentCapture({
    moon: {clientProgramKeyedAcquisitionMatchesProgram: () => true,
      clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ({$tag: 1, _0: ['source', 'contract', 'schema', 'policy', 'internal', 'view']}),
      clientProgramKeyedLookupCapacity: () => assert.fail('static count is not required')},
    publications: {checkClientCompiledRunOwner() {}, checkClientCompiledRunDefinition() {}},
    control, preparedProgram: program, plan: {compiled: {}, runDefinition: definition}, acquisition,
    ledger, maxBytes: 4096, store: {storeAuthorityCid: 'store', status: () => ({closed: false})},
    namespaceId: 'namespace', authorityScopeCid: 'scope', storeAuthorityCid: 'store',
    principalId: 'principal', ownerPrincipal: 'principal', now: () => '2026-11-04T00:00:00.000Z',
    authorize: () => true, inputAvailable: () => available,
    retainExecution(value) {assert.equal(events.length, 0); execution = value;},
  });
  return {frame, events, execution, constructorFailure,
    capture: () => frame.capture({keyedAcquisition: acquisition, request: {},
      verifyRead: async () => {}, readSubjectCid: 'original read', bytes: Buffer.from('data')}),
    restore: inventory => frame.recoverInventory({keyedAcquisition: acquisition,
      verifyRead: async () => {}, inventory})};
}

test('captured inventory grows before a candidate constructor and keeps the same cleanup', async () => {
  const f = fixture();
  await assert.rejects(f.capture(), error => error === f.constructorFailure);
  assert.deepEqual(f.events, ['reserve', ['grow', 1], 'candidate']);
  assert.equal(await f.execution.cleanup(), true);
  assert.equal(await f.execution.cleanup(), true);
  assert.deepEqual(f.events, ['reserve', ['grow', 1], 'candidate', 'release']);
});

test('captured inventory refuses growth before candidate or Store construction', async () => {
  const failure = new Error('original Resource refusal');
  const f = fixture({grow() {throw failure;}});
  await assert.rejects(f.capture(), error => error === failure);
  assert.deepEqual(f.events, ['reserve', ['grow', 1]]);
  assert.equal(await f.execution.cleanup(), true);
  assert.deepEqual(f.events, ['reserve', ['grow', 1], 'release']);
});

test('captured inventory fences current loss and reentry during the original growth', async () => {
  const f = fixture({grow({frame, revoke}) {
    assert.throws(() => frame.recoverInventory({}), /InstalledKeyedContentInventoryMismatch/);
    revoke();
  }});
  await assert.rejects(f.capture(), /InstalledContentAuthorityUnavailable/);
  assert.deepEqual(f.events, ['reserve', ['grow', 1]]);
  assert.equal(await f.execution.cleanup(), true);
});

test('restored inventory funds its actual copy and refuses replacement during current', async () => {
  const original = {version: 'actql-installed-captured-content-inventory/0.1',
    runDefinitionCid: 'same original Run', entries: [
      {referenceWire: 'one', captureAuthorityCid: 'read one'},
      {referenceWire: 'two', captureAuthorityCid: 'read two'},
    ]};
  const f = fixture({grow() {original.entries.push({referenceWire: 'three', captureAuthorityCid: 'read three'});}});
  assert.throws(() => f.restore(original), /InstalledKeyedContentInventoryMismatch/);
  assert.deepEqual(f.events, ['reserve', ['grow', 2]]);
  assert.equal(await f.execution.cleanup(), true);
});

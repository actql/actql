import assert from 'node:assert/strict';
import test from 'node:test';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';

type Setup = Parameters<typeof installRunKeyedContentCapture>[0];
type Frame = ReturnType<typeof installRunKeyedContentCapture>;
type Execution = Parameters<Setup['retainExecution']>[0];
type Growth = Readonly<{frame: Frame; count: number; units: bigint | undefined; revoke(): void}>;
type Control = Setup['control'];

// Execute the actual installed frame with explicit compiler/Resource ports.
// These counters are not an ordinary admission, byte loan or physical ACK.
function fixture({grow}: Readonly<{grow?: (state: Growth) => void}> = {}) {
  const program = {}, acquisition = {}, ledger = {}, reservation = {}, events: (string | [string, number, bigint])[] = [];
  const candidate = {}, wire = '{"reference":"one"}';
  const constructorFailure = new Error('original candidate constructor');
  let execution: Execution | undefined, frame: Frame, available = true;
  const definition = {identity: 'same original Run', wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'};
  // These ports intentionally reach only the workspace and constructor cut.
  const control: Omit<Control, 'inspect' | 'issuer' | 'issue'> & {
    inspect(value: Parameters<Control['inspect']>[0]): Omit<ReturnType<Control['inspect']>, 'identity' | 'contentCid'>;
  } = {
    reserveWorkspace(original, maximum, count) {
      assert.equal(original, ledger); assert.equal(maximum, 4096); assert.equal(count, 0);
      events.push('reserve'); return reservation;
    },
    growWorkspace(original, value, maximum, count, units): undefined {
      assert.equal(original, ledger); assert.equal(value, reservation); assert.equal(maximum, 4096);
      assert.equal(typeof units, 'bigint');
      events.push(['grow', count, units!]); grow?.({frame, count, units, revoke() {available = false;}});
    },
    releaseWorkspace(original, value): undefined {
      assert.equal(original, ledger); assert.equal(value, reservation); events.push('release');
    },
    candidateForRun() {events.push('candidate'); return candidate;},
    inspect(value) {assert.equal(value, candidate);return {wire, storeCid:'store', workspaceScopeCid:'scope',
      effectiveDataPolicyCid:'policy', sizeBytes:4, mediaType:'text/plain'};},
    holdingCid() {return 'holding';},
    recoveryCandidateForRun() {events.push('restore candidate'); throw constructorFailure;},
    reissuer(resolve) {assert.equal(typeof resolve, 'function'); return {};},
  };
  // The omitted operations are unreachable in these constructor/growth controls.
  frame = installRunKeyedContentCapture({
    moon: {clientProgramKeyedAcquisitionMatchesProgram: () => true,
      clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ({$tag: 1, _0: ['source', 'contract', 'schema', 'policy', 'internal', 'view']}),
      clientProgramKeyedLookupCapacity: () => assert.fail('static count is not required')} as unknown as Setup['moon'],
    publications: {checkClientCompiledRunOwner() {}, checkClientCompiledRunDefinition() {}} as unknown as Setup['publications'],
    control: control as Control, preparedProgram: program, plan: {compiled: {}, runDefinition: definition}, acquisition,
    ledger, maxBytes: 4096, store: {storeAuthorityCid: 'store', status: () => ({closed: false}),
      createPreparedObjectWriter() {events.push('writer');throw constructorFailure;}} as unknown as Setup['store'],
    namespaceId: 'namespace', authorityScopeCid: 'scope', storeAuthorityCid: 'store',
    principalId: 'principal', ownerPrincipal: 'principal', now: () => '2026-11-04T00:00:00.000Z',
    authorize: () => true, inputAvailable: () => available,
    retainExecution(value) {assert.equal(events.length, 0); execution = value;},
  });
  return {frame, events, execution: execution!, constructorFailure,
    capture: () => frame.capture({keyedAcquisition: acquisition, request: {},
      verifyRead: async () => {}, readSubjectCid: 'original read', bytes: Buffer.from('data')} as unknown as Parameters<Frame['capture']>[0]),
    restore: (inventory: unknown) => frame.recoverInventory({keyedAcquisition: acquisition,
      verifyRead: async () => {}, inventory})};
}

test('captured inventory grows actual persistent extent after its prepaid frame and before Store construction', async () => {
  const f = fixture();
  await assert.rejects(f.capture(), error => error === f.constructorFailure);
  assert.deepEqual(f.events, ['reserve', 'candidate', ['grow', 1, 19n], 'writer']);
  assert.equal(await f.execution.cleanup(), true);
  assert.equal(await f.execution.cleanup(), true);
  assert.deepEqual(f.events, ['reserve', 'candidate', ['grow', 1, 19n], 'writer', 'release']);
});

test('captured inventory refuses persistent growth before Store or issued Ref construction', async () => {
  const failure = new Error('original Resource refusal');
  const f = fixture({grow() {throw failure;}});
  await assert.rejects(f.capture(), error => error === failure);
  assert.deepEqual(f.events, ['reserve', 'candidate', ['grow', 1, 19n]]);
  assert.equal(await f.execution.cleanup(), true);
  assert.deepEqual(f.events, ['reserve', 'candidate', ['grow', 1, 19n], 'release']);
});

test('captured inventory fences current loss and reentry during the original growth', async () => {
  const f = fixture({grow({frame, revoke}) {
    assert.throws(() => frame.recoverInventory({} as Parameters<Frame['recoverInventory']>[0]), /InstalledKeyedContentInventoryMismatch/);
    revoke();
  }});
  await assert.rejects(f.capture(), /InstalledContentAuthorityUnavailable/);
  assert.deepEqual(f.events, ['reserve', 'candidate', ['grow', 1, 19n]]);
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
  assert.deepEqual(f.events, ['reserve', ['grow', 4, 12n]]);
  assert.equal(await f.execution.cleanup(), true);
});

test('restored inventory keeps its measured count when a borrowed getter appends during copying', async () => {
  const original = {version: 'actql-installed-captured-content-inventory/0.1',
    runDefinitionCid: 'same original Run', entries: [
      {referenceWire: 'one', captureAuthorityCid: 'read one'},
      {referenceWire: 'two', captureAuthorityCid: 'read two'},
    ]};
  let reads = 0;
  const f = fixture({grow() {
    Object.defineProperty(original.entries[0], 'referenceWire', {enumerable: true, get() {
      reads++;
      original.entries.push({referenceWire: '', captureAuthorityCid: 'unexpected'});
      return 'one';
    }});
  }});
  assert.throws(() => f.restore(original), /InstalledKeyedContentInventoryMismatch/);
  assert.equal(reads, 1);
  assert.deepEqual(f.events, ['reserve', ['grow', 4, 12n]]);
  assert.equal(await f.execution.cleanup(), true);
});

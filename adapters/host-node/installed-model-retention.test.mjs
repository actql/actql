// Real Core admission, with an explicit immutable-input Store double. These
// cases cover process-local leases; installed tests cover durable recovery.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';

const capturedBinding = () => ({version: 'actql-installed-keyed-read-binding/0.1',
  selectionCid: `sha256:${'c'.repeat(64)}`, physicalBindingCid: `sha256:${'d'.repeat(64)}`,
  connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
  bindingCid: `sha256:${'e'.repeat(64)}`, connection: 'fixture:files'});

async function setup({control} = {}) {
  const runtime = await loadCheckpointRuntime();
  const fixture = JSON.parse(readFileSync(new URL('./fixtures/model-resolution-crypto.json', import.meta.url), 'utf8'));
  const inventory = JSON.parse(runtime.modelCallSetAdmit(canonicalJson(fixture.request)));
  assert.equal(inventory.ok, true);
  const receipt = {runId: inventory.runId, runDefinitionCid: inventory.runDefinitionCid};
  const originals = {...fixture.request, fixedInputReceiptWire: canonicalJson(receipt)};
  const snapshot = {version: 'actql-installed-model-input/0.1', scopeCid: inventory.scopeCid,
    inputArtifactCid: inventory.inputArtifactCid, originals};
  let reads = 0;
  let terminal = false;
  const controller = await installNodeModelContinuation({control, getCheckpoints: () => ({
    journal: {getRunState: () => ({status: terminal ? 'succeeded' : 'waiting'}),
      isTerminalRunOutcome: status => status === 'succeeded', hasUnresolvedModelCalls: () => false,
      discoverModelCallSets: () => [{originals}]},
    async readModelInput(actual) {
      assert.deepEqual(actual, receipt);
      reads++;
      return Buffer.from(canonicalJson(snapshot));
    },
  })});
  return {controller, snapshot, record: {originals, scopeCid: inventory.scopeCid,
    inventory, checkpointCid: JSON.parse(originals.checkpointWire).checkpoint_cid},
    reads: () => reads, finish: () => { terminal = true; }};
}

test('Model input release is exact-token guarded and preserves another consumer', async () => {
  const {controller, record, reads, finish} = await setup();
  const first = await controller.prime(record);
  const second = await controller.prime(record);
  assert.equal(controller.usage().retainedInputScopes, 1);
  assert.equal(controller.usage().retainedInputs, 2);
  assert.ok(controller.usage().retainedInputBytes > 0);
  controller.release(first);
  assert.equal(first.available, false);
  assert.equal(second.available, true);
  assert.equal(controller.verifier.admitCallSet(record.originals).scopeCid, record.scopeCid);
  controller.release(first);
  assert.equal(controller.usage().retainedInputs, 1);
  controller.release(second);
  assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0, retainedInputBytes: 0, retainedInventoryScopes: 1});
  assert.equal(controller.verifier.admitCallSet(record.originals).scopeCid, record.scopeCid,
    'waiting journal checks retain only admitted receipt metadata');
  const third = await controller.prime(record);
  controller.release(second);
  assert.equal(third.available, true);
  assert.equal(controller.verifier.admitCallSet(record.originals).scopeCid, record.scopeCid);
  assert.equal(reads(), 3, 'a new consumer reads durable input again');
  finish();
  controller.release(third);
  assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0,
    retainedInputBytes: 0, retainedInventoryScopes: 0});
  assert.throws(() => controller.verifier.admitCallSet(record.originals), {code: 'ModelFixedInputCustodyUnavailable'});
});

test('failed Model inventory admission releases only its own new input lease', async () => {
  const {controller, record, snapshot} = await setup();
  const original = await controller.prime(record);
  snapshot.originals = {...snapshot.originals, slotWires: []};
  await assert.rejects(controller.prime(record), {code: 'ModelFixedInputOriginalMismatch'});
  assert.equal(original.available, true);
  assert.equal(controller.usage().retainedInputs, 1);
  controller.release(original);
  assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0, retainedInputBytes: 0, retainedInventoryScopes: 1});
});

test('terminal Model sweep retires metadata after an earlier waiting input release', async () => {
  const {controller, record, finish} = await setup();
  const token = await controller.prime(record);
  controller.release(token);
  assert.equal(controller.usage().retainedInputs, 0);
  assert.equal(controller.usage().retainedInventoryScopes, 1);
  finish();
  controller.retire(record);
  assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0,
    retainedInputBytes: 0, retainedInventoryScopes: 0});
});

test('first Model admission failure retains neither payload nor inventory metadata', async () => {
  const {controller, record, snapshot} = await setup();
  snapshot.originals = {...snapshot.originals, slotWires: []};
  await assert.rejects(controller.prime(record), {code: 'ModelFixedInputOriginalMismatch'});
  assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0,
    retainedInputBytes: 0, retainedInventoryScopes: 0});
});

test('Model custody digest distinguishes original wire carriage returns from line feeds', async () => {
  const {controller, record, snapshot} = await setup();
  const original = record.originals.originalRunWire;
  snapshot.originals = {...snapshot.originals, originalRunWire: `${original}\r`};
  record.originals = {...record.originals, originalRunWire: `${original}\n`};
  await assert.rejects(controller.prime(record), {code: 'ModelFixedInputOriginalMismatch'});
  assert.equal(controller.usage().retainedInputs, 0);
  assert.equal(controller.usage().retainedInventoryScopes, 0);
});

test('Model fixed input preserves the exact captured Content inventory without deriving read authority', async () => {
  const {controller, record, snapshot} = await setup();
  const capturedContent = {version: 'actql-installed-captured-content-inventory/0.1',
    runDefinitionCid: record.inventory.runDefinitionCid, entries: [
      {referenceWire: '{"original":"e\u0301\\r\\n"}', captureAuthorityCid: `sha256:${'a'.repeat(64)}`},
      {referenceWire: '{"original":"\u00e9\\n"}', captureAuthorityCid: `sha256:${'b'.repeat(64)}`},
    ]};
  snapshot.capturedContent = capturedContent;
  snapshot.capturedContentBinding = capturedBinding();
  const first = await controller.prime(record);
  assert.deepEqual(first.snapshot.capturedContent, capturedContent);
  assert.deepEqual(controller.capturedContentBinding(first, record.inventory.runDefinitionCid), capturedBinding());
  assert.equal(controller.capturedContent(first, record.inventory.runDefinitionCid),
    first.snapshot.capturedContent, 'borrow the authenticated original, not an envelope copy');
  assert.throws(() => { first.snapshot.capturedContent.entries[0].referenceWire = 'replacement'; }, TypeError);
  assert.throws(() => { first.snapshot.capturedContent.entries.push(capturedContent.entries[0]); }, TypeError);
  assert.throws(() => { first.receipt.runDefinitionCid = `sha256:${'f'.repeat(64)}`; }, TypeError);
  assert.deepEqual(first.snapshot.capturedContent, capturedContent);
  assert.throws(() => controller.capturedContent({...first}, record.inventory.runDefinitionCid),
    {code: 'ModelFixedInputCustodyUnavailable'});
  assert.throws(() => controller.capturedContent(first, `sha256:${'f'.repeat(64)}`),
    {code: 'ModelFixedInputCustodyUnavailable'});
  const foreign = await setup();
  assert.throws(() => foreign.controller.capturedContent(first, record.inventory.runDefinitionCid),
    {code: 'ModelFixedInputCustodyUnavailable'});
  controller.release(first);
  assert.throws(() => controller.capturedContent(first, record.inventory.runDefinitionCid),
    {code: 'ModelFixedInputCustodyUnavailable'});
  const second = await controller.prime(record);
  assert.deepEqual(second.snapshot.capturedContent, capturedContent,
    'a new input lease reads the same durable inventory rather than recapturing');
  assert.equal(second.referenceIssuer, undefined, 'saved inventory alone grants no reference authority');
  controller.release(second);
});

test('saved Model scope requires the original live continuation lease before invoking its common reader', async () => {
  // The scope reader is a boundary spy. Real common scope admission is covered
  // by the keyed/composed owner fixtures; this checks its custody callback.
  const calls = [];
  const {controller, record} = await setup({control: {
    readCheckedClientInferSavedInputScope(...args) { calls.push(args); return 'plain'; },
    readCheckedClientComposedInferSavedInputScope(...args) { calls.push(args); return 'composed'; },
  }});
  const token = await controller.prime(record);
  const plan = {compiled: {}, runDefinition: {identity: record.inventory.runDefinitionCid}};
  const selected = {graph: {}, step: 1};
  const read = (lease, current = plan) => controller.savedScope(current, {}, selected, lease);
  assert.throws(() => read({...token}), {code: 'ModelFixedInputCustodyUnavailable'});
  const foreign = await setup();
  const foreignToken = await foreign.controller.prime(foreign.record);
  assert.throws(() => read(foreignToken), {code: 'ModelFixedInputCustodyUnavailable'});
  assert.throws(() => read(token, {...plan, runDefinition: {identity: `sha256:${'f'.repeat(64)}`}}),
    {code: 'ModelFixedInputCustodyUnavailable'});
  assert.equal(calls.length, 0);
  assert.equal(read(token), 'plain');
  assert.equal(controller.savedScope(plan, {}, {...selected, occurrence: {}}, token), 'composed');
  const available = calls.map(args => args.at(-1));
  assert.deepEqual(available.map(check => check()), [true, true]);
  controller.release(token);
  assert.deepEqual(available.map(check => check()), [false, false]);
  assert.throws(() => read(token), {code: 'ModelFixedInputCustodyUnavailable'});
  assert.equal(calls.length, 2);
  foreign.controller.release(foreignToken);
  assert.equal(controller.usage().retainedInputs, 0);
  assert.equal(foreign.controller.usage().retainedInputs, 0);
});

for (const change of ['foreign-run', 'extra-field', 'duplicate-ref', 'missing-authority', 'invalid-authority']) {
  test(`Model fixed input rejects ${change} captured inventory before retaining a lease`, async () => {
    const {controller, record, snapshot} = await setup();
    const entry = {referenceWire: '{"original":true}', captureAuthorityCid: `sha256:${'a'.repeat(64)}`};
    snapshot.capturedContent = {version: 'actql-installed-captured-content-inventory/0.1',
      runDefinitionCid: record.inventory.runDefinitionCid, entries: [entry]};
    snapshot.capturedContentBinding = capturedBinding();
    if (change === 'foreign-run') snapshot.capturedContent.runDefinitionCid = `sha256:${'f'.repeat(64)}`;
    if (change === 'extra-field') snapshot.capturedContent.repaired = true;
    if (change === 'duplicate-ref') snapshot.capturedContent.entries.push({...entry});
    if (change === 'missing-authority') delete entry.captureAuthorityCid;
    if (change === 'invalid-authority') entry.captureAuthorityCid = 'unverified';
    await assert.rejects(controller.prime(record), {code: 'ModelCapturedInventoryMismatch'});
    assert.deepEqual(controller.usage(), {retainedInputScopes: 0, retainedInputs: 0,
      retainedInputBytes: 0, retainedInventoryScopes: 0});
  });
}

for (const change of ['missing', 'extra-field', 'invalid-physical', 'invalid-revision']) {
  test(`Model fixed input rejects ${change} original captured Source binding`, async () => {
    const {controller, record, snapshot} = await setup();
    snapshot.capturedContent = {version: 'actql-installed-captured-content-inventory/0.1',
      runDefinitionCid: record.inventory.runDefinitionCid, entries: []};
    snapshot.capturedContentBinding = capturedBinding();
    if (change === 'missing') delete snapshot.capturedContentBinding;
    if (change === 'extra-field') snapshot.capturedContentBinding.assumed = true;
    if (change === 'invalid-physical') snapshot.capturedContentBinding.physicalBindingCid = 'unverified';
    if (change === 'invalid-revision') snapshot.capturedContentBinding.connectorRevision = null;
    await assert.rejects(controller.prime(record), {code: 'ModelCapturedBindingMismatch'});
    assert.equal(controller.usage().retainedInputs, 0);
  });
}

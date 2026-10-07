// Real Core admission, with an explicit immutable-input Store double. These
// cases cover process-local leases; installed tests cover durable recovery.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';

async function setup() {
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
  const controller = await installNodeModelContinuation({getCheckpoints: () => ({
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

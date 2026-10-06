import test from 'node:test';
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {hash} from './inputs.mjs';
import {canonicalReceipt} from './receipts.mjs';
import {checkCostObservation} from './costs.mjs';
import {costFixture as fixture} from './costs-fixture.mjs';

const bytes = value => Buffer.from(`${encode(value)}\n`);

test('the complete 30-action catalog retains every fresh cost alongside one optional reused action', () => {
  for (const reused of [false, true]) {
    const request = fixture(reused, true), result = checkCostObservation(request);
    assert.equal(result.actions.length, 30);
    assert.equal(result.knownProducerMilliseconds, reused ? 511 : 525);
    const bridge = result.actions.filter(row => row.actionId.startsWith('events-'));
    assert.deepEqual(bridge.map(row => row.actionId), ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']);
    assert.deepEqual(bridge.map(row => row.currentMilliseconds), [11, 17, 17, 17]);
    assert(bridge.every(row => row.acquisition === 'fresh' && row.observation === 'executed'));
    assert.equal(result.actions.filter(row => row.currentMilliseconds === null).length, reused ? 1 : 0);
    for (const id of bridge.map(row => row.actionId)) {
      const missingReceipt = fixture(reused, true);
      missingReceipt.receipts = missingReceipt.receipts.filter(receipt => receipt.action.id !== id);
      assert.throws(() => checkCostObservation(missingReceipt), /Incomplete cost receipt inventory/u);
      const missingAcquisition = fixture(reused, true);
      missingAcquisition.acquisition.actions = missingAcquisition.acquisition.actions.filter(row => row.actionId !== id);
      assert.throws(() => checkCostObservation(missingAcquisition), /Incomplete cost acquisition/u);
    }
  }
});

test('fresh preparation is counted once and nested comparison costs are not summed twice', () => {
  const request = fixture(), originals = request.receipts.map(canonicalReceipt);
  const result = checkCostObservation(request);
  assert.equal(result.knownProducerMilliseconds, 55);
  assert.equal(result.actions[1].currentMilliseconds, 17);
  assert.equal(result.actions[1].exclusiveMilliseconds, 14);
  assert.equal(result.netRunnerSavingsMilliseconds, null);
  assert.deepEqual(result.producerOwner, {runId: 30, runAttempt: 1, jobId: 4});
  assert(result.residual.length > 0);
  request.receipts.forEach((receipt, index) => assert(canonicalReceipt(receipt).equals(originals[index])));
});

test('reused origin cost remains historical, current count/time is null, and preparation/acquisition is retained', () => {
  const request = fixture(true), result = checkCostObservation(request), row = result.actions[1];
  assert.equal(result.knownProducerMilliseconds, 41);
  assert.equal(row.observation, 'reused-not-executed');
  assert.equal(row.originMilliseconds, 17); assert.equal(row.originRunAttempt, 2);
  assert.equal(row.currentUnits, null); assert.equal(row.currentMilliseconds, null); assert.equal(row.exclusiveMilliseconds, null);
  assert.equal(result.producerPhases.isolatedPreparationMilliseconds, 3);
  assert.equal(result.producerPhases.acquisitionMilliseconds, 7);
});

for (const [name, change] of [
  ['unbound cost bytes', request => {request.collectionBytes = Buffer.from('{}\n');}],
  ['missing digest', request => {delete request.certificate.collectionCostsDigest;}],
  ['wrong certificate attempt', request => {request.certificate = {...request.certificate, context: {...request.certificate.context, runAttempt: 2}};}],
  ['missing receipt', request => {request.receipts.pop();}],
  ['duplicate receipt', request => {request.receipts[1] = request.receipts[0];}],
  ['wrong fresh job', request => {request.receipts[0].origin.jobId++;}],
  ['wrong target', request => {request.receipts[0].action.target = 'js';}],
  ['wrong preparation', request => {request.isolatedExecution.costs.preparationMilliseconds++;}],
  ['wrong isolated owner', request => {request.isolatedExecution.owner = '30:2:4';}],
  ['negative isolated cost', request => {request.isolatedExecution.costs.buildMilliseconds = -1;}],
  ['missing isolated costs', request => {request.isolatedExecution = null;}],
  ['wrong reused attempt', request => {request.acquisition.actions[1].origin.runAttempt++;}],
  ['reused receipt digest substitution', request => {request.acquisition.actions[1].origin.receiptDigest = 'f'.repeat(64);}],
  ['reused execution attribution', request => {request.isolatedExecution = {costs: {}};}],
]) test(`cost correspondence rejects ${name}`, () => {
  const request = fixture(name.startsWith('wrong reused') || name.startsWith('reused'));
  change(request); assert.throws(() => checkCostObservation(request));
});

test('self-consistent invalid/unknown costs and overflow do not become zero or complete savings', () => {
  for (const alter of [
    value => {value.acquisitionMilliseconds = null;}, value => {value.runtimeObservation.milliseconds = -1;},
    value => {value.unlisted = 0;}, value => {value.runtimeObservation.inputDigest = 'f'.repeat(64);},
    value => {value.runtimeObservation.milliseconds = Number.MAX_SAFE_INTEGER;},
  ]) {
    const request = fixture(), value = JSON.parse(request.collectionBytes); alter(value);
    request.collectionBytes = bytes(value); request.certificate.collectionCostsDigest = hash(request.collectionBytes);
    assert.throws(() => checkCostObservation(request));
  }
});

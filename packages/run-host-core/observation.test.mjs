import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {admitObservationScope, observationScopeKey, openObservationBudget,
  chargeObservation, observationBudgetSnapshot} from './observation.mjs';

const cid = character => `sha256:${character.repeat(64)}`;
const scope = (workspace = 'ws_a', revision = 'collector.1') =>
  admitObservationScope({workspace, authorityScopeCid: cid('a'),
    destinationRevision: revision, disclosureRevision: 'metadata-only.1',
    purpose: 'customer_telemetry'});

test('portable owner charges exact limits and preserves custody across restart', () => {
  const admitted = scope(), request = cid('b');
  const budget = openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: true});
  assert.equal(chargeObservation(budget, admitted, request, 3, 'task;0;1'), true);
  const saved = observationBudgetSnapshot(budget);
  assert.deepEqual(saved, {scopeKey: observationScopeKey(admitted),
    requestKey: request, maxRecords: 2, maxBytes: 8,
    records: 1, bytes: 3,
    factHashes: [createHash('sha256').update('task;0;1').digest('hex')]});
  const restored = openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false, saved});
  assert.equal(chargeObservation(restored, admitted, request, 5, 'task;1;1'), true);
  assert.equal(chargeObservation(restored, admitted, request, 5, 'task;1;1'), false);
  assert.equal(chargeObservation(restored, admitted, request, 3, 'task;0;1'), false);
  assert.throws(() => chargeObservation(restored, admitted, request, 1),
    {code: 'ObservationCustodyRejected'});
  assert.equal(observationBudgetSnapshot(restored).bytes, 8);
});

test('changed scope, missing custody, malformed snapshot and forged handles refuse', () => {
  const admitted = scope(), request = cid('b');
  const budget = openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: true});
  const saved = observationBudgetSnapshot(budget);
  for (const other of [scope('ws_b'), scope('ws_a', 'collector.2')]) {
    assert.throws(() => openObservationBudget(other, request,
      {maxRecords: 2, maxBytes: 8, freshRequest: false, saved}),
    {code: 'ObservationCustodyRejected'});
  }
  assert.throws(() => openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false}),
  {code: 'ObservationCustodyRejected'});
  assert.throws(() => openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false,
      saved: {...saved, bytes: undefined}}), /InvalidObservationBudgetSnapshot/u);
  assert.throws(() => observationBudgetSnapshot({}), /ForeignObservationHandle/u);
  assert.throws(() => observationScopeKey({}), /ForeignObservationHandle/u);
});

test('interleaved facts remain suppressed after serialized custody restoration', () => {
  const admitted = scope(), request = cid('b');
  const budget = openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: true});
  assert.equal(chargeObservation(budget, admitted, request, 4, 'task.0.7.settled'), true);
  assert.equal(chargeObservation(budget, admitted, request, 4, 'task.1.3.running'), true);
  const saved = observationBudgetSnapshot(budget);
  assert.equal(Object.isFrozen(saved.factHashes), true);
  const external = JSON.parse(JSON.stringify(saved));
  const restored = openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false, saved: external});
  external.factHashes[0] = '0'.repeat(64);
  assert.equal(chargeObservation(restored, admitted, request, 4, 'task.0.7.settled'), false);
  assert.deepEqual(observationBudgetSnapshot(restored), saved);
  assert.throws(() => chargeObservation(restored, admitted, request, 1, 'task.1.4.settled'),
    {code: 'ObservationCustodyRejected'});
  const damaged = {...saved, factHashes: [saved.factHashes[0], saved.factHashes[0]]};
  assert.throws(() => openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false, saved: damaged}),
    {code: 'ObservationCustodyRejected'});
  const {factHashes, ...legacy} = saved;
  assert.throws(() => openObservationBudget(admitted, request,
    {maxRecords: 2, maxBytes: 8, freshRequest: false,
      saved: {...legacy, lastFact: 'task.1.3.running'}}),
    /InvalidObservationBudgetSnapshot/u);
});

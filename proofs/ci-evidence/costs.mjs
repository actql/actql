// Cost correspondence is separate from reuse authorization. Enclosing job
// spans, uploads and uninstrumented work remain required for net savings.
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {hash} from './inputs.mjs';
import {canonicalReceipt} from './receipts.mjs';

const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort(), 'Missing/extra cost field');
const duration = value => {
  assert(Number.isSafeInteger(value) && value >= 0, 'Invalid cost observation');
  return value;
};
const sum = values => {
  const total = values.reduce((n, value) => n + duration(value), 0);
  return duration(total);
};
export const costVersion = 'actql-verification-family-costs/0.1';

export function checkCostObservation({collectionBytes, certificate, state, catalog, acquisition,
  comparison, receipts, isolatedExecution = null}) {
  assert.equal(hash(collectionBytes), certificate.collectionCostsDigest, 'Changed collection cost bytes');
  const collection = JSON.parse(collectionBytes);
  assert.equal(collectionBytes.toString('utf8'), `${encode(collection)}\n`, 'Noncanonical cost observation');
  exact(collection, ['runtimeObservation', 'isolatedPreparationMilliseconds', 'stagedSourceBytes', 'comparison', 'acquisitionMilliseconds']);
  exact(collection.runtimeObservation, ['milliseconds', 'entries', 'bytes', 'inputDigest']);
  for (const field of ['milliseconds', 'entries', 'bytes']) duration(collection.runtimeObservation[field]);
  assert.equal(collection.runtimeObservation.inputDigest, hash(encode(state.runtime)), 'Wrong observed runtime cost owner');
  duration(collection.isolatedPreparationMilliseconds); duration(collection.stagedSourceBytes);
  duration(collection.acquisitionMilliseconds); duration(certificate.milliseconds);
  exact(collection.comparison, ['checkpointMilliseconds', 'transferMilliseconds', 'inspectionMilliseconds', 'totalMilliseconds']);
  Object.values(collection.comparison).forEach(duration);
  assert.deepEqual(collection.comparison, comparison.costs, 'Wrong comparison cost observation');
  assert.equal(collection.acquisitionMilliseconds, acquisition.milliseconds, 'Wrong acquisition cost observation');
  assert.deepEqual(acquisition.context, state.context, 'Wrong acquisition cost owner');
  assert.deepEqual(comparison.context, state.context, 'Wrong comparison cost owner');
  assert.deepEqual(certificate.context, state.context, 'Wrong certificate cost owner');
  assert.deepEqual(acquisition.actions.map(entry => entry.actionId), catalog.actions.map(action => action.id), 'Incomplete cost acquisition');
  assert.equal(receipts.length, catalog.actions.length, 'Incomplete cost receipt inventory');
  const byId = new Map(receipts.map(receipt => [receipt.action.id, receipt]));
  assert.equal(byId.size, receipts.length, 'Duplicate cost receipt');
  const actions = catalog.actions.map((action, index) => {
    const entry = acquisition.actions[index], receipt = byId.get(action.id);
    assert(receipt, 'Missing cost receipt');
    assert.deepEqual(receipt.action, action, 'Wrong cost action/target/scope');
    const digest = hash(canonicalReceipt(receipt));
    let currentUnits = null, currentMilliseconds = null, exclusiveMilliseconds = null;
    if (entry.acquisition === 'fresh') {
      assert.deepEqual(receipt.origin, state.origin, 'Wrong current cost execution owner');
      assert.equal(receipt.inputs.key, entry.candidateActionKey, 'Wrong current cost input');
      currentUnits = receipt.execution.units;
      currentMilliseconds = receipt.execution.milliseconds;
      exclusiveMilliseconds = currentMilliseconds;
      if (action.id === 'mutations-js') {
        assert(isolatedExecution, 'Missing actual isolated cost observation');
        exact(isolatedExecution.costs, ['preparationMilliseconds', 'buildMilliseconds', 'executionMilliseconds', 'inspectionMilliseconds', 'closeMilliseconds']);
        assert.equal(isolatedExecution.owner, `${state.origin.runId}:${state.origin.runAttempt}:${state.origin.jobId}`, 'Wrong isolated cost owner');
        assert.equal(isolatedExecution.costs.preparationMilliseconds, collection.isolatedPreparationMilliseconds, 'Wrong isolated preparation cost');
        assert.equal(sum(Object.values(isolatedExecution.costs)), currentMilliseconds, 'Wrong isolated action cost envelope');
        // Preparation is already included in both collection and the receipt.
        // Count it once, preserving the complete original receipt unchanged.
        exclusiveMilliseconds = currentMilliseconds - collection.isolatedPreparationMilliseconds;
        duration(exclusiveMilliseconds);
      }
    } else {
      assert.equal(entry.acquisition, 'reused'); assert.equal(action.id, 'mutations-js', 'Unreviewed reused cost action');
      assert.equal(digest, entry.origin.receiptDigest, 'Wrong reused cost original');
      assert.equal(receipt.origin.testedRevision, entry.origin.revision);
      assert.equal(receipt.origin.runId, entry.origin.runId); assert.equal(receipt.origin.runAttempt, entry.origin.runAttempt);
      assert.equal(receipt.inputs.key, entry.origin.actionKey, 'Wrong reused cost input');
      assert.equal(isolatedExecution, null, 'Reused action cannot have current isolated execution costs');
    }
    return {actionId: action.id, acquisition: entry.acquisition,
      observation: entry.acquisition === 'fresh' ? 'executed' : 'reused-not-executed',
      currentUnits, currentMilliseconds, exclusiveMilliseconds,
      originRevision: receipt.origin.testedRevision, originRunId: receipt.origin.runId,
      originRunAttempt: receipt.origin.runAttempt, originReceiptDigest: digest,
      originUnits: receipt.execution.units, originMilliseconds: receipt.execution.milliseconds};
  });
  const producerPhases = {
    runtimeObservationMilliseconds: collection.runtimeObservation.milliseconds,
    isolatedPreparationMilliseconds: collection.isolatedPreparationMilliseconds,
    comparisonMilliseconds: collection.comparison.totalMilliseconds,
    acquisitionMilliseconds: collection.acquisitionMilliseconds,
    checkerMilliseconds: certificate.milliseconds,
  };
  return {version: costVersion, context: state.context, collectionCostsDigest: hash(collectionBytes),
    stagedSourceBytes: collection.stagedSourceBytes, producerPhases,
    comparisonSubphases: {...collection.comparison}, actions,
    knownProducerMilliseconds: sum([...Object.values(producerPhases),
      ...actions.filter(entry => entry.acquisition === 'fresh').map(entry => entry.exclusiveMilliseconds)]),
    netRunnerSavingsMilliseconds: null,
    residual: ['partial producer phases: source/input construction, receipt hashing/writes and precollection verification are not timed here',
      'producer/final enclosing job spans and archive uploads/downloads are needed for total runner measurement',
      'comparison subphases are inside comparisonMilliseconds; consumer verification encloses its comparison/hashing work',
      'origin elapsed time is a historical observation, not candidate execution or a causal speedup estimate']};
}

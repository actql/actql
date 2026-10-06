import test from 'node:test';
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {actionInputs, hash, sharedFiles, mutationSnapshotExtras} from './inputs.mjs';
import {readCatalog} from './actions.mjs';
import {sealReceipt, canonicalReceipt, mutationIds} from './receipts.mjs';
import {checkCostObservation} from './costs.mjs';

const bytes = value => Buffer.from(`${encode(value)}\n`);
function fixture(reused = false) {
  // Hand-authored timing/receipt fixture, not an isolated mutation execution.
  const catalog = readCatalog(); catalog.actions = catalog.actions.filter(action => ['model', 'mutations-js'].includes(action.id));
  catalog.actions.forEach(action => {action.dependencies = [];});
  const context = {candidateRevision: 'b'.repeat(40), runId: 30, runAttempt: 1};
  const origin = {repository: 'actql/actql', repositoryId: 1, workflowId: 2, workflowPath: '.github/workflows/ci.yml',
    testedRevision: context.candidateRevision, runHeadRevision: context.candidateRevision,
    runId: context.runId, runAttempt: context.runAttempt, jobId: 4, event: 'pull_request', branch: 'feature'};
  const runtime = {profile: 'controlled-test-runtime', unresolved: []}, state = {context, origin, runtime};
  const files = new Map([...sharedFiles, ...mutationSnapshotExtras,
    ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'mutations.mjs', 'evidence.mjs'].map(path => `proofs/bounded-session/${path}`),
    ...['bounded_execution', 'connectors/local', 'query_integration'].map(path => `src/${path}/moon.pkg`)].map(path => [path, path]));
  const tree = {entries: new Map([...files.keys()].map(path => [path, {mode: '100644', kind: 'blob'}])),
    read: path => Buffer.from(path.endsWith('moon.pkg') ? '' : files.get(path))};
  const receipts = catalog.actions.map(action => {
    const from = reused && action.id === 'mutations-js' ? {...origin, testedRevision: 'a'.repeat(40),
      runHeadRevision: 'a'.repeat(40), runId: 3, runAttempt: 2, event: 'workflow_dispatch', branch: 'main'} : origin;
    return sealReceipt({origin: {...from}, action: structuredClone(action), inputs: actionInputs({tree, revision: from.testedRevision, action, runtime}),
      output: action.id === 'model' ? 'Checked 14 theorems, expected claim types and axiom dependencies\n' :
        mutationIds.map(id => `${id}: detected by replacement tests`).join('\n'),
      status: 0, milliseconds: action.id === 'model' ? 11 : 17});
  });
  const acquisition = {context, milliseconds: 7, actions: receipts.map(receipt => ({actionId: receipt.action.id,
    acquisition: reused && receipt.action.id === 'mutations-js' ? 'reused' : 'fresh', candidateActionKey: receipt.inputs.key,
    origin: {revision: receipt.origin.testedRevision, runId: receipt.origin.runId, runAttempt: receipt.origin.runAttempt,
      actionKey: receipt.inputs.key, receiptDigest: hash(canonicalReceipt(receipt))}}))};
  const comparison = {context, costs: {checkpointMilliseconds: 1, transferMilliseconds: 2, inspectionMilliseconds: 3, totalMilliseconds: 5}};
  const collection = {runtimeObservation: {milliseconds: 2, entries: 3, bytes: 4, inputDigest: hash(encode(runtime))},
    isolatedPreparationMilliseconds: 3, stagedSourceBytes: 100, comparison: comparison.costs, acquisitionMilliseconds: 7};
  const collectionBytes = bytes(collection), certificate = {context, milliseconds: 13, collectionCostsDigest: hash(collectionBytes)};
  const isolatedExecution = reused ? null : {owner: '30:1:4', costs: {preparationMilliseconds: 3,
    buildMilliseconds: 4, executionMilliseconds: 6, inspectionMilliseconds: 2, closeMilliseconds: 2}};
  return {state, catalog, acquisition, comparison, receipts, collectionBytes, certificate, isolatedExecution};
}

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

// Offline cost correspondence, never origin authentication or reuse permission.
import assert from 'node:assert/strict';
import {readCatalog} from '../proofs/ci-evidence/actions.mjs';
import {encode} from '../proofs/bounded-session/action-inputs.mjs';
import {hash} from '../proofs/ci-evidence/inputs.mjs';
import {parseReceipt} from '../proofs/ci-evidence/receipts.mjs';
import {checkCostObservation} from '../proofs/ci-evidence/costs.mjs';

export async function projectSessionCosts(zip, provenance) {
  const catalog = readCatalog(), state = await zip.json('context.json');
  const certificate = await zip.json('checked.json');
  assert.equal(certificate.version, 'actql-verification-family-certificate/0.1');
  assert.equal(certificate.mode, 'scoped-execution');
  assert.equal(certificate.catalogDigest, hash(encode(catalog)), 'Wrong independent cost catalog');
  assert.equal(state.context.candidateRevision, provenance.executionSha, 'Wrong cost execution revision');
  assert.equal(state.context.runId, provenance.runId, 'Wrong cost run');
  assert.equal(state.context.runAttempt, provenance.attempt, 'Wrong cost attempt');
  assert.equal(state.origin.repository, provenance.repository, 'Wrong cost repository');
  assert.equal(state.origin.runId, provenance.runId, 'Wrong cost producer run');
  assert.equal(state.origin.runAttempt, provenance.attempt, 'Wrong cost producer attempt');
  assert.equal(state.origin.testedRevision, provenance.executionSha, 'Wrong cost producer revision');
  assert(Number.isSafeInteger(state.origin.jobId) && state.origin.jobId > 0, 'Missing cost producer');
  assert.equal(state.origin.runHeadRevision, provenance.headSha, 'Wrong cost run head');
  assert.equal(state.origin.event, provenance.event, 'Wrong cost event');
  assert.equal(state.origin.workflowPath, provenance.workflowPath, 'Wrong cost workflow');
  const acquisitionBytes = await zip.read('acquisition-plan.json');
  const comparisonBytes = await zip.read('comparison-plan.json');
  assert.equal(certificate.acquisitionDigest, hash(acquisitionBytes), 'Changed cost acquisition bytes');
  assert.equal(certificate.comparisonDigest, hash(comparisonBytes), 'Changed cost comparison bytes');
  const acquisition = JSON.parse(acquisitionBytes), comparison = JSON.parse(comparisonBytes);
  const receipts = await Promise.all(catalog.actions.map(async action =>
    parseReceipt(await zip.read(`receipts/${action.id}.json`))));
  assert.deepEqual(certificate.receiptDigests, receipts.map(receipt =>
    ({actionId: receipt.action.id, digest: hash(Buffer.from(`${encode(receipt)}\n`))})), 'Changed cost original receipts');
  const reused = acquisition.actions.some(entry => entry.acquisition === 'reused');
  if (reused) assert(!zip.entries.some(entry => entry.path === 'isolated-execution.json'), 'Reused cost has current isolated execution');
  const cost = checkCostObservation({collectionBytes: await zip.read('collection-costs.json'),
    certificate, state, catalog, acquisition, comparison, receipts,
    isolatedExecution: reused ? null : await zip.json('isolated-execution.json')});
  return {authority: 'offline-bound-cost-observation', reuseAuthorized: false,
    catalogDigest: certificate.catalogDigest, cost,
    runner: {complete: false, reason: 'missing-attempt-timing', selectedJobMilliseconds: null,
      attemptRunnerMilliseconds: null}, netRunnerSavingsMilliseconds: null};
}

export function bindSessionRunnerCosts(sample, timing) {
  const projection = sample.sessionCosts, owner = projection.cost.producerOwner;
  const selected = timing.measurements.filter(row => row.kind === 'job' &&
    row.repository === sample.provenance.repository && row.runId === owner.runId && row.attempt === owner.runAttempt);
  const producers = selected.filter(row => row.jobId === owner.jobId);
  assert(producers.length <= 1, 'Duplicate cost producer');
  if (producers.length) assert.equal(producers[0].jobName, 'session-evidence', 'Cost producer is another job');
  const finals = selected.filter(row => row.jobName === 'check');
  assert(finals.length <= 1, 'Ambiguous cost final owner');
  const total = timing.runnerConsumption.find(row => row.repository === sample.provenance.repository &&
    row.runId === owner.runId && row.attempt === owner.runAttempt);
  const jobs = [...producers, ...finals];
  assert(new Set(jobs.map(row => row.jobId)).size === jobs.length, 'Cost jobs counted twice');
  for (const job of jobs) assert.equal(job.sourceSha, sample.provenance.headSha, 'Wrong cost job head');
  const measured = jobs.length === 2 && jobs.every(row => row.identityValid &&
    row.status === 'completed' && row.conclusion === 'success' && row.execution.seconds !== null) &&
    total?.successfulSample && total.totalJobSeconds !== null;
  const milliseconds = seconds => {
    const value = Math.round(seconds * 1000);
    assert(Number.isSafeInteger(value) && value >= 0, 'Invalid enclosing cost duration');
    return value;
  };
  projection.runner = {complete: !!measured,
    reason: measured ? null : jobs.length !== 2 ? 'missing-producer-or-final-job' : 'incomplete-successful-attempt',
    producer: producers[0] ?? null, final: finals[0] ?? null,
    selectedJobMilliseconds: measured ? milliseconds(jobs.reduce((sum, row) => sum + row.execution.seconds, 0)) : null,
    attemptRunnerMilliseconds: measured ? milliseconds(total.totalJobSeconds) : null,
    observedJobWallSpan: total?.observedJobWallSpan ?? null,
    boundary: 'distinct producer and final job intervals, including their setup, transfer and verification',
    nestedPhasesAdded: false};
  // These are independently observed enclosing costs, not a counterfactual.
  // Original elapsed time and partial phase sums never become net savings.
  projection.netRunnerSavingsMilliseconds = null;
  return projection;
}

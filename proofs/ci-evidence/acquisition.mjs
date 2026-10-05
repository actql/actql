// Limited execution policy: main remains fresh; only mutations-js can reuse a
// completed main comparison accepted by the actual final consumer.
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {encode} from '../bounded-session/action-inputs.mjs';
import {hash} from './inputs.mjs';
import {unavailableTransport} from './transport.mjs';

export const acquisitionVersion = 'actql-verification-family-acquisition/0.1';
const same = (a, b) => encode(a) === encode(b);
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort());
const reasons = ['ordinary-fresh', 'main-fresh', 'comparison-not-ready', 'acceptance-unavailable', 'comparison-period-pending', 'verified-main-comparison'];

export async function acquisitionPlan({context, catalog, comparison, event, readReady}) {
  assert(same(comparison.context, context) && comparison.reuseAuthorized === false);
  assert.equal(comparison.catalogDigest, hash(encode(catalog)));
  assert.deepEqual(comparison.actions.map(entry => entry.actionId), catalog.actions.map(action => action.id));
  const plan = {version: acquisitionVersion, context, catalogDigest: hash(encode(catalog)),
    actions: comparison.actions.map(entry => ({actionId: entry.actionId, acquisition: 'fresh',
      candidateActionKey: entry.candidateActionKey, reason: ['push', 'workflow_dispatch'].includes(event) ? 'main-fresh' : 'ordinary-fresh', origin: null})),
    milliseconds: 0};
  if (event !== 'pull_request') return plan;
  const entry = comparison.actions.find(value => value.actionId === 'mutations-js');
  const decision = plan.actions.find(value => value.actionId === 'mutations-js');
  if (!decision) return plan;
  decision.reason = 'comparison-not-ready';
  if (!entry.closed || !entry.equal || entry.status !== 'closed-inputs-match' || !entry.origin || !comparison.artifact) return plan;
  const started = performance.now();
  let accepted;
  try { accepted = await readReady(); }
  catch (error) {
    if (!unavailableTransport(error)) throw error;
    decision.reason = 'acceptance-unavailable'; plan.milliseconds = Math.round(performance.now() - started); return plan;
  }
  plan.milliseconds = Math.round(performance.now() - started);
  const ready = accepted.ready.find(value => value.actionId === 'mutations-js');
  decision.reason = 'comparison-period-pending';
  if (!ready) return plan;
  assert.equal(ready.actionKey, entry.origin.actionKey);
  assert.equal(ready.receiptDigest, entry.origin.receiptDigest);
  assert.equal(ready.scientificDigest, entry.origin.scientificDigest);
  decision.acquisition = 'reused'; decision.reason = 'verified-main-comparison';
  decision.origin = {revision: entry.origin.revision, runId: entry.origin.runId, runAttempt: entry.origin.runAttempt,
    actionKey: entry.origin.actionKey, receiptDigest: entry.origin.receiptDigest, scientificDigest: ready.scientificDigest,
    artifactId: comparison.artifact.id, archiveDigest: comparison.artifact.digest.replace(/^sha256:/u, ''),
    acceptanceArtifactId: accepted.artifactId, acceptanceArchiveDigest: accepted.archiveDigest};
  return plan;
}

// Reused evidence is mandatory after an action was omitted. Its later outage
// must fail this check; only decisions made before execution can fall back.
export async function verifyAcquisition({plan, context, catalog, comparison, event, readReady}) {
  exact(plan, ['version', 'context', 'catalogDigest', 'actions', 'milliseconds']);
  assert.equal(plan.version, acquisitionVersion); assert(same(plan.context, context));
  assert.equal(plan.catalogDigest, hash(encode(catalog)));
  assert(Number.isSafeInteger(plan.milliseconds) && plan.milliseconds >= 0);
  assert.deepEqual(plan.actions.map(entry => entry.actionId), catalog.actions.map(action => action.id), 'Incomplete acquisition inventory');
  for (const [index, entry] of plan.actions.entries()) {
    exact(entry, ['actionId', 'acquisition', 'candidateActionKey', 'reason', 'origin']);
    assert.equal(entry.candidateActionKey, comparison.actions[index].candidateActionKey);
    assert(['fresh', 'reused'].includes(entry.acquisition) && reasons.includes(entry.reason));
    if (entry.acquisition === 'fresh') assert(entry.origin === null && entry.reason !== 'verified-main-comparison');
    else assert(entry.actionId === 'mutations-js' && event === 'pull_request' && entry.reason === 'verified-main-comparison', 'Unreviewed reusable action');
  }
  if (!plan.actions.some(entry => entry.acquisition === 'reused')) return plan;
  // Do not use the producer's carried authorization as the replay input.
  // Read the retained immutable evidence again and authenticate live API IDs.
  const accepted = await readReady();
  const replay = await acquisitionPlan({context, catalog, comparison, event, readReady: async () => accepted});
  for (const entry of plan.actions.filter(value => value.acquisition === 'reused')) {
    assert(same(entry, replay.actions.find(value => value.actionId === entry.actionId)), 'Changed/invalid reused applicability');
  }
  return plan;
}

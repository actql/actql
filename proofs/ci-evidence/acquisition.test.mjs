import test from 'node:test';
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog} from './actions.mjs';
import {hash} from './inputs.mjs';
import {acquisitionPlan, verifyAcquisition} from './acquisition.mjs';
import {ArtifactUnavailable} from './transport.mjs';

function fixture() {
  const catalog = readCatalog();
  const context = {candidateRevision: 'b'.repeat(40), runId: 30, runAttempt: 1};
  const origin = {revision: 'a'.repeat(40), runId: 3, runAttempt: 2, actionKey: 'c'.repeat(64),
    receiptDigest: 'd'.repeat(64), scientificDigest: 'e'.repeat(64)};
  const comparison = {context, catalogDigest: hash(encode(catalog)), reuseAuthorized: false,
    artifact: {id: 6, digest: `sha256:${'f'.repeat(64)}`},
    actions: catalog.actions.map(action => ({actionId: action.id, candidateActionKey: 'c'.repeat(64),
      status: action.id === 'mutations-js' ? 'closed-inputs-match' : 'same-inputs-open',
      closed: action.id === 'mutations-js', equal: true, origin}))};
  const accepted = {artifactId: 7, archiveDigest: '1'.repeat(64),
    ready: [{actionId: 'mutations-js', actionKey: origin.actionKey, receiptDigest: origin.receiptDigest, scientificDigest: origin.scientificDigest}]};
  return {catalog, context, comparison, event: 'pull_request', readReady: async () => accepted, accepted};
}

test('a completed comparison selects only the registered JS action and retains every other obligation', async () => {
  const f = fixture(), plan = await acquisitionPlan(f), before = encode(f.comparison);
  assert.equal(plan.actions.length, f.catalog.actions.length);
  assert.deepEqual(plan.actions.filter(entry => entry.acquisition === 'reused').map(entry => entry.actionId), ['mutations-js']);
  assert(plan.actions.filter(entry => entry.actionId !== 'mutations-js').every(entry => entry.acquisition === 'fresh'));
  await verifyAcquisition({plan, ...f}); assert.equal(encode(f.comparison), before);
});

for (const event of ['push', 'workflow_dispatch']) test(`${event} is always fresh and never requests comparison authorization`, async () => {
  const plan = await acquisitionPlan({...fixture(), event, readReady: async () => { assert.fail('Main must execute fresh'); }});
  assert(plan.actions.every(entry => entry.acquisition === 'fresh' && entry.origin === null));
  assert(plan.actions.every(entry => entry.reason === 'main-fresh'));
});

test('changed, unknown, partial or missing input comparisons execute fresh without consulting ready labels', async () => {
  for (const change of [
    f => f.comparison.actions.find(entry => entry.actionId === 'mutations-js').closed = false,
    f => f.comparison.actions.find(entry => entry.actionId === 'mutations-js').equal = false,
    f => f.comparison.actions.find(entry => entry.actionId === 'mutations-js').status = 'origin-receipt-unavailable',
    f => f.comparison.artifact = null,
  ]) {
    const f = fixture(); change(f);
    const plan = await acquisitionPlan({...f, readReady: async () => { assert.fail('Unready inputs cannot authorize reuse'); }});
    assert(plan.actions.every(entry => entry.acquisition === 'fresh'));
  }
});

test('missing, expired or unavailable acceptance falls back before execution; corrupt identity is rejected', async () => {
  for (const error of [new ArtifactUnavailable(), new DOMException('timeout', 'TimeoutError')]) {
    const f = fixture(), plan = await acquisitionPlan({...f, readReady: async () => { throw error; }});
    assert(plan.actions.every(entry => entry.acquisition === 'fresh'));
    assert.equal(plan.actions.find(entry => entry.actionId === 'mutations-js').reason, 'acceptance-unavailable');
    // A later recovery cannot retroactively turn this fresh run into a skip.
    await verifyAcquisition({plan, ...f});
  }
  await assert.rejects(acquisitionPlan({...fixture(), readReady: async () => { throw new Error('Archive digest mismatch'); }}), /digest/u);
});

test('a comparison period without final confirmation remains fresh; scientific/input bindings cannot be swapped', async () => {
  const f = fixture(); f.accepted.ready = [];
  assert((await acquisitionPlan(f)).actions.every(entry => entry.acquisition === 'fresh'));
  for (const field of ['actionKey', 'receiptDigest', 'scientificDigest']) {
    const changed = fixture(); changed.accepted.ready[0][field] = '9'.repeat(64);
    await assert.rejects(acquisitionPlan(changed));
  }
});

test('a skipped action requires live original acceptance at final check; availability cannot promote to success', async () => {
  const f = fixture(), plan = await acquisitionPlan(f);
  await assert.rejects(verifyAcquisition({plan, ...f, readReady: async () => { throw new ArtifactUnavailable(); }}));
  const changed = structuredClone(f.accepted); changed.artifactId++;
  await assert.rejects(verifyAcquisition({plan, ...f, readReady: async () => changed}), /Changed\/invalid/u);
});

test('omission, duplicate scope, main reuse, wrong owner and forged authorization cannot bypass final inventory', async () => {
  const f = fixture(), plan = await acquisitionPlan(f);
  for (const change of [
    value => value.actions.pop(),
    value => value.actions[0] = value.actions.find(entry => entry.acquisition === 'reused'),
    value => value.context.runAttempt++,
    value => value.actions.find(entry => entry.acquisition === 'reused').candidateActionKey = '9'.repeat(64),
    value => value.actions.find(entry => entry.acquisition === 'reused').origin.runAttempt++,
  ]) {
    const changed = structuredClone(plan); change(changed);
    await assert.rejects(verifyAcquisition({plan: changed, ...f}));
  }
  await assert.rejects(verifyAcquisition({plan, ...f, event: 'push'}));
});

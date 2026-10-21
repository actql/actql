import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';
import {readFileSync} from 'node:fs';
import {originalSubmission, readySubmissionAttempt, submissionEpoch} from './submission-fixture.mjs';

// Count completed SDK wire-admission passes, not transport copies, cheap
// identity comparisons, nested validator entries, or cache hits. The wrappers
// always invoke the unchanged real validator and maintain no result cache.
const admissions = new Map();
const counterKey = Symbol.for('actql.sdk.operation-validation.test');
globalThis[counterKey] = admissions;
const names = ['validClientAdmission', 'validSubmissionAttempt', 'validSubmissionLookup',
  'validRequestLookup', 'validRequestCancellation', 'validCancellationAttempt',
  'validCancellationLookup', 'validDeliveryAttemptLookup', 'validCheckOutcome'];
const wireUrl = new URL('../client-wire/index.mjs', import.meta.url).href;
const wrapper = `import * as wire from ${JSON.stringify(wireUrl)};
export * from ${JSON.stringify(wireUrl)};
${names.map(name => `export function ${name}(...args) {
  const result = wire.${name}(...args);
  const counts = globalThis[Symbol.for('actql.sdk.operation-validation.test')];
  counts.set('${name}', (counts.get('${name}') ?? 0) + 1);
  return result;
}`).join('\n')}`;
const wrapperUrl = `data:text/javascript,${encodeURIComponent(wrapper)}`;
const hook = registerHooks({resolve(specifier, context, nextResolve) {
  if (specifier === '@actql/client-wire' && context.parentURL?.includes('/packages/sdk/')) {
    return {url: wrapperUrl, shortCircuit: true};
  }
  return nextResolve(specifier, context);
}});
const sdk = await import('./index.mjs');
hook.deregister();

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const cancelRef = {...ref, cancelId: 'cancel', expectedRevision: 6};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const admission = {ref, durability: 'durable', revision: 1};
const delivered = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const checked = JSON.parse(readFileSync(new URL('../client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));

async function fixture(t, respond) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return admission;
      return respond(operation, body);
    },
  });
  t.after(() => client.close());
  return {client, calls};
}
const assertPasses = expected => assert.deepEqual(Object.fromEntries(admissions), expected);

test('ready submit admits its envelope once and constructs a Run without readmission', async t => {
  const f = await fixture(t, (_operation, body) => readySubmissionAttempt(body, admission));
  admissions.clear();
  const run = await f.client.start({}, {submissionRef: originalSubmission('original')});
  assert.deepEqual(run.ref, ref);
  assertPasses({validSubmissionAttempt: 1});
  const before = new Map(admissions);
  run.result('answer');
  sdk.explainSubmission(run);
  sdk.getSubmissionInput(run);
  assert.deepEqual(admissions, before);
  assert.deepEqual(f.calls, ['connect', 'submit-intent']);
});

test('attach validates one admission and pure handle access performs no admission', async t => {
  const f = await fixture(t);
  admissions.clear();
  const run = await f.client.attach(ref);
  assertPasses({validClientAdmission: 1});
  admissions.clear();
  assert.deepEqual(run.ref, ref);
  run.result('answer');
  assertPasses({});
  assert.deepEqual(f.calls, ['connect', 'attach']);
});

for (const [name, validator, reply, invoke] of [
  ['request lookup', 'validRequestLookup', {kind: 'found', requestId: 'saved', ref,
    durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'},
  f => f.client.lookupRequest('saved')],
  ['request cancel', 'validRequestCancellation', {kind: 'accepted', requestId: 'saved', ref, revision: 7},
  f => f.client.cancelRequest('saved')],
  ['submission lookup', 'validSubmissionLookup', {kind: 'preparing',
    submissionRef: originalSubmission('original'), intentCid: cid('c')},
  f => f.client.lookupSubmission(originalSubmission('original'))],
  ['cancel', 'validCancellationAttempt', {kind: 'accepted',
    attemptRef: {operation: 'cancel', attemptId: 'attempt'},
    cancellation: {kind: 'accepted', ref, cancelRef, revision: 7}},
  f => f.run.cancel({cancelId: 'cancel', expectedRevision: 6, attemptId: 'attempt'})],
  ['cancel lookup', 'validCancellationLookup', {kind: 'found',
    cancellation: {kind: 'accepted', ref, cancelRef, revision: 7}},
  f => f.run.lookupCancellation(cancelRef)],
  ['delivery lookup', 'validDeliveryAttemptLookup', delivered,
  f => f.run.result('answer').deliveryAttempt('read-a')],
  ['static check', 'validCheckOutcome', checked,
  f => f.client.check('SELECT 1 AS n', {kind: 'text', scope: 'bound_input', format: 'sql'})],
]) {
  test(`${name} admits one captured reply and no repeated verification`, async t => {
    const f = await fixture(t, () => reply);
    f.run = await f.client.attach(ref);
    admissions.clear();
    const answer = await invoke(f);
    assertPasses({[validator]: 1});
    assert.equal(Object.isFrozen(answer), true);
    const before = new Map(admissions);
    sdk.explainSubmission(answer);
    sdk.explainCancellation(answer);
    sdk.explainRequestLookup(answer);
    sdk.explainDeliveryAttempt(answer);
    assert.deepEqual(admissions, before);
    assert.equal(f.calls.length, 3);
  });
}

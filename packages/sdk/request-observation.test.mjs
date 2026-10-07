import assert from 'node:assert/strict';
import test from 'node:test';
import {mock} from 'node:test';
import {inspect} from 'node:util';
import * as sdk from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const checkpoint = {checkpointId: 'checkpoint', checkpointCid: cid('c'), kind: 'run_scope',
  expiresAt: '2099-01-01T00:00:00.000Z'};
const held = state => ({kind: 'held', requestId: 'saved', prepareAttemptId: 'preparation',
  state, durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  ...(state === 'waiting_checkpoint' ? {checkpoint: {...checkpoint}} : {}),
  ...(state === 'ended' ? {endReason: 'private-provider-text', terminalErrorCode: 'private-terminal-code'} : {})});
async function fixture(t, reply) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'lookup-request' || operation === 'submit' || operation === 'cancel-request') return reply;
      assert.fail('Unexpected operation');
    },
  });
  t.after(() => client.close());
  return {client, calls};
}
const next = {operation: 'lookupRequest', requestId: 'saved',
  lookupContext: {endpoint: 'actql:embedded', scopeRef: 'scope'}};
const summaries = {
  lookup_unresolved: 'This lookup does not establish whether the submission was accepted.',
  lookup_unavailable: 'The Host could not supply a request lookup observation. Acceptance remains unresolved.',
  run_reference_received: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
  waiting_checkpoint: 'The Host durably holds this request while preparation waits for a Checkpoint. No Run reference was returned.',
  resuming: 'The Host reports that preparation of this held request is resuming. No Run reference was returned.',
  ended: 'The Host reports that preparation of this held request ended. No Run reference was returned.',
};
// Independent wire fixtures prove SDK admission/projection, not Owner transitions.
for (const [label, reply, observation] of [
  ['absent', {kind: 'not_found'}, 'lookup_unresolved'],
  ['unknown', {kind: 'unknown', reason: 'private-store-cause'}, 'lookup_unavailable'],
  ['found', {kind: 'found', requestId: 'saved', ref, durability: 'durable',
    lookupExpiresAt: '2099-01-01T00:00:00.000Z'}, 'run_reference_received'],
  ...['waiting_checkpoint', 'resuming', 'ended'].map(state => [state, held(state), 'request_held']),
]) {
  test(`request observation retains ${label} without inferring execution or resend permission`, async t => {
    const f = await fixture(t, reply), answer = await f.client.lookupRequest('saved');
    assert.equal(typeof sdk.explainRequestLookup, 'function', '[check-mutation:request-observation-classification]');
    const explanation = sdk.explainRequestLookup(answer);
    assert.equal(explanation.observation, observation, '[check-mutation:request-observation-classification]');
    assert.equal(explanation.summary, summaries[reply.state ?? observation]);
    assert.deepEqual(explanation.next, label === 'found' ? {operation: 'status', ref} : next);
    if (reply.kind === 'held') {
      assert.equal(explanation.preparationState, reply.state);
      assert.equal(explanation.prepareAttemptId, 'preparation');
      assert.equal(explanation.durability, 'durable');
    }
    for (const field of ['runStatus', 'accepted', 'notAccepted', 'stopped', 'cleanupComplete', 'permission', 'reason', 'endReason', 'terminalErrorCode']) {
      assert.equal(Object.hasOwn(explanation, field), false);
    }
    assert.equal(sdk.explainRequestLookup(structuredClone(answer)), undefined, '[check-mutation:request-observation-custody]');
    assert.equal(sdk.getSubmissionInput(answer), undefined);
    const before = [...f.calls];
    for (const locale of ['en', 'ja']) for (const format of ['text', 'html', 'json']) {
      const text = sdk.formatRequestLookup(answer, {locale, format}); assert.ok(text);
      assert.doesNotMatch(text, /private-store-cause|private-provider-text|private-terminal-code/u);
      if (format === 'json') {
        const {summary, hint, ...facts} = JSON.parse(text).explanation;
        const {summary: original, hint: originalHint, ...expected} = explanation;
        assert.deepEqual(facts, expected);
        if (locale === 'ja') assert.notEqual(summary, original);
      }
    }
    assert.deepEqual(f.calls, before);
    assert.equal(Object.isFrozen(explanation.next), true);
  });
}
test('request lookup snapshots detach a reused held checkpoint', async t => {
  const reply = held('waiting_checkpoint'), f = await fixture(t, reply);
  const first = await f.client.lookupRequest('saved');
  assert.equal(Object.isFrozen(reply), false, '[check-mutation:request-lookup-detached]');
  reply.checkpoint.checkpointId = 'later';
  assert.equal(first.checkpoint.checkpointId, 'checkpoint', '[check-mutation:request-lookup-snapshot]');
  reply.state = 'ended'; reply.endReason = 'cancelled';
  const second = await f.client.lookupRequest('saved');
  assert.equal(first.state, 'waiting_checkpoint');
  assert.equal(Object.isFrozen(first.checkpoint), true, '[check-mutation:request-lookup-freeze]');
  assert.equal(second.state, 'ended');
});
for (const fault of ['clone changes a field', 'reply cannot be cloned']) {
  test(`request lookup rejects ${fault}`, async t => {
    const f = await fixture(t, held('waiting_checkpoint'));
    const original = globalThis.structuredClone;
    mock.method(globalThis, 'structuredClone', value => {
      if (value?.kind !== 'held') return original(value);
      if (fault === 'reply cannot be cloned') throw new Error('private-clone-cause');
      return {...original(value), requestId: 'foreign'};
    });
    t.after(() => mock.restoreAll());
    let failure;try {await f.client.lookupRequest('saved');} catch (error) {failure = error;}
    assert.equal(failure?.code, 'InvalidHostRequestLookup', '[check-mutation:request-lookup-admission]');
    assert.equal(sdk.explainRequestLookup(failure).observation, 'lookup_uninterpretable');
    assert.deepEqual(sdk.explainRequestLookup(failure).next, next);
  });
}
test('held submit explanations retain the admitted preparation state', async t => {
  const reply = held('waiting_checkpoint'), f = await fixture(t, reply);
  let failure;try {await f.client.start({params: {}, stages: []}, {requestId: 'saved'});} catch (error) {failure = error;}
  assert.ok(failure instanceof sdk.RequestHeld);
  const explanation = sdk.explainSubmission(failure);
  assert.equal(explanation.preparationState, 'waiting_checkpoint', '[check-mutation:request-held-state]');
  assert.equal(explanation.summary, summaries.waiting_checkpoint);
  assert.deepEqual(explanation.next, next);
  reply.checkpoint.checkpointId = 'later';
  assert.equal(failure.held.checkpoint.checkpointId, 'checkpoint');
  assert.deepEqual(f.calls, ['connect', 'submit']);
});
for (const fault of ['held clone changes its admitted branch', 'held reply cannot be cloned']) {
  test(`submission uncertainty retains original lookup when ${fault}`, async t => {
    const f = await fixture(t, held('waiting_checkpoint'));
    const original = globalThis.structuredClone;
    mock.method(globalThis, 'structuredClone', value => {
      if (value?.kind !== 'held') return original(value);
      if (fault === 'held reply cannot be cloned') throw new Error('private-clone-cause');
      return {ref, durability: 'durable', revision: 1};
    });
    t.after(() => mock.restoreAll());
    let failure;try {await f.client.start({params: {}, stages: []}, {requestId: 'saved'});} catch (error) {failure = error;}
    assert.equal(failure?.code, 'SubmissionUnknown', '[check-mutation:request-held-admission]');
    assert.equal(failure instanceof sdk.RequestHeld, false);
    assert.equal(sdk.explainSubmission(failure).observation, 'acceptance_unknown');
    assert.deepEqual(sdk.explainSubmission(failure).next, next);
    assert.equal(sdk.getSubmissionInput(failure).requestId, 'saved');
    assert.deepEqual(f.calls, ['connect', 'submit']);
  });
}
for (const [label, reply] of [
  ['unknown branch', {kind: 'succeeded', requestId: 'saved', permission: 'submit'}],
  ['malformed held branch', {...held('waiting_checkpoint'), checkpoint: undefined}],
]) {
  test(`request lookup retains an uninterpretable ${label} without admitting its fields`, async t => {
    const f = await fixture(t, reply);
    let failure;try {await f.client.lookupRequest('saved');} catch (error) {failure = error;}
    assert.equal(failure?.code, 'InvalidHostRequestLookup');
    const explanation = sdk.explainRequestLookup(failure);
    assert.equal(explanation.observation, 'lookup_uninterpretable');
    assert.deepEqual(explanation.next, next);
    failure.code = 'Succeeded'; failure.message = 'success';
    assert.deepEqual(sdk.explainRequestLookup(failure), explanation);
    assert.equal(sdk.explainRequestLookup({...failure}), undefined);
    assert.equal(Object.hasOwn(explanation, 'prepareAttemptId'), false);
    assert.equal(Object.hasOwn(explanation, 'permission'), false);
  });
}
test('request lookup retains its original target after a primitive credential failure', async t => {
  let calls = 0, credentials = 0;
  mock.method(globalThis, 'fetch', async () => {calls++; return Response.json({...profile, mode: 'remote', owner: 'remote'});});
  t.after(() => mock.restoreAll());
  const client = await sdk.connect({mode: 'remote', endpoint: 'https://example.test/',
    token() {if (credentials++ === 0) return 'fixture-token'; throw 'private-credential-cause';}});
  t.after(() => client.close());
  let failure;try {await client.lookupRequest('saved');} catch (error) {failure = error;}
  assert.equal(failure.code, 'ClientTransportUnknown');
  const explanation = sdk.explainRequestLookup(failure);
  assert.equal(explanation.observation, 'lookup_unavailable');
  assert.deepEqual(explanation.next, {operation: 'lookupRequest', requestId: 'saved',
    lookupContext: {endpoint: 'https://example.test/', scopeRef: 'scope'}});
  assert.doesNotMatch(sdk.formatRequestLookup(failure, {format: 'json'}), /private-credential-cause/u);
  assert.equal(calls, 1);
});

test('request lookup failures detach a reused credential exception for each call', async t => {
  let credentials = 0, calls = 0;
  const shared = new sdk.ClientError('HostUnavailable', {status: 503, cause: 'private-credential-cause'});
  mock.method(globalThis, 'fetch', async () => {calls++; return Response.json({...profile, mode: 'remote', owner: 'remote'});});
  t.after(() => mock.restoreAll());
  const client = await sdk.connect({mode: 'remote', endpoint: 'https://example.test/',
    token() {if (credentials++ === 0) return 'fixture-token'; throw shared;}});
  t.after(() => client.close());
  let first, second;
  try {await client.lookupRequest('saved');} catch (error) {first = error;}
  try {await client.lookupRequest('later');} catch (error) {second = error;}
  assert.equal(first === shared, false, '[check-mutation:request-failure-custody]');
  assert.notEqual(first, second);
  assert.equal(first.code, 'HostUnavailable');
  assert.equal(first.status, 503);
  assert.equal(first.cause, undefined);
  assert.deepEqual(sdk.explainRequestLookup(first).next, {operation: 'lookupRequest', requestId: 'saved',
    lookupContext: {endpoint: 'https://example.test/', scopeRef: 'scope'}});
  assert.equal(sdk.explainRequestLookup(second).next.requestId, 'later');
  assert.equal(sdk.explainRequestLookup(first).observation, 'lookup_unavailable');
  assert.equal(sdk.explainRequestLookup(shared), undefined);
  shared.code = 'Succeeded';
  assert.equal(first.code, 'HostUnavailable');
  assert.doesNotMatch(sdk.formatRequestLookup(first, {format: 'json'}), /private-credential-cause/u);
  assert.equal(calls, 1);
});

const cancellationSummaries = {
  accepted: 'The Host recorded cancellation of this request. This response does not establish physical stop or resource release.',
  already_requested: 'The Host reports a previously recorded cancellation of this request. This response does not establish physical stop or resource release.',
  already_terminal: 'The Host reports that this request is already terminal. This response does not establish its execution outcome, physical stop or resource release.',
};
// Closed independent wire fixtures, separate from actual Owner acceptance.
for (const kind of ['accepted', 'already_requested', 'already_terminal']) {
  for (const withRun of [false, true]) {
    test(`request cancellation retains ${kind} ${withRun ? 'with Run' : 'without Run'} without stop or release claims`, async t => {
      const reply = {kind, requestId: 'saved', ...(withRun ? {ref: {...ref}, revision: 7} : {})};
      const f = await fixture(t, reply), answer = await f.client.cancelRequest('saved');
      assert.equal(typeof sdk.explainRequestCancellation, 'function', '[check-mutation:request-cancel-classification]');
      const explanation = sdk.explainRequestCancellation(answer);
      assert.equal(explanation.observation, kind, '[check-mutation:request-cancel-classification]');
      assert.equal(explanation.requestId, 'saved');
      assert.equal(explanation.summary, cancellationSummaries[kind]);
      assert.deepEqual(explanation.next, withRun ? {operation: 'status', ref} : next);
      if (withRun) assert.equal(explanation.revision, 7);
      else assert.equal(Object.hasOwn(explanation, 'revision'), false);
      for (const field of ['physicalStop', 'stopped', 'cleanupComplete', 'resourcesReleased', 'runStatus', 'effectOutcome', 'cancelRef', 'permission']) {
        assert.equal(Object.hasOwn(explanation, field), false);
      }
      assert.equal(sdk.explainRequestCancellation(structuredClone(answer)), undefined, '[check-mutation:request-cancel-custody]');
      assert.equal(sdk.getSubmissionInput(answer), undefined);
      const before = [...f.calls];
      for (const locale of ['en', 'ja']) for (const format of ['text', 'html', 'json']) {
        const rendered = sdk.formatRequestCancellation(answer, {locale, format}); assert.ok(rendered);
        if (format === 'json') {
          const {summary, hint, ...facts} = JSON.parse(rendered).explanation;
          const {summary: original, hint: originalHint, ...expected} = explanation;
          assert.deepEqual(facts, expected);
          if (locale === 'ja') assert.notEqual(summary, original);
        }
      }
      assert.deepEqual(f.calls, before);
      assert.equal(Object.isFrozen(answer), true);
    });
  }
}
test('request cancellation snapshots detach reused response and Run references', async t => {
  const reply = {kind: 'accepted', requestId: 'saved', ref: {...ref}, revision: 7};
  const f = await fixture(t, reply), first = await f.client.cancelRequest('saved');
  assert.equal(Object.isFrozen(reply.ref), false, '[check-mutation:request-cancel-detached]');
  reply.ref.runDefinitionCid = cid('d'); reply.revision = 9; reply.kind = 'already_terminal';
  const second = await f.client.cancelRequest('saved');
  assert.equal(first.ref.runDefinitionCid, cid('b'), '[check-mutation:request-cancel-snapshot]');
  assert.equal(first.kind, 'accepted');
  assert.equal(sdk.explainRequestCancellation(first).revision, 7);
  assert.equal(sdk.explainRequestCancellation(second).observation, 'already_terminal');
  assert.deepEqual(sdk.explainRequestCancellation(first).next.ref, ref);
});
for (const fault of ['clone changes request identity', 'clone changes known branch', 'clone changes Run reference', 'clone throws']) {
  test(`request cancellation rejects ${fault}`, async t => {
    const f = await fixture(t, {kind: 'accepted', requestId: 'saved', ref: {...ref}, revision: 7});
    const original = globalThis.structuredClone;
    mock.method(globalThis, 'structuredClone', value => {
      if (value?.kind !== 'accepted') return original(value);
      if (fault === 'clone throws') throw new Error('private-clone-cause');
      const copy = original(value);
      if (fault === 'clone changes request identity') copy.requestId = 'foreign';
      else if (fault === 'clone changes known branch') copy.kind = 'already_terminal';
      else copy.ref.runDefinitionCid = cid('d');
      return copy;
    });
    t.after(() => mock.restoreAll());
    let failure;try {await f.client.cancelRequest('saved');} catch (error) {failure = error;}
    assert.equal(failure?.code, 'CancellationUnknown', '[check-mutation:request-cancel-admission]');
    const explanation = sdk.explainRequestCancellation(failure);
    assert.equal(explanation.observation, 'outcome_unknown');
    assert.equal(explanation.problem, 'response_uninterpretable');
    assert.deepEqual(explanation.next, next);
    assert.equal(Object.hasOwn(explanation, 'revision'), false);
    assert.equal(sdk.explainRequestCancellation({...failure}), undefined);
    assert.doesNotMatch(sdk.formatRequestCancellation(failure, {format: 'json'}), /private-clone-cause/u);
  });
}
for (const reply of [{kind: 'succeeded', requestId: 'saved'}, {kind: 'accepted', requestId: 'saved', revision: 7}]) {
  test(`request cancellation admits no facts from ${reply.kind === 'succeeded' ? 'unknown' : 'malformed known'} reply`, async t => {
    const f = await fixture(t, reply);
    let failure;try {await f.client.cancelRequest('saved');} catch (error) {failure = error;}
    assert.equal(failure.code, 'CancellationUnknown');
    const explanation = sdk.explainRequestCancellation(failure);
    assert.equal(explanation.observation, 'outcome_unknown');
    assert.equal(explanation.problem, 'response_uninterpretable');
    assert.deepEqual(explanation.next, next);
    failure.code = 'Succeeded'; failure.message = 'success';
    assert.deepEqual(sdk.explainRequestCancellation(failure), explanation);
    assert.equal(Object.hasOwn(explanation, 'revision'), false);
  });
}
test('request cancellation failures detach reused credential errors without choosing outcome from their codes', async t => {
  let credentials = 0, calls = 0;
  const shared = new sdk.ClientError('ClientConnectionDenied', {status: 403});
  mock.method(globalThis, 'fetch', async () => {calls++; return Response.json({...profile, mode: 'remote', owner: 'remote'});});
  t.after(() => mock.restoreAll());
  const client = await sdk.connect({mode: 'remote', endpoint: 'https://example.test/',
    token() {if (credentials++ === 0) return 'fixture-token'; throw shared;}});
  t.after(() => client.close());
  let first, second;
  try {await client.cancelRequest('saved');} catch (error) {first = error;}
  shared.code = 'Succeeded';
  try {await client.cancelRequest('later');} catch (error) {second = error;}
  assert.equal(first === shared, false, '[check-mutation:request-cancel-failure-custody]');
  assert.notEqual(first, second);
  assert.equal(first.code, 'ClientConnectionDenied');
  assert.equal(first.status, 403);
  assert.equal(first.requestId, undefined);
  assert.equal(sdk.explainRequestCancellation(first).observation, 'outcome_unknown');
  assert.equal(sdk.explainRequestCancellation(first).problem, 'exchange_failed');
  assert.equal(sdk.explainRequestCancellation(first).next.requestId, 'saved');
  assert.equal(sdk.explainRequestCancellation(second).next.requestId, 'later');
  assert.equal(sdk.explainRequestCancellation(shared), undefined);
  assert.equal(calls, 1);
});

test('request cancellation failure keeps safe recovery metadata without borrowed private causes', async t => {
  let credentials = 0;
  const privateCause = Object.assign(new Error('private-credential-secret'), {
    sourceLocator: 'connector://private-credential-secret', cause: new Error('private-credential-secret'),
  });
  mock.method(globalThis, 'fetch', async () => Response.json({...profile, mode: 'remote', owner: 'remote'}));
  t.after(() => mock.restoreAll());
  const client = await sdk.connect({mode: 'remote', endpoint: 'https://example.test/',
    token() {if (credentials++ === 0) return 'fixture-token'; throw privateCause;}});
  t.after(() => client.close());
  let failure;try {await client.cancelRequest('saved');} catch (error) {failure = error;}
  assert.equal(failure.code, 'CancellationUnknown');
  assert.equal(failure.requestId, 'saved');
  assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-credential-secret/u,
    '[check-mutation:request-cancel-private-cause]');
  assert.equal(failure.cause.code, 'ClientTransportUnknown');
  assert.equal(failure.cause.cause, undefined);
  assert.equal(sdk.explainRequestCancellation(failure).problem, 'exchange_failed');
});

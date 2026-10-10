import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {ClientError, RequestHeld, connectInProcess, connect} from './index.mjs';
import {submissionEpoch, originalSubmission, submissionAttempt} from './submission-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = Object.freeze({namespaceId: 'local', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')});
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: cid('a'), capabilities: [], submissionEpoch, limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2,
    maxBatchRetainedValueBytes: 2048}};
const held = {kind: 'held', requestId: 'saved', prepareAttemptId: 'preparation',
  state: 'waiting_checkpoint', durability: 'durable', lookupExpiresAt: '2099-01-01',
  checkpoint: {checkpointId: 'checkpoint', checkpointCid: cid('c'), kind: 'run_scope',
    expiresAt: '2099-01-01'}};
const found = {kind: 'found', requestId: 'saved', ref, durability: 'durable',
  lookupExpiresAt: '2099-01-01'};
const requestTarget = {operation: 'lookupRequest', requestId: 'saved',
  lookupContext: {endpoint: 'actql:embedded', scopeRef: cid('a')}};
const target = {operation: 'lookupSubmission', submissionRef: originalSubmission('saved'),
  lookupContext: {endpoint: 'actql:embedded', scopeRef: cid('a')}};
const admission = {ref, durability: 'durable', revision: 1};
const submissionReply = (value, body) => value.kind === 'held'
  ? {kind: 'held', submissionRef: body.submissionRef, intentCid: body.intentCid ?? cid('e'), held: value}
  : value.ref ? {kind: 'ready', submissionRef: body.submissionRef,
    intentCid: body.intentCid ?? cid('e'), admission: value.kind === 'found' ? admission : value}
  : value;

async function fixture(t, submit = held) {
  const calls = [];
  let reply = held, denial;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body, signal) {
      calls.push({operation, body, signal});
      signal?.throwIfAborted();
      if (operation === 'connect') return profile;
      if (operation === 'submit-intent') return submissionAttempt(body, submissionReply(submit, body));
      if (denial) throw denial;
      if (operation === 'lookup-request') return reply;
      if (operation === 'lookup-submission') return submissionReply(reply, body);
      if (operation === 'attach') return admission;
      if (operation === 'wait') return {version: 'actql-run-state/0.1', run_id: 'run',
        status: 'succeeded', updated_at: '2026-10-07T00:00:00.000Z', result_available: true,
        next_action: {kind: 'read_result', results: ['answer']}, result_availability: {
          answer: {state: 'available', observed_at: '2026-10-07T00:00:00.000Z', reason: 'confirmed_present'}}};
      assert.fail(`Unexpected operation: ${operation}`);
    },
  });
  t.after(() => client.close());
  return {client, calls, reply(value) {reply = value;}, deny(error) {denial = error;}};
}
const operations = f => f.calls.map(call => call.operation);
async function submitted(f) {
  try {return await f.client.start({stages: []}, {submissionRef: originalSubmission('saved')});}
  catch (error) {return error;}
}

test('request recovery preserves held custody and performs only explicit lookup then attach', async t => {
  const f = await fixture(t), original = await submitted(f);
  assert.ok(original instanceof RequestHeld);
  Object.defineProperties(original, {
    requestId: {get() {throw new Error('mutable private field');}},
    lookupContext: {get() {throw new Error('mutable private context');}},
  });
  const recovery = f.client.recoverRequest(original);
  assert.deepEqual(recovery.target, target);
  assert.ok(Object.isFrozen(recovery)); assert.ok(Object.isFrozen(recovery.target.lookupContext));
  assert.deepEqual(operations(f), ['connect', 'submit-intent']);
  const waiting = await recovery.lookup();
  assert.equal(waiting.kind, 'held');
  assert.equal(waiting.held.prepareAttemptId, 'preparation');
  await assert.rejects(recovery.attach(waiting), {code: 'InvalidRequestRecoveryObservation'});
  f.reply(found);
  const observed = await recovery.lookup();
  const execution = await recovery.attach(observed);
  assert.deepEqual(execution.ref, ref);
  assert.deepEqual(operations(f), ['connect', 'submit-intent', 'lookup-submission', 'lookup-submission', 'attach']);
  assert.equal(Object.hasOwn(recovery, 'ref'), false);
  assert.equal(Object.hasOwn(recovery, 'submit'), false);
});

for (const outcome of ['unknown submission', 'received execution']) {
  test(`request recovery obtains ${outcome} only from original SDK custody`, async t => {
    const f = await fixture(t, outcome === 'unknown submission' ? {kind: 'foreign'} : admission);
    const original = await submitted(f);
    if (outcome === 'unknown submission') {
      assert.equal(original.code, 'SubmissionUnknown');
      original.requestId = 'forged'; original.lookupContext = {};
    }
    const recovery = f.client.recoverRequest(original);
    assert.deepEqual(recovery.target, target);
    assert.throws(() => f.client.recoverRequest({...original}), {code: 'InvalidRequestRecoveryTarget'});
    assert.throws(() => f.client.recoverRequest(new RequestHeld(held, target.lookupContext)),
      {code: 'InvalidRequestRecoveryTarget'});
    assert.deepEqual(operations(f), ['connect', 'submit-intent']);
  });
}

test('a genuine short-query Result retains its original request lookup target', async t => {
  const f = await fixture(t, admission);
  const result = await f.client.sql('SELECT 1 AS id', undefined, {submissionRef: originalSubmission('saved')});
  const recovery = f.client.recoverRequest(result);
  assert.deepEqual(recovery.target, target);
  assert.throws(() => f.client.recoverRequest({...result}), {code: 'InvalidRequestRecoveryTarget'});
  assert.deepEqual(operations(f), ['connect', 'submit-intent', 'wait']);
});

test('original lookup observations retain their target but do not seed attachment custody', async t => {
  const f = await fixture(t); f.reply(found);
  const original = await f.client.lookupRequest('saved');
  const recovery = f.client.recoverRequest(original);
  assert.deepEqual(recovery.target, requestTarget);
  await assert.rejects(recovery.attach(original), {code: 'InvalidRequestRecoveryObservation'});
  const observed = await recovery.lookup(), second = f.client.recoverRequest(original);
  for (const value of [original, {...observed}, structuredClone(observed), ref, null, 1]) {
    await assert.rejects(recovery.attach(value), {code: 'InvalidRequestRecoveryObservation'});
  }
  await assert.rejects(second.attach(observed), {code: 'InvalidRequestRecoveryObservation'});
  const other = await fixture(t); other.reply(found);
  const otherObserved = await other.client.recoverRequest(requestTarget).lookup();
  await assert.rejects(recovery.attach(otherObserved), {code: 'InvalidRequestRecoveryObservation'});
  assert.equal(f.calls.filter(call => call.operation === 'attach').length, 0);
  assert.deepEqual((await recovery.attach(observed)).ref, ref);
});

test('saved targets are detached lookup data and never contain inputs or authority', async t => {
  const f = await fixture(t), saved = JSON.parse(JSON.stringify(target));
  const recovery = f.client.recoverRequest(saved);
  saved.requestId = 'changed'; saved.lookupContext.scopeRef = cid('d');
  assert.deepEqual(JSON.parse(JSON.stringify(recovery.target)), target);
  assert.deepEqual(operations(f), ['connect']);
  await recovery.lookup();
  assert.equal(f.calls.at(-1).body.submissionRef.nonce, 'saved');
  assert.deepEqual(Object.keys(recovery.target).sort(), ['lookupContext', 'operation', 'submissionRef']);
});

test('malformed saved targets and forged error properties cannot supply recovery custody', async t => {
  const f = await fixture(t); let reads = 0;
  const accessor = {...target};
  Object.defineProperty(accessor, 'requestId', {enumerable: true, get() {reads++; return 'saved';}});
  const contextGetter = {...target, lookupContext: {endpoint: 'actql:embedded',
    get scopeRef() {reads++; return cid('a');}}};
  const malformed = [undefined, null, 'saved', [], ref, Object.create(target),
    new class {constructor() {Object.assign(this, target);}}(),
    {...target, toJSON() {reads++; return target;}}, {...target, [Symbol('extra')]: true},
    {...target, operation: 'submit'}, {...target, requestId: ''},
    {...target, requestId: 'x'.repeat(257)}, {...target, requestId: 'saved\n'},
    {...target, requestId: {toString() {reads++; return 'saved';}}},
    {...target, lookupContext: {...target.lookupContext, token: 'private'}},
    {...target, lookupContext: {endpoint: 1, scopeRef: cid('a')}},
    {code: 'SubmissionUnknown', requestId: 'saved', lookupContext: target.lookupContext},
    {...target, submissionRef: {nonce: 'saved'}},
    {...target, submissionRef: {epoch: {...submissionEpoch, authenticator: 'invalid'}, nonce: 'saved'}},
    {...target, submissionRef: {epoch: {...submissionEpoch, extra: true}, nonce: 'saved'}},
    {...target, submissionRef: {get epoch() {reads++; return submissionEpoch;}, nonce: 'saved'}},
    {...target, submissionRef: {epoch: {...submissionEpoch, get epochNonce() {reads++; return 'b'.repeat(64);}}, nonce: 'saved'}},
    accessor, contextGetter, new Proxy({}, {ownKeys() {throw new Error('private trap');}})];
  const cycle = {...target}; cycle.lookupContext = cycle; malformed.push(cycle);
  for (const value of malformed) {
    assert.throws(() => f.client.recoverRequest(value), {code: 'InvalidRequestRecoveryTarget'});
  }
  assert.equal(reads, 0); assert.deepEqual(operations(f), ['connect']);
});

test('endpoint and scope mismatches refuse before credential resolution or Host lookup', async t => {
  let credentials = 0, calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {calls++;
    return Response.json({...profile, mode: 'remote', owner: 'remote'});});
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/',
    token() {credentials++; return 'fixture';}});
  t.after(() => client.close());
  for (const context of [{endpoint: 'https://other.example/', scopeRef: cid('a')},
    {endpoint: 'https://host.example/', scopeRef: 'old-principal'},
    {endpoint: 'https://host.example/', scopeRef: cid('d')}]) {
    assert.throws(() => client.recoverRequest({...target, lookupContext: context}),
      {code: 'RequestRecoveryScopeMismatch'});
  }
  assert.equal(credentials, 1); assert.equal(calls, 1);
});

for (const reply of [{kind: 'not_found'}, {kind: 'unknown', reason: 'store_unavailable'},
  {kind: 'held', requestId: 'saved', prepareAttemptId: 'preparation', state: 'ended',
    durability: 'durable', lookupExpiresAt: '2099-01-01', endReason: 'cancelled'}]) {
  test(`request recovery preserves ${reply.kind}/${reply.state ?? ''} without fabricating a Run`, async t => {
    const f = await fixture(t); f.reply(reply);
    const recovery = f.client.recoverRequest(requestTarget), observation = await recovery.lookup();
    assert.deepEqual(observation, reply);
    assert.deepEqual(f.client.recoverRequest(observation).target, requestTarget);
    await assert.rejects(recovery.attach(observation), {code: 'InvalidRequestRecoveryObservation'});
    assert.deepEqual(operations(f), ['connect', 'lookup-request']);
  });
}

test('lookup failures retain existing diagnostics and current authority still decides attach', async t => {
  const f = await fixture(t), recovery = f.client.recoverRequest(target);
  f.reply({kind: 'invalid'});
  let malformed; try {await recovery.lookup();} catch (error) {malformed = error;}
  assert.equal(malformed.code, 'InvalidHostSubmissionLookup');
  assert.deepEqual(f.client.recoverRequest(malformed).target, target);
  f.deny(new ClientError('ClientConnectionDenied'));
  let denied; try {await recovery.lookup();} catch (error) {denied = error;}
  assert.equal(denied.code, 'ClientConnectionDenied');
  assert.deepEqual(f.client.recoverRequest(denied).target, target);
  f.deny(undefined); f.reply(found);
  const observed = await recovery.lookup();
  f.deny(new ClientError('ClientConnectionDenied'));
  await assert.rejects(recovery.attach(observed), {code: 'ClientConnectionDenied'});
  assert.deepEqual(operations(f), ['connect', 'lookup-submission', 'lookup-submission', 'lookup-submission', 'attach']);
});

test('recovery respects Client closure, including a caller trap during target capture', async t => {
  const f = await fixture(t), recovery = f.client.recoverRequest(target);
  const closing = new Proxy({...target}, {ownKeys(value) {void f.client.close(); return Reflect.ownKeys(value);}});
  assert.throws(() => f.client.recoverRequest(closing), {code: 'ClientClosed'});
  assert.throws(() => f.client.recoverRequest(target), {code: 'ClientClosed'});
  await assert.rejects(recovery.lookup(), {code: 'ClientClosed'});
  await assert.rejects(recovery.attach(found), {code: 'ClientClosed'});
  assert.deepEqual(operations(f), ['connect']);
});

test('recovery forwards abort to the existing operation without cancelling or resubmitting', async t => {
  const f = await fixture(t), recovery = f.client.recoverRequest(target);
  const signal = AbortSignal.abort();
  await assert.rejects(recovery.lookup({signal}), {code: 'ClientTransportUnknown'});
  assert.equal(f.calls.at(-1).signal, signal);
  f.reply(found);
  const observed = await recovery.lookup();
  await assert.rejects(recovery.attach(observed, {signal}), {code: 'ClientTransportUnknown'});
  assert.equal(f.calls.at(-1).signal, signal);
  assert.deepEqual(operations(f), ['connect', 'lookup-submission', 'lookup-submission', 'attach']);
});

test('request recovery preserves the complete original epoch across a reconnect', async t => {
  const f = await fixture(t, admission), original = await submitted(f);
  const saved = JSON.parse(JSON.stringify(f.client.recoverRequest(original).target));
  const calls = [];
  const fresh = await connectInProcess({mode: 'local', owner: 'local'}, {perform(op, body) {
    calls.push({op, body});
    if (op === 'connect') return {...profile, submissionEpoch: {...submissionEpoch, epochNonce: 'd'.repeat(64)}};
    if (op === 'lookup-submission') return submissionReply(found, body);
    if (op === 'attach') return admission;
    assert.fail(op);
  }});
  t.after(() => fresh.close());
  const recovery = fresh.recoverRequest(saved);
  saved.submissionRef.epoch.epochNonce = 'f'.repeat(64);
  const observed = await recovery.lookup();
  assert.equal(observed.kind, 'ready');
  assert.deepEqual(calls.at(-1).body.submissionRef, originalSubmission('saved'));
  await recovery.attach(observed);
  assert.deepEqual(calls.map(c => c.op), ['connect', 'lookup-submission', 'attach']);
});

test('request recovery public types retain the existing lookup union and associated ready/found attachment', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL('../../node_modules/typescript/bin/tsc', import.meta.url)),
    '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022',
    fileURLToPath(new URL('./request-recovery.typecheck.mts', import.meta.url))], {stdio: 'inherit'});
});

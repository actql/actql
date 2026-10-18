import assert from 'node:assert/strict';
import test from 'node:test';
import {captureSourcePreparation, sourcePreparationPort} from
  './internal/private-source-preparation.mjs';

// Explicit private-port doubles. These cases establish forwarding and capture
// order only, not an actual installed Source issuer or physical resource loan.
test('private Source forwarding retains the same receiver and original arguments', () => {
  const receipt = {}, input = {}, options = {}, body = {}, packet = {};
  const calls = [];
  const receiver = {
    beforeSourceSnapshot(...args) {calls.push([this, 'before', ...args]); return receipt;},
    bindSourceSnapshot(...args) {calls.push([this, 'snapshot', ...args]);},
    bindSourceRequest(...args) {calls.push([this, 'request', ...args]);},
    finishSourceProducer(...args) {calls.push([this, 'finish', ...args]);},
  };
  const port = {[sourcePreparationPort]: receiver};
  const captured = captureSourcePreparation(port);
  port[sourcePreparationPort] = {};
  for (const name of Object.keys(receiver)) receiver[name] = () => assert.fail('ReplacementCalled');
  assert.equal(captured.beforeSourceSnapshot('aql', input, options), receipt);
  captured.bindSourceSnapshot(receipt, body);
  captured.bindSourceRequest(receipt, body, packet);
  captured.finishSourceProducer(receipt, 'returned');
  assert.deepEqual(calls, [
    [receiver, 'before', 'aql', input, options],
    [receiver, 'snapshot', receipt, body],
    [receiver, 'request', receipt, body, packet],
    [receiver, 'finish', receipt, 'returned'],
  ]);
});

test('unselected ports have no Source preparation connection', () => {
  assert.equal(captureSourcePreparation(undefined), undefined);
  assert.equal(captureSourcePreparation({perform() {}}), undefined);
});

test('private Source capture refuses accessors without invoking them', () => {
  let reads = 0;
  const port = Object.defineProperty({}, sourcePreparationPort,
    {get() {reads++; return {};}});
  assert.throws(() => captureSourcePreparation(port), {code: 'NodeSourceManagedAdmissionUnavailable'});
  const receiver = {bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {}};
  Object.defineProperty(receiver, 'beforeSourceSnapshot', {get() {reads++; return () => ({});}});
  assert.throws(() => captureSourcePreparation({[sourcePreparationPort]: receiver}),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
  assert.equal(reads, 0);
});

test('asynchronous Source admission cannot move the synchronous snapshot past an await', async () => {
  let captures = 0;
  const input = Object.defineProperty({}, 'text', {get() {captures++; return 'original';}});
  let release;
  const pending = new Promise(resolve => {release = resolve;});
  const captured = captureSourcePreparation({[sourcePreparationPort]: {
    beforeSourceSnapshot() {return pending;},
    bindSourceSnapshot() {assert.fail('NoOriginalSnapshot');},
    bindSourceRequest() {assert.fail('NoOriginalPacket');},
    finishSourceProducer() {assert.fail('NoProducerTerminal');},
  }});
  assert.throws(() => captured.beforeSourceSnapshot('aql', input, {}),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
  assert.equal(captures, 0);
  release({});
  await pending;
  assert.equal(captures, 0);
});

test('original Source preparation failure retains its original cleanup handle', () => {
  const cleanupHandle = {}, original = Object.assign(new Error('OriginalPending'), {cleanupHandle});
  const captured = captureSourcePreparation({[sourcePreparationPort]: {
    beforeSourceSnapshot() {throw original;},
    bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {},
  }});
  assert.throws(() => captured.beforeSourceSnapshot('aql', 'original', {}),
    error => error === original && error.cleanupHandle === cleanupHandle);
});

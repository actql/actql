import assert from 'node:assert/strict';
import test from 'node:test';
import {captureSourcePreparation, sourcePreparationPort} from
  './internal/private-source-preparation.mjs';
import {connectInProcess} from './host-port.mjs';
import {submissionEpoch} from './submission-fixture.mjs';
import {createTransport} from './internal/transport.mjs';

// Explicit private-port doubles. These cases establish forwarding and capture
// order only, not an actual installed Source issuer or physical resource loan.
test('private Source forwarding retains the same receiver and original arguments', () => {
  const receipt = {}, input = {}, options = {}, body = {}, packet = {}, publication = {};
  const snapshot = value => {assert.strictEqual(value, input); return body;};
  const calls = [];
  const required = ['beforeSourceSnapshot', 'bindSourceSnapshot', 'bindSourceRequest',
    'finishSourceProducer', 'intentCid', 'captureSourceSnapshot',
    'assertSourceSnapshotCurrent', 'publishSourceSnapshot'];
  const reads = new Map(required.map(name => [name, 0]));
  const originalMethods = {
    captureSourceSnapshot(...args) {calls.push([this, 'capture', ...args]); return args[2](args[1]);},
    assertSourceSnapshotCurrent(...args) {calls.push([this, 'current', ...args]);},
    publishSourceSnapshot(...args) {calls.push([this, 'publish', ...args]);},
    beforeSourceSnapshot(...args) {calls.push([this, 'before', ...args]); return receipt;},
    bindSourceSnapshot(...args) {calls.push([this, 'snapshot', ...args]);},
    bindSourceRequest(...args) {calls.push([this, 'request', ...args]);},
    finishSourceProducer(...args) {calls.push([this, 'finish', ...args]);},
    intentCid(...args) {calls.push([this, 'intent', ...args]); return 'sha256:' + 'a'.repeat(64);},
  };
  const receiver = new Proxy(originalMethods, {getOwnPropertyDescriptor(target, name) {
    if (reads.has(name)) reads.set(name, reads.get(name) + 1);
    return Reflect.getOwnPropertyDescriptor(target, name);
  }});
  const port = {[sourcePreparationPort]: receiver};
  const captured = captureSourcePreparation(port);
  port[sourcePreparationPort] = {};
  for (const name of required) originalMethods[name] = () => assert.fail('ReplacementCalled');
  assert.equal(captured.beforeSourceSnapshot('aql', input, options), receipt);
  captured.assertSourceSnapshotCurrent(receipt);
  assert.strictEqual(captured.captureSourceSnapshot(receipt, input, snapshot), body);
  captured.bindSourceSnapshot(receipt, body);
  captured.publishSourceSnapshot(receipt, body, publication);
  assert.equal(captured.intentCid(receipt, body), 'sha256:' + 'a'.repeat(64));
  captured.bindSourceRequest(receipt, body, packet);
  captured.finishSourceProducer(receipt, 'returned');
  assert.deepEqual(calls, [
    [receiver, 'before', 'aql', input, options, undefined],
    [receiver, 'current', receipt],
    [receiver, 'capture', receipt, input, snapshot],
    [receiver, 'snapshot', receipt, body],
    [receiver, 'publish', receipt, body, publication],
    [receiver, 'intent', receipt, body],
    [receiver, 'request', receipt, body, packet],
    [receiver, 'finish', receipt, 'returned'],
  ]);
  assert.deepEqual([...reads.values()], required.map(() => 1));
});

test('unselected ports have no Source preparation connection', () => {
  assert.equal(captureSourcePreparation(undefined), undefined);
  assert.throws(() => captureSourcePreparation({perform() {}}),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
});

test('structural in-process wire ports gain no Source preparation while selected bindings stay strict', async () => {
  // Controlled wire profile only. No installed capacity, Account, Root or Run
  // is issued by this regression's explicit transport port.
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'required-preparation', capabilities: [],
    submissionEpoch, limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
  {
    let connects = 0;
    const port = {async perform(operation) {
      assert.equal(operation, 'connect'); connects++; return profile;
    }};
    assert.equal(createTransport({wire: {}}, port, () => false).sourcePreparation, undefined);
    const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
    await client.close();
    assert.equal(connects, 1);
  }
  let reads = 0;
  for (const selection of ['inherited', 'accessor', 'undefined', 'promise']) {
    let connects = 0;
    const port = {async perform() {connects++; return profile;}};
    if (selection === 'inherited') Object.setPrototypeOf(port, {
      [sourcePreparationPort]: {beforeSourceSnapshot() {assert.fail('InheritedReceiver');}},
    });
    else if (selection === 'accessor') Object.defineProperty(port, sourcePreparationPort,
      {get() {reads++; return {};}});
    else Object.defineProperty(port, sourcePreparationPort,
      {value: selection === 'promise' ? Promise.resolve({}) : undefined});
    const observed = await connectInProcess({mode: 'local', owner: 'local'}, port)
      .then(client => ({client}), error => ({error}));
    if (observed.client) await observed.client.close();
    assert.equal(observed.error?.code, 'NodeSourceManagedAdmissionUnavailable');
    assert.equal(connects, 0);
  }
  assert.equal(reads, 0);
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
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return pending;},
    bindSourceSnapshot() {assert.fail('NoOriginalSnapshot');},
    bindSourceRequest() {assert.fail('NoOriginalPacket');},
    finishSourceProducer() {assert.fail('NoProducerTerminal');},
    intentCid() {assert.fail('NoIntent');},
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
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {throw original;},
    bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {},
    intentCid() {assert.fail('NoIntent');},
  }});
  assert.throws(() => captured.beforeSourceSnapshot('aql', 'original', {}),
    error => error === original && error.cleanupHandle === cleanupHandle);
});

test('a selected Source receiver cannot omit the original intent identity operation', () => {
  const receiver = {
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {}, bindSourceSnapshot() {},
    bindSourceRequest() {}, finishSourceProducer() {}};
  assert.throws(() => captureSourcePreparation({[sourcePreparationPort]: receiver}),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
});

test('Source intent identity refuses asynchronous or malformed observations without assimilation', async () => {
  let observed, reads = 0;
  const captured = captureSourcePreparation({[sourcePreparationPort]: {
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {}, bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {},
    intentCid() {return observed;},
  }});
  for (observed of [undefined, 'sha256:short', Object.defineProperty({}, 'then',
    {get() {reads++;}}), Promise.reject(new Error('OriginalIntentIdentityPending'))]) {
    assert.throws(() => captured.intentCid({}, {}), {code: 'NodeSourceManagedAdmissionUnavailable'});
  }
  await Promise.resolve();
  assert.equal(reads, 0);
});


test('native snapshot fence captures the original required receipt method and refuses accessor or async replacements', async () => {
  const receipt = {}, calls = [];
  const receiver = {
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {}, bindSourceSnapshot() {}, bindSourceRequest() {},
    finishSourceProducer() {}, intentCid() {},
    assertSourceSnapshotCurrent(actual) {assert.equal(this, receiver);assert.equal(actual, receipt);calls.push(actual);}};
  const captured = captureSourcePreparation({[sourcePreparationPort]: receiver});
  receiver.assertSourceSnapshotCurrent = () => assert.fail('ReplacedSnapshotCurrent');
  captured.assertSourceSnapshotCurrent(receipt);
  assert.deepEqual(calls, [receipt]);
  let reads = 0;
  Object.defineProperty(receiver, 'assertSourceSnapshotCurrent', {get() {reads++;}});
  assert.throws(() => captureSourcePreparation({[sourcePreparationPort]: receiver}),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
  assert.equal(reads, 0);
  let release;
  const pending = new Promise(resolve => {release = resolve;});
  const asyncReceiver = {
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {}, bindSourceSnapshot() {}, bindSourceRequest() {},
    finishSourceProducer() {}, intentCid() {}, assertSourceSnapshotCurrent() {return pending;}};
  const asyncCaptured = captureSourcePreparation({[sourcePreparationPort]: asyncReceiver});
  assert.throws(() => asyncCaptured.assertSourceSnapshotCurrent(receipt),
    {code: 'NodeSourceManagedAdmissionUnavailable'});
  release(); await pending;
});

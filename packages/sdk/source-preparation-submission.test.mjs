import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess, getSubmissionInput, getSubmissionOutcome} from './index.mjs';
import {sourcePreparationPort} from './internal/private-source-preparation.mjs';
import {freezeInput} from './internal/data.mjs';
import {submissionEpoch, originalSubmission, readySubmissionAttempt} from './submission-fixture.mjs';

// Explicit Source receiver/Host doubles; these tests do not issue operational
// capacity. The real installed owner must authenticate every original receipt.
const cid = value => 'sha256:' + value.repeat(64);
const admission = {ref: {namespaceId: 'source-receiver', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')}, durability: 'volatile', revision: 0};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'source-receiver', capabilities: ['aql-document'],
  submissionEpoch, limits: {maxReadWireBytes: 256, maxRowWireBytes: 128,
    maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 1024}};

async function fixture(receiver, perform) {
  // Explicit metadata-only Source double; no canonical-identity proof or
  // operational supplier is inferred from this synthetic response.
  const port = {[sourcePreparationPort]: receiver, async perform(operation, packet) {
    if (operation === 'connect') return profile;
    return perform(operation, packet);
  }};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  return {client, port};
}

test('selected Local Source rejects incomplete required methods before connect or caller access', async () => {
  for (const method of ['captureSourceSnapshot', 'assertSourceSnapshotCurrent', 'publishSourceSnapshot']) {
    for (const form of ['missing', 'inherited', 'accessor', 'undefined', 'nonfunction']) {
      let reads = 0, connects = 0, entries = 0;
      const receiver = {
        beforeSourceSnapshot() {entries++; return {};},
        captureSourceSnapshot(_receipt, value, snapshot) {entries++; return snapshot(value);},
        assertSourceSnapshotCurrent() {entries++;},
        bindSourceSnapshot() {entries++;}, publishSourceSnapshot() {entries++;},
        bindSourceRequest() {entries++;}, finishSourceProducer() {entries++;},
        intentCid() {entries++; return cid('d');},
      };
      if (form === 'missing' || form === 'inherited') delete receiver[method];
      if (form === 'inherited') Object.setPrototypeOf(receiver, {[method]() {entries++;}});
      if (form === 'accessor') Object.defineProperty(receiver, method,
        {get() {reads++; assert.fail('RequiredMethodGetterMustNotRun');}});
      if (form === 'undefined') receiver[method] = undefined;
      if (form === 'nonfunction') receiver[method] = {};
      const observed = await connectInProcess({mode: 'local', owner: 'local'}, {
        [sourcePreparationPort]: receiver,
        async perform(operation) {assert.equal(operation, 'connect'); connects++; return profile;},
      }).then(client => ({client}), error => ({error}));
      if (observed.client) await observed.client.close();
      assert.equal(observed.error?.code, 'NodeSourceManagedAdmissionUnavailable', `${method}:${form}`);
      assert.equal(connects, 0); assert.equal(reads, 0); assert.equal(entries, 0);
    }
  }
});

test('closed selected Source queries reject locally without touching the retired Host receiver', async () => {
  let hostCalls = 0, sends = 0;
  const retired = () => {
    hostCalls++;
    throw Object.assign(new Error('ClientHostClosing'), {code: 'ClientHostClosing'});
  };
  const {client} = await fixture({
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot: retired,
    beforeSourceQuery: retired, bindSourceSnapshot: retired,
    bindSourceRequest: retired, finishSourceProducer: retired,
    intentCid: retired, beforeResultRead: retired, assertResultReadCurrent: retired},
  () => {sends++; assert.fail('ClosedClientMustNotSend');});
  await client.close();
  const notSent = error => {
    assert.equal(error.code, 'SubmissionNotSent');
    assert.equal(error.cause?.code, 'ClientClosed');
    return true;
  };
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql'}), notSent);
  for (const format of ['sql', 'aql']) {
    for (const collection of [undefined, 'all', 'one', 'scalar']) {
      const query = client[format]('SELECT 1 AS n');
      await assert.rejects(collection === undefined ? query : query[collection](), notSent);
    }
  }
  assert.equal(hostCalls, 0);
  assert.equal(sends, 0);
});

test('Source refusal precedes every original option access and sends nothing', async t => {
  let reads = 0, sends = 0;
  const original = Object.assign(new Error('Unavailable'), {code: 'NodeSourceManagedAdmissionUnavailable'});
  const options = new Proxy({}, {get() {reads++; throw new Error('ReadBeforeAdmission');},
    ownKeys() {reads++; throw new Error('EnumeratedBeforeAdmission');}});
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot(kind, input, supplied) {
    assert.equal(kind, 'aql'); assert.equal(input, 'original'); assert.equal(supplied, options);
    throw original;
  }, bindSourceSnapshot() {assert.fail('NoSnapshot');},
  bindSourceRequest() {assert.fail('NoPacket');}, finishSourceProducer() {assert.fail('NoReceipt');}},
  () => {sends++;});
  t.after(() => client.close());
  await assert.rejects(client.startSource('original', options), error => error === original);
  assert.equal(reads, 0); assert.equal(sends, 0);
});

test('selected Source observes omitted options before the SDK creates its default', async t => {
  const original = Object.freeze(new Error('OriginalAdmissionRefusal'));
  const observed = [];
  let sends = 0;
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot(kind, input, options) {
    observed.push({kind, input, options}); throw original;
  }, bindSourceSnapshot() {assert.fail('NoSnapshot');},
  bindSourceRequest() {assert.fail('NoPacket');}, finishSourceProducer() {assert.fail('NoReceipt');}},
  () => {sends++;});
  t.after(() => client.close());
  const program = Object.freeze({version: 'actql/0.1'});
  await assert.rejects(client.startSource('original'), error => error === original);
  await assert.rejects(client.start(program), error => error === original);
  assert.deepEqual(observed, [{kind: 'aql', input: 'original', options: undefined},
    {kind: 'program', input: program, options: undefined}]);
  assert.equal(sends, 0);
});

test('unselected omitted options retain the existing document refusals', async t => {
  let sends = 0;
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      if (operation === 'connect') return profile;
      sends++; assert.fail('NoInvalidDocumentSend');
    },
  });
  t.after(() => client.close());
  await assert.rejects(client.startSource('original'), {code: 'InvalidAqlDocument'});
  await assert.rejects(client.start(null), {code: 'InvalidProgramDocument'});
  assert.equal(sends, 0);
});

test('one original receipt binds the synchronous frozen snapshot and exact transport packet', async t => {
  const receipt = {}, parameters = {n: 1}, order = [];
  const options = {format: 'sql', parameters, submissionRef: originalSubmission('source-original')};
  let body, packet;
  const receiver = {
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot(kind, text, originalOptions) {
      order.push('before'); assert.equal(kind, 'aql'); assert.equal(text, 'SELECT @n AS n');
      assert.equal(originalOptions, options); return receipt;
    },
    bindSourceSnapshot(original, value) {
      order.push('snapshot'); assert.equal(original, receipt); body = value;
      assert.equal(Object.isFrozen(body), true); assert.equal(Object.isFrozen(body.parameters), true);
      assert.equal(body.parameters.n, 1);
    },
    bindSourceRequest(original, snapshot, value) {
      order.push('packet'); assert.equal(original, receipt); assert.equal(snapshot, body);
      assert.equal(value.parameters.n, 1); packet = value;
    },
    finishSourceProducer(original, terminal) {
      order.push('finish'); assert.equal(original, receipt); assert.equal(terminal, 'returned');
    },
  };
  const {client, port} = await fixture(receiver, (operation, value) => {
    order.push('perform'); assert.equal(operation, 'submit-intent'); assert.equal(value, packet);
    return readySubmissionAttempt(value, admission);
  });
  t.after(() => client.close());
  const pending = client.startSource('SELECT @n AS n', options);
  assert.deepEqual(order, ['before', 'snapshot']);
  parameters.n = 2;
  port[sourcePreparationPort] = {};
  const execution = await pending;
  assert.deepEqual(order, ['before', 'snapshot', 'packet', 'perform', 'finish']);
  assert.equal(getSubmissionInput(pending).parameters.n, 1);
  assert.equal(getSubmissionOutcome(execution).kind, 'ready');
  assert.deepEqual(execution.ref, admission.ref);
  assert.equal(Object.getOwnPropertySymbols(packet).length, 0);
  assert.equal(Object.hasOwn(packet, 'sourceProducer'), false);
});

test('submission wrapper shares SDK frozen input without a second deep traversal', async t => {
  const receipt = {}, visits = new Map();
  const input = Object.freeze({rows: Array.from({length: 1000}, (_, id) =>
    ({id, values: [null, 'e\u0301', id]}))});
  const parameters = {options: {labels: ['\r\n', 'é']}};
  const consentRefs = ['original-consent'];
  let body, sends = 0;
  const remember = value => {
    if (value === null || typeof value !== 'object') return;
    visits.set(value, 0);
    for (const key of Object.keys(value)) remember(value[key]);
  };
  const receiver = {
    beforeSourceSnapshot() {return receipt;},
    assertSourceSnapshotCurrent(original) {assert.strictEqual(original, receipt);},
    captureSourceSnapshot(original, value, snapshot) {
      assert.strictEqual(original, receipt);
      const captured = snapshot(value);
      remember(captured.input); remember(captured.parameters);
      return captured;
    },
    bindSourceSnapshot(original, value) {assert.strictEqual(original, receipt); body = value;},
    publishSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {},
    intentCid() {return cid('d');},
  };
  const client = await connectInProcess({mode: 'local', owner: 'local', consentRefs}, {
    [sourcePreparationPort]: receiver,
    async perform(operation, packet) {
      if (operation === 'connect') return profile;
      assert.equal(operation, 'submit-intent'); sends++;
      return readySubmissionAttempt(packet, admission);
    },
  });
  t.after(() => client.close());
  const values = Object.values;
  let pending, settled;
  try {
    Object.values = value => {
      if (visits.has(value)) visits.set(value, visits.get(value) + 1);
      return values(value);
    };
    pending = client.start(input, {parameters,
      submissionRef: originalSubmission('single-body-freeze')});
    settled = pending.then(value => ({value}), error => ({error}));
    const publicInput = getSubmissionInput(pending);
    assert.strictEqual(publicInput.input, body.input);
    assert.strictEqual(publicInput.parameters, body.parameters);
    assert.notStrictEqual(publicInput.input, input);
    assert.equal(Object.isFrozen(publicInput), true);
    assert.equal(Object.isFrozen(publicInput.lookupContext), true);
    assert.equal(Object.isFrozen(publicInput.connection), true);
    assert.equal(Object.isFrozen(publicInput.connection.consentRefs), true);
    assert.equal(Object.isFrozen(publicInput.connection.runners), true);
    assert.equal(visits.size, 2005);
    for (const [value, count] of visits) {
      assert.equal(Object.isFrozen(value), true);
      assert.equal(count, 1, 'SDK-owned body descendants must not be recursively frozen twice');
    }
    input.rows[0].values[1] = 'caller mutation';
    parameters.options.labels[0] = 'caller mutation';
    consentRefs.push('later-consent');
    assert.equal(publicInput.input.rows[0].values[1], 'e\u0301');
    assert.equal(publicInput.parameters.options.labels[0], '\r\n');
    assert.deepEqual(publicInput.connection.consentRefs, ['original-consent']);
  } finally {Object.values = values;}
  const result = await settled;
  assert.equal(result.error, undefined);
  assert.strictEqual(getSubmissionInput(result.value), getSubmissionInput(pending));
  assert.equal(sends, 1);
});

test('external shallow freeze cannot skip deep protection of mutable descendants', () => {
  const child = {values: [null, {text: 'e\u0301'}]};
  const external = Object.freeze({child});
  assert.equal(Object.isFrozen(child), false);
  assert.strictEqual(freezeInput(external), external);
  assert.equal(Object.isFrozen(child), true);
  assert.equal(Object.isFrozen(child.values), true);
  assert.equal(Object.isFrozen(child.values[1]), true);
  assert.throws(() => {child.values[1].text = 'changed';}, TypeError);
});

test('failed producer cleanup retains original Unknown and retries only alias retirement on close', async () => {
  let sends = 0, finishes = 0;
  const receipt = {}, cleanup = new Error('OriginalAliasPending');
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return receipt;},
    bindSourceSnapshot() {}, bindSourceRequest() {},
    finishSourceProducer(original, terminal) {
      assert.equal(original, receipt); assert.equal(terminal, 'failed');
      if (++finishes === 1) throw cleanup;
    }}, () => {sends++; throw new Error('OriginalReplyLost');});
  let original;
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-unknown')}), error => {
    original = error; return error.code === 'SubmissionUnknown';
  });
  assert.equal(original.requestId, 'source-unknown');
  assert.equal(sends, 1); assert.equal(finishes, 1);
  await client.close();
  assert.equal(sends, 1); assert.equal(finishes, 2);
});

test('successful producer cleanup failure retains the original returned Run without resubmission', async () => {
  let sends = 0, finishes = 0;
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return {};},
    bindSourceSnapshot() {}, bindSourceRequest() {}, finishSourceProducer() {
      if (++finishes === 1) throw new Error('OriginalAliasPending');
    }}, (_operation, packet) => {sends++; return readySubmissionAttempt(packet, admission);});
  let failure;
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-cleanup')}), error => {
    failure = error; return error.code === 'ClientCleanupPending';
  });
  assert.deepEqual(failure.execution.ref, admission.ref);
  assert.equal(Object.getOwnPropertyDescriptor(failure, 'execution').enumerable, false);
  assert.equal(getSubmissionOutcome(failure).kind, 'ready');
  await client.close();
  assert.equal(sends, 1); assert.equal(finishes, 2);
});

test('packet binding refusal remains NotSent and never reaches the Host', async t => {
  let sends = 0, finishes = 0;
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return {};}, bindSourceSnapshot() {},
    bindSourceRequest() {throw new Error('ForeignOriginalPacket');},
    finishSourceProducer(_original, terminal) {assert.equal(terminal, 'failed'); finishes++;}},
  () => {sends++;});
  t.after(() => client.close());
  await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-no-send')}), {code: 'SubmissionNotSent'});
  assert.equal(sends, 0); assert.equal(finishes, 1);
});

test('selected Source uses its original same-body intent identity without starting WebCrypto', async t => {
  let digests = 0, hashes = 0, sends = 0, body;
  const originalDigest = Object.getOwnPropertyDescriptor(crypto.subtle, 'digest');
  Object.defineProperty(crypto.subtle, 'digest', {configurable: true,
    value() {digests++; throw new Error('UnfundedNativeDigest');}});
  t.after(() => {
    if (originalDigest === undefined) delete crypto.subtle.digest;
    else Object.defineProperty(crypto.subtle, 'digest', originalDigest);
  });
  const receipt = {};
  const {client} = await fixture({
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return receipt;},
    bindSourceSnapshot(original, value) {assert.equal(original, receipt); body = value;},
    intentCid(original, value) {
      assert.equal(original, receipt); assert.equal(value, body); hashes++;
      return cid('e'); // Explicit port metadata, not a canonical-identity oracle.
    }, bindSourceRequest() {}, finishSourceProducer() {}}, (_operation, request) => {
    assert.equal(request.intentCid, cid('e')); sends++;
    return readySubmissionAttempt(request, admission);
  });
  await client.startSource('SELECT 1 AS n', {format: 'sql',
    submissionRef: originalSubmission('source-owned-intent'), attemptId: 'original-attempt'});
  await client.close();
  assert.equal(digests, 0); assert.equal(hashes, 1); assert.equal(sends, 1);
});


test('native snapshot fence stops original retired producer before clone freeze and retains primary cleanup carrier', async t => {
  const receipt = {}, order = [], cleanupHandle = {};
  const primary = Object.assign(new Error('OriginalSnapshotCurrentLost'), {cleanupHandle});
  let retired = false, sends = 0, freezes = 0;
  const receiver = {
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {order.push('before');return receipt;},
    assertSourceSnapshotCurrent(actual) {assert.equal(actual, receipt);order.push('current');if (retired) throw primary;},
    bindSourceSnapshot() {order.push('bind');throw primary;}, bindSourceRequest() {assert.fail('NoPacket');},
    finishSourceProducer(actual, terminal) {assert.equal(actual, receipt);order.push(terminal);}};
  const {client} = await fixture(receiver, () => {sends++;assert.fail('NoDispatch');});
  t.after(() => client.close());
  const values = Object.values;
  Object.values = value => {if (Object.hasOwn(value, 'snapshotFenceTarget')) freezes++;return values(value);};
  t.after(() => {Object.values = values;});
  const parameters = {value: {toJSON() {order.push('toJSON');retired = true;return {snapshotFenceTarget: true};}}};
  await assert.rejects(client.startSource('SELECT @value AS value', {format: 'sql', parameters,
    submissionRef: originalSubmission('snapshot-current')}), error => error === primary && error.cleanupHandle === cleanupHandle);
  assert.equal(freezes, 0);assert.equal(sends, 0);
  assert.deepEqual(order, ['before', 'current', 'toJSON', 'current', 'failed']);
});

test('native snapshot fence preserves thrown undefined while same producer cleanup remains retryable', async () => {
  const receipt = {};let visits = 0, finishes = 0, rejected = false, failure = 'not-rejected';
  const {client} = await fixture({
    intentCid() {return cid('d');},
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {return receipt;},
    assertSourceSnapshotCurrent(actual) {assert.equal(actual, receipt);throw undefined;},
    bindSourceSnapshot() {assert.fail('NoSnapshot');}, bindSourceRequest() {assert.fail('NoPacket');},
    finishSourceProducer(actual, terminal) {assert.equal(actual, receipt);assert.equal(terminal, 'failed');
      if (++finishes === 1) throw new Error('SameProducerCleanupPending');}}, () => assert.fail('NoDispatch'));
  const parameters = {get value() {visits++;throw new Error('NoNativeSnapshot');}};
  try {await client.startSource('SELECT @value AS value', {format: 'sql', parameters,
    submissionRef: originalSubmission('snapshot-undefined')});} catch (error) {rejected = true;failure = error;}
  assert.equal(rejected, true);assert.equal(failure, undefined);assert.equal(visits, 0);assert.equal(finishes, 1);
  await client.close();assert.equal(finishes, 2);assert.equal(visits, 0);
});


test('selected snapshot uses the captured original serializer receiver once before binding', async t => {
  const receipt = {}, events = [];let gets = 0, body, originalWire;
  const parameters = {get n() {gets++; return 7;}};
  const receiver = {
    intentCid() {return cid('d');},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot() {events.push('before');return receipt;},
    captureSourceSnapshot(original, value, snapshot) {
      assert.equal(this, receiver);assert.equal(original, receipt);assert.equal(gets, 0);
      events.push('capture');
      return snapshot(value, (_units, wire) => {if (wire !== undefined) originalWire = wire;});
    },
    bindSourceSnapshot(original, value) {
      assert.equal(original, receipt);assert.equal(gets, 1);body = value;events.push('bind');
      assert.deepEqual(JSON.parse(originalWire), value);
    },
    bindSourceRequest() {},finishSourceProducer() {events.push('finish');},
  };
  const {client} = await fixture(receiver, (_operation, packet) => readySubmissionAttempt(packet, admission));
  t.after(() => client.close());
  receiver.captureSourceSnapshot = () => assert.fail('ReplacedSnapshotMethod');
  const execution = await client.startSource('SELECT @n AS n', {format: 'sql', parameters,
    submissionRef: originalSubmission('source-funded-snapshot')});
  assert.equal(body.parameters.n, 7);assert.equal(gets, 1);
  assert.deepEqual(events, ['before', 'capture', 'bind', 'finish']);
  assert.equal(getSubmissionOutcome(execution).kind, 'ready');
});

test('snapshot preserves only the original observer failure and maps caller errors independently', async () => {
  for (const resourceFailure of [true, false]) {
    const receipt = {}, original = Object.assign(new Error('SameSpelling'), {code: 'PreparationCapacityExceeded'});
    let sends = 0, finishes = 0;
    const receiver = {
      intentCid() {return cid('d');},
      assertSourceSnapshotCurrent() {},
      publishSourceSnapshot() {},
      beforeSourceSnapshot() {return receipt;},
      captureSourceSnapshot(actual, value, snapshot) {
        assert.equal(actual, receipt);
        return snapshot(value, resourceFailure ? () => {throw original;} : undefined);
      },
      bindSourceSnapshot() {assert.fail('FailedSnapshotMustNotBind');},bindSourceRequest() {},
      finishSourceProducer(actual, terminal) {assert.equal(actual, receipt);assert.equal(terminal, 'failed');finishes++;},
    };
    const {client} = await fixture(receiver, () => {sends++;assert.fail('NoFailedSnapshotSend');});
    try {
      const parameters = resourceFailure ? {n: 7} : {get n() {throw original;}};
      await assert.rejects(client.startSource('SELECT @n AS n', {format: 'sql', parameters,
        submissionRef: originalSubmission('source-snapshot-failure')}), cause =>
        resourceFailure ? cause === original : cause.code === 'InvalidClientPayload' && cause !== original);
      assert.equal(sends, 0);assert.equal(finishes, 1);
    } finally {await client.close();}
  }
});


test('selected capture cannot replace or repeat the SDK original native snapshot', async () => {
  for (const selected of ['skip', 'copy', 'repeat', 'foreign']) {
    let finishes = 0, sends = 0;
    const {client} = await fixture({
      intentCid() {return cid('d');},
      assertSourceSnapshotCurrent() {},
      publishSourceSnapshot() {},
      beforeSourceSnapshot() {return {};},
      captureSourceSnapshot(_receipt, value, snapshot) {
        if (selected === 'skip') return value;
        if (selected === 'foreign') return snapshot({...value});
        const original = snapshot(value);
        if (selected === 'copy') return {...original};
        return snapshot(value);
      },
      bindSourceSnapshot() {assert.fail('NoSubstitutedSnapshotBind');},bindSourceRequest() {},
      finishSourceProducer(_receipt, terminal) {assert.equal(terminal, 'failed');finishes++;},
    }, () => {sends++;assert.fail('NoSubstitutedSnapshotSend');});
    try {
      await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql',
        submissionRef: originalSubmission('source-snapshot-original')}), {code: 'InvalidHostSourceSnapshot'});
      assert.equal(finishes, 1);assert.equal(sends, 0);
    } finally {await client.close();}
  }
});

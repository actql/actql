import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer, request as sendRequest} from 'node:http';
import {createClientHttpHandler} from './client-http.mjs';
import {installHttpRequestPreparation} from './http-request-preparation.mjs';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

test('HTTP ingress requires Request preparation before installing a handler', () => {
  let calls = 0;
  const installation = {
    authenticate() {calls++; return 'principal';},
    authorizeConnection() {calls++; return true;},
  };
  // Missing preparation cannot select an unprepared dispatch route. The
  // rejection is installation failure, not a submitted operation outcome.
  assert.throws(() => createClientHttpHandler(installation),
    {name: 'TypeError', message: 'InvalidClientHostInstallation'});
  assert.equal(calls, 0);
});

// Actual Node HTTP input and wire validation; Resource/preflight are explicit
// ports here. The separate Core case owns measured geometry, not this fixture.
async function rawHttpFixture(run, {maxRequestBytes = 65536, denyAuth = false,
  denyConnection = false, failRead = false, failJson = false, mutateAfterDecode = false} = {}) {
  const events = [], current = {}, parent = {}, receivers = [];
  let ownReads = 0, opened = 0, prepared = 0, firstRead;
  const readStarted = new Promise(resolve => {firstRead = resolve;});
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'raw-input', capabilities: ['aql-document'],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
  const prepare = () => assert.fail('Raw input must not open a second Request');
  Object.defineProperty(prepare, 'beforeBody', {value(operation, limit) {
    opened++; events.push('parent');
    assert.equal(operation, 'connect'); assert.equal(limit, maxRequestBytes);
    const receiver = {
      beforeRead(bytes, chunks, quantum) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        assert(Number.isSafeInteger(bytes) && bytes <= limit + 1);
        assert(Number.isSafeInteger(chunks) && chunks > 0);
        assert(Number.isSafeInteger(quantum) && quantum > 0 && quantum <= limit + 1);
        events.push('reserve');
        if (failRead) throw Object.assign(new Error('same raw refusal'), {code: 'ClientRequestTooLarge'});
        current.reserved = true;
      },
      beforeJson(wire) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        events.push('geometry'); assert.equal(typeof wire, 'string');
        if (failJson) throw Object.assign(new Error('same current refusal'), {code: 'ClientConnectionDenied'});
      },
      prepareRequest(request) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        prepared++; events.push('snapshot');
        return {body: request, bindRequest() {}, beforeReply() {events.push('reply');},
          finish(terminal) {events.push(`finish:${terminal}`);}};
      },
      finish(terminal) {
        assert.strictEqual(this, receiver); events.push(`raw-finish:${terminal}`);
      },
    };
    current.parent = parent; receivers.push(receiver); return receiver;
  }});
  const handler = createClientHttpHandler({maxRequestBytes, prepareRequest: prepare,
    authenticate() {events.push('authenticate'); return denyAuth ? undefined : 'principal';},
    async authorizeConnection() {
      events.push('authorize');
      if (mutateAfterDecode) {
        for (const receiver of receivers) for (const key of Object.keys(receiver)) {
          receiver[key] = () => assert.fail('A changed method cannot replace the captured original');
        }
        await new Promise(resolve => setImmediate(resolve));
      }
      return !denyConnection;
    },
    negotiate() {events.push('dispatch'); return profile;}});
  const active = new Set();
  const server = createServer((request, response) => {
    const read = request.read;
    request.read = function(count) {
      if (Number.isInteger(count) && count > 0) {
        ownReads++; firstRead();
        assert.strictEqual(current.parent, parent);
        assert.equal(current.reserved, true, 'Reserve before the consumer read(n)');
      }
      return Reflect.apply(read, this, [count]);
    };
    const handled = handler(request, response); active.add(handled);
    handled.finally(() => active.delete(handled)).catch(() => {});
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    await run({url: `http://127.0.0.1:${server.address().port}/actql/client/0.1/connect`,
      events, receivers, readStarted, settled: () => Promise.allSettled([...active]),
      inspect: () => ({ownReads, opened, prepared})});
  } finally {
    server.closeAllConnections();
    await Promise.allSettled([...active]);
    await new Promise(resolve => server.close(resolve));
  }
}
const rawBody = JSON.stringify({connection: {mode: 'local', owner: 'local',
  consentRefs: [], runners: []}});
const postRaw = (url, body = rawBody) => fetch(url, {method: 'POST',
  headers: {'content-type': 'application/json'}, body, signal: AbortSignal.timeout(10000)});

test('HTTP raw input reserves one original before own read and decodes before authorization and snapshot', async () => {
  await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url);
    assert.equal(response.status, 200); assert.equal((await response.json()).scopeRef, 'raw-input');
    assert.deepEqual(inspect().opened, 1); assert.equal(inspect().prepared, 1);
    assert(inspect().ownReads > 0);
    assert(events.indexOf('authenticate') < events.indexOf('parent'));
    assert(events.indexOf('parent') < events.indexOf('reserve'));
    assert(events.indexOf('reserve') < events.indexOf('geometry'));
    assert(events.indexOf('geometry') < events.indexOf('authorize'));
    assert(events.indexOf('authorize') < events.indexOf('snapshot'));
    assert(events.indexOf('snapshot') < events.indexOf('dispatch'));
    assert.equal(events.filter(value => value === 'finish:returned').length, 1);
    assert.equal(events.filter(value => value.startsWith('raw-finish')).length, 0);
  });
});

test('HTTP raw refusal preserves its primary before read and before JSON construction', async () => {
  for (const [options, status, code, beforeRead] of [
    [{failRead: true}, 413, 'ClientRequestTooLarge', true],
    [{failJson: true}, 403, 'ClientConnectionDenied', false],
  ]) await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url);
    assert.equal(response.status, status); assert.deepEqual(await response.json(), {code});
    assert.equal(inspect().prepared, 0);
    if (beforeRead) assert.equal(inspect().ownReads, 0);
    assert.equal(events.includes('authorize'), false);
    assert.equal(events.includes('dispatch'), false);
    assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
  }, options);
});

test('HTTP raw input keeps authentication wire UTF8 and connection refusal boundaries', async () => {
  for (const [options, body, status, code] of [
    [{denyAuth: true}, rawBody, 403, 'ClientAuthenticationDenied'],
    [{maxRequestBytes: 16}, rawBody, 413, 'ClientRequestTooLarge'],
    [{}, Buffer.from([0xff]), 400, 'InvalidClientRequest'],
    [{}, '{', 400, 'InvalidClientRequest'],
    [{denyConnection: true}, rawBody, 403, 'ClientConnectionDenied'],
  ]) await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url, body);
    assert.equal(response.status, status); assert.deepEqual(await response.json(), {code});
    assert.equal(inspect().prepared, 0); assert.equal(events.includes('dispatch'), false);
    if (options.denyAuth) {assert.equal(inspect().opened, 0); assert.equal(inspect().ownReads, 0);}
    else assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
  }, options);
});


test('HTTP raw abort settles only its original parent and releases reader listeners', {timeout: 10000}, async () => {
  await rawHttpFixture(async ({url, events, readStarted, settled, inspect}) => {
    const client = sendRequest(url, {method: 'POST', headers: {
      'content-type': 'application/json', 'content-length': 1000}});
    client.on('error', () => {});
    client.write('{');
    await readStarted;
    client.destroy();
    await settled();
    assert.equal(inspect().opened, 1);
    assert.equal(inspect().prepared, 0);
    assert.equal(events.includes('geometry'), false);
    assert.equal(events.includes('dispatch'), false);
    assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
  });
});

test('HTTP raw captured receiver survives awaited authorization method replacement', async () => {
  await rawHttpFixture(async ({url, events}) => {
    const response = await postRaw(url);
    assert.equal(response.status, 200); await response.json();
    assert.equal(events.filter(value => value === 'snapshot').length, 1);
    assert.equal(events.filter(value => value === 'finish:returned').length, 1);
  }, {mutateAfterDecode: true});
});

test('HTTP raw selected larger wire policy accepts above 64 KiB and smaller refusal recovers', async () => {
  const body = JSON.stringify({connection: {mode: 'local', owner: 'local', runners: [],
    consentRefs: Array.from({length: 400}, (_, index) => `${index}:` + 'x'.repeat(200))}});
  assert(Buffer.byteLength(body) > 65536 && Buffer.byteLength(body) < 131072);
  // Actual Node HTTP/validation with explicit Resource ports. A matching
  // installed Common/Host remains a separate ordinary artifact qualification.
  await rawHttpFixture(async ({url, inspect, events}) => {
    const response = await postRaw(url, body);
    assert.equal(response.status, 200); await response.json();
    assert.equal(inspect().opened, 1); assert.equal(inspect().prepared, 1);
    assert.equal(events.filter(value => value === 'finish:returned').length, 1);
  }, {maxRequestBytes: 131072});
  await rawHttpFixture(async ({url, inspect, events}) => {
    const refused = await postRaw(url, body);
    assert.equal(refused.status, 413);
    assert.deepEqual(await refused.json(), {code: 'ClientRequestTooLarge'});
    assert.equal(inspect().prepared, 0);
    const recovered = await postRaw(url);
    assert.equal(recovered.status, 200); await recovered.json();
    assert.equal(inspect().opened, 2); assert.equal(inspect().prepared, 1);
    assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
    assert.equal(events.filter(value => value === 'finish:returned').length, 1);
  });
});

// Actual adapter/registry; manager/compiler/current and pending cleanup are
// explicit ports. No new Common ABI or successful business execution is implied.
test('HTTP raw adapter retains its single receipt through snapshot and pending cleanup', async () => {
  const registry = createEmbeddedHostRegistry(() => true);
  const host = {}, installation = {}, originals = {host, installation, generation: host};
  registry.registerPreparation(host, installation, host);
  const receipt = {}, primary = new Error('OriginalRawCleanupPending');
  const events = [];
  let pending = true;
  const manager = {
    beforeHttpRequestBody() {assert.strictEqual(this, manager); events.push('parent'); return receipt;},
    reserveHttpRequestBody(original, ...geometry) {
      assert.strictEqual(this, manager); assert.strictEqual(original, receipt);
      assert.deepEqual(geometry, [128, 1, 128, 131072]); events.push('reserve');
    },
    prepareHttpRequestJson(original, wire) {
      assert.strictEqual(this, manager); assert.strictEqual(original, receipt);
      assert.equal(wire, '{}'); events.push('json');
    },
    bindHttpRequestKind(original, kind, connection) {
      assert.strictEqual(original, receipt); assert.equal(kind, 'aql');
      assert.strictEqual(connection, request.connection); events.push('kind');
    },
    beforeSourceSnapshot() {assert.fail('A second Request is forbidden');},
    captureSourceSnapshot(original, supplied, capture) {
      assert.strictEqual(original, receipt); assert.strictEqual(supplied, request);
      events.push('snapshot'); return capture(supplied);
    },
    assertSourceSnapshotCurrent(original) {assert.strictEqual(original, receipt);},
    bindSourceSnapshot(original, body) {assert.strictEqual(original, receipt); assert(Object.isFrozen(body.input));},
    bindSourceRequest(original) {assert.strictEqual(original, receipt);},
    finishSourceProducer(original, terminal) {
      assert.strictEqual(this, manager); assert.strictEqual(original, receipt);
      assert.equal(terminal, 'failed'); events.push('finish');
      if (pending) throw primary;
    },
  };
  const request = Object.freeze({kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'},
    connection: Object.freeze({mode: 'local', owner: 'local', consentRefs: [], runners: []})});
  const prepare = installHttpRequestPreparation({requestPreparation: () => manager,
    beforeResultPublicationOperation(operation) {assert.equal(operation, 'plan');},
    assertResultPublicationCurrent() {}}, registry, originals, {rawInput: true});
  const raw = prepare.beforeBody('plan', 131072);
  raw.beforeRead(128, 1, 128); raw.beforeJson('{}');
  const lifetime = raw.prepareRequest(request);
  assert.notStrictEqual(lifetime.body.input, request.input);
  const derived = {...lifetime.body}; lifetime.bindRequest(derived);
  assert.strictEqual(registry.originalSourceRequest(host, installation, host, derived), request);
  lifetime.finish('failed'); // Pending duty remains with the SAME manager.
  assert.equal(pending, true);
  raw.finish('failed'); // The outer fallback cannot duplicate that pending call.
  assert.equal(events.filter(value => value === 'finish').length, 1);
  await Promise.resolve();
  assert.throws(() => registry.originalSourceRequest(host, installation, host, derived),
    {code: 'InstalledHostPreparationChanged'});
  pending = false; lifetime.finish('failed');
  assert.equal(events.filter(value => value === 'finish').length, 2);
  assert.deepEqual(events.slice(0, 5), ['parent', 'reserve', 'json', 'kind', 'snapshot']);
  registry.retirePreparation(host, installation, host);
});

test('HTTP raw adapter refuses missing capabilities and preserves a failed snapshot primary', () => {
  assert.throws(() => installHttpRequestPreparation({requestPreparation: () => ({})}, {}, {},
    {rawInput: true}), /InvalidClientHostPreparation/);
  const primary = new Error('OriginalSnapshotRefusal'), cleanup = new Error('OriginalCleanupPending');
  const receipt = {}, calls = [];
  const manager = {beforeHttpRequestBody: () => receipt, reserveHttpRequestBody() {},
    prepareHttpRequestJson() {}, bindHttpRequestKind() {},
    captureSourceSnapshot() {throw primary;},
    finishSourceProducer(original, terminal) {
      assert.strictEqual(original, receipt); assert.equal(terminal, 'failed'); calls.push('finish'); throw cleanup;
    }};
  const prepare = installHttpRequestPreparation({requestPreparation: () => manager,
    beforeResultPublicationOperation() {}}, {retainRequest() {}}, {}, {rawInput: true});
  const raw = prepare.beforeBody('plan', 65536); raw.beforeJson('{}');
  assert.throws(() => raw.prepareRequest({kind: 'aql', connection: {}}), error => error === primary);
  assert.doesNotThrow(() => raw.finish('failed'));
  assert.deepEqual(calls, ['finish']);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {open, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {prepareOpenAIChatRequest} from
  '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';
import {createSdkModelPreflight} from
  '../../packages/provider-ai-sdk/_internal/model-port.mjs';
import {createModelRawTransportPersistence} from './infer-raw-capture.mjs';
import {rawCaptureStoreFixture} from './infer-raw-capture.fixture.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {createInferIoNotification, claimInferIoNotification} from './infer-io-notification.mjs';

const wire = '{"id":"original-response","model":"reported-model","choices":' +
  '[{"index":0,"message":{"role":"assistant","content":"{\\"risk\\":\\"low\\"}"},' +
  '"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2},' +
  '"opaque":"é\\r\\n"}\r\n';
const input = 'Original é\r\n';
const observedAt = '2026-10-12T00:00:00.000Z';
const responseLimits = {maxBytes: 4096, maxChunkBytes: 4096, maxChunks: 8,
  maxHeaderBytes: 128, observedHeaders: ['content-type']};

async function until(read, predicate, io) {
  for (let i = 0; i < 300; i++) {
    const ticket = io.arm();
    try {
      const value = read();
      if (predicate(value)) return value;
      assert.notEqual(value?.kind, 'unknown', 'Unexpected original physical Unknown');
      await ticket.promise;
    } finally {
      ticket.dispose();
    }
  }
  assert.fail('Joined private SDK/Store did not reach its finite observation');
}

async function joinedFixture(t, {bytes = Buffer.from(wire), storeFault = {},
  physicalFor = f => f.physical, beforeStart = async () => {}} = {}) {
  const f = await rawCaptureStoreFixture(t, {bytes, ...storeFault});
  const notification = createInferIoNotification();
  const io = claimInferIoNotification(notification);
  t.after(() => io.close());
  const wait = (read, predicate) => until(read, predicate, io);
  t.diagnostic('joined boundary: original Store fixture opened');
  const serverState = {requests: 0, requestBody: undefined};
  const server = createServer((request, response) => {
    serverState.requests++;
    const chunks = [];
    let used = 0;
    request.on('data', chunk => {
      used += chunk.length;
      if (used > 4096) { request.destroy(); return; }
      chunks.push(chunk);
    });
    request.on('end', () => {
      serverState.requestBody = Buffer.concat(chunks).toString('utf8');
      assert.equal(request.method, 'POST');
      assert.equal(request.url, '/v1/chat/completions');
      assert.equal(JSON.parse(serverState.requestBody).messages[0].content, input);
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(bytes);
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.diagnostic('joined boundary: loopback fixture listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  });
  const request = Object.freeze({original: Symbol('semantic request double')});
  const prepared = Object.freeze({original: Symbol('prepared call set double')});
  const entry = Object.freeze({original: Symbol('consumed original Entry double')});
  const registration = Object.freeze({original: Symbol('raw grant double')});
  let originalCall;
  let observes = 0;
  let physicalStarts = 0;
  const retained = [];
  // Real pinned SDK, final loopback fetch and encrypted Store/holding. The
  // Common grant/Entry/nominal receipt below are explicitly doubles; this is
  // neither a public Run nor original Ledger/complete-answer acceptance.
  const moon = {...f.moon,
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(actual, count, tokens, cost, duration,
      profile, installation, start) {
      assert.equal(actual, request);
      assert.ok(count > 0n && count <= 4096n);
      assert.equal(tokens, 16n);
      assert.equal(cost, 0n);
      assert.equal(duration, 500n);
      return {$tag: 1, _0: {start}};
    },
    clientProgramModelPhysicalCall(actual, calls, poll, cancel, cleanup) {
      assert.equal(actual, entry);
      assert.equal(calls, prepared);
      assert.equal(originalCall, undefined);
      originalCall = Object.freeze({poll, cancel, cleanup});
      return originalCall;
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: response => ({kind: 'chat', response}),
    clientProgramObserveInferRawCapture(call, grant, content, count, status, eof, at) {
      assert.equal(call, originalCall);
      assert.equal(grant, registration);
      assert.equal(content, f.binding.contentCid);
      assert.equal(count, bytes.byteLength);
      assert.equal(status, 200);
      assert.equal(eof, true);
      assert.equal(at, observedAt);
      observes++;
      return {$tag: 1, _0: f.view};
    },
  };
  const persistence = createModelRawTransportPersistence({store: physicalFor(f),
    moon, registration, retainHolding: value => retained.push(value), notify: io.notify});
  const preparation = prepareOpenAIChatRequest({modelId: 'gpt-4.1-nano',
    baseURL: `http://127.0.0.1:${server.address().port}/v1`,
    apiKey: 'fixture-only-not-a-service-secret', maxRequestBytes: 4096,
    maxHeaderBytes: 4096, maxHeaders: 16, notify: io.notify, options: {
      prompt: [{role: 'user', content: [{type: 'text', text: input}]}],
      maxOutputTokens: 16, responseFormat: {type: 'json'},
    }});
  const port = createSdkModelPreflight({moon, request, preparation,
    profile: {}, installation: {}, quantities: {tokens: 16n, costUnits: 0n,
      durationMs: 500n}, fetch(...args) { physicalStarts++; return fetch(...args); },
    responseLimits, persistRaw: persistence, cleanupRaw: persistence.cleanup,
    notify: io.notify, checked, observeAt: () => observedAt});
  port.bindPrepared(prepared);
  const {_1: plan} = await wait(() => port.preflight.advance(), value => value._0);
  t.diagnostic('joined boundary: fixed SDK preflight prepared');
  assert.equal(serverState.requests, 0);
  assert.equal(physicalStarts, 0);
  await beforeStart(f);
  const call = plan.start(entry);
  t.diagnostic('joined boundary: fixed transport started');
  assert.equal(physicalStarts, 1);
  assert.equal(plan.start(entry), undefined);
  return {...f, port, call, plan, entry, retained, serverState, wait,
    counters: () => ({physicalStarts, observes})};
}

test('joined fixed SDK and original encrypted Store preserve exact raw bytes across Store reopen', async t => {
  const f = await joinedFixture(t);
  const observed = await f.wait(() => f.call.poll(), value => value.kind === 'chat');
  t.diagnostic('joined boundary: original raw saved Chat view observed');
  assert.equal(observed.response.actual, f.receipt);
  assert.equal(observed.response.body, wire);
  assert.equal(observed.response.metadata, undefined);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.commits, 1);
  assert.equal(f.retained.length, 1);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  t.diagnostic('joined boundary: original SDK/raw cleanup finished');
  // SDK cleanup drops local aliases, not the parent's durable raw custody.
  assert.equal(f.retained[0].holding.status().committed, true);
  await f.store.close();
  t.diagnostic('joined boundary: original Store closed');
  const reopened = await openLocalPublicationStore({...f.storeOptions,
    privateEvidenceKey: Buffer.from(f.storeOptions.privateEvidenceKey)},
    createPublicationContractControlFixture());
  t.after(() => reopened.close());
  const saved = await reopened.confirmModelRawEvidence(f.binding);
  t.diagnostic('joined boundary: reopened Store raw bytes reconfirmed');
  assert.deepEqual(saved.bytes, Buffer.from(wire));
  assert.equal(f.serverState.requests, 1);
  assert.deepEqual(f.counters(), {physicalStarts: 1, observes: 1});
  await reopened.retirePhysicalHolding(f.binding.holdingCid);
});

test('joined actual raw reader close failure blocks SDK cleanup until the same FD closes', {timeout: 5000}, async t => {
  let original, prototype, createReadStream;
  let originalCleanup;
  let closeAttempts = 0, captures = 0;
  const failure = Object.assign(new Error('OriginalRawReaderClosePending'), {code: 'EIO'});
  const restore = () => {
    if (prototype !== undefined) prototype.createReadStream = createReadStream;
  };
  const f = await joinedFixture(t, {physicalFor: fixture => ({...fixture.physical,
    async confirmModelRawEvidence(...args) {
      try { return await fixture.store.confirmModelRawEvidence(...args); }
      catch (error) {
        originalCleanup ??= error.cleanupHandle;
        throw error;
      }
    },
  }), beforeStart: async fixture => {
    const objects = join(fixture.storeOptions.directory, 'objects');
    const [name] = await readdir(objects);
    const probe = await open(join(objects, name), 'r');
    prototype = Object.getPrototypeOf(probe);
    createReadStream = prototype.createReadStream;
    await probe.close();
    // Fault only the actual consumeObject FD. Verification/metadata readers
    // retain their own scope; no fake cleanup handle is supplied to the port.
    prototype.createReadStream = function(options) {
      if (captures === 0 && new Error().stack.includes('at consumeObject ')) {
        captures++;
        original = this;
        const close = this.close;
        this.close = function() {
          closeAttempts++;
          if (closeAttempts <= 2) return Promise.reject(failure);
          return Reflect.apply(close, this, []);
        };
      }
      return Reflect.apply(createReadStream, this, [options]);
    };
  }});
  t.after(async () => {
    restore();
    // Preserve test failure evidence without leaking this test's original FD.
    if (original?.fd >= 0) {
      closeAttempts = Math.max(closeAttempts, 2);
      await originalCleanup.retry();
    }
  });
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  t.diagnostic('joined failed original FD: terminal Unknown observed');
  restore();
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(captures, 1);
  assert.equal(closeAttempts, 1);
  assert.ok(original.fd >= 0);
  assert.equal(f.state.commits, 1);
  assert.equal(f.retained[0].holding.status().committed, false,
    'durable Store commit is not the failed holding confirmation');
  assert.equal(f.state.acknowledgements, 0);
  const stored = f.store.status().storedBytes;
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal((await f.store.retirePhysicalHolding(f.binding.holdingCid)).deleted, false);
  assert.equal(f.port.preflight.cleanup(), false);
  await f.wait(() => closeAttempts, attempts => attempts >= 2);
  t.diagnostic('joined failed original FD: first cleanup retry failed');
  assert.ok(original.fd >= 0, 'failed retry retains the original FD');
  assert.equal(f.store.status().storedBytes, stored);
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(f.call.poll().kind, 'unknown');
  assert.deepEqual(f.counters(), {physicalStarts: 1, observes: 1});
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  t.diagnostic('joined failed original FD: original SDK cleanup completed');
  assert.equal(original.fd, -1);
  const completed = closeAttempts;
  assert.equal(f.port.preflight.cleanup(), true);
  assert.equal(closeAttempts, completed, 'settled cleanup does not close twice');
  assert.equal(f.serverState.requests, 1);
  assert.equal((await f.store.retirePhysicalHolding(f.binding.holdingCid)).deleted, true);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes);
});

test('joined commit reply loss reconfirms one durable cell with one stable Promise and no second fetch', async t => {
  const lostReply = new Error('Original raw commit reply lost');
  let replyLost = false;
  const f = await joinedFixture(t, {physicalFor: fixture => ({...fixture.physical,
    async commitPhysicalHolding(...args) {
      await fixture.physical.commitPhysicalHolding(...args);
      replyLost = true;
      throw lostReply;
    },
    async confirmModelRawEvidence(...args) {
      if (replyLost) { replyLost = false; throw new Error('Immediate raw confirmation unavailable'); }
      return fixture.store.confirmModelRawEvidence(...args);
    },
  })});
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  const failure = f.port.rawFailure();
  assert.equal(failure, lostReply);
  assert.equal(failure.rawCustodyRetained, true);
  const original = f.port.reconcileRaw(f.call);
  assert.equal(f.port.reconcileRaw(f.call), original);
  const saved = await original;
  assert.equal(saved.response.body, wire);
  assert.equal(f.port.reconcileRaw(f.call), original);
  assert.equal((await f.port.reconcileRaw(f.call)).response, saved.response);
  assert.equal(f.call.poll().kind, 'unknown');
  assert.equal(f.port.rawFailure(), failure);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.commits, 1);
  assert.equal(f.retained.length, 1);
  assert.deepEqual(f.counters(), {physicalStarts: 1, observes: 1});
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.equal(f.serverState.requests, 1);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('joined raw cleanup retries the same failed writer without another SDK request', async t => {
  const f = await joinedFixture(t, {storeFault: {refuseCommit: true, releaseFailure: true}});
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  assert.equal(f.retained[0].holding.status().preparedPending, true);
  assert.equal(f.state.writes, 1);
  assert.equal(f.port.preflight.cleanup(), false);
  await f.wait(() => f.state.releases, value => value > 0);
  assert.equal(f.state.releases, 1);
  assert.equal(f.retained[0].holding.status().preparedPending, true);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.equal(f.retained[0].holding.status().abandoned, true);
  assert.equal(f.retained[0].holding.status().preparedPending, false);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.commits, 1);
  assert.equal(f.serverState.requests, 1);
  assert.deepEqual(f.counters(), {physicalStarts: 1, observes: 1});
});

test('joined invalid UTF8 retains the actual Store raw receipt and Unknown without repair', async t => {
  const bytes = Uint8Array.of(0x7b, 0xc3, 0x28, 0x7d);
  const f = await joinedFixture(t, {bytes});
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  const original = f.port.rawFailure();
  assert.equal(original.code, 'ERR_ENCODING_INVALID_ENCODED_DATA');
  assert.equal(original.rawReceipt, f.receipt);
  assert.equal(original.rawCustodyRetained, true);
  const reconfirmation = f.port.reconcileRaw(f.call);
  await assert.rejects(reconfirmation, {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
  assert.equal(f.port.reconcileRaw(f.call), reconfirmation);
  assert.equal(f.port.rawFailure(), original);
  assert.equal(f.state.decoded.length, 0);
  const saved = await f.store.confirmModelRawEvidence(f.binding);
  assert.deepEqual(saved.bytes, Buffer.from(bytes));
  assert.equal(f.state.writes, 1);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.equal(f.serverState.requests, 1);
  assert.deepEqual(f.counters(), {physicalStarts: 1, observes: 1});
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

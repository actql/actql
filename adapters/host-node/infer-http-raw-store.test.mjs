import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createHttpChatPreflight} from '../../packages/provider-http/_internal/model-port.mjs';
import {rawCaptureStoreFixture} from './infer-raw-capture.fixture.mjs';
import {createModelRawTransportPersistence} from './infer-raw-capture.mjs';
import {createInferIoNotification, claimInferIoNotification} from './infer-io-notification.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// Independent raw bytes include unknown fields, decomposed Unicode and CRLF.
// They are not repaired, parsed as an answer, or inferred from SDK defaults.
const wire = '{"id":"http-original","choices":[{"index":0,"message":' +
  '{"content":"{\\"ok\\":true}"},"finish_reason":"stop"}],' +
  '"usage":{"prompt_tokens":0},"opaque":"é\\r\\n"}\r\n';
const requestBody = '{"model":"fixture","n":1,"stream":false}';
const at = '2026-10-13T00:00:00.000Z';

async function joined(t, {storeFault, physicalFor = f => f.physical} = {}) {
  let port, wait;
  // Retry physical cleanup before the original Store fixture can close/remove
  // its directory. A cancelled transport is not a cleanup acknowledgement.
  t.after(async () => { if (port !== undefined) await wait(() => port.preflight.cleanup(), Boolean); });
  const f = await rawCaptureStoreFixture(t, {bytes: Buffer.from(wire), ...storeFault});
  const notification = createInferIoNotification();
  const io = claimInferIoNotification(notification);
  t.after(() => io.close());
  wait = async (read, accept) => {
    for (let i = 0; i < 40; i++) {
      const ticket = io.arm();
      try { const value = read(); if (accept(value)) return value; await ticket.promise; }
      finally { ticket.dispose(); }
    }
    assert.fail('Original HTTP/Store observation exceeded its finite transitions');
  };
  let requests = 0;
  const server = createServer((req, res) => {
    requests++;
    assert.equal(req.method, 'POST');
    assert.equal(req.url, '/chat');
    let count = 0;
    const chunks = [];
    req.on('data', chunk => {
      count += chunk.length;
      if (count > 4096) { req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => {
      assert.equal(Buffer.concat(chunks).toString('utf8'), requestBody);
      res.writeHead(200, {'content-type': 'application/json'});
      res.end(wire);
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const endpoint = `http://127.0.0.1:${server.address().port}/chat`;
  const request = {}, provider = {}, entry = {}, registration = {};
  let call, starts = 0, observes = 0;
  const holdings = [];
  // Common request/Entry/grant/receipt are explicit doubles. Actual HTTP,
  // bounded reader, encrypted Store, original holding and reopen execute here.
  // This is not a checked Run, canonical issuer or complete numerical profile.
  const moon = {...f.moon,
    clientProgramProjectHTTPChatRequest(p, r, model) {
      assert.equal(p, provider); assert.equal(r, request); assert.equal(model, 'fixture');
      return {$tag: 1, _0: {_0: requestBody, _1: 'task', _2: 'prompt', _3: 'schema', _4: 'selector'}};
    },
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(r, bytes, tokens, cost, duration, profile, installation, start) {
      assert.equal(r, request); assert.equal(bytes, BigInt(Buffer.byteLength(requestBody)));
      return {$tag: 1, _0: {start}};
    },
    clientProgramModelPhysicalCallForRequest(actual, r, poll, cancel, cleanup) {
      assert.equal(actual, entry); assert.equal(r, request); assert.equal(call, undefined);
      call = Object.freeze({poll, cancel, cleanup}); return call;
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: response => ({kind: 'chat', response}),
    clientProgramObserveInferRawCapture(original, grant, content, bytes, status, eof, observed) {
      assert.equal(original, call); assert.equal(grant, registration);
      assert.equal(content, f.binding.contentCid); assert.equal(bytes, Buffer.byteLength(wire));
      assert.equal(status, 200); assert.equal(eof, true); assert.equal(observed, at);
      observes++; return {$tag: 1, _0: f.view};
    },
  };
  const persistence = createModelRawTransportPersistence({store: physicalFor(f), moon,
    registration, retainHolding: value => holdings.push(value), notify: io.notify});
  port = createHttpChatPreflight({moon, request, admittedProvider: provider, modelId: 'fixture',
    taskCid: 'task', promptCid: 'prompt', outputSchemaCid: 'schema', modelSelector: 'selector',
    projectionLimits: {maxBytes: 4096, maxNodes: 128, maxDepth: 16, maxFrames: 32, maxWork: 4096},
    endpoint, headers: [['content-type', 'application/json']],
    requestLimits: {maxBytes: 4096, maxHeaders: 4, maxHeaderBytes: 128},
    responseLimits: {maxBytes: 512, maxChunkBytes: 512, maxChunks: 4,
      maxHeaderBytes: 64, observedHeaders: ['content-type']},
    quantities: {tokens: 16n, costUnits: 0n, durationMs: 1n}, profile: {}, installation: {},
    fetch(url, init) { starts++; assert.equal(url, endpoint); return fetch(url, init); },
    notify: io.notify, observeAt: () => at, checked,
    persistRaw: persistence, cleanupRaw: persistence.cleanup});
  const plan = port.preflight.advance()._1;
  assert.notEqual(plan, undefined); assert.equal(starts, 0);
  assert.equal(plan.start(entry), call); assert.notEqual(call, undefined);
  assert.equal(plan.start(entry), undefined);
  return {...f, port, call, wait, holdings, plan, entry,
    counters: () => ({requests, starts, observes})};
}

test('independent HTTP joins original encrypted raw Store and exact reopen', {timeout: 5000}, async t => {
  const f = await joined(t);
  const result = await f.wait(() => f.call.poll(), value => value.kind === 'chat');
  assert.equal(result.response.actual, f.receipt);
  assert.equal(result.response.body, wire); assert.equal(result.response.metadata, undefined);
  assert.equal(f.state.writes, 1); assert.equal(f.state.commits, 1);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.equal(f.holdings[0].holding.status().committed, true);
  await f.store.close();
  const reopened = await openLocalPublicationStore({...f.storeOptions,
    privateEvidenceKey: Buffer.from(f.storeOptions.privateEvidenceKey)}, createPublicationContractControlFixture());
  try {
    const saved = await reopened.confirmModelRawEvidence(f.binding);
    assert.deepEqual(saved.bytes, Buffer.from(wire));
    await reopened.retirePhysicalHolding(f.binding.holdingCid);
  } finally { assert.equal(await reopened.close(), true); }
  assert.deepEqual(f.counters(), {requests: 1, starts: 1, observes: 1});
});

test('independent HTTP commit loss retains Unknown and same-cell reconciliation without resend', {timeout: 5000}, async t => {
  const lost = Error('OriginalHTTPCommitReplyLost');
  let confirmationLost = false;
  const f = await joined(t, {physicalFor: original => ({...original.physical,
    async commitPhysicalHolding(...args) {
      await original.physical.commitPhysicalHolding(...args);
      confirmationLost = true; throw lost;
    },
    async confirmModelRawEvidence(...args) {
      if (confirmationLost) { confirmationLost = false; throw Error('ImmediateOriginalConfirmationLost'); }
      return original.store.confirmModelRawEvidence(...args);
    },
  })});
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  assert.equal(f.port.rawFailure(), lost); assert.equal(lost.rawCustodyRetained, true);
  const original = f.port.reconcileRaw(f.call);
  assert.equal(f.port.reconcileRaw(f.call), original);
  const saved = await original;
  assert.equal(saved.response.body, wire);
  assert.equal(f.port.reconcileRaw(f.call), original);
  assert.equal(f.call.poll().kind, 'unknown'); assert.equal(f.port.rawFailure(), lost);
  assert.equal(f.state.writes, 1); assert.equal(f.state.commits, 1); assert.equal(f.holdings.length, 1);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.deepEqual(f.counters(), {requests: 1, starts: 1, observes: 1});
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('independent HTTP failed writer cleanup keeps original holding and retries only the failed descriptor', {timeout: 5000}, async t => {
  // The existing raw Store owns two prepared objects in descriptor/content
  // order. Track each original handle: one failed descriptor release retries,
  // while the content releases once. A whole-holding count obscures this.
  const releaseCalls = [0, 0];
  const f = await joined(t, {storeFault: {refuseCommit: true, releaseFailure: true},
    physicalFor: original => ({...original.physical,
      async prepareModelRawEvidence(...args) {
        const originals = await original.physical.prepareModelRawEvidence(...args);
        assert.equal(originals.length, 2);
        return originals.map((value, index) => ({...value, prepared: {
          status: () => value.prepared.status(),
          async release() { releaseCalls[index]++; return value.prepared.release(); },
        }}));
      },
    }),
  });
  await f.wait(() => f.call.poll(), value => value.kind === 'unknown');
  const original = f.port.rawFailure();
  assert.equal(f.holdings[0].holding.status().preparedPending, true);
  f.call.cancel(); assert.equal(f.call.poll().kind, 'unknown');
  assert.equal(f.port.preflight.cleanup(), false);
  await f.wait(() => f.state.releases, attempts => attempts === 1);
  assert.deepEqual(releaseCalls, [1, 0]);
  assert.equal(f.holdings[0].holding.status().preparedPending, true);
  assert.equal(f.port.rawFailure(), original);
  await f.wait(() => f.port.preflight.cleanup(), Boolean);
  assert.equal(f.holdings[0].holding.status().preparedPending, false);
  assert.equal(f.holdings[0].holding.status().abandoned, true);
  assert.deepEqual(releaseCalls, [2, 1]);
  assert.equal(f.port.preflight.cleanup(), true);
  assert.deepEqual(releaseCalls, [2, 1], 'retired cleanup releases neither original object twice');
  assert.equal(f.state.acknowledgements, 0); assert.equal(f.state.writes, 1); assert.equal(f.state.commits, 1);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes);
  assert.deepEqual(f.counters(), {requests: 1, starts: 1, observes: 1});
});

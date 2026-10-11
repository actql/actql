import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {rawCaptureStoreFixture as fixture} from './infer-raw-capture.fixture.mjs';
import {createModelRawCaptureStorePort, createModelRawTransportPersistence}
  from './infer-raw-capture.mjs';

const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

test('private raw port confirms same original Store bytes before acknowledging its view', async t => {
  const f = await fixture(t);
  const port = createModelRawCaptureStorePort(f.physical, f.moon, f.view, f.bytes);
  const saved = await port.persist();
  assert.equal(saved.receipt, f.receipt);
  assert.deepEqual(saved.bytes, Buffer.from(f.bytes));
  assert.throws(() => new TextDecoder('utf8', {fatal: true}).decode(saved.bytes));
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.acknowledgements, 1);
  assert.equal(port.holding.status().committed, true);
  await port.persist();
  assert.equal(f.state.writes, 1);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

async function rawFixtureCleanup(persist, call, wake) {
  for (let i = 0; i < 40; i++) {
    const prior = wake.count;
    if (persist.cleanup(call)) return;
    await wake.wait(prior);
  }
  assert.fail('Original raw temporary cleanup did not finish');
}

function cleanupWakeFixture() {
  let count = 0;
  let waiting;
  return {
    get count() { return count; },
    notify() { count++; waiting?.(); waiting = undefined; },
    wait(prior) {
      if (count > prior) return Promise.resolve();
      assert.equal(waiting, undefined);
      return new Promise(resolve => { waiting = resolve; });
    },
  };
}

test('raw caller cleanup retries original failed writer release without replacement or early capacity return', async t => {
  const f = await fixture(t, {refuseCommit: true, releaseFailure: true});
  const call = Object.freeze({original: Symbol('original physical call double')});
  let observes = 0;
  f.moon.clientProgramObserveInferRawCapture = () => {
    observes++;
    return {$tag: 1, _0: f.view};
  };
  const retained = [];
  const wake = cleanupWakeFixture();
  const persist = createModelRawTransportPersistence({store: f.physical,
    moon: f.moon, registration: {}, retainHolding: value => retained.push(value),
    notify: () => wake.notify()});
  const raw = Object.freeze({body: f.bytes, status: 503,
    transportComplete: false, observedAt: '2026-10-12T00:00:00.000Z'});
  // Store seal converts writer reservation to stored physical-object charge
  // before the holding manifest commits. Independently count the two AES-GCM
  // envelopes: 12-byte nonce/16-byte tag, base64 ciphertext exactly plaintext
  // length, and the closed 0.1 JSON envelope. This is not Model heap funding.
  const encryptedBytes = plaintextBytes => Buffer.byteLength(
    '{"version":"actql-private-publication-evidence/0.1","nonce":"AAAAAAAAAAAAAAAA",' +
    '"tag":"AAAAAAAAAAAAAAAAAAAAAAAA","ciphertext":""}',
  ) + Math.ceil(plaintextBytes / 3) * 4;
  const pendingBytes = encryptedBytes(f.bytes.byteLength) +
    encryptedBytes(Buffer.byteLength(f.binding.wire));
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes);
  await assert.rejects(persist(call, raw), {message: 'BeforeOriginalHoldingCommit'});
  const original = retained[0];
  assert.equal(original.holding.status().preparedPending, true);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes + pendingBytes);
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(persist.cleanup(call), false);
  await wake.wait(0);
  assert.equal(f.state.releases, 1);
  assert.equal(original.holding.status().preparedPending, true);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes + pendingBytes);
  assert.equal(persist.cleanup({}), false);
  await rawFixtureCleanup(persist, call, wake);
  assert.equal(original.holding.status().preparedPending, false);
  assert.equal(original.holding.status().abandoned, true);
  assert.equal(f.store.status().reservedBytes, 0);
  assert.equal(f.store.status().storedBytes, f.originalObjectBytes);
  assert.equal(retained.length, 1);
  assert.equal(observes, 1);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.commits, 1);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(persist.cleanup(call), true);
  assert.equal(persist.cleanup({}), false);
  await assert.rejects(persist(call, raw), {message: 'OriginalRawPersistenceRetired'});
});

test('raw persistence retry reuses the original Save and holding and refuses a substituted call or raw view', async t => {
  const f = await fixture(t, {bytes: Buffer.from('{"opaque":"original"}')});
  const call = Object.freeze({original: Symbol('original call double')});
  let observes = 0;
  f.moon.clientProgramObserveInferRawCapture = () => {
    observes++;
    return {$tag: 1, _0: f.view};
  };
  const retained = [];
  const physical = {...f.physical, async commitPhysicalHolding(...args) {
    if (f.state.commits++ === 0) throw new Error('BeforeOriginalCommit');
    await f.store.commitPhysicalHolding(...args);
  }};
  const persist = createModelRawTransportPersistence({store: physical,
    moon: f.moon, registration: {}, retainHolding: value => retained.push(value),
    notify() {}});
  const raw = Object.freeze({body: f.bytes, status: 200,
    transportComplete: true, observedAt: '2026-10-12T00:00:00.000Z'});
  await assert.rejects(persist(call, raw), {message: 'BeforeOriginalCommit'});
  const original = retained[0];
  assert.equal(original.holding.status().preparedPending, true);
  await assert.rejects(persist({}, raw), {message: 'ForeignOriginalRawPersistence'});
  await assert.rejects(persist(call, {...raw}), {message: 'ForeignOriginalRawPersistence'});
  const saved = await persist(call, raw);
  assert.equal(saved.receipt, f.receipt);
  assert.equal(retained[0], original);
  assert.equal(retained.length, 1);
  assert.equal(observes, 1);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.commits, 2);
  assert.equal(f.state.acknowledgements, 1);
  assert.equal(persist.cleanup(call), true);
  await assert.rejects(persist(call, raw), {message: 'OriginalRawPersistenceRetired'});
  assert.notEqual(await f.store.inspectPhysicalHolding(f.binding.holdingCid), undefined);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('saved raw revocation cleanup preserves durable parent custody without issuing an ACK', async t => {
  const f = await fixture(t, {revokeAfterCommit: true});
  const call = Object.freeze({original: Symbol('original call double')});
  f.moon.clientProgramObserveInferRawCapture = () => ({$tag: 1, _0: f.view});
  const retained = [];
  const persist = createModelRawTransportPersistence({store: f.physical,
    moon: f.moon, registration: {}, retainHolding: value => retained.push(value),
    notify() {}});
  await assert.rejects(persist(call, Object.freeze({body: f.bytes, status: 503,
    transportComplete: false, observedAt: '2026-10-12T00:00:00.000Z'})),
  {code: 'MoonBitHostFailure'});
  assert.equal(retained.length, 1);
  assert.equal(retained[0].holding.status().committed, true);
  assert.equal(persist.cleanup(call), true);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(f.state.writes, 1);
  assert.notEqual(await f.store.inspectPhysicalHolding(f.binding.holdingCid), undefined);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('lost raw commit reply reconciles the original durable cell without a second write or holding', async t => {
  const bytes = Buffer.from('{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}');
  const f = await fixture(t, {bytes});
  const call = Object.freeze({original: Symbol('original entered call double')});
  let observes = 0;
  let confirms = 0;
  f.moon.clientProgramObserveInferRawCapture = () => {
    observes++;
    return {$tag: 1, _0: f.view};
  };
  const retained = [];
  const physical = {...f.physical,
    async commitPhysicalHolding(...args) {
      f.state.commits++;
      await f.store.commitPhysicalHolding(...args);
      throw new Error('OriginalCommitReplyLost');
    },
    async confirmModelRawEvidence(...args) {
      if (++confirms === 2) throw new Error('OriginalReconfirmationUnavailable');
      return f.store.confirmModelRawEvidence(...args);
    },
  };
  const persist = createModelRawTransportPersistence({store: physical,
    moon: f.moon, registration: {}, retainHolding: value => retained.push(value),
    notify() {}});
  const raw = Object.freeze({body: bytes, status: 200,
    transportComplete: true, observedAt: '2026-10-12T00:00:00.000Z'});
  await assert.rejects(persist(call, raw), error => {
    assert.equal(error.message, 'OriginalCommitReplyLost');
    assert.equal(error.reconciliationFailure.message, 'OriginalReconfirmationUnavailable');
    assert.equal(error.rawCustodyRetained, true);
    assert.equal(error.cleanupHandle, retained[0].holding);
    return true;
  });
  assert.equal(f.state.acknowledgements, 0);
  assert.notEqual(await f.store.inspectPhysicalHolding(f.binding.holdingCid), undefined);
  const saved = await persist(call, raw);
  assert.equal(saved.receipt, f.receipt);
  assert.equal(saved.response.body, bytes.toString('utf8'));
  assert.equal(retained.length, 1);
  assert.equal(observes, 1);
  assert.equal(f.state.commits, 1);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.acknowledgements, 1);
  assert.equal(persist.cleanup(call), true);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('private raw port refuses revoked current facts before any encryption', async t => {
  const f = await fixture(t);
  const port = createModelRawCaptureStorePort(f.physical, f.moon, f.view, f.bytes);
  f.state.allowed = false;
  await assert.rejects(port.persist(), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.rawPersistenceConfirmed, false);
    assert.equal(error.rawCustodyRetained, true);
    assert.equal(error.cleanupHandle, port.holding);
    return true;
  });
  assert.equal(f.state.writes, 0);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(await port.holding.abort(), true);
});

test('private raw port preserves saved custody on revocation before nominal receipt adoption', async t => {
  const f = await fixture(t, {revokeAfterCommit: true});
  const port = createModelRawCaptureStorePort(f.physical, f.moon, f.view, f.bytes);
  await assert.rejects(port.persist(), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.rawPersistenceConfirmed, true);
    assert.equal(error.rawCustodyRetained, true);
    assert.equal(error.cleanupHandle, port.holding);
    return true;
  });
  assert.equal(port.holding.status().committed, true);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(await port.holding.abort(), false);
  f.state.allowed = true;
  assert.equal((await port.persist()).receipt, f.receipt);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.acknowledgements, 1);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('private raw Chat port decodes only saved bytes and preserves BOM Unicode and line endings', async t => {
  const original = '\ufeff{"text":"é\\r\\n","nested":{"empty":""}}\r\n';
  const f = await fixture(t, {bytes: Buffer.from(original, 'utf8')});
  const port = createModelRawCaptureStorePort(f.physical, f.moon, f.view, f.bytes);
  const result = await port.persistChat(undefined);
  assert.equal(result.receipt, f.receipt);
  assert.equal(result.response.body, original);
  assert.equal(result.response.actual, f.receipt);
  assert.equal(f.state.decoded.length, 1);
  assert.equal(f.state.writes, 1);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('private raw Chat port retains invalid UTF8 saved receipt without issuing a decoded response', async t => {
  const f = await fixture(t);
  const port = createModelRawCaptureStorePort(f.physical, f.moon, f.view, f.bytes);
  await assert.rejects(port.persistChat(undefined), error => {
    assert.equal(error.code, 'ERR_ENCODING_INVALID_ENCODED_DATA');
    assert.equal(error.rawPersistenceConfirmed, true);
    assert.equal(error.rawCustodyRetained, true);
    assert.equal(error.rawReceipt, f.receipt);
    assert.equal(error.cleanupHandle, port.holding);
    return true;
  });
  assert.equal(f.state.decoded.length, 0);
  assert.equal(f.state.writes, 1);
  assert.equal(port.holding.status().committed, true);
  assert.equal(await port.holding.abort(), false);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('installed raw transport caller binds actual bytes and facts before same Store receipt', async t => {
  const bytes = Buffer.from('{"opaque":"é\\r\\n"}', 'utf8');
  const f = await fixture(t, {bytes});
  const call = Object.freeze({original: Symbol('physical call double')});
  const registration = Object.freeze({original: Symbol('installed capture double')});
  const retained = [];
  let observations = 0;
  f.moon.clientProgramObserveInferRawCapture = (actual, installation, content,
    count, status, eof, at) => {
    assert.equal(actual, call);
    assert.equal(installation, registration);
    assert.equal(content, digest(bytes));
    assert.equal(count, bytes.byteLength);
    assert.equal(status, 200);
    assert.equal(eof, true);
    assert.equal(at, '2026-10-12T00:00:00.000Z');
    observations++;
    return {$tag: 1, _0: f.view};
  };
  const persist = createModelRawTransportPersistence({store: f.physical,
    moon: f.moon, registration, retainHolding: port => retained.push(port), notify() {}});
  const saved = await persist(call, {body: bytes, status: 200,
    transportComplete: true, observedAt: '2026-10-12T00:00:00.000Z'});
  assert.equal(saved.receipt, f.receipt);
  assert.equal(saved.response.body, bytes.toString('utf8'));
  assert.equal(observations, 1);
  assert.equal(retained.length, 1);
  assert.equal(retained[0].holding.status().committed, true);
  assert.equal(f.state.writes, 1);
  assert.equal(f.state.acknowledgements, 1);
  await f.store.retirePhysicalHolding(f.binding.holdingCid);
});

test('missing Host clock or foreign Core call refuses before raw persistence', async t => {
  const f = await fixture(t);
  let observations = 0;
  let holdings = 0;
  f.moon.clientProgramObserveInferRawCapture = () => {
    observations++;
    return {$tag: 0, _0: {kind: 'ForeignCall'}};
  };
  const persist = createModelRawTransportPersistence({store: f.physical,
    moon: f.moon, registration: {}, retainHolding: () => { holdings++; }, notify() {}});
  await assert.rejects(persist({}, {body: f.bytes, status: 503,
    transportComplete: false}), {message: 'MissingOriginalRawTransportFacts'});
  assert.equal(observations, 0);
  await assert.rejects(persist({}, {body: f.bytes, status: 503,
    transportComplete: false, observedAt: '2026-10-12T00:00:00.000Z'}),
  {code: 'MoonBitHostFailure'});
  assert.equal(observations, 1);
  assert.equal(holdings, 0);
  assert.equal(f.state.writes, 0);
});

test('parent custody refusal keeps same cleanup handle and performs no Store write', async t => {
  const f = await fixture(t);
  f.moon.clientProgramObserveInferRawCapture = () => ({$tag: 1, _0: f.view});
  const persist = createModelRawTransportPersistence({store: f.physical,
    moon: f.moon, registration: {}, retainHolding: () => { throw 'custody refused'; },
    notify() {}});
  let originalCleanup;
  await assert.rejects(persist({}, {body: f.bytes, status: 503,
    transportComplete: false, observedAt: '2026-10-12T00:00:00.000Z'}), error => {
    assert.equal(error.message, 'ModelRawCustodyPending');
    assert.equal(error.rawCustodyRetained, true);
    originalCleanup = error.cleanupHandle;
    return true;
  });
  assert.equal(f.state.writes, 0);
  assert.equal(f.state.acknowledgements, 0);
  assert.equal(await originalCleanup.abort(), true);
});

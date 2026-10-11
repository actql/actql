import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {createModelRawCaptureStorePort} from './infer-raw-capture.mjs';

const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const authority = digest('raw Store authority');

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-original-raw-port-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 40, maxContractNodes: 128,
    maxContractDepth: 8, privateEvidenceKey: Buffer.alloc(32, 7),
  }, createPublicationContractControlFixture());
  t.after(() => store.close());
  const originals = ['retention_contract', 'metadata_retention_policy',
    'clock_contract', 'data_policy'].map(kind => {
    const wire = JSON.stringify({independent: kind});
    return {kind, cid: digest(wire), wire};
  });
  for (const original of originals) await store.putSemantic(original.wire, original.cid);
  const bytes = options.bytes ?? Uint8Array.of(0x7b, 0xc3, 0x28, 0x7d);
  const binding = {semanticCid: digest('raw descriptor'), holdingCid: digest('raw cell'),
    wire: '{"independent":"raw descriptor"}', contentCid: digest(bytes),
    byteCount: bytes.byteLength};
  const view = Object.freeze({original: Symbol('original Model view double')});
  const receipt = Object.freeze({view});
  const state = {allowed: true, writes: 0, acknowledgements: 0, decoded: []};
  // Core installation/Entry/grant/receipt doubles only. Actual Store bytes,
  // encryption, original availability and reconfirmation run below. This does
  // not claim a joined real nominal Core receipt or public Provider acceptance.
  const moon = {
    clientProgramInferRawCaptureSaveCurrent(actual) {
      assert.equal(actual, view);
      return state.allowed ? {$tag: 1, _0: undefined}
        : {$tag: 0, _0: {kind: 'OriginalCaptureRevoked'}};
    },
    clientProgramInferRawCaptureSaveBinding(actual) {
      assert.equal(actual, view);
      return [binding.semanticCid, binding.holdingCid, binding.wire,
        binding.contentCid, binding.byteCount];
    },
    clientProgramInferRawCaptureSaveOriginals(actual) {
      assert.equal(actual, view);
      return originals.map(value => [value.kind, value.cid, value.wire]);
    },
    clientProgramAcknowledgeSavedInferRawCapture(actual) {
      assert.equal(actual, view);
      assert.equal(state.allowed, true);
      state.acknowledgements++;
      return {$tag: 1, _0: receipt};
    },
    clientProgramInferSavedRawChatResponse(actual, body, metadata) {
      assert.equal(actual, receipt);
      const response = Object.freeze({actual, body, metadata});
      state.decoded.push(response);
      return {$tag: 1, _0: response};
    },
  };
  const physical = {...store,
    async prepareModelRawEvidence(...args) {
      state.writes++;
      return store.prepareModelRawEvidence(...args);
    },
    async commitPhysicalHolding(...args) {
      await store.commitPhysicalHolding(...args);
      if (options.revokeAfterCommit) state.allowed = false;
    },
  };
  return {store, physical, moon, view, receipt, state, bytes, binding};
}

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

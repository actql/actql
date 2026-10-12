import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const authority = digest('raw Store authority');

// Shared physical Store fixture only. These independent contract/grant/Entry
// doubles cannot establish canonical admission, original funding or a Run.
export async function rawCaptureStoreFixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-original-raw-port-'));
  const storeOptions = {directory,
    storeAuthorityCid: authority, capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 40, maxContractNodes: 128,
    maxContractDepth: 8, privateEvidenceKey: Buffer.alloc(32, 7),
  };
  // Store close zeroizes its owned key. A reopened fixture receives a fresh
  // copy from this explicit test secret source, not that zeroized instance.
  const store = await openLocalPublicationStore({...storeOptions,
    privateEvidenceKey: Buffer.from(storeOptions.privateEvidenceKey)},
    createPublicationContractControlFixture());
  t.after(async () => {
    // Keep the original Store and directory until the same close confirms
    // release; removing owner.json first cannot authorize successful cleanup.
    assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
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
  const state = {allowed: true, writes: 0, acknowledgements: 0, decoded: [],
    commits: 0, releases: 0};
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
      const originals = await store.prepareModelRawEvidence(...args);
      if (!options.releaseFailure) return originals;
      return originals.map(value => ({...value, prepared: {
        status: () => value.prepared.status(),
        async release() {
          if (++state.releases === 1) throw new Error('OriginalWriterReleaseFailed');
          return value.prepared.release();
        },
      }}));
    },
    async commitPhysicalHolding(...args) {
      state.commits++;
      if (options.refuseCommit) throw new Error('BeforeOriginalHoldingCommit');
      await store.commitPhysicalHolding(...args);
      if (options.revokeAfterCommit) state.allowed = false;
    },
  };
  return {store, storeOptions, physical, moon, view, receipt, state, bytes, binding,
    originalObjectBytes: originals.reduce((sum, value) => sum + Buffer.byteLength(value.wire), 0)};
}

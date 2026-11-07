// Actual installed capture/cleanup composition and physical Store. Common
// candidate/funding ports are explicit fixtures, not public admission evidence.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function fixture(t, installedBeforeFailure) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'keyed-holding-cleanup-', label: 'original keyed holding cleanup'});
  const directory = join(scratch.path, 'store');
  const bytes = Buffer.from('independent captured Content bytes\n');
  const holdingCid = cid('original capture holding'), scope = cid('original scope');
  const policy = cid('original Source policy'), authority = cid('original Store authority');
  const fault = Object.assign(new Error('Independent capture commit reply lost'), {code: 'EIO'});
  let rejectCommit = false, pending, prepared, execution, current = true;
  const counts = {writers: 0, candidates: 0, commits: 0, reserves: 0, releases: 0, issues: 0};
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: authority,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32}, createPublicationContractControlFixture(), {
    async syncDirectory(path) {
      if (rejectCommit && path === join(directory, 'physical-holdings')) throw fault;
      const fd = await open(path, 'r');
      try { await fd.sync(); } finally { await fd.close(); }
    },
  });
  // Arm the lost-commit fault after the Store has initialized its directories.
  rejectCommit = true;
  const physical = {...store,
    createPreparedObjectWriter(maximum) {
      counts.writers++;
      const writer = store.createPreparedObjectWriter(maximum);
      return {...writer, async seal(expected) {
        const value = await writer.seal(expected);
        prepared = value.prepared;
        return value;
      }};
    },
    async commitPhysicalHolding(value, handles) {
      counts.commits++;
      pending = value;
      if (!installedBeforeFailure && rejectCommit) throw fault;
      return store.commitPhysicalHolding(value, handles);
    },
  };
  const compiled = {}, program = {}, acquisition = {}, ledger = {}, reservation = {};
  const candidate = {};
  const description = {storeCid: authority, workspaceScopeCid: scope,
    effectiveDataPolicyCid: policy, mediaType: 'text/plain', contentCid: cid(bytes),
    identity: cid('independent candidate'), sizeBytes: bytes.length,
    wire: '{"fixture":"original candidate, not issued authority"}'};
  const control = {
    reserveWorkspace(original) { assert.equal(original, ledger); counts.reserves++; return reservation; },
    growWorkspace(original, handle, maximum, count) {
      assert.equal(original, ledger); assert.equal(handle, reservation);
      assert.equal(maximum, 4096); assert.equal(count, 1);
    },
    releaseWorkspace(original, handle) {
      assert.equal(original, ledger); assert.equal(handle, reservation);
      assert.equal(prepared.status().pending, false, 'original physical child retires before funding');
      counts.releases++;
    },
    reissuer: () => ({}),
    candidateForRun(...args) {
      assert.equal(args[0], compiled); assert.equal(args[2], acquisition);
      counts.candidates++; return candidate;
    },
    inspect(value) { assert.equal(value, candidate); return description; },
    holdingCid: () => holdingCid,
    issuer() { counts.issues++; assert.fail('failed capture cleanup must not issue a reference'); },
  };
  const owner = installRunKeyedContentCapture({
    moon: {clientProgramKeyedAcquisitionMatchesProgram: () => true,
      clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ({$tag: 1,
        _0: ['fixture Source', cid('contract'), cid('schema'), policy, 'internal', cid('view')]}),
      clientProgramKeyedLookupCapacity: () => assert.fail('static count is not a workspace prerequisite')},
    publications: {checkClientCompiledRunOwner() {}, checkClientCompiledRunDefinition() {}},
    control, preparedProgram: program, plan: {compiled, runDefinition: {
      identity: cid('original Run'), wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'}},
    acquisition, ledger, maxBytes: 4096, store: physical, namespaceId: 'fixture',
    authorityScopeCid: scope, storeAuthorityCid: authority, principalId: 'fixture',
    ownerPrincipal: 'fixture', now: () => '2026-10-13T00:00:00.000Z',
    authorize: () => current, inputAvailable: () => current,
    retainExecution(value) { execution = value; },
  });
  t.after(async () => {
    rejectCommit = false;
    try {
      if (pending !== undefined && await store.inspectPhysicalHolding(holdingCid) !== undefined) {
        await store.commitPhysicalHolding(pending, []);
      }
      if (prepared?.status().pending) await prepared.release();
      if (!store.status().closed) await store.close();
    } catch (error) { t.diagnostic(`Original diagnostic custody retained: ${error.code ?? error.message}`); }
  });
  return {scratch, bytes, store, owner, counts, fault, holdingCid,
    execution: () => execution, prepared: () => prepared,
    capture: () => owner.capture({keyedAcquisition: acquisition, request: {},
      verifyRead: async () => { assert.equal(current, true); }, readSubjectCid: cid('original read'),
      bytes, contentCid: cid(bytes), mediaType: 'text/plain'}),
    allowConfirmation() { rejectCommit = false; current = false; }};
}

test('installed keyed cleanup confirms the same lost holding before releasing original funding', async t => {
  const f = await fixture(t, true);
  await assert.rejects(f.capture(), error => error === f.fault);
  assert.equal(f.prepared().status().pending, true);
  const execution = f.execution();
  await assert.rejects(execution.cleanup(), error => error === f.fault);
  assert.equal(execution.cleanupPending(), true);
  assert.equal(f.counts.releases, 0);
  assert.deepEqual(await readFile(join(f.scratch.path, 'store', 'objects', cid(f.bytes).slice(7))), f.bytes);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  f.allowConfirmation();
  // Current execution authority is now absent. Same-owner cleanup must still
  // reconcile original custody, without granting another capture or send.
  const retry = execution.cleanup();
  assert.strictEqual(execution.close(), retry);
  assert.equal(await retry, true);
  assert.equal(f.prepared().status().pending, false);
  assert.equal(f.counts.releases, 1);
  assert.equal(f.counts.writers, 1);
  assert.equal(f.counts.candidates, 1);
  assert.equal(f.counts.commits, 3);
  assert.equal(f.counts.issues, 0);
  assert.equal(f.store.status().storedBytes, f.bytes.length, 'temporary cleanup preserves committed Content');
  const counts = {...f.counts};
  assert.equal(await execution.cleanup(), true);
  assert.deepEqual(f.counts, counts, 'acknowledged cleanup does not confirm or settle twice');
  await f.store.retirePhysicalHolding(f.holdingCid);
  await f.store.close();
  f.scratch.passed();
});

test('installed keyed cleanup releases a not-installed holding without inventing a commit', async t => {
  const f = await fixture(t, false);
  await assert.rejects(f.capture(), error => error === f.fault);
  assert.equal(await f.store.inspectPhysicalHolding(f.holdingCid), undefined);
  assert.equal(await f.execution().cleanup(), true);
  assert.equal(f.prepared().status().pending, false);
  assert.equal(f.counts.releases, 1);
  assert.equal(f.counts.commits, 1, 'cleanup of an absent holding never creates it');
  assert.equal(f.counts.writers, 1);
  assert.equal(f.counts.candidates, 1);
  assert.equal(f.counts.issues, 0);
  assert.equal(f.store.status().storedBytes, 0);
  await f.store.close();
  f.scratch.passed();
});

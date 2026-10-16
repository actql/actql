// Real encrypted Store and private holding owner; the contract-control fixture
// and injected commit/confirmation faults do not prove genuine Core admission.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createPublicationContractControlFixture} from './publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {preparePrivatePublicationHolding} from './private-publication-holding.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function fixture(t, lostReply, originalFailure) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-private-frozen-failure-'));
  const binding = Object.freeze({name: 'source_evidence',
    semanticCid: cid('frozen original semantic'), holdingCid: cid('frozen original holding'),
    wire: '{"original":null}'});
  const primary = originalFailure ?? Object.freeze(Object.assign(new Error('OriginalPrivateCommitFailure'),
    {code: 'OriginalPrivateCommitFailure'}));
  const secondary = Object.freeze(new Error('OriginalPrivateReconciliationFailure'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('frozen original authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32}, createPublicationContractControlFixture());
  let injected = true, afterCommit = false;
  const counts = {prepare: 0, commit: 0, confirm: 0};
  const owner = preparePrivatePublicationHolding({
    async confirmPrivateEvidence(value) {
      counts.confirm++;
      if (injected && lostReply && afterCommit) throw secondary;
      return store.confirmPrivateEvidence(value);
    },
    async preparePrivateEvidence(...args) {
      counts.prepare++;
      return store.preparePrivateEvidence(...args);
    },
    async commitPhysicalHolding(...args) {
      counts.commit++;
      if (injected && !lostReply) throw primary;
      const result = await store.commitPhysicalHolding(...args);
      afterCommit = true;
      if (injected) throw primary;
      return result;
    },
  }, binding);
  // Reconcile only this fixture's original holding before teardown. Failure
  // leaves its directory and original cleanup responsibility intact.
  t.after(async () => {
    injected = false;
    await owner.abort();
    if (await store.inspectPhysicalHolding(binding.holdingCid) !== undefined) {
      await store.retirePhysicalHolding(binding.holdingCid);
    }
    assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  return {store, owner, binding, primary, secondary, counts,
    reconcile() { injected = false; }};
}

for (const lostReply of [false, true]) {
  test(`private holding exports same cleanup custody for frozen ${lostReply ? 'lost reply and failed reconciliation' : 'pre-commit failure'}`, async t => {
    const f = await fixture(t, lostReply);
    await assert.rejects(f.owner.commit(), error => {
      assert.equal(error.code, f.primary.code);
      assert.equal(error.cause, f.primary);
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle, f.owner);
      if (lostReply) assert.equal(error.reconciliationFailure, f.secondary);
      return true;
    });
    assert.equal(f.owner.status().committed, false);
    assert.equal(Object.hasOwn(f.primary, 'cleanupHandle'), false);
    assert.equal(Object.hasOwn(f.primary, 'reconciliationFailure'), false);
    f.reconcile();
    const record = await f.owner.retry();
    assert.equal(record.holding_cid, f.binding.holdingCid);
    assert.equal(f.owner.status().committed, true);
    assert.equal(f.owner.status().preparedPending, false);
    assert.equal(f.counts.prepare, 1);
    assert.equal(f.counts.commit, lostReply ? 1 : 2);
    assert.equal((await f.store.readPrivateEvidence(f.binding.name,
      f.binding.semanticCid, f.binding.holdingCid)).toString('utf8'), f.binding.wire);
  });
}

test('private holding preserves untouched frozen confirmation failure before acquiring custody', async () => {
  const primary = Object.freeze(new Error('OriginalOpeningConfirmationFailure'));
  let preparations = 0, commits = 0;
  const owner = preparePrivatePublicationHolding({
    async confirmPrivateEvidence() { throw primary; },
    async preparePrivateEvidence() { preparations++; },
    async commitPhysicalHolding() { commits++; },
  }, {name: 'source_evidence', semanticCid: cid('unacquired semantic'),
    holdingCid: cid('unacquired holding'), wire: 'null'});
  await assert.rejects(owner.commit(), error => error === primary);
  assert.equal(owner.status().preparedPending, false);
  assert.deepEqual({preparations, commits}, {preparations: 0, commits: 0});
});

const diagnosticFields = ['cleanupPending', 'cleanupHandle', 'reconciliationFailure'];
const originalFailure = () => Object.assign(new Error('OriginalPrivateCommitFailure'),
  {code: 'OriginalPrivateCommitFailure'});
const staleHandle = Object.freeze({original: 'unrelated diagnostic handle'});
const staleReconciliation = Object.freeze(new Error('EarlierReconciliationFailure'));
const existingValue = field => field === 'cleanupPending' ? false
  : field === 'cleanupHandle' ? staleHandle : staleReconciliation;
const descriptorCases = diagnosticFields.map(field => ({
  name: `own read-only ${field}`,
  create() {
    const primary = Object.defineProperty(originalFailure(), field, {value: existingValue(field)});
    const descriptor = Object.getOwnPropertyDescriptor(primary, field);
    return {primary, wraps: true, check() {
      assert.deepEqual(Object.getOwnPropertyDescriptor(primary, field), descriptor);
    }};
  },
}));
descriptorCases.push({
  name: 'inherited read-only cleanupHandle',
  create() {
    const primary = originalFailure();
    const prototype = Object.defineProperty(Object.create(Error.prototype),
      'cleanupHandle', {value: staleHandle});
    Object.setPrototypeOf(primary, prototype);
    return {primary, wraps: true, check() {
      assert.equal(Object.getPrototypeOf(primary), prototype);
      assert.equal(Object.hasOwn(primary, 'cleanupHandle'), false);
    }};
  },
}, {
  name: 'accessor cleanupHandle without invoking it',
  create() {
    let accesses = 0;
    const primary = Object.defineProperty(originalFailure(), 'cleanupHandle', {
      get() { accesses++; return staleHandle; },
      set() { accesses++; throw new Error('DiagnosticSetterMustNotRun'); },
    });
    return {primary, wraps: true, check() { assert.equal(accesses, 0); }};
  },
}, {
  name: 'existing writable diagnostics without replacing the original',
  create() {
    const primary = Object.assign(originalFailure(), {cleanupPending: false,
      cleanupHandle: staleHandle, reconciliationFailure: staleReconciliation});
    return {primary, wraps: false, check() {}};
  },
});

for (const descriptorCase of descriptorCases) {
  for (const lostReply of [false, true]) {
    test(`private holding preserves ${descriptorCase.name} during ${lostReply ? 'lost reply and failed reconciliation' : 'pre-commit failure'}`, async t => {
      const original = descriptorCase.create();
      assert.equal(Object.isExtensible(original.primary), true);
      const descriptors = Object.getOwnPropertyDescriptors(original.primary);
      const f = await fixture(t, lostReply, original.primary);
      await assert.rejects(f.owner.commit(), error => {
        assert.equal(error.code, f.primary.code);
        if (original.wraps) {
          assert.notEqual(error, f.primary);
          assert.equal(error.cause, f.primary);
        } else {
          assert.equal(error, f.primary);
        }
        assert.equal(error.cleanupPending, true);
        assert.equal(error.cleanupHandle, f.owner);
        if (lostReply) assert.equal(error.reconciliationFailure, f.secondary);
        return true;
      });
      original.check();
      if (original.wraps) {
        assert.deepEqual(Object.getOwnPropertyDescriptors(f.primary), descriptors);
      }
      assert.equal(f.owner.status().committed, false);
      assert.equal(f.owner.status().operationPending, false);
      assert.equal(f.counts.prepare, 1);
      assert.equal(f.counts.commit, 1);
      f.reconcile();
      const record = await f.owner.retry();
      assert.equal(record.holding_cid, f.binding.holdingCid);
      assert.equal(f.owner.status().committed, true);
      assert.equal(f.owner.status().preparedPending, false);
      assert.equal(f.counts.prepare, 1);
      assert.equal(f.counts.commit, lostReply ? 1 : 2);
      assert.equal((await f.store.readPrivateEvidence(f.binding.name,
        f.binding.semanticCid, f.binding.holdingCid)).toString('utf8'), f.binding.wire);
    });
  }
}

for (const field of diagnosticFields) {
  test(`private holding preserves unacquired failure identity with read-only ${field}`, async () => {
    const primary = Object.defineProperty(originalFailure(), field, {value: existingValue(field)});
    const descriptors = Object.getOwnPropertyDescriptors(primary);
    let preparations = 0, commits = 0;
    const owner = preparePrivatePublicationHolding({
      async confirmPrivateEvidence() { throw primary; },
      async preparePrivateEvidence() { preparations++; },
      async commitPhysicalHolding() { commits++; },
    }, {name: 'source_evidence', semanticCid: cid('unacquired semantic'),
      holdingCid: cid('unacquired holding'), wire: 'null'});
    await assert.rejects(owner.commit(), error => error === primary);
    assert.equal(owner.status().preparedPending, false);
    assert.deepEqual(Object.getOwnPropertyDescriptors(primary), descriptors);
    assert.deepEqual({preparations, commits}, {preparations: 0, commits: 0});
  });
}

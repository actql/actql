import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

async function fixture(effectRequirements) {
  const root = await mkdtemp(join(tmpdir(), 'actql-ordinary-result-'));
  const originals = Object.freeze({host: {}, installation: {root}, generation: {},
    supplier() {}, moduleLifetime: import.meta});
  const journal = prepareOrdinaryHostJournal(originals);
  await journal.admitRootFormat(root);
  const native = await journal.openRequestJournal(join(root, 'requests'), {});
  const control = Object.freeze(Object.fromEntries(['admit', 'recordTransition', 'deliveryTransition',
    'deliverySuccessValid', 'trustedClockNotBefore', 'recordAllowsCommit', 'effectFreeCommitValid']
    .map(name => [name, () => assert.fail(name + ' unused')])));
  const subject = Object.freeze({root, principalId: 'ordinary-test', control,
    storeAuthorityCid: 'sha256:' + 'a'.repeat(64)});
  const prepared = Object.freeze({});
  const view = prepareOrdinaryHostResult(originals, subject, (held, value) => {
    assert.strictEqual(held, originals); assert.strictEqual(value, prepared);
    return Object.freeze({resultCount: 1, maxRows: 100, maxContractBytes: 1000000});
  }, effectRequirements);
  const options = {directory: join(root, 'publication'), storeAuthorityCid: subject.storeAuthorityCid,
    capacityBytes: 536870912, maxObjectBytes: 10000000, maxObjects: 10000,
    maxContractNodes: 10000, maxContractDepth: 64};
  return {root, originals, journal, native, control, subject, prepared, view, options};
}

test('ordinary Result acquires the actual same-Host Store and retains separate Journal cleanup', async () => {
  const f = await fixture();
  f.view.admitRun(f.prepared);
  const first = f.view.openStore(f.options, f.control);
  assert.strictEqual(f.view.openStore(f.options, f.control), first);
  const store = await first;
  assert.equal(store.status().closed, false);
  assert.equal(store.publicationCapacitySupports({requiredBytes: 1, objectCount: 1, maxObjectBytes: 1}), true);
  assert.equal(observeOriginalClientRequestJournalCustody(f.native).databaseClosed, false);
  await f.journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(f.native).databaseClosed, true);
  assert.equal((await f.view.close()).pending, false);
  assert.equal(store.status().closed, true);
  assert.equal((await f.journal.close()).pending, false);
});

test('ordinary Result refuses another control or key authority before Store work without fallback', async () => {
  const f = await fixture();
  assert.throws(() => f.view.openStore(f.options, {...f.control}));
  assert.throws(() => f.view.openStore({...f.options, privateEvidenceKey: Buffer.alloc(32)}, f.control));
  assert.throws(() => f.view.admitRun({}));
  assert.equal((await f.view.close()).pending, false);
  assert.equal((await f.journal.close()).pending, false);
});

test('ordinary Model publication uses the same admitted Run and live Store, not copied limits', async () => {
  const f = await fixture();
  try {
    assert.throws(() => f.view.modelPublicationCapacity(f.prepared),
      {message: 'HostResultPublicationRunUnavailable'});
    f.view.admitRun(f.prepared);
    assert.throws(() => f.view.modelPublicationCapacity(f.prepared),
      {message: 'HostResultPublicationRunUnavailable'});
    await f.view.openStore(f.options, f.control);
    const selected = f.view.modelPublicationCapacity(f.prepared);
    assert.deepEqual(selected, {retainedBytes: 1000000n, workspaceBytes: 1000000n});
    assert.equal(Object.isFrozen(selected), true);
    f.view.admitRun(f.prepared);
    assert.strictEqual(f.view.modelPublicationCapacity(f.prepared), selected);
    assert.throws(() => f.view.modelPublicationCapacity({...f.prepared}),
      {message: 'HostResultPublicationRunUnavailable'});
    assert.throws(() => Reflect.apply(f.view.modelPublicationCapacity, {}, [f.prepared]),
      {message: 'ForeignInstalledHostPublicationStore'});
    await f.journal.close();
    assert.throws(() => f.view.modelPublicationCapacity(f.prepared));
  } finally {
    await f.view.close();
    assert.equal((await f.journal.close()).pending, false);
  }
});

test('ordinary Effect publication retains its own same-Host purpose without converting Pure admission', async () => {
  let calls = 0;
  const f = await fixture((originals, prepared) => {
    assert.strictEqual(originals, f.originals); assert.strictEqual(prepared, f.prepared);
    calls++;
    return {resultCount: 1, maxRows: 100, maxContractBytes: 1000000};
  });
  try {
    f.view.admitEffectRun(f.prepared);
    await f.view.openStore(f.options, f.control);
    assert.deepEqual(f.view.modelPublicationCapacity(f.prepared),
      {retainedBytes: 1000000n, workspaceBytes: 1000000n});
    f.view.admitEffectRun(f.prepared);
    assert.equal(calls, 2);
    assert.throws(() => f.view.admitRun(f.prepared), {message: 'HostResultPublicationChanged'});
    assert.throws(() => f.view.admitEffectRun({}));
  } finally {
    await f.journal.close();
    await f.view.close();
    assert.equal((await f.journal.close()).pending, false);
  }
});

test('ordinary Effect publication refuses an absent supplier and never borrows the Pure callback', async () => {
  const f = await fixture();
  try {
    assert.throws(() => f.view.admitEffectRun(f.prepared), {message: 'HostEffectResultPublicationUnavailable'});
    f.view.admitRun(f.prepared);
  } finally {
    await f.journal.close();
    await f.view.close();
    assert.equal((await f.journal.close()).pending, false);
  }
});

test('ordinary command-only Effect retains its Result purpose with zero requested Named Results', async () => {
  let resultCount = 0;
  const f = await fixture((originals, prepared) => {
    assert.strictEqual(originals, f.originals); assert.strictEqual(prepared, f.prepared);
    return {resultCount, maxRows: 100, maxContractBytes: 1000000};
  });
  const pure = prepareOrdinaryHostResult(f.originals, f.subject,
    () => ({resultCount: 0, maxRows: 100, maxContractBytes: 1000000}));
  try {
    assert.throws(() => pure.admitRun(f.prepared), {message: 'HostResultPublicationUnsupported'});
    f.view.admitEffectRun(f.prepared);
    const store = await f.view.openStore(f.options, f.control);
    assert.equal(store.status().closed, false);
    const capacity = f.view.modelPublicationCapacity(f.prepared);
    assert.deepEqual(capacity, {retainedBytes: 1000000n, workspaceBytes: 1000000n});
    f.view.admitEffectRun(f.prepared);
    assert.strictEqual(f.view.modelPublicationCapacity(f.prepared), capacity);
    assert.throws(() => f.view.admitRun(f.prepared), {message: 'HostResultPublicationChanged'});
    resultCount = 1;
    assert.throws(() => f.view.admitEffectRun(f.prepared), {message: 'HostResultPublicationChanged'});
    assert.throws(() => f.view.admitEffectRun({...f.prepared}));
    await f.journal.close();
    assert.throws(() => f.view.admitEffectRun(f.prepared), {code: 'HostJournalPreparationUnavailable'});
  } finally {
    await pure.close();
    await f.journal.close();
    assert.equal((await f.view.close()).pending, false);
    assert.equal((await f.journal.close()).pending, false);
  }
});

test('ordinary command-only Effect preserves finite result, row and contract limits', async () => {
  let value;
  const f = await fixture(() => value);
  try {
    const valid = {resultCount: 0, maxRows: 100, maxContractBytes: 1000000};
    for (const change of [{resultCount: -1}, {resultCount: 0.5}, {resultCount: 11}, {resultCount: NaN},
      {maxRows: -1}, {maxRows: 10001}, {maxContractBytes: 0}, {maxContractBytes: 2147483648}]) {
      value = {...valid, ...change};
      assert.throws(() => f.view.admitEffectRun(f.prepared), {message: 'HostResultPublicationUnsupported'});
    }
  } finally {
    await f.journal.close();
    assert.equal((await f.view.close()).pending, false);
    assert.equal((await f.journal.close()).pending, false);
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

async function fixture() {
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
    return Object.freeze({resultCount: 1, maxRows: 100});
  });
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

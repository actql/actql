import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareHostJournalInstallation} from './node-host-journal-installation.mjs';
import {observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), 'actql-ordinary-journal-'));
  const originals = Object.freeze({host: {}, installation: {root}, generation: {},
    supplier() {}, moduleLifetime: import.meta});
  const view = await prepareHostJournalInstallation(originals);
  await view.admitRootFormat(root);
  return {root, originals, view};
}

test('ordinary actual Journal opens independent Hosts and reopens the same saved state in one process', async () => {
  const a = await fixture(), b = await fixture();
  assert.equal(await a.view.admitRootFormat(a.root), 'new');
  assert.equal(await b.view.admitRootFormat(b.root), 'new');
  const ja = await a.view.openRequestJournal(join(a.root, 'requests'), {});
  const jb = await b.view.openRequestJournal(join(b.root, 'requests'), {});
  assert.equal(observeOriginalClientRequestJournalCustody(ja).databaseClosed, false);
  assert.equal(observeOriginalClientRequestJournalCustody(jb).databaseClosed, false);
  ja.observationStorage();
  assert.equal(observeOriginalClientRequestJournalCustody(ja).observationDatabaseClosed, false);
  assert.equal((await a.view.close()).pending, false);
  assert.equal(observeOriginalClientRequestJournalCustody(ja).databaseClosed, true);
  assert.equal(observeOriginalClientRequestJournalCustody(ja).observationDatabaseClosed, true);
  b.view.assertCurrent();
  const reopened = await prepareHostJournalInstallation(a.originals);
  assert.equal(await reopened.admitRootFormat(a.root), 'current');
  const ja2 = await reopened.openRequestJournal(join(a.root, 'requests'), {});
  assert.notStrictEqual(ja2, ja);
  assert.equal((await reopened.close()).pending, false);
  assert.equal((await b.view.close()).pending, false);
  // New test state remains at its original path; no old Run/key is replayed.
});

test('ordinary Journal serializes the same-root writer before SQLite and keeps one acquisition', async () => {
  const a = await fixture();
  const original = a.view.openRequestJournal(join(a.root, 'requests'), {});
  await assert.rejects(a.view.openRequestJournal(join(a.root, 'requests'), {}),
    {name: 'TypeError', message: 'ForeignInstalledHostJournal'});
  const journal = await original;
  const other = await prepareHostJournalInstallation({...a.originals, host: {}, generation: {}});
  await assert.rejects(other.openRequestJournal(join(a.root, 'requests'), {}));
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, false);
  assert.equal((await other.close()).pending, false);
  assert.equal((await a.view.close()).pending, false);
});

test('ordinary Journal forwards only its prepared Store exclusion once and closes after its own native ACK', async () => {
  const a = await fixture();
  assert.throws(() => a.view.publicationOwnership());
  await assert.rejects(a.view.openRequestJournal(join(a.root, 'foreign'), {}));
  const journal = await a.view.openRequestJournal(join(a.root, 'requests'), {});
  const ownership = a.view.publicationOwnership();
  assert.equal(typeof ownership, 'object');
  assert.throws(() => a.view.publicationOwnership());
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  assert.equal((await a.view.close()).pending, false);
  assert.throws(() => a.view.assertCurrent());
});

test('ordinary Journal close retains an ownership acquisition already in flight', async () => {
  const a = await fixture();
  const opening = a.view.openRequestJournal(join(a.root, 'requests'), {});
  const rejected = assert.rejects(opening, {code: 'InstalledHostJournalCleanupPending'});
  assert.equal((await a.view.close()).pending, false);
  await rejected;
  // A new Host can acquire this new test directory only after the original
  // opening/close has actually released its exclusion, not merely its Promise.
  const b = await prepareHostJournalInstallation({...a.originals, host: {}, generation: {}});
  await b.openRequestJournal(join(a.root, 'requests'), {});
  assert.equal((await b.close()).pending, false);
});

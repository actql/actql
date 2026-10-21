import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {prepareHostJournalInstallation} from './node-host-journal-installation.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

test('owned native admission requires the same live Store original and preserves default limits', async () => {
  const a = await fixture(), b = await fixture();
  const original = a.view.privateEvidenceInitializationOwnership();
  const directory = join(a.root, 'requests');
  for (const foreign of [true, {}, {...original}, b.view.privateEvidenceInitializationOwnership()]) {
    assert.throws(() => openClientRequestJournal(directory, {}, foreign));
  }
  assert.throws(() => openClientRequestJournal(join(a.root, 'other'), {}, original));
  const journal = openClientRequestJournal(directory, {}, original);
  journal.close();
  const reopened = openClientRequestJournal(directory, {}, original);
  reopened.close();
  assert.equal((await a.view.close()).pending, false);
  assert.throws(() => openClientRequestJournal(directory, {}, original));
  assert.equal((await b.view.close()).pending, false);
});

for (const mutation of ['PRAGMA user_version=99', 'DROP TABLE client_submitted_intent_usage']) {
  test('owned native admission refuses adopted metadata loss without recreating it: ' + mutation, async () => {
    const a = await fixture();
    await a.view.openRequestJournal(join(a.root, 'requests'), {});
    assert.equal((await a.view.close()).pending, false);
    const path = join(a.root, 'requests', 'client-requests.sqlite3');
    const database = new DatabaseSync(path);
    try {database.exec(mutation);} finally {database.close();}
    const reopened = await prepareHostJournalInstallation({...a.originals, host: {}, generation: {}});
    await assert.rejects(reopened.openRequestJournal(join(a.root, 'requests'), {}));
    assert.equal((await reopened.close()).pending, false);
    const observed = new DatabaseSync(path, {readOnly: true});
    try {
      if (mutation.startsWith('PRAGMA')) {
        assert.equal(observed.prepare('PRAGMA user_version').get().user_version, 99);
      } else {
        assert.equal(observed.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name='client_submitted_intent_usage'").get().n, 0);
      }
    } finally {observed.close();}
  });
}

test('owned native format refusal retains the captured close and Store exclusion until its real ACK', () => {
  const script = `
    import assert from 'node:assert/strict';
    import fs from 'node:fs';
    import {tmpdir} from 'node:os';
    import {join} from 'node:path';
    import {DatabaseSync} from 'node:sqlite';
    const {prepareOrdinaryHostJournal}=await import(${JSON.stringify(new URL('./ordinary-host-journal.mjs', import.meta.url).href)});
    const root=fs.mkdtempSync(join(tmpdir(),'actql-owned-journal-fault-'));
    const originals=()=>({host:{},installation:{root},generation:{},supplier(){},moduleLifetime:import.meta});
    const first=prepareOrdinaryHostJournal(originals());
    await first.admitRootFormat(root);
    await first.openRequestJournal(join(root,'requests'),{});
    assert.equal((await first.close()).pending,false);
    const db=new DatabaseSync(join(root,'requests','client-requests.sqlite3'));
    db.exec('PRAGMA user_version=99');db.close();
    const nativeClose=DatabaseSync.prototype.close,nativeOpen=DatabaseSync.prototype.open;
    let allow=false,closes=0,replacements=0,opens=0;
    const failure=new Error('OriginalNativeClosePending');
    DatabaseSync.prototype.close=function(){closes++;if(!allow)throw failure;return Reflect.apply(nativeClose,this,[]);};
    DatabaseSync.prototype.open=function(){opens++;const result=Reflect.apply(nativeOpen,this,[]);this.close=()=>{replacements++;};return result;};
    const current=prepareOrdinaryHostJournal(originals());
    await current.admitRootFormat(root);
    await assert.rejects(current.openRequestJournal(join(root,'requests'),{}));
    assert.equal(closes,1);assert.equal(opens,1);
    const owner=join(root,'publication','owner','owner.json');
    const token=fs.readFileSync(owner,'utf8');
    assert.equal((await current.close()).pending,true);
    assert.equal(fs.readFileSync(owner,'utf8'),token);
    // The first owner observation captures the opening failure's cleanup
    // handle. The next retry operates on that same captured native child.
    assert.equal(closes,1);
    assert.equal((await current.close()).pending,true);
    assert.equal(fs.readFileSync(owner,'utf8'),token);
    assert.equal(closes,2);assert.equal(opens,1);assert.equal(replacements,0);
    allow=true;
    assert.equal((await current.close()).pending,false);
    assert.equal(closes,3);assert.equal(opens,1);assert.equal(replacements,0);
    assert.equal(fs.existsSync(owner),false);
    DatabaseSync.prototype.close=nativeClose;DatabaseSync.prototype.open=nativeOpen;
  `;
  execFileSync(process.execPath, ['--input-type=module', '-e', script],
    {encoding: 'utf8', maxBuffer: 1024 * 1024});
});

test('ordinary owned Journal reopens with native admission without copying retired history', () => {
  const script = `
    import assert from 'node:assert/strict';
    import fs from 'node:fs';
    import {syncBuiltinESMExports} from 'node:module';
    import {tmpdir} from 'node:os';
    import {join} from 'node:path';
    import {DatabaseSync} from 'node:sqlite';
    let copiedBytes=0,copies=0;
    const read=fs.readSync,temporary=fs.mkdtempSync;
    fs.readSync=function(fd,buffer,...args){const count=Reflect.apply(read,this,[fd,buffer,...args]);if(buffer.byteLength===65536)copiedBytes+=count;return count;};
    fs.mkdtempSync=function(prefix,...args){if(prefix.includes('actql-journal-format-'))copies++;return Reflect.apply(temporary,this,[prefix,...args]);};
    syncBuiltinESMExports();
    const {prepareOrdinaryHostJournal}=await import(${JSON.stringify(new URL('./ordinary-host-journal.mjs', import.meta.url).href)});
    const root=fs.mkdtempSync(join(tmpdir(),'actql-owned-journal-native-'));
    const originals=()=>({host:{},installation:{root},generation:{},supplier(){},moduleLifetime:import.meta});
    const first=prepareOrdinaryHostJournal(originals());
    await first.admitRootFormat(root);
    await first.openRequestJournal(join(root,'requests'),{});
    assert.equal((await first.close()).pending,false);
    const path=join(root,'requests','client-requests.sqlite3');
    const database=new DatabaseSync(path);
    database.exec('BEGIN IMMEDIATE');
    const insert=database.prepare("INSERT INTO client_submitted_intents(submission_id,authority_scope_cid,nonce,epoch_wire,intent_cid,intent_wire,accepted_at,phase)VALUES(?,?,?,?,?,?,0,'preparing')");
    for(let index=0;index<128;index++)insert.run('retired-'+index,'scope','nonce','{}','intent','x'.repeat(8192));
    database.exec('DELETE FROM client_submitted_intents; COMMIT');
    database.close();
    assert(fs.statSync(path).size>1048576);
    copiedBytes=copies=0;
    const reopened=prepareOrdinaryHostJournal(originals());
    await reopened.admitRootFormat(root);
    await reopened.openRequestJournal(join(root,'requests'),{});
    assert.equal((await reopened.close()).pending,false);
    assert.equal(copiedBytes,0,'owned ordinary open must not copy DB/WAL history through JS');
    assert.equal(copies,0,'owned ordinary open must not create an isolated SQLite inspection copy');
    console.log(JSON.stringify({copies,copiedBytes,databaseBytes:fs.statSync(path).size}));
  `;
  execFileSync(process.execPath, ['--input-type=module', '-e', script],
    {encoding: 'utf8', maxBuffer: 1024 * 1024});
});

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

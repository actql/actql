import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {prepareHostJournalInstallation} from './node-host-journal-installation.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

async function selectedRowsFixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-journal-selected-rows-'));
  const journal = openClientRequestJournal(directory);
  t.after(() => journal.close());
  // Explicit request-control fixture, not Common issuance or authorization.
  // Native SQLite and the Journal's actual row-selection paths are unchanged.
  const keys = ['authorityScopeCid', 'requestId', 'programDefinitionCid',
    'parameterValuesCid', 'callerInputIntentCid', 'logicalRequestScopeCid', 'intentFingerprintCid'];
  const cid = digit => 'sha256:' + digit.repeat(64);
  const control = {clientRequestAdmitRecord(...fields) {
    return Object.freeze(Object.fromEntries(keys.map((key, index) => [key, fields[index]])));
  }, clientRequestRelation(a, b) {
    return keys.every(key => a[key] === b[key]) ? 1 : 2;
  }};
  for (const [method, key] of Object.entries({clientRequestAuthorityScopeCid: 'authorityScopeCid',
    clientRequestCallerId: 'requestId', clientRequestScopeCid: 'logicalRequestScopeCid',
    clientRequestIntentCid: 'intentFingerprintCid', clientRequestProgramCid: 'programDefinitionCid',
    clientRequestParametersCid: 'parameterValuesCid', clientRequestInputCid: 'callerInputIntentCid'})) {
    control[method] = value => value[key];
  }
  let selected;
  for (let index = 0; index < 16; index++) {
    const identity = Object.freeze(Object.fromEntries(keys.map((key, position) =>
      [key, position === 1 ? 'selected-request-' + index : position === 5
        ? 'sha256:' + (index + 32).toString(16).padStart(64, '0') : cid(String(position))])));
    const accepted = journal.accept(identity, {namespaceId: 'selected-rows',
      runDefinitionCid: 'sha256:' + index.toString(16).padStart(64, '0'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'}, control);
    selected ??= {ref: accepted.ref, key: {namespaceId: accepted.ref.namespaceId,
      authorityScopeCid: identity.authorityScopeCid, requestId: identity.requestId}};
  }
  const records = [];
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), events: {level: 'diagnostic'},
    measurements: {include: ['rows']}, include: ['run'],
  }));
  journal.installObservationProjection(observer);
  t.after(() => observer.close());
  return {journal, control, observer, records, ...selected};
}

const selectedRowTrace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};

test('Journal selected-row observations count actual target rows without traversing other Runs', async t => {
  const f = await selectedRowsFixture(t);
  await f.observer.run('read', selectedRowTrace, () => {
    for (let index = 0; index < 2; index++) {
      assert.throws(() => f.journal.markPhysicalClose(f.ref), {code: 'ClientRunStopObservationDenied'});
    }
    assert.equal(f.journal.lookupRunDefinition({...f.ref,
      runDefinitionCid: 'sha256:' + 'f'.repeat(64)}, f.control, {}), undefined);
  });
  await f.observer.close();
  const rows = f.records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].attributes['actql.rows.returned'], 2);
  assert.equal(rows[0].attributes['actql.rows.unrelated'], 0);
  assert.equal(rows[0].attributes['actql.rows.owner'], 'request-journal');
  assert.equal(rows[0].attributes['actql.rows.coverage'], 'selected-returned');
  assert.equal(rows[0].attributes['actql.run.definition_cid'], undefined,
    'Distinct selected refs must not borrow an eventual or earlier Run identity');
  assert.deepEqual(rows[0].parent, selectedRowTrace);
});

test('Journal selected-row observations retain unknown classification before a Run is selected', async t => {
  const f = await selectedRowsFixture(t);
  await f.observer.run('read', selectedRowTrace, () => {
    assert.deepEqual(f.journal.lookup(f.key, f.control).ref, f.ref);
    assert.equal(f.journal.lookupReconciliationState(f.ref), undefined);
    assert.equal(f.journal.lookupReconciliationState({...f.ref,
      runDefinitionCid: 'sha256:' + 'f'.repeat(64)}), undefined);
  });
  await f.observer.close();
  const rows = f.records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].attributes['actql.rows.returned'], 2,
    'A present row with a null reconciliation field is still one materialized row');
  assert.equal(rows[0].attributes['actql.rows.selection'], 'mixed-selected');
  assert.equal(Object.hasOwn(rows[0].attributes, 'actql.rows.unrelated'), false);
  assert.equal(Object.hasOwn(rows[0].attributes, 'actql.run.definition_cid'), false);
});

test('Journal selected-row observations do not turn refused or failed reads into empty results', async t => {
  const f = await selectedRowsFixture(t);
  await f.observer.run('read', selectedRowTrace, () => {
    assert.throws(() => f.journal.lookupReconciliationState({}), {code: 'InvalidClientRunLookup'});
    f.journal.close();
    assert.throws(() => f.journal.lookupReconciliationState(f.ref), {code: 'ClientRequestJournalClosed'});
  });
  await f.observer.close();
  assert.equal(f.records.filter(record => record.event === 'selected_rows_observed').length, 0);
});

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

for (const owned of [true, false]) {
  test(`ordinary Journal keeps native directory admission separate from accepted row projection (${owned ? 'owned' : 'strict'})`, async t => {
    const owner = owned ? await fixture() : undefined;
    const directory = owned ? join(owner.root, 'requests') :
      await mkdtemp(join(tmpdir(), 'actql-strict-journal-row-'));
    const journal = owned ? await owner.view.openRequestJournal(directory, {}) :
      openClientRequestJournal(directory);
    t.after(async () => {
      journal.close();
      if (owner !== undefined) assert.equal((await owner.view.close()).pending, false);
    });
    // Explicit request-control protocol fixture only. SQLite transactions,
    // Store exclusion and row projection are real; no Common authority or
    // whole Host execution is supplied by these synthetic identity fields.
    const keys = ['authorityScopeCid', 'requestId', 'programDefinitionCid',
      'parameterValuesCid', 'callerInputIntentCid', 'logicalRequestScopeCid',
      'intentFingerprintCid'];
    const cid = digit => 'sha256:' + digit.repeat(64);
    const identity = Object.freeze(Object.fromEntries(keys.map((key, index) =>
      [key, index === 1 ? 'ordinary-row-request' : cid(String(index))])));
    const control = {clientRequestAdmitRecord(...fields) {
      return Object.freeze(Object.fromEntries(keys.map((key, index) => [key, fields[index]])));
    }, clientRequestRelation(a, b) {
      return keys.every(key => a[key] === b[key]) ? 1 : 2;
    }};
    for (const [method, key] of Object.entries({clientRequestAuthorityScopeCid: 'authorityScopeCid',
      clientRequestCallerId: 'requestId', clientRequestScopeCid: 'logicalRequestScopeCid',
      clientRequestIntentCid: 'intentFingerprintCid', clientRequestProgramCid: 'programDefinitionCid',
      clientRequestParametersCid: 'parameterValuesCid', clientRequestInputCid: 'callerInputIntentCid'})) {
      control[method] = value => value[key];
    }
    const input = {namespaceId: 'ordinary-row', runDefinitionCid: cid('a'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    const first = journal.accept(identity, input, control);
    const key = {namespaceId: input.namespaceId, authorityScopeCid: identity.authorityScopeCid,
      requestId: identity.requestId};
    assert.deepEqual(journal.lookup(key, control).ref, first.ref);
    assert.deepEqual(journal.accept(identity, input, control).ref, first.ref);
    assert.equal(journal.lookup(key, control).revision, first.revision);
    journal.close();
    const reopened = openClientRequestJournal(directory, {},
      owner?.view.privateEvidenceInitializationOwnership());
    try {assert.deepEqual(reopened.lookup(key, control).ref, first.ref);}
    finally {reopened.close();}
  });
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

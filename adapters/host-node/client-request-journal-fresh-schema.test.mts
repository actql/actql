import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash, type BinaryLike} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from '../store-local/prepared-publication-store-ownership.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import schemaSupport from './host-journal-schema-support.cjs';

type CloseableJournal = Readonly<{close(): void}>;
const selectedSchema = {
  maxDatabaseBytes: 4194304,
  primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
    maxSchemaPages: 256, maxWalFrames: 8192},
  primarySchemaSqlSupport: schemaSupport.sql,
};

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'journal-fresh-schema-',label:'original Journal schema initialization',preserve:true});
  return {scratch,directory:join(scratch.path,'requests')};
}

// Actual Node SQLite and filesystem, with original methods restored in finally.
// This counts schema transactions and marker ACKs, not wall time, Core funding,
// or SQLite's internal native fsync calls.
test('fresh Journal commits its complete current schema once before publishing format markers',async()=>{
  const {scratch,directory}=await fixture();
  const originalExec=DatabaseSync.prototype.exec,originalOpen=fs.openSync,originalFsync=fs.fsyncSync;
  const events: string[] = [];let markerFsyncs=0,directoryFsyncs=0,journal: CloseableJournal | undefined;
  DatabaseSync.prototype.exec=function(sql){
    const result=Reflect.apply(originalExec,this,[sql]);
    if(sql==='BEGIN IMMEDIATE'||sql==='COMMIT'||sql==='ROLLBACK')events.push(sql);
    return result;
  };
  fs.openSync=function(path,...args){
    const fd=Reflect.apply(originalOpen,fs,[path,...args]);
    if(typeof path==='string'&&path.startsWith(directory+'/')&&args[0]==='wx')events.push('marker');
    return fd;
  };
  fs.fsyncSync=function(fd){
    if(fs.fstatSync(fd).isDirectory())directoryFsyncs++;else markerFsyncs++;
    return Reflect.apply(originalFsync,fs,[fd]);
  };
  syncBuiltinESMExports();
  try {
    journal=openClientRequestJournal(directory);
    console.log('JOURNAL_SCHEMA_COUNTS '+JSON.stringify({begins:events.filter(x=>x==='BEGIN IMMEDIATE').length,
      commits:events.filter(x=>x==='COMMIT').length,markerFsyncs,directoryFsyncs,events}));
    assert.equal(events.filter(x=>x==='BEGIN IMMEDIATE').length,1);
    assert.equal(events.filter(x=>x==='COMMIT').length,1);
    assert.equal(events.includes('ROLLBACK'),false);
    assert.ok(events.indexOf('COMMIT')<events.indexOf('marker'));
    assert.equal(markerFsyncs,8);
    assert.equal(directoryFsyncs,1);
  } finally {
    DatabaseSync.prototype.exec=originalExec;fs.openSync=originalOpen;fs.fsyncSync=originalFsync;
    syncBuiltinESMExports();journal?.close();
  }
  scratch.passed();
});

function inspectDatabase<Result>(directory: string, read: (database: DatabaseSync) => Result) {
  const database=new DatabaseSync(join(directory,'client-requests.sqlite3'));
  try {return read(database);} finally {database.close();}
}
const schema = (database: DatabaseSync) =>database.prepare(`SELECT type,name,sql FROM sqlite_master
  WHERE sql IS NOT NULL ORDER BY type,name`).all().map(row=>({...row}));
const databaseBytes = (directory: string) =>fs.readFileSync(join(directory,'client-requests.sqlite3'));
const digest = (value: BinaryLike) =>createHash('sha256').update(value).digest('hex');

function retainedDirectory(directory: string) {
  return fs.readdirSync(directory).sort().map(name => {
    const path = join(directory, name);
    const {dev, ino} = fs.lstatSync(path, {bigint: true});
    return {name, dev, ino, sha256: digest(fs.readFileSync(path))};
  });
}

function retainOriginalRun(database: DatabaseSync) {
  const identity = 'sha256:' + '1'.repeat(64);
  database.prepare(`INSERT INTO client_requests (authority_scope_cid,caller_request_id,
    logical_request_scope_cid,intent_fingerprint_cid,program_definition_cid,
    parameter_values_cid,caller_input_intent_cid,namespace_id,run_definition_cid,
    revision,lookup_expires_at) VALUES (?,?,?,?,?,?,?,?,?,0,?)`)
    .run(identity, 'retained-original', identity, identity, identity, identity, identity,
      'fixture', identity, '2030-01-01T00:00:00.000Z');
  database.exec('UPDATE client_submission_custody SET issued_count=1 WHERE singleton=1');
}

for (const version of [0, 1, 2]) {
  test(`existing Journal v${version} refuses before opening the writable original`, async () => {
    const {scratch, directory} = await fixture();
    openClientRequestJournal(directory).close();
    inspectDatabase(directory, database => {
      retainOriginalRun(database);
      // Old private v1/v2 counters used the smaller per-table byte bound.
      for (const table of ['client_submitted_intent_usage', 'client_submission_restart_usage']) {
        const triggers = database.prepare('SELECT name,sql FROM sqlite_schema WHERE tbl_name=? AND type=?')
          .all(table.includes('intent') ? 'client_submitted_intents' : 'client_submission_restarts', 'trigger')
          .filter(row => (row.name as string).startsWith(table + '_'));
        assert.equal(triggers.length, 3);
        for (const {name} of triggers) database.exec(`DROP TRIGGER ${name}`);
        database.exec(`DROP TABLE ${table}`);
        if (version > 0) {
          database.exec(`CREATE TABLE ${table} (
            singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
            retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
            retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 67108864),
            revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
          ) STRICT; INSERT INTO ${table} VALUES (1, 0, 0, 0);`);
          for (const {sql} of triggers) database.exec(sql as string);
        }
      }
      if (version < 2) {
        for (const table of ['client_request_row_usage', 'client_cancellation_row_usage']) {
          for (const suffix of ['insert', 'delete']) database.exec(`DROP TRIGGER ${table}_${suffix}`);
          database.exec(`DROP TABLE ${table}`);
        }
      }
      database.exec(`PRAGMA user_version = ${version}`);
    });
    const before = retainedDirectory(directory);
    const originalOpen = DatabaseSync.prototype.open;
    const originalFile = join(fs.realpathSync(directory), 'client-requests.sqlite3');
    let writableOriginalOpens = 0;
    DatabaseSync.prototype.open = function (...args) {
      const opened = Reflect.apply(originalOpen, this, args);
      if (this.location('main') === originalFile) writableOriginalOpens++;
      return opened;
    };
    try {
      assert.throws(() => openClientRequestJournal(directory, selectedSchema), {code: 'LegacyClientRequestJournalFormat'});
    } finally {
      DatabaseSync.prototype.open = originalOpen;
    }
    assert.equal(writableOriginalOpens, 0);
    assert.deepEqual(retainedDirectory(directory), before);
    inspectDatabase(directory, database => {
      assert.equal(database.prepare('PRAGMA user_version').get()!.user_version, version);
      assert.equal(database.prepare('SELECT caller_request_id FROM client_requests').get()!.caller_request_id,
        'retained-original');
    });
    scratch.passed();
  });
}

test('owned Journal reopens a current original without a database or WAL copy', async () => {
  const {scratch, directory} = await fixture();
  const owner = await prepareLocalPublicationStoreOwnership(join(scratch.path, 'publication'));
  const originalMkdtemp = fs.mkdtempSync, originalOpen = DatabaseSync.prototype.open;
  let copies = 0;
  const originalPaths: (string | null)[] = [];
  try {
    openClientRequestJournal(directory, selectedSchema, owner).close();
    assert.equal(fs.existsSync(join(directory, 'client-requests.sqlite3-wal')), false);
    const before = retainedDirectory(directory);
    fs.mkdtempSync = function (prefix, ...args) {
      if (String(prefix).endsWith('actql-journal-format-')) copies++;
      return Reflect.apply(originalMkdtemp, fs, [prefix, ...args]);
    };
    DatabaseSync.prototype.open = function (...args) {
      const opened = Reflect.apply(originalOpen, this, args);
      originalPaths.push(this.location('main'));
      return opened;
    };
    syncBuiltinESMExports();
    openClientRequestJournal(directory, selectedSchema, owner).close();
    assert.equal(copies, 0);
    assert.deepEqual(originalPaths, Array(2).fill(join(fs.realpathSync(directory), 'client-requests.sqlite3')));
    assert.deepEqual(retainedDirectory(directory), before);
  } finally {
    fs.mkdtempSync = originalMkdtemp;
    DatabaseSync.prototype.open = originalOpen;
    syncBuiltinESMExports();
    assert.equal((await closePreparedLocalPublicationStoreOwnership(owner)).pending, false);
  }
  scratch.passed();
});

test('owned Journal refuses the v2 SQLite version in its retained WAL before opening the original', async () => {
  const {scratch, directory} = await fixture();
  const owner = await prepareLocalPublicationStoreOwnership(join(scratch.path, 'publication'));
  openClientRequestJournal(directory, {}, owner).close();
  const original = new DatabaseSync(join(directory, 'client-requests.sqlite3'));
  try {
    assert.equal(databaseBytes(directory).readUInt32BE(60), 3);
    original.exec('PRAGMA wal_autocheckpoint=0; PRAGMA user_version=2');
    assert.ok(fs.statSync(join(directory, 'client-requests.sqlite3-wal')).size > 0);
    assert.ok(fs.statSync(join(directory, 'client-requests.sqlite3-shm')).size > 0);
    assert.equal(databaseBytes(directory).readUInt32BE(60), 3);
    assert.equal(original.prepare('PRAGMA user_version').get()!.user_version, 2);
    const before = retainedDirectory(directory);
    const originalOpen = DatabaseSync.prototype.open;
    const originalFile = join(fs.realpathSync(directory), 'client-requests.sqlite3');
    let originalOpens = 0;
    DatabaseSync.prototype.open = function (...args) {
      const opened = Reflect.apply(originalOpen, this, args);
      if (this.location('main') === originalFile) originalOpens++;
      return opened;
    };
    try {
      assert.throws(() => openClientRequestJournal(directory, selectedSchema, owner), {code: 'LegacyClientRequestJournalFormat'});
    } finally { DatabaseSync.prototype.open = originalOpen; }
    assert.equal(originalOpens, 0);
    assert.deepEqual(retainedDirectory(directory), before);
  } finally {
    original.close();
    assert.equal((await closePreparedLocalPublicationStoreOwnership(owner)).pending, false);
  }
  scratch.passed();
});

test('owned Journal does not recreate missing SHM while refusing a retained v2 WAL', async () => {
  const {scratch, directory} = await fixture();
  const owner = await prepareLocalPublicationStoreOwnership(join(scratch.path, 'publication'));
  try {
    openClientRequestJournal(directory, {}, owner).close();
    const databasePath = join(directory, 'client-requests.sqlite3');
    const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
      import {DatabaseSync} from 'node:sqlite';
      const original = new DatabaseSync(process.argv[1]);
      original.exec('PRAGMA wal_autocheckpoint=0; PRAGMA user_version=2');
      // Exit with the original committed SQLite WAL separate from the DB.
      process.exit(0);
    `, databasePath], {encoding: 'utf8', timeout: 10000});
    assert.equal(child.error, undefined);
    assert.equal(child.status, 0, child.stderr);
    assert.ok(fs.statSync(databasePath + '-wal').size > 0);
    fs.unlinkSync(databasePath + '-shm');
    const before = retainedDirectory(directory);
    assert.throws(() => openClientRequestJournal(directory, selectedSchema, owner), {code: 'LegacyClientRequestJournalFormat'});
    assert.deepEqual(retainedDirectory(directory), before);
  } finally {
    assert.equal((await closePreparedLocalPublicationStoreOwnership(owner)).pending, false);
  }
  scratch.passed();
});

test('Journal rejects current header with a missing original lookup or a foreign trigger definition', async () => {
  for (const table of ['client_keyed_lookup_originals', 'client_cancellation_row_usage_insert']) {
    const {scratch, directory} = await fixture();
    openClientRequestJournal(directory).close();
    inspectDatabase(directory, database => {
      retainOriginalRun(database);
      if (table === 'client_keyed_lookup_originals') database.exec('DROP TABLE client_keyed_lookup_originals');
      else database.exec(`DROP TRIGGER client_cancellation_row_usage_insert;
        CREATE TRIGGER client_cancellation_row_usage_insert AFTER INSERT ON client_cancellation_operations
          BEGIN SELECT 1; END;`);
      assert.equal(database.prepare('PRAGMA user_version').get()!.user_version, 3);
    });
    const before = retainedDirectory(directory);
    assert.throws(() => openClientRequestJournal(directory), {code: 'UnknownClientRequestJournalFormat'});
    assert.deepEqual(retainedDirectory(directory), before);
    scratch.passed();
  }
});

test('selected Source operation schema is inside the same fresh transaction',async()=>{
  const {scratch,directory}=await fixture();
  const originalExec=DatabaseSync.prototype.exec;let commits=0,tableInsideTransaction=false,journal: CloseableJournal | undefined;
  DatabaseSync.prototype.exec=function(sql){
    if(sql.startsWith('CREATE TABLE client_source_operation_originals'))tableInsideTransaction=this.isTransaction;
    if(sql==='COMMIT')commits++;
    return Reflect.apply(originalExec,this,[sql]);
  };
  try {journal=openClientRequestJournal(directory,{sourceOperationLimits:{maxRecords:2,maxWireBytes:4096}});}
  finally {DatabaseSync.prototype.exec=originalExec;journal?.close();}
  assert.equal(tableInsideTransaction,true);assert.equal(commits,1);
  inspectDatabase(directory,database=>assert.equal(database.prepare(
    "SELECT count(*) AS n FROM client_source_operation_originals").get()!.n,0));
  scratch.passed();
});

for(const stage of ['before-commit','after-commit','partial-markers','after-directory-ack']) {
  test('abrupt fresh initialization at '+stage+' preserves original state for the next open',async()=>{
    const {scratch,directory}=await fixture();
    const childSource=`
      import {DatabaseSync} from 'node:sqlite';
      import fs from 'node:fs';
      import {syncBuiltinESMExports} from 'node:module';
      import {openClientRequestJournal} from ${JSON.stringify(new URL('./client-request-journal.mjs',import.meta.url).href)};
      const directory=${JSON.stringify(directory)},stage=${JSON.stringify(stage)};
      const exec=DatabaseSync.prototype.exec,open=fs.openSync,fsync=fs.fsyncSync;
      let markers=0;
      DatabaseSync.prototype.exec=function(sql){
        if(sql==='COMMIT'&&stage==='before-commit')process.exit(73);
        const result=Reflect.apply(exec,this,[sql]);
        if(sql==='COMMIT'&&stage==='after-commit')process.exit(73);
        return result;
      };
      fs.openSync=function(path,...args){
        const fd=Reflect.apply(open,fs,[path,...args]);
        if(typeof path==='string'&&path.startsWith(directory+'/')&&args[0]==='wx'&&++markers===3&&stage==='partial-markers')process.exit(73);
        return fd;
      };
      fs.fsyncSync=function(fd){
        const result=Reflect.apply(fsync,fs,[fd]);
        if(fs.fstatSync(fd).isDirectory()&&stage==='after-directory-ack')process.exit(73);
        return result;
      };
      syncBuiltinESMExports();
      openClientRequestJournal(directory);
      process.exit(74);
    `;
    const child=spawnSync(process.execPath,['--input-type=module','--eval',childSource],{
      encoding:'utf8',timeout:10000,maxBuffer:1024*1024,env:{...process.env,NODE_OPTIONS:''}});
    assert.equal(child.error,undefined);assert.equal(child.signal,null);
    assert.equal(child.status,73,child.stderr);
    const before=databaseBytes(directory),entries=fs.readdirSync(directory).sort();
    const committed=stage==='after-directory-ack' ? inspectDatabase(directory,database=>({
      schema:schema(database),version:database.prepare('PRAGMA user_version').get()!.user_version,
      tables:schema(database).filter(row=>row.type==='table').map(({name})=>({name,
        rows:database.prepare(`SELECT * FROM "${(name as string).replaceAll('"','""')}"`).all()})),
    })) : undefined;
    let journal: CloseableJournal | undefined;
    try {
      if(stage==='after-directory-ack')journal=openClientRequestJournal(directory);
      else assert.throws(()=>{journal=openClientRequestJournal(directory);},{code:
        stage==='partial-markers'?'UnknownClientRequestJournalFormat':'LegacyClientRequestJournalFormat'});
    } finally {journal?.close();}
    if(stage!=='after-directory-ack'){
      assert.equal(digest(databaseBytes(directory)),digest(before));
      assert.deepEqual(fs.readdirSync(directory).sort(),entries);
    } else {
      // A completed directory ACK permits reopening the exact committed
      // schema and rows. SQLite may checkpoint its physical WAL on reopen.
      assert.deepEqual(inspectDatabase(directory,database=>({
        schema:schema(database),version:database.prepare('PRAGMA user_version').get()!.user_version,
        tables:schema(database).filter(row=>row.type==='table').map(({name})=>({name,
          rows:database.prepare(`SELECT * FROM "${(name as string).replaceAll('"','""')}"`).all()})),
      })),committed);
    }
    scratch.passed();
  });
}

test('a failed marker fsync retains the committed schema without ready or automatic reset',async()=>{
  const {scratch,directory}=await fixture();
  const originalFsync=fs.fsyncSync;const primary=new Error('OriginalMarkerAckFailed');
  let journal: CloseableJournal | undefined,markerAcks=0;
  fs.fsyncSync=function(fd){
    if(!fs.fstatSync(fd).isDirectory()&&++markerAcks===2)throw primary;
    return Reflect.apply(originalFsync,fs,[fd]);
  };
  syncBuiltinESMExports();
  try {assert.throws(()=>{journal=openClientRequestJournal(directory);},error=>error===primary);}
  finally {fs.fsyncSync=originalFsync;syncBuiltinESMExports();journal?.close();}
  const before=databaseBytes(directory),entries=fs.readdirSync(directory).sort();
  assert.throws(()=>{journal=openClientRequestJournal(directory);},{code:'UnknownClientRequestJournalFormat'});
  assert.equal(digest(databaseBytes(directory)),digest(before));
  assert.deepEqual(fs.readdirSync(directory).sort(),entries);
  scratch.passed();
});

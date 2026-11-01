import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

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
  const events=[];let markerFsyncs=0,directoryFsyncs=0,journal;
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

function inspectDatabase(directory, read) {
  const database=new DatabaseSync(join(directory,'client-requests.sqlite3'));
  try {return read(database);} finally {database.close();}
}
const schema=database=>database.prepare(`SELECT type,name,sql FROM sqlite_master
  WHERE sql IS NOT NULL ORDER BY type,name`).all().map(row=>({...row}));
const databaseBytes=directory=>fs.readFileSync(join(directory,'client-requests.sqlite3'));
const digest=value=>createHash('sha256').update(value).digest('hex');

test('actual older base format adopts the same DDL and preserves its original row on current reopen',async()=>{
  const {scratch,directory}=await fixture();
  let journal=openClientRequestJournal(directory);journal.close();journal=undefined;
  const currentSchema=inspectDatabase(directory,schema);
  const identity='sha256:'+'1'.repeat(64);
  inspectDatabase(directory,database=>{
    // This fixture downgrades ONLY its newly created test database to the
    // retained base format. Product code never resets an admitted database.
    database.exec('PRAGMA foreign_keys=OFF');
    for(const {name} of database.prepare("SELECT name FROM sqlite_master WHERE type='trigger'").all()) {
      database.exec(`DROP TRIGGER ${name}`);
    }
    for(const {name} of database.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name!='client_requests'").all()) {
      database.exec(`DROP TABLE ${name}`);
    }
    database.exec('PRAGMA user_version=0');
    database.prepare(`INSERT INTO client_requests (authority_scope_cid,caller_request_id,
      logical_request_scope_cid,intent_fingerprint_cid,program_definition_cid,
      parameter_values_cid,caller_input_intent_cid,namespace_id,run_definition_cid,
      revision,lookup_expires_at) VALUES (?,?,?,?,?,?,?,?,?,0,?)`)
      .run(identity,'retained-original',identity,identity,identity,identity,identity,
        'fixture',identity,'2030-01-01T00:00:00.000Z');
  });
  for(const name of fs.readdirSync(directory).filter(name=>name.endsWith('-format.json')&&name!=='journal-format.json')) {
    fs.unlinkSync(join(directory,name));
  }
  try {journal=openClientRequestJournal(directory);} finally {journal?.close();journal=undefined;}
  const retained=inspectDatabase(directory,database=>({schema:schema(database),
    authority:database.prepare('SELECT * FROM client_submission_epoch_authority').get(),
    custody:database.prepare('SELECT * FROM client_submission_custody').get(),
    usage:database.prepare('SELECT * FROM client_request_row_usage').get(),
    rows:database.prepare('SELECT * FROM client_requests').all(),
    version:database.prepare('PRAGMA user_version').get().user_version}));
  assert.deepEqual(retained.schema,currentSchema);
  assert.equal(retained.custody.issued_count,1);assert.equal(retained.usage.retained_count,1);
  assert.equal(retained.rows[0].caller_request_id,'retained-original');assert.equal(retained.version,2);
  const originalExec=DatabaseSync.prototype.exec;let transactions=0;
  DatabaseSync.prototype.exec=function(sql){if(sql==='BEGIN IMMEDIATE')transactions++;
    return Reflect.apply(originalExec,this,[sql]);};
  try {journal=openClientRequestJournal(directory);} finally {DatabaseSync.prototype.exec=originalExec;journal?.close();}
  assert.equal(transactions,0);
  assert.deepEqual(inspectDatabase(directory,database=>({schema:schema(database),
    authority:database.prepare('SELECT * FROM client_submission_epoch_authority').get(),
    custody:database.prepare('SELECT * FROM client_submission_custody').get(),
    usage:database.prepare('SELECT * FROM client_request_row_usage').get(),
    rows:database.prepare('SELECT * FROM client_requests').all(),
    version:database.prepare('PRAGMA user_version').get().user_version})),retained);
  scratch.passed();
});

test('selected Source operation schema is inside the same fresh transaction',async()=>{
  const {scratch,directory}=await fixture();
  const originalExec=DatabaseSync.prototype.exec;let commits=0,tableInsideTransaction=false,journal;
  DatabaseSync.prototype.exec=function(sql){
    if(sql.startsWith('CREATE TABLE client_source_operation_originals'))tableInsideTransaction=this.isTransaction;
    if(sql==='COMMIT')commits++;
    return Reflect.apply(originalExec,this,[sql]);
  };
  try {journal=openClientRequestJournal(directory,{sourceOperationLimits:{maxRecords:2,maxWireBytes:4096}});}
  finally {DatabaseSync.prototype.exec=originalExec;journal?.close();}
  assert.equal(tableInsideTransaction,true);assert.equal(commits,1);
  inspectDatabase(directory,database=>assert.equal(database.prepare(
    "SELECT count(*) AS n FROM client_source_operation_originals").get().n,0));
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
    let journal;
    try {
      if(stage==='after-directory-ack')journal=openClientRequestJournal(directory);
      else assert.throws(()=>{journal=openClientRequestJournal(directory);},{code:
        stage==='partial-markers'?'UnknownClientRequestJournalFormat':'LegacyClientRequestJournalFormat'});
    } finally {journal?.close();}
    if(stage!=='after-directory-ack'){
      assert.equal(digest(databaseBytes(directory)),digest(before));
      assert.deepEqual(fs.readdirSync(directory).sort(),entries);
    } else inspectDatabase(directory,database=>assert.equal(database.prepare('PRAGMA user_version').get().user_version,2));
    scratch.passed();
  });
}

test('a failed marker fsync retains the committed schema without ready or automatic reset',async()=>{
  const {scratch,directory}=await fixture();
  const originalFsync=fs.fsyncSync;const primary=new Error('OriginalMarkerAckFailed');
  let journal,markerAcks=0;
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

import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync,StatementSync} from 'node:sqlite';
import {stageLegacySubmissionUsageCounters} from './fixtures/journal-legacy-usage.fixture.mjs';
import {openClientRequestJournal,observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

const moon=await import(process.env.ACTQL_TEST_COMMON_RUNTIME??new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const MiB=1024*1024,fields={authorityScopeCid:'sha256:'+'a'.repeat(64),currentAuthorization:true};
const now=1_800_000_000_000;
const policy={maxRecords:1024,maxDatabaseBytes:128*MiB,maxInspectionBytes:128*MiB,
  submissionEpochTtlMs:1000000,submissionEpochNow:()=>now};
async function fixture(t,selected=policy){
 const directory=await mkdtemp(join(tmpdir(),'actql-journal-parent-budget-')),journals=[];
 t.after(async()=>{for(const journal of journals)journal.close();if(t.passed)await rm(directory,{recursive:true});});
 const open=()=>{const journal=openClientRequestJournal(directory,selected);journals.push(journal);return journal;};
 const database=use=>{const db=new DatabaseSync(join(directory,'client-requests.sqlite3'));try{return use(db);}finally{db.close();}};
 return {directory,open,database};
}
function originalIntent(text){
 const original=moon.clientSubmittedIntent(JSON.stringify({kind:'aql',input:{format:'aql-text',text},parameters:null}),2*MiB,65536,64);
 assert(original,'the existing actual Core must admit this bounded intent original');return original;
}

// Actual Core intent/epoch originals, SQLite and cold snapshot. The selected
// diagnostic Journal policy is explicit; this supplies no Account or Run grant.
test('Journal retains intent bytes above the old subquota under its same finite durable parent and cold history',async t=>{
 const f=await fixture(t),journal=f.open(),epoch=journal.issueSubmissionEpoch(fields,moon);
 const original=originalIntent("SELECT '"+'x'.repeat(900000)+"' AS value");
 const references=[];let retainedBytes=0;
 for(let i=0;retainedBytes<=64*MiB;i++){
  const reference={epoch,nonce:'parent-'+i};
  const result=journal.recordSubmittedIntent(reference,original,fields,moon);
  assert.equal(result.inserted,true);retainedBytes+=Buffer.byteLength(result.intentWire);references.push(reference);
 }
 assert(retainedBytes>64*MiB&&retainedBytes<128*MiB);
 const before=f.database(db=>({version:db.prepare('PRAGMA user_version').get().user_version,
  usage:{...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
  issued:db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,
  history:db.prepare('SELECT submission_id,intent_cid,revision FROM client_submitted_intents ORDER BY submission_id').all()}));
 assert.equal(before.usage.retained_bytes,retainedBytes);assert.equal(before.issued,references.length);
 journal.close();assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed,true);
 const cold=f.open();
 for(const reference of [references[0],references.at(-1)]){
  assert.equal(cold.lookupSubmittedIntent(reference,fields,moon).intentCid,moon.clientSubmittedIntentCid(original));
  assert.equal(cold.recordSubmittedIntent(reference,original,fields,moon).inserted,false);
 }
 const after=f.database(db=>({version:db.prepare('PRAGMA user_version').get().user_version,
  usage:{...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
  issued:db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,
  history:db.prepare('SELECT submission_id,intent_cid,revision FROM client_submitted_intents ORDER BY submission_id').all()}));
 assert.deepEqual(after,before,'cold read/dedup preserves every original history and counter, with no refund');
 cold.close();assert.equal(observeOriginalClientRequestJournalCustody(cold).databaseClosed,true);
});

function snapshot(f){return f.database(db=>({
 usage:['client_submitted_intent_usage','client_submission_restart_usage'].map(table=>({...db.prepare(`SELECT * FROM ${table}`).get()})),
 custody:['client_submitted_intent_custody','client_submitted_intent_retirement','client_submission_restart_custody'].map(table=>({...db.prepare(`SELECT * FROM ${table}`).get()})),
 history:db.prepare('SELECT * FROM client_submitted_intents ORDER BY submission_id').all(),
 restarts:db.prepare('SELECT * FROM client_submission_restarts ORDER BY fresh_submission_id').all(),
 rowUsage:['client_request_row_usage','client_cancellation_row_usage'].map(table=>({...db.prepare(`SELECT * FROM ${table}`).get()})),
}));}

function historicalAggregateCounter(t){
 const queries=new WeakMap(),scans=[];const prepare=DatabaseSync.prototype.prepare,get=StatementSync.prototype.get;
 t.mock.method(DatabaseSync.prototype,'prepare',function(sql,...args){const stmt=Reflect.apply(prepare,this,[sql,...args]);queries.set(stmt,sql);return stmt;});
 t.mock.method(StatementSync.prototype,'get',function(...args){const sql=queries.get(this)??'';
  if(/\b(?:COUNT|SUM)\s*\(/iu.test(sql)&&/\bFROM\s+client_(?:submitted_intents|submission_restarts|requests|cancellation_operations)\b/iu.test(sql))scans.push(sql);
  return Reflect.apply(get,this,args);
 });return scans;
}

test('selected parent exhaustion refuses before native intent bind and preserves the same cold original',async t=>{
 const queries=new WeakMap();let inserts=0;const prepare=DatabaseSync.prototype.prepare,run=StatementSync.prototype.run;
 t.mock.method(DatabaseSync.prototype,'prepare',function(sql,...args){const stmt=Reflect.apply(prepare,this,[sql,...args]);queries.set(stmt,sql);return stmt;});
 t.mock.method(StatementSync.prototype,'run',function(...args){if(/INSERT INTO client_submitted_intents VALUES/u.test(queries.get(this)??''))inserts++;return Reflect.apply(run,this,args);});
 const f=await fixture(t,{...policy,maxDatabaseBytes:2*MiB,maxInspectionBytes:MiB}),journal=f.open();
 const epoch=journal.issueSubmissionEpoch(fields,moon),first={epoch,nonce:'held'},second={epoch,nonce:'over-parent'};
 const original=originalIntent("SELECT '"+'y'.repeat(600000)+"' AS value");
 const retained=journal.recordSubmittedIntent(first,original,fields,moon);assert.equal(inserts,1);
 const before=snapshot(f);
 assert.throws(()=>journal.recordSubmittedIntent(second,original,fields,moon),{code:'ClientSubmittedIntentCapacity'});
 assert.equal(inserts,1,'the refused intent never reaches native binding/INSERT');assert.deepEqual(snapshot(f),before);
 journal.close();assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed,true);
 const cold=f.open();assert.equal(cold.lookupSubmittedIntent(first,fields,moon).intentCid,retained.intentCid);
 assert.equal(cold.lookupSubmittedIntent(second,fields,moon),undefined);assert.deepEqual(snapshot(f),before);
 cold.close();assert.equal(observeOriginalClientRequestJournalCustody(cold).databaseClosed,true);
});

test('legacy v2 counter adoption preserves both original histories and revisions without a rescan',async t=>{
 let time=now;const f=await fixture(t,{...policy,submissionEpochTtlMs:1000,submissionEpochNow:()=>time}),journal=f.open();
 const prior={epoch:journal.issueSubmissionEpoch(fields,moon),nonce:'unresolved-original'};time+=1000;
 const ref={epoch:journal.issueSubmissionEpoch(fields,moon),nonce:'original-restart'},original=originalIntent('SELECT 1 AS value');
 const restart={...fields,actorId:'original-actor',unresolvedHistory:{submissionRef:prior,acknowledgement:'possible_prior_execution_and_effects'}};
 const retained=journal.recordSubmittedIntent(ref,original,restart,moon);
 assert.equal(retained.unresolvedHistory.actorId,'original-actor');journal.close();f.database(stageLegacySubmissionUsageCounters);
 const before=snapshot(f);assert.equal(before.usage[0].revision,1);assert.equal(before.usage[1].revision,1);
 const scans=historicalAggregateCounter(t);const restored=f.open();
 assert.deepEqual(snapshot(f),before);assert.deepEqual(scans,[],'two constant-size counters migrate; no business history is censused');
 assert.equal(restored.lookupSubmittedIntent(ref,fields,moon).intentCid,retained.intentCid);
 restored.close();assert.equal(observeOriginalClientRequestJournalCustody(restored).databaseClosed,true);
 const again=f.open();assert.deepEqual(snapshot(f),before);assert.deepEqual(scans,[]);again.close();
 f.database(db=>assert.equal(db.prepare('PRAGMA user_version').get().user_version,3));
});

test('failed legacy counter DDL rolls back under the same original cleanup without resetting history',async t=>{
 const f=await fixture(t),journal=f.open(),ref={epoch:journal.issueSubmissionEpoch(fields,moon),nonce:'before-adoption'};
 journal.recordSubmittedIntent(ref,originalIntent('SELECT 2 AS value'),fields,moon);journal.close();f.database(stageLegacySubmissionUsageCounters);
 const before=snapshot(f),original=new Error('same original counter adoption refusal'),exec=DatabaseSync.prototype.exec;let rejected=false,failedDatabase;
 const mock=t.mock.method(DatabaseSync.prototype,'exec',function(sql,...args){
  if(sql==='DROP TABLE client_submission_restart_usage'&&!rejected){rejected=true;failedDatabase=this;throw original;}
  return Reflect.apply(exec,this,[sql,...args]);
 });
 assert.throws(()=>f.open(),error=>error===original);assert(rejected);assert.equal(failedDatabase.isOpen,false,'the failed original connection is physically closed before return');mock.mock.restore();
 assert.deepEqual(snapshot(f),before,'original rollback retains counter revisions and all original history');
 f.database(db=>assert.equal(db.prepare('PRAGMA user_version').get().user_version,2));
 const recovered=f.open();assert.deepEqual(snapshot(f),before);recovered.close();
 assert.equal(observeOriginalClientRequestJournalCustody(recovered).databaseClosed,true);
});

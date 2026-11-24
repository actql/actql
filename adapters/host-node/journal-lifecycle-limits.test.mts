import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import type {TestContext} from 'node:test';
import {boundedPrimarySql, fail, guardJournalCurrentness, snapshotPrimaryExecutionLimits,
  snapshotPrimarySqlLimits} from './client-request-journal-sql.mjs';

type SqlOwner = ReturnType<typeof boundedPrimarySql>;
function sqlite(t: TestContext, {retained=1024,sqlBytes=64,entries=4,current=()=>{}}:
 Readonly<{retained?:number; sqlBytes?:number; entries?:number; current?:NonNullable<Parameters<typeof boundedPrimarySql>[3]>}> = {}) {
 const db=new DatabaseSync(':memory:');let closed=false;
 t.after(()=>{if(!closed)db.close();});
 const connection={prepare:(sql: string)=>db.prepare(sql),exec:(sql: string)=>db.exec(sql),get isTransaction(){return db.isTransaction;}};
 const owner=boundedPrimarySql(connection,
  {maxPreparedStatements:entries,maxSqlBytes:sqlBytes,maxTotalSqlBytes:retained},
  {maxParameters:4,maxParameterBytes:16,maxResultRows:2},current);
 return {db,owner,close(){db.close();closed=true;owner.retireClosedNativeAliases();}};
}

test('new original Journal operations remain usable beyond former 4096 lifetime attempts',()=>{
 let active=true,calls=0,current=0,closed=0;
 const original={read(){calls++;return calls;},close(){closed++;}};
 const guarded=guardJournalCurrentness(original,()=>{current++;if(!active)fail('StaleOriginal');});
 for(let i=1;i<=5000;i++)assert.equal(guarded.read(),i);
 assert.equal(guarded.read(),5001);assert.equal(current,5001);
 active=false;assert.throws(()=>guarded.read(),{code:'StaleOriginal'});
 guarded.close();assert.equal(closed,1);assert.equal(calls,5001);
});

test('real SQLite cached original executes beyond former 65536 lifetime calls without retained growth',t=>{
 const {owner,close}=sqlite(t,{entries:1,retained:18});
 const statement=owner.database.prepare('SELECT ? AS value');
 for(let i=0;i<65540;i++)assert.equal(statement.get(i)!.value,i);
 assert.equal(owner.database.prepare('SELECT ? AS value'),statement);
 assert.equal(statement.get(65540)!.value,65540);
 assert.throws(()=>owner.database.prepare('SELECT 2'),{code:'ClientRequestJournalSqlUnavailable'});
 close();assert.throws(()=>statement.get(1),{code:'ClientRequestJournalSqlUnavailable'});
});

test('real SQLite transient exec work does not consume retained SQL-text quota',t=>{
 const {owner}=sqlite(t,{entries:1,retained:8});
 for(let i=0;i<4200;i++){owner.database.exec('BEGIN');owner.database.exec('ROLLBACK');}
 assert.equal(owner.database.prepare('SELECT 1').get()!['1'],1);
 assert.throws(()=>owner.database.prepare('SELECT 22'),{code:'ClientRequestJournalSqlUnavailable'});
});

test('failed native prepare leaves no returned logical statement; later original work remains usable',t=>{
 const {owner}=sqlite(t,{entries:1,retained:8});
 for(let i=0;i<4200;i++)assert.throws(()=>owner.database.prepare('SELEC 1'));
 assert.equal(owner.database.prepare('SELECT 1').get()!['1'],1);
});

test('per-operation operand and cursor bounds plus currentness and reentry stay enforced',t=>{
 let active=true,reenter=false,owner!: SqlOwner;
 ({owner}=sqlite(t,{current:()=>{if(!active)fail('StaleOriginal');if(reenter)owner.database.exec('SELECT 1');}}));
 const statement=owner.database.prepare('SELECT ? AS value');
 assert.equal(statement.get('猫'.repeat(5))!.value,'猫'.repeat(5));
 assert.throws(()=>statement.get('猫'.repeat(6)),{code:'ClientRequestJournalSqlUnavailable'});
 const rows=owner.database.prepare('SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3');
 assert.throws(()=>rows.all(),{code:'ClientRequestJournalSqlUnavailable'});
 assert.equal(statement.get(3)!.value,3,'bounded iterator was actually closed');
 reenter=true;assert.throws(()=>statement.get(1),{code:'ClientRequestJournalSqlCleanupPending'});reenter=false;
 active=false;assert.throws(()=>statement.get(1),{code:'StaleOriginal'});active=true;
 assert.equal(statement.get(4)!.value,4);
});

test('obsolete lifetime-limit fields are removed, not silently mapped to larger quotas',()=>{
 assert.deepEqual(snapshotPrimarySqlLimits({maxPreparedStatements:1,maxSqlBytes:8,maxTotalSqlBytes:8}),
 {maxPreparedStatements:1,maxSqlBytes:8,maxTotalSqlBytes:8});
 assert.throws(()=>snapshotPrimarySqlLimits({maxCalls:4096,maxPreparedStatements:1,maxSqlBytes:8,maxTotalSqlBytes:8}),
 {code:'InvalidClientRequestJournalConfiguration'});
 assert.throws(()=>snapshotPrimaryExecutionLimits({maxStatementCalls:65536,maxParameters:1,maxParameterBytes:8,maxResultRows:1}),
 {code:'InvalidClientRequestJournalConfiguration'});
});

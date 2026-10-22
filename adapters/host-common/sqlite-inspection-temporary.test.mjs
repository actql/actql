import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';

const schemaSql='CREATE TABLE value_original(value TEXT)';
const selected={maxSourceBytes:1024*1024,
  schemaReadLimits:{maxSchemaBytes:65536,maxSchemaEntries:16,maxSchemaPages:16,maxWalFrames:256},
  schemaSqlSupport:[schemaSql]};
async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'sqlite-inspection-temporary-',label:'same-copy selected temporary native facility'});
  const path=join(scratch.path,'source.sqlite3'),database=new DatabaseSync(path);
  database.exec(schemaSql);database.prepare('INSERT INTO value_original VALUES (?)').run('same original');
  database.close();
  return {scratch,path,bytes:readFileSync(path)};
}

test('selected own-DDL inspection selects actual memory temporary storage before its callback',async()=>{
  const f=await fixture();let original;
  assert.equal(inspectSqliteSnapshot(f.path,database=>{
    original=database;
    assert.equal(database.prepare('PRAGMA temp_store').get().temp_store,2);
    return database.prepare('SELECT value FROM value_original').get().value;
  },selected),'same original');
  assert.equal(original.isOpen,false);
  assert.deepEqual(readFileSync(f.path),f.bytes);f.scratch.passed();
});

test('unselected inspection keeps its original temporary storage behavior',async()=>{
  const f=await fixture();let original;
  assert.equal(inspectSqliteSnapshot(f.path,database=>{
    original=database;return database.prepare('PRAGMA temp_store').get().temp_store;
  }),0);
  assert.equal(original.isOpen,false);
  assert.deepEqual(readFileSync(f.path),f.bytes);f.scratch.passed();
});

test('selected temporary support refusal retains the same copy connection until original close',async()=>{
  const f=await fixture(),prepare=DatabaseSync.prototype.prepare,close=DatabaseSync.prototype.close;
  let original,failure,inspections=0,allow=false,closes=0,probes=0;
  DatabaseSync.prototype.prepare=function(sql){
    const statement=Reflect.apply(prepare,this,[sql]);
    if(sql==="SELECT sqlite_compileoption_used('TEMP_STORE=1') AS supported"){
      original=this;probes++;statement.get=()=>({supported:0});
    }
    return statement;
  };
  DatabaseSync.prototype.close=function(){
    if(this===original){closes++;if(!allow)return false;}
    return Reflect.apply(close,this,[]);
  };
  try{
    assert.throws(()=>inspectSqliteSnapshot(f.path,()=>{inspections++;},selected),cause=>{
      failure=cause;return cause.cleanupHandle?.status().pending===true;
    });
    assert.equal(inspections,0);assert.equal(probes,1);assert.equal(closes,1);
    assert.equal(failure.primaryFailure.code,'SqliteInspectionTemporaryUnavailable');
    assert.equal(original.isOpen,true);
    DatabaseSync.prototype.close=()=>undefined;
    assert.equal(failure.cleanupHandle.retry().pending,true);assert.equal(closes,2);
    allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);
    assert.equal(original.isOpen,false);assert.equal(closes,3);assert.equal(probes,1);
    assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(closes,3);
  }finally{
    allow=true;failure?.cleanupHandle?.retry();
    DatabaseSync.prototype.prepare=prepare;DatabaseSync.prototype.close=close;
    if(original?.isOpen)Reflect.apply(close,original,[]);
  }
  assert.deepEqual(readFileSync(f.path),f.bytes);f.scratch.passed();
});

test('selected inspection retains original prepare and exec before native open callbacks',async()=>{
  const f=await fixture(),open=DatabaseSync.prototype.open;
  const prepare=DatabaseSync.prototype.prepare,exec=DatabaseSync.prototype.exec;
  let replacementCalls=0,original;
  DatabaseSync.prototype.open=function(){
    const result=Reflect.apply(open,this,[]);original=this;
    DatabaseSync.prototype.prepare=DatabaseSync.prototype.exec=()=>{replacementCalls++;throw new Error('Replacement');};
    return result;
  };
  try{
    assert.equal(inspectSqliteSnapshot(f.path,database=>
      Reflect.apply(prepare,database,['PRAGMA temp_store']).get().temp_store,selected),2);
    assert.equal(replacementCalls,0);assert.equal(original.isOpen,false);
  }finally{
    DatabaseSync.prototype.open=open;DatabaseSync.prototype.prepare=prepare;DatabaseSync.prototype.exec=exec;
    if(original?.isOpen)original.close();
  }
  assert.deepEqual(readFileSync(f.path),f.bytes);f.scratch.passed();
});

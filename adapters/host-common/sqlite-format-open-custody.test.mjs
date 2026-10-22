import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {existsSync,readFileSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'sqlite-inspection-open-',label:'same original isolated SQLite open'});
  const path=join(scratch.path,'journal.sqlite3');
  const database=new DatabaseSync(path);
  database.exec('CREATE TABLE metadata(value TEXT) STRICT; INSERT INTO metadata VALUES (\'original\')');
  database.close();
  return {scratch,path,bytes:readFileSync(path)};
}

test('isolated inspection retains its actual wrapper before fallible native open',async()=>{
  const {scratch,path,bytes}=await fixture();const open=DatabaseSync.prototype.open;
  let opens=0;
  DatabaseSync.prototype.open=function(){opens++;assert.equal(this.isOpen,false);
    return Reflect.apply(open,this,[]);};
  try {
    assert.equal(inspectSqliteSnapshot(path,database=>
      database.prepare('SELECT value FROM metadata').get().value,{maxSourceBytes:65536}),'original');
    assert.equal(opens,1);assert.deepEqual(readFileSync(path),bytes);
  } finally {DatabaseSync.prototype.open=open;}
  scratch.passed();
});

for(const mode of ['false','throw'])test('isolated post-open failure retains copy and source duties through '+mode+' close',async()=>{
  const {scratch,path,bytes}=await fixture();
  const open=DatabaseSync.prototype.open,close=DatabaseSync.prototype.close;
  const primary=new Error('OriginalInspectionOpenFailure');
  let observed,isolated,opens=0,closes=0,allow=false,failure,inspections=0;
  DatabaseSync.prototype.close=function(){assert.equal(this,observed);closes++;
    if(!allow){if(mode==='throw')throw new Error('OriginalInspectionClosePending');return false;}
    return Reflect.apply(close,this,[]);};
  DatabaseSync.prototype.open=function(){observed=this;opens++;
    Reflect.apply(open,this,[]);isolated=dirname(this.location());
    this.close=()=>undefined;throw primary;};
  try {
    assert.throws(()=>inspectSqliteSnapshot(path,()=>{inspections++;},
      {maxSourceBytes:65536}),error=>{
      failure=error;return error.primaryFailure===primary&&error.cleanupHandle?.status().pending===true;
    });
    assert.equal(opens,1);assert.equal(closes,1);assert.equal(inspections,0);
    assert.equal(observed.isOpen,true);assert.equal(existsSync(isolated),true);
    assert.equal(failure.cleanupHandle.retry().pending,true);assert.equal(closes,2);
    allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);
    assert.equal(observed.isOpen,false);assert.equal(existsSync(isolated),false);
    assert.equal(opens,1);assert.equal(closes,3);assert.equal(inspections,0);
    assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(closes,3);
    assert.deepEqual(readFileSync(path),bytes);
  } finally {
    DatabaseSync.prototype.open=open;DatabaseSync.prototype.close=close;
    allow=true;
    if(failure?.cleanupHandle.status().pending)failure.cleanupHandle.retry();
    if(observed?.isOpen)Reflect.apply(close,observed,[]);
  }
  scratch.passed();
});

test('isolated pre-open refusal preserves its cause and closes pinned originals without an unopened close',async()=>{
  const {scratch,path,bytes}=await fixture();
  const open=DatabaseSync.prototype.open,close=DatabaseSync.prototype.close;
  const primary=new Error('OriginalInspectionOpenRefused');let opens=0,closes=0,inspections=0;
  DatabaseSync.prototype.open=function(){opens++;assert.equal(this.isOpen,false);throw primary;};
  DatabaseSync.prototype.close=function(){closes++;return Reflect.apply(close,this,[]);};
  try {
    assert.throws(()=>inspectSqliteSnapshot(path,()=>{inspections++;},
      {maxSourceBytes:65536}),error=>error===primary);
    assert.equal(opens,1);assert.equal(closes,0);assert.equal(inspections,0);
    assert.deepEqual(readFileSync(path),bytes);
  } finally {DatabaseSync.prototype.open=open;DatabaseSync.prototype.close=close;}
  scratch.passed();
});

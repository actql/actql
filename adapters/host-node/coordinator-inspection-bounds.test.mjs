import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {syncBuiltinESMExports} from 'node:module';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openSqliteCoordinatorDispatchJournal} from './sqlite-coordinator-journal.mjs';

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'coordinator-inspection-bound-',label:'original bounded Coordinator inspection'});
  const directory=join(scratch.path,'original');
  const options={coordinatorAuthority:'original-coordinator'};
  const first=openSqliteCoordinatorDispatchJournal(directory,options);first.close();
  return {scratch,directory,options};
}

test('Coordinator startup distinguishes bounded inspection refusal from existing format and preserves bytes',async()=>{
  const{scratch,directory,options}=await fixture();
  const path=join(directory,'coordinator-dispatch-journal.sqlite3');
  const original=fs.readFileSync(path);
  let opened;
  try{
    assert.throws(()=>{opened=openSqliteCoordinatorDispatchJournal(directory,{...options,maxInspectionBytes:1});},
      {code:'CoordinatorJournalInspectionUnavailable'});
    assert.deepEqual(fs.readFileSync(path),original);
    fs.writeFileSync(join(directory,'retained-unrelated'),'same-unrelated-original');
    assert.throws(()=>{opened=openSqliteCoordinatorDispatchJournal(directory,{...options,maxInspectionEntries:1});},
      {code:'CoordinatorJournalInspectionUnavailable'});
    assert.deepEqual(fs.readFileSync(path),original);
    opened=openSqliteCoordinatorDispatchJournal(directory,{...options,maxInspectionBytes:original.length,
      maxInspectionEntries:fs.readdirSync(directory).length});
    opened.close();opened=undefined;
    assert.equal(fs.readFileSync(join(directory,'retained-unrelated'),'utf8'),'same-unrelated-original');
  }finally{opened?.close();}
  scratch.passed();
});

test('Coordinator pending Dir cleanup keeps the same original receiver before any database handoff',async()=>{
  const{scratch,directory,options}=await fixture();
  const open=fs.opendirSync;
  let allow=false,reads=0,closes=0,failure,opened;
  fs.opendirSync=function(path,settings){
    assert.equal(path,directory);assert.deepEqual(settings,{bufferSize:1});
    const original=Reflect.apply(open,fs,[path,settings]);
    const close=original.closeSync,read=original.readSync;
    original.closeSync=function(){assert.equal(this,original);closes++;
      return allow?Reflect.apply(close,original,[]):false;};
    original.readSync=function(){reads++;original.closeSync=()=>undefined;
      return Reflect.apply(read,original,[]);};
    return original;
  };
  syncBuiltinESMExports();
  try{
    assert.throws(()=>{opened=openSqliteCoordinatorDispatchJournal(directory,options);},cause=>{
      failure=cause;return cause.code==='CoordinatorJournalInspectionCleanupPending';
    });
    const acquiredReads=reads;
    assert.equal(failure.cleanupHandle.status().pending,true);
    assert.equal(failure.cleanupHandle.retry().pending,true);
    allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);
    assert.equal(closes,3);assert.equal(reads,acquiredReads);
  }finally{
    allow=true;if(failure?.cleanupHandle.status().pending)failure.cleanupHandle.retry();
    opened?.close();fs.opendirSync=open;syncBuiltinESMExports();
  }
  scratch.passed();
});

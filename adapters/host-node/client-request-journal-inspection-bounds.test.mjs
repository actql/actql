import assert from 'node:assert/strict';
import {mkdir, readdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const root=fileURLToPath(new URL('../../_build/',import.meta.url));
async function fixture(){
  const scratch=await createOwnedScratch({parent:root,prefix:'journal-directory-bound-',
    label:'original bounded journal inspection'});
  const directory=join(scratch.path,'requests');
  return{directory,scratch};
}

// Real Node SQLite/filesystem initialization and read-only classification only.
// No Core Run, ordinary initial-control issuer, business grant or numerical
// funding is supplied by the constructor's inspection-work ceiling.
test('directory acquisition refuses during the bounded scan without reclassifying current bytes as corruption',async()=>{
  const{directory,scratch}=await fixture();
  let journal=openClientRequestJournal(directory);
  journal.close();journal=undefined;
  const before=await readdir(directory);
  const database=await readFile(join(directory,'client-requests.sqlite3'));
  try{
    assert.throws(()=>{journal=openClientRequestJournal(directory,{maxInspectionEntries:1});},
      {code:'ClientRequestJournalInspectionUnavailable'});
    assert.deepEqual(await readdir(directory),before);
    assert.deepEqual(await readFile(join(directory,'client-requests.sqlite3')),database);
  }finally{journal?.close();}
  scratch.passed();
});

test('an exact directory ceiling preserves full-name currentness and unknown retained entries',async()=>{
  const{directory,scratch}=await fixture();
  let journal=openClientRequestJournal(directory);journal.close();journal=undefined;
  await writeFile(join(directory,'retained-unrelated-original'),'preserve-original');
  const entries=await readdir(directory);
  try{
    journal=openClientRequestJournal(directory,{maxInspectionEntries:entries.length});
    journal.close();journal=undefined;
    assert.equal(await readFile(join(directory,'retained-unrelated-original'),'utf8'),'preserve-original');
    await writeFile(join(directory,'one-more-original'),'also-preserve');
    assert.throws(()=>{journal=openClientRequestJournal(directory,{maxInspectionEntries:entries.length});},
      {code:'ClientRequestJournalInspectionUnavailable'});
    assert.equal(await readFile(join(directory,'one-more-original'),'utf8'),'also-preserve');
  }finally{journal?.close();}
  scratch.passed();
});

test('invalid inspection-work ceilings refuse before creating a journal',async()=>{
  const{directory,scratch}=await fixture();
  await mkdir(directory,{recursive:true});
  for(const maxInspectionEntries of[0,-1,NaN,Infinity,1.5]){
    let journal;
    try{assert.throws(()=>{journal=openClientRequestJournal(directory,{maxInspectionEntries});},
      {code:'InvalidClientRequestJournalConfiguration'});}
    finally{journal?.close();}
  }
  assert.deepEqual(await readdir(directory),[]);
  scratch.passed();
});

for(const mode of['false','throw'])test('real Dir '+mode+' close retains the same original callback and refuses handoff',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const originalOpen=fs.opendirSync;
  let pending,allowClose=false,reads=0,closes=0,journal;
  const cause=Object.freeze(new Error('OriginalDirectoryCloseRefusal'));
  fs.opendirSync=function(path,options){
    assert.equal(path,directory);assert.deepEqual(options,{bufferSize:1});
    const original=Reflect.apply(originalOpen,fs,[path,options]);
    const read=original.readSync,close=original.closeSync;
    original.closeSync=function(){
      assert.equal(this,original);closes++;
      if(!allowClose){if(mode==='throw')throw cause;return false;}
      return Reflect.apply(close,original,[]);
    };
    original.readSync=function(){
      reads++;
      original.closeSync=()=>undefined;
      return Reflect.apply(read,original,[]);
    };
    return original;
  };
  syncBuiltinESMExports();
  try{
    assert.throws(()=>{journal=openClientRequestJournal(directory);},failure=>{
      assert.equal(failure.code,'ClientRequestJournalInspectionCleanupPending');
      pending=failure.cleanupHandle;return failure.cleanupPending===true;
    });
    assert.equal(pending.status().pending,true);assert.equal(closes,1);
    const capturedReads=reads;
    assert.equal(pending.retry().pending,true);assert.equal(closes,2);
    assert.equal(reads,capturedReads);
    allowClose=true;
    assert.equal(pending.retry().pending,false);assert.equal(closes,3);
    assert.equal(reads,capturedReads);
  }finally{
    fs.opendirSync=originalOpen;syncBuiltinESMExports();
    allowClose=true;if(pending?.status().pending)pending.retry();journal?.close();
  }
  assert.equal(pending.status().pending,false);
  scratch.passed();
});

test('a full-name snapshot still refuses a new unrelated entry added during SQLite inspection',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const originalWrite=fs.writeSync;
  let changed=false,journal;
  fs.writeSync=function(...args){
    const result=Reflect.apply(originalWrite,fs,args);
    if(!changed){changed=true;fs.writeFileSync(join(directory,'concurrent-original'),'preserve-new-original');}
    return result;
  };
  syncBuiltinESMExports();
  try{
    assert.throws(()=>{journal=openClientRequestJournal(directory);},
      {code:'UnknownClientRequestJournalFormat'});
    assert.equal(changed,true);
    assert.equal(await readFile(join(directory,'concurrent-original'),'utf8'),'preserve-new-original');
  }finally{fs.writeSync=originalWrite;syncBuiltinESMExports();journal?.close();}
  scratch.passed();
});

test('bounded inspection keeps legacy and unknown format refusal separate from resource refusal',async()=>{
  const{directory,scratch}=await fixture();
  const other=join(scratch.path,'unknown');
  await mkdir(directory,{recursive:true});await mkdir(other);
  await writeFile(join(directory,'client-requests.sqlite3'),'preserve-legacy-original');
  await writeFile(join(other,'unrecognized'),'preserve-unknown-original');
  assert.throws(()=>openClientRequestJournal(directory,{maxInspectionEntries:1}),
    {code:'LegacyClientRequestJournalFormat'});
  assert.throws(()=>openClientRequestJournal(other,{maxInspectionEntries:1}),
    {code:'UnknownClientRequestJournalFormat'});
  assert.equal(await readFile(join(directory,'client-requests.sqlite3'),'utf8'),'preserve-legacy-original');
  assert.equal(await readFile(join(other,'unrecognized'),'utf8'),'preserve-unknown-original');
  scratch.passed();
});

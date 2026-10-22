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

test('fixed journal markers use no whole-file materialization during admission or currentness',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const originalRead=fs.readFileSync;
  let materializations=0,journal;
  fs.readFileSync=function(path,...args){
    if(typeof path==='string'&&path.startsWith(directory+'/')&&path.endsWith('.json')){
      materializations++;throw new Error('WholeMarkerReadForbidden');
    }
    return Reflect.apply(originalRead,fs,[path,...args]);
  };
  syncBuiltinESMExports();
  try{journal=openClientRequestJournal(directory);journal.close();journal=undefined;}
  finally{fs.readFileSync=originalRead;syncBuiltinESMExports();journal?.close();}
  assert.equal(materializations,0);
  scratch.passed();
});

test('consumed marker close Unknown cannot close a reused descriptor during cleanup observation',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const sentinel=join(scratch.path,'separate-original');
  await writeFile(sentinel,'separate original must stay open');
  const originalOpen=fs.openSync,originalClose=fs.closeSync;
  let marker,reused,pending,closes=0,injected=false;
  const cause=Object.freeze(new Error('OriginalCloseOutcomeLost'));
  fs.openSync=function(path,...args){
    const fd=Reflect.apply(originalOpen,fs,[path,...args]);
    if(path===join(directory,'journal-format.json'))marker=fd;
    return fd;
  };
  fs.closeSync=function(fd){
    if(fd===marker){
      closes++;
      if(!injected){
        injected=true;
        Reflect.apply(originalClose,fs,[fd]);
        reused=Reflect.apply(originalOpen,fs,[sentinel,'r']);
        assert.equal(reused,marker,'fresh synchronous descriptor reuse is required by this counter');
        throw cause;
      }
    }
    return Reflect.apply(originalClose,fs,[fd]);
  };
  syncBuiltinESMExports();
  try{
    assert.throws(()=>openClientRequestJournal(directory),failure=>{
      assert.equal(failure.code,'ClientRequestJournalInspectionCleanupPending');
      assert.strictEqual(failure.primaryFailure,cause);
      pending=failure.cleanupHandle;return failure.cleanupPending===true;
    });
    assert.equal(injected,true);
    const identity=fs.statSync(sentinel,{bigint:true});
    for(let attempt=0;attempt<2;attempt++){
      assert.equal(pending.retry().pending,true);
      const actual=fs.fstatSync(reused,{bigint:true});
      assert.equal(actual.dev,identity.dev);assert.equal(actual.ino,identity.ino);
    }
    assert.equal(closes,1);
  }finally{
    fs.openSync=originalOpen;fs.closeSync=originalClose;syncBuiltinESMExports();
    // Only the counter owns this separate fresh descriptor. This is not an
    // ACK of the product's unknown original or a cleanup retry for its number.
    if(reused!==undefined){try{fs.fstatSync(reused);Reflect.apply(originalClose,fs,[reused]);}
      catch(error){if(error.code!=='EBADF')throw error;}}
  }
  scratch.passed();
});

for(const mode of['false','throw'])test('real marker FD '+mode+' close retains consumed-close Unknown without another close',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const originalOpen=fs.openSync,originalRead=fs.readSync,originalClose=fs.closeSync;
  let fd,pending,allow=false,reads=0,closes=0,journal;
  const cause=Object.freeze(new Error('OriginalMarkerCloseRefusal'));
  fs.openSync=function(path,...args){
    const opened=Reflect.apply(originalOpen,fs,[path,...args]);
    if(path===join(directory,'journal-format.json'))fd=opened;
    return opened;
  };
  fs.closeSync=function(value){
    if(value===fd){closes++;if(!allow){if(mode==='throw')throw cause;return false;}}
    return Reflect.apply(originalClose,fs,[value]);
  };
  fs.readSync=function(value,...args){
    if(value===fd){reads++;fs.closeSync=()=>undefined;syncBuiltinESMExports();}
    return Reflect.apply(originalRead,fs,[value,...args]);
  };
  syncBuiltinESMExports();
  try{
    assert.throws(()=>{journal=openClientRequestJournal(directory);},failure=>{
      assert.equal(failure.code,'ClientRequestJournalInspectionCleanupPending');
      pending=failure.cleanupHandle;return failure.cleanupPending===true;
    });
    const capturedReads=reads;
    assert.equal(pending.status().pending,true);assert.equal(closes,1);
    assert.equal(pending.retry().pending,true);assert.equal(closes,1);
    assert.equal(reads,capturedReads);
    allow=true;assert.equal(pending.retry().pending,true);assert.equal(closes,1);
    assert.equal(reads,capturedReads);
  }finally{
    fs.openSync=originalOpen;fs.readSync=originalRead;fs.closeSync=originalClose;syncBuiltinESMExports();
    // This fault fixture deliberately did NOT enter the native close. The
    // fixture still owns that open descriptor and closes it exactly once for
    // teardown; this does not turn the product's unknown outcome into an ACK.
    if(fd!==undefined)Reflect.apply(originalClose,fs,[fd]);
    journal?.close();
  }
  scratch.passed();
});

test('retained journal copy extent is an inspection Unavailable, not corrupt or rewritten state',async()=>{
  const{directory,scratch}=await fixture();
  const first=openClientRequestJournal(directory);first.close();
  const before=await readFile(join(directory,'client-requests.sqlite3'));
  let journal;
  try{
    assert.throws(()=>{journal=openClientRequestJournal(directory,{maxInspectionBytes:1});},
      {code:'ClientRequestJournalInspectionUnavailable'});
    assert.deepEqual(await readFile(join(directory,'client-requests.sqlite3')),before);
    journal=openClientRequestJournal(directory,{maxInspectionBytes:before.length});journal.close();journal=undefined;
    assert.deepEqual(await readFile(join(directory,'client-requests.sqlite3')),before);
  }finally{journal?.close();}
  scratch.passed();
});

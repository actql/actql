import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'journal-open-original-',label:'same original Journal connection initialization'});
  return {scratch,directory:join(scratch.path,'requests')};
}

// Actual Node SQLite/FS only. Injected open/close failures establish original
// connection custody, not a selected operational supplier, grant or funded Run.
test('Journal retains its actual connection before invoking the fallible open',async()=>{
  const {scratch,directory}=await fixture();
  const originalOpen=DatabaseSync.prototype.open;
  let opens=0,journal;
  DatabaseSync.prototype.open=function(){opens++;assert.equal(this.isOpen,false);
    return Reflect.apply(originalOpen,this,[]);};
  try {journal=openClientRequestJournal(directory);assert.equal(opens,1);}
  finally {DatabaseSync.prototype.open=originalOpen;journal?.close();}
  scratch.passed();
});

test('post-open failure keeps the same captured close and never reopens on cleanup',async()=>{
  const {scratch,directory}=await fixture();
  const originalOpen=DatabaseSync.prototype.open,originalClose=DatabaseSync.prototype.close;
  const primary=new Error('OriginalOpenOutcomeFailed');
  let database,opens=0,closes=0,allowClose=false,failure,journal;
  DatabaseSync.prototype.close=function(){assert.equal(this,database);closes++;
    if(!allowClose)throw new Error('OriginalConnectionClosePending');
    return Reflect.apply(originalClose,this,[]);};
  DatabaseSync.prototype.open=function(){database=this;opens++;
    Reflect.apply(originalOpen,this,[]);
    this.close=()=>undefined;
    throw primary;};
  try {
    assert.throws(()=>{journal=openClientRequestJournal(directory);},error=>{
      failure=error;return error.primaryFailure===primary&&error.cleanupHandle?.status().pending===true;
    });
    assert.equal(opens,1);assert.equal(closes,1);assert.equal(database.isOpen,true);
    assert.equal(failure.cleanupHandle.retry().pending,true);
    assert.equal(opens,1);assert.equal(closes,2);
    allowClose=true;
    assert.equal(failure.cleanupHandle.retry().pending,false);
    assert.equal(database.isOpen,false);assert.equal(closes,3);
    assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(closes,3);
  } finally {
    DatabaseSync.prototype.open=originalOpen;DatabaseSync.prototype.close=originalClose;
    if(database?.isOpen)Reflect.apply(originalClose,database,[]);
    journal?.close();
  }
  scratch.passed();
});

test('pre-open failure returns the original cause without closing an unopened connection',async()=>{
  const {scratch,directory}=await fixture();
  const originalOpen=DatabaseSync.prototype.open,originalClose=DatabaseSync.prototype.close;
  const primary=new Error('OriginalOpenRefused');let opens=0,closes=0,journal;
  DatabaseSync.prototype.open=function(){opens++;assert.equal(this.isOpen,false);throw primary;};
  DatabaseSync.prototype.close=function(){closes++;return Reflect.apply(originalClose,this,[]);};
  try {
    assert.throws(()=>{journal=openClientRequestJournal(directory);},error=>error===primary);
    assert.equal(opens,1);assert.equal(closes,0);
  } finally {
    DatabaseSync.prototype.open=originalOpen;DatabaseSync.prototype.close=originalClose;
    journal?.close();
  }
  scratch.passed();
});

test('selected Journal constructor does not acquire inherited option callbacks',async()=>{
  const {scratch,directory}=await fixture();
  const previous=Object.getOwnPropertyDescriptor(Object.prototype,'allowBareNamedParameters');
  let reads=0,journal;
  Object.defineProperty(Object.prototype,'allowBareNamedParameters',{configurable:true,
    get(){reads++;throw new Error('InheritedSqliteOptionMustNotRun');}});
  try {
    journal=openClientRequestJournal(directory,{primaryCurrent(){}});
    assert.equal(reads,0);
  } finally {
    if(previous===undefined)delete Object.prototype.allowBareNamedParameters;
    else Object.defineProperty(Object.prototype,'allowBareNamedParameters',previous);
    journal?.close();
  }
  scratch.passed();
});

test('selected observation constructor keeps its separate original without inherited options',async()=>{
  const {scratch,directory}=await fixture();
  const journal=openClientRequestJournal(directory,{primaryCurrent(){}});
  const previous=Object.getOwnPropertyDescriptor(Object.prototype,'allowBareNamedParameters');
  let reads=0;
  Object.defineProperty(Object.prototype,'allowBareNamedParameters',{configurable:true,
    get(){reads++;throw new Error('InheritedObservationOptionMustNotRun');}});
  try {
    assert.ok(journal.observationStorage());
    assert.equal(reads,0);
  } finally {
    if(previous===undefined)delete Object.prototype.allowBareNamedParameters;
    else Object.defineProperty(Object.prototype,'allowBareNamedParameters',previous);
    journal.close();
  }
  scratch.passed();
});

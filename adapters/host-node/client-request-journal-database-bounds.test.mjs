import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'journal-database-bound-',label:'actual Journal database extent support'});
  return {scratch,directory:join(scratch.path,'requests')};
}
function originalDatabase(directory,options) {
  const open=DatabaseSync.prototype.open;let database,journal;
  DatabaseSync.prototype.open=function(){database=this;return Reflect.apply(open,this,[]);};
  try {journal=openClientRequestJournal(directory,options);}
  finally {DatabaseSync.prototype.open=open;}
  return {database,journal};
}

// The captured native handle is an explicit physical test observation, never
// a product getter, selected Root, business capacity or mutation authority.
test('optional Journal database extent is enforced by the same actual connection',async()=>{
  const {scratch,directory}=await fixture();const bytes=1024*1024;
  const {database,journal}=originalDatabase(directory,{maxDatabaseBytes:bytes});
  try {
    const page=database.prepare('PRAGMA page_size').get().page_size;
    assert.ok(database.prepare('PRAGMA max_page_count').get().max_page_count*page<=bytes);
    database.exec('CREATE TABLE extent_fixture(value BLOB) STRICT');
    assert.throws(()=>database.prepare('INSERT INTO extent_fixture VALUES (zeroblob(?))').run(bytes*2),
      error=>error.code==='ERR_SQLITE_ERROR'&&error.errcode===13);
    assert.equal(database.isTransaction,false);
    assert.ok(database.prepare('PRAGMA page_count').get().page_count*page<=bytes);
    assert.equal(database.prepare('SELECT count(*) AS n FROM extent_fixture').get().n,0);
  } finally {journal.close();}
  assert.equal(database.isOpen,false);scratch.passed();
});

test('selected smaller database ceiling refuses original bytes before SQLite inspection opens',async()=>{
  const {scratch,directory}=await fixture();
  const {database,journal}=originalDatabase(directory);
  try {database.exec('CREATE TABLE extent_fixture(value BLOB) STRICT');
    database.prepare('INSERT INTO extent_fixture VALUES (zeroblob(?))').run(2*1024*1024);
  } finally {journal.close();}
  const path=join(directory,'client-requests.sqlite3'),before=readFileSync(path);
  assert.ok(before.length>1024*1024);
  const open=DatabaseSync.prototype.open;let opens=0,next;
  DatabaseSync.prototype.open=function(){opens++;return Reflect.apply(open,this,[]);};
  try {assert.throws(()=>{next=openClientRequestJournal(directory,{maxDatabaseBytes:1024*1024});},
    {code:'ClientRequestJournalInspectionUnavailable'});assert.equal(opens,0);}
  finally {DatabaseSync.prototype.open=open;next?.close();}
  assert.deepEqual(readFileSync(path),before);scratch.passed();
});

test('invalid optional database ceilings refuse before creating any Journal',async()=>{
  const {scratch,directory}=await fixture();
  for(const [index,maxDatabaseBytes]of[0,-1,NaN,Infinity,1.5].entries()) {
    const path=directory+index;let journal;
    try {assert.throws(()=>{journal=openClientRequestJournal(path,{maxDatabaseBytes});},
      {code:'InvalidClientRequestJournalConfiguration'});}
    finally {journal?.close();}
    assert.equal(existsSync(path),false);
  }
  scratch.passed();
});

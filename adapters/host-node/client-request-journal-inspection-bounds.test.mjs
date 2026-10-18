import assert from 'node:assert/strict';
import {mkdir, readdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
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

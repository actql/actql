import assert from 'node:assert/strict';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

async function fixture() {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'journal-fresh-schema-',label:'original Journal schema initialization',preserve:true});
  return {scratch,directory:join(scratch.path,'requests')};
}

// Actual Node SQLite and filesystem, with original methods restored in finally.
// This counts schema transactions and marker ACKs, not wall time, Core funding,
// or SQLite's internal native fsync calls.
test('fresh Journal commits its complete current schema once before publishing format markers',async()=>{
  const {scratch,directory}=await fixture();
  const originalExec=DatabaseSync.prototype.exec,originalOpen=fs.openSync,originalFsync=fs.fsyncSync;
  const events=[];let markerFsyncs=0,directoryFsyncs=0,journal;
  DatabaseSync.prototype.exec=function(sql){
    const result=Reflect.apply(originalExec,this,[sql]);
    if(sql==='BEGIN IMMEDIATE'||sql==='COMMIT'||sql==='ROLLBACK')events.push(sql);
    return result;
  };
  fs.openSync=function(path,...args){
    const fd=Reflect.apply(originalOpen,fs,[path,...args]);
    if(typeof path==='string'&&path.startsWith(directory+'/')&&args[0]==='wx')events.push('marker');
    return fd;
  };
  fs.fsyncSync=function(fd){
    if(fs.fstatSync(fd).isDirectory())directoryFsyncs++;else markerFsyncs++;
    return Reflect.apply(originalFsync,fs,[fd]);
  };
  syncBuiltinESMExports();
  try {
    journal=openClientRequestJournal(directory);
    console.log('JOURNAL_SCHEMA_COUNTS '+JSON.stringify({begins:events.filter(x=>x==='BEGIN IMMEDIATE').length,
      commits:events.filter(x=>x==='COMMIT').length,markerFsyncs,directoryFsyncs,events}));
    assert.equal(events.filter(x=>x==='BEGIN IMMEDIATE').length,1);
    assert.equal(events.filter(x=>x==='COMMIT').length,1);
    assert.equal(events.includes('ROLLBACK'),false);
    assert.ok(events.indexOf('COMMIT')<events.indexOf('marker'));
    assert.equal(markerFsyncs,8);
    assert.equal(directoryFsyncs,1);
  } finally {
    DatabaseSync.prototype.exec=originalExec;fs.openSync=originalOpen;fs.fsyncSync=originalFsync;
    syncBuiltinESMExports();journal?.close();
  }
  scratch.passed();
});

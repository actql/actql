// Actual fresh Store/FD counters. The contract-control fixture is explicit;
// no retained product Run, installed campaign or genuine Core grant is used.
import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import test from 'node:test';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const isCustody = bytes => Buffer.isBuffer(bytes) && bytes.toString('utf8').startsWith(
  '{"version":"actql-local-prepared-custody/0.1"');
async function fixture(maxObjects) {
  const scratch = await createOwnedScratch({parent:new URL('../../_build/',import.meta.url).pathname,
    prefix:'custody-pending-admission-',label:'original metadata duty admission and healthy parallelism'});
  const store = await openLocalPublicationStore({directory:join(scratch.path,'store'),
    storeAuthorityCid:cid('fresh custody admission'),capacityBytes:65536,maxObjectBytes:4096,
    maxObjects,maxContractNodes:256,maxContractDepth:32},createPublicationContractControlFixture());
  return {scratch,store};
}

for (const mode of ['false','rejected']) {
  test(`pending ${mode}-close original metadata refuses another acquisition until the same FD retires`,async()=>{
    const {scratch,store}=await fixture(1);
    const originalOpen=fs.open,metadataHandles=[],writers=[],stored=[];
    const primary=Object.freeze(new Error('original failed metadata close'));
    let refusing=true,phase='idle',metadataWrites=0,metadataOpens=0,firstFailure;
    fs.open=async(...args)=>{
      const handle=await originalOpen(...args),write=handle.write.bind(handle),close=handle.close.bind(handle);
      let metadata=false;
      if(phase==='seal' && typeof args[1]==='number' &&
          (args[1] & (constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY))===
          (constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY)) metadataOpens++;
      handle.write=async(...values)=>{
        if(isCustody(values[0])){metadata=true;metadataWrites++;metadataHandles.push(handle);}
        return write(...values);
      };
      handle.close=async()=>{
        if(metadata && refusing){if(mode==='false')return false;throw primary;}
        return close();
      };
      return handle;
    };
    syncBuiltinESMExports();
    try {
      const first=store.createPreparedObjectWriter(5);writers.push(first);
      await first.append('first');phase='seal';
      await assert.rejects(first.seal(cid('first')),error=>{
        firstFailure=error;return error.code==='PublicationStoreCleanupPending';
      });phase='idle';
      if(mode==='rejected')assert.equal(firstFailure.primaryFailure,primary);
      const snapshot=firstFailure.cleanupHandle.status();
      assert.equal(snapshot.pending,true);
      assert.equal(first.status().reservationHeld,false,
        'this counter keeps the original released payload reservation, not an invented FD quota');
      assert.equal(metadataWrites,1);assert.equal(metadataOpens,1);
      assert.equal(metadataHandles.length,1);
      const originalFd=metadataHandles[0].fd;
      assert.ok(originalFd>=0);await metadataHandles[0].stat();
      const second=store.createPreparedObjectWriter(6);writers.push(second);
      await second.append('second');phase='seal';
      await assert.rejects(second.seal(cid('second')), {code:'PublicationStoreCleanupPending'});
      phase='idle';
      assert.equal(metadataOpens,1,'the second metadata FD must not be opened');
      assert.equal(metadataWrites,1,'the pending original duty must not be followed by another metadata write');
      assert.equal(metadataHandles[0].fd,originalFd);
      assert.equal(firstFailure.cleanupHandle.status().pending,true);
      await assert.rejects(firstFailure.cleanupHandle.retry(),mode==='false'
        ? {code:'PublicationStoreCleanupPending'} : error=>error===primary);
      assert.equal(metadataWrites,1);assert.equal(metadataOpens,1);
      refusing=false;
      const retry=firstFailure.cleanupHandle.retry();
      assert.equal(firstFailure.cleanupHandle.retry(),retry,'cleanup remains one flight on the same FD');
      assert.equal((await retry).pending,false);
      assert.equal(metadataHandles[0].fd,-1);
      assert.equal(snapshot.pending,true,'previous frozen status is not changed');
      const third=store.createPreparedObjectWriter(5);writers.push(third);
      await third.append('third');phase='seal';
      stored.push(await third.seal(cid('third')));phase='idle';
      assert.equal(metadataOpens,2,'ordinary preparation resumes only after original cleanup');
      assert.equal(metadataWrites,2);
      assert.equal(store.status().storedBytes,5);
      await stored[0].prepared.release();
      assert.equal(store.status().storedBytes,0);
      await store.close();
      scratch.passed();
    } finally {
      refusing=false;phase='idle';fs.open=originalOpen;syncBuiltinESMExports();
      for(const value of stored)if(value.prepared.status().pending)await value.prepared.release();
      for(const writer of writers)await writer.cancel();
      if(!store.status().closed)await store.close();
      for(const handle of metadataHandles)assert.equal(handle.fd,-1);
    }
  });
}

test('healthy custody writers can acquire and write metadata while an independent healthy write is awaiting',async()=>{
  const {scratch,store}=await fixture(2),originalOpen=fs.open,stored=[];
  let enterFirst,enterSecond,continueFirst;
  const firstEntered=new Promise(resolve=>{enterFirst=resolve;});
  const secondEntered=new Promise(resolve=>{enterSecond=resolve;});
  const firstContinues=new Promise(resolve=>{continueFirst=resolve;});
  let metadataWrites=0;
  fs.open=async(...args)=>{
    const handle=await originalOpen(...args),write=handle.write.bind(handle);
    handle.write=async(...values)=>{
      if(isCustody(values[0])){
        metadataWrites++;
        if(metadataWrites===1){enterFirst();await firstContinues;}
        else if(metadataWrites===2)enterSecond();
      }
      return write(...values);
    };
    return handle;
  };
  syncBuiltinESMExports();
  let firstSeal,secondSeal;
  try {
    const first=store.createPreparedObjectWriter(5),second=store.createPreparedObjectWriter(6);
    await Promise.all([first.append('first'),second.append('second')]);
    firstSeal=first.seal(cid('first')).then(value=>{stored.push(value);return value;});
    await firstEntered;
    secondSeal=second.seal(cid('second')).then(value=>{stored.push(value);return value;});
    await Promise.race([secondEntered,secondSeal.then(()=>assert.fail('No second metadata write'))]);
    assert.equal(metadataWrites,2,'the healthy first writer is not a serialization fence');
    continueFirst();
    await Promise.all([firstSeal,secondSeal]);
    assert.equal(store.status().storedBytes,11);
    for(const value of stored)await value.prepared.release();
    await store.close();scratch.passed();
  } finally {
    continueFirst();fs.open=originalOpen;syncBuiltinESMExports();
    await Promise.allSettled([firstSeal,secondSeal].filter(Boolean));
    for(const value of stored)if(value.prepared.status().pending)await value.prepared.release();
    if(!store.status().closed)await store.close();
  }
});

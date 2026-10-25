import assert from 'node:assert/strict';
import test, {before} from 'node:test';
import {registerHooks} from 'node:module';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const hookKey=Symbol.for('actql.test.validation-close');
let open,coherence,loader;
before(async()=>{
 coherence=await verifyLocalSourceRuntime(root);
 const target=new URL('../../packages/local-node/adapters/host-common/runtime-core.mjs',import.meta.url).href;
 loader=registerHooks({load(url,context,next){
  const loaded=next(url,context);if(url!==target)return loaded;
  const original=String(loaded.source);
  const begin='          moon.clientProgramAdvanceValidation(validation, 256)));';
  const cancel='      moon.clientProgramCancelValidation(validation);';
  assert.equal(original.split(begin).length,2,'one exact typed validation advance seam');
  assert.equal(original.split(cancel).length,2,'one exact typed validation cancel seam');
  const source=original.replace(begin,begin+`\n        if (requireCurrent !== undefined) await globalThis[Symbol.for('actql.test.validation-close')].afterAdvance(validation);`).replace(cancel,cancel+`\n      if (requireCurrent !== undefined) globalThis[Symbol.for('actql.test.validation-close')].afterCancel(validation);`);
  console.log(JSON.stringify({testInstrumentation:'validation-close-negative',path:target,originalSha256:createHash('sha256').update(original).digest('hex'),instrumentedSha256:createHash('sha256').update(source).digest('hex')}));
  return {...loaded,source};
 }});
 ({open}=await import('../../packages/node/index.mjs'));
});

// Instrumented actual public publication: only a nonrejecting scheduling barrier
// after the original checker advances. Store currentness, verdicts, reservations
// and cancellation are unchanged. The reopened full checker has a separate test.
test('ordinary Local close waits for Store-held retained validator cancellation', {timeout:60000}, async()=>{
 const stateDir=await mkdtemp(join(tmpdir(),'actql-validation-close-'));
 let db=await open({stateDir}),success=false,release,reached,selected,armed=true;
 const held=new Promise(resolve=>{release=resolve;});
 const barrier=new Promise(resolve=>{reached=resolve;});
 const events=[];
 globalThis[hookKey]={
  async afterAdvance(validation){if(armed){armed=false;selected=validation;events.push('held');reached();await held;}},
  afterCancel(validation){if(validation===selected)events.push('cancelled');},
 };
 try{
  const count=1000;
  const program={version:'actql/0.1',id:'validation-close',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:Array.from({length:count},(_,x)=>({x}))}}],results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
  const expected=Array.from({length:count},(_,x)=>({x}));
  const run=await db.start(program),ref=run.ref;
  const waiting=run.wait({signal:AbortSignal.timeout(30000)}).then(value=>({value}),error=>({error}));
  await Promise.race([barrier,new Promise((_,reject)=>{const signal=AbortSignal.timeout(30000);signal.addEventListener('abort',()=>reject(new Error('Store-held retained validation barrier not reached')),{once:true});})]);
  let closed=false;
  const closing=db.close().then(()=>{closed=true;events.push('closed');return {};},error=>({error}));
  await Promise.resolve();await Promise.resolve();assert.equal(closed,false);
  assert.deepEqual(events,['held']);release();
  const closeOutcome=await closing;
  if(closeOutcome.error)assert.match(closeOutcome.error.code??closeOutcome.error.message,/CleanupPending|cleanup/i);
  await waiting;
  await db.close();db=undefined;
  assert.ok(events.includes('cancelled'),'the original typed checker finally must run');
  if(events.includes('closed'))assert.ok(events.indexOf('cancelled')<events.indexOf('closed'));
  // Resolve the original current-version state rather than inventing success or
  // absence. A committed Run must remain fully readable after reopen.
  db=await open({stateDir});
  const restored=await db.attach(ref),status=await restored.status();
  assert.equal(status.control.physical_stop,'confirmed');
  if(status.status==='succeeded')assert.deepEqual(await restored.result('answer').all(),expected);
  else assert.ok(['failed','cancelled'].includes(status.status),JSON.stringify(status));
  const subsequent=await db.start(program);
  assert.equal((await subsequent.wait({signal:AbortSignal.timeout(30000)})).status,'succeeded');
  assert.deepEqual(await subsequent.result('answer').all(),expected);
  await db.close();db=undefined;success=true;
 }finally{
  release();
  try{if(db)await db.close();}finally{delete globalThis[hookKey];loader?.deregister();}
  assertSourceRuntimeReceiptCurrent(coherence);
  if(success)await rm(stateDir,{recursive:true,force:true});
 }
});

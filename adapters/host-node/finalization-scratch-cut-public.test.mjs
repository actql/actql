import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';
import {createHash} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime,assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

// Read-only original accounting at the fixed manager boundary. No compiled
// function-name matching, cleanup calls, reservation changes or forged owners.
// The old driver produces identical rows but fails the E equality assertion.
test('completed managed finalization retires scratch before publication while output remains pinned',{timeout:120000},async()=>{
 const root=fileURLToPath(new URL('../../',import.meta.url));
 const coherence=await verifyLocalSourceRuntime(root);
 const target=new URL('../../packages/local-node/adapters/host-node/ordinary-source-managed.mjs',import.meta.url).href;
 const key=Symbol.for('actql.test.finalization-scratch-cut');
 const samples=[];
 globalThis[key]=(state,phase)=>{
  const value=state.context.runtime.clientProgramRequestPreparationAccounting(state.parent);
  const names=['reservedR','reservedE','held','peakR','tokenR','tokenE'];
  const sample={phase};
  for(let i=0;i<6;i++){const n=runtimeField(value,i);assert.equal(typeof n,'bigint');sample[names[i]]=n;}
  samples.push(sample);
 };
 const loader=registerHooks({load(url,context,next){
  const loaded=next(url,context);if(url!==target)return loaded;
  const original=String(loaded.source);
  const reserve=`      return checkedPreparation(state.context.runtime,
        state.context.runtime.clientProgramReservePublication(
          run.value, prepared));`;
  const stop='      liveRuns.delete(run);producer.liveRuns--;';
  assert.equal(original.split(reserve).length,2);assert.equal(original.split(stop).length,2);
  const source=original.replace(reserve,`      const publication = checkedPreparation(state.context.runtime,
        state.context.runtime.clientProgramReservePublication(
          run.value, prepared));
      globalThis[Symbol.for('actql.test.finalization-scratch-cut')](state,'publication');
      return publication;`).replace(stop,`      globalThis[Symbol.for('actql.test.finalization-scratch-cut')](state,'stopped');\n${stop}`);
  console.log(JSON.stringify({testInstrumentation:'readonly-finalization-accounting',cohort:coherence.sourceTreeDigest,originalSha256:createHash('sha256').update(original).digest('hex'),instrumentedSha256:createHash('sha256').update(source).digest('hex')}));
  return {...loaded,source};
 }});
 let db,success=false;const stateDir=await mkdtemp(join(tmpdir(),'actql-finalization-cut-'));
 try{
  const {open}=await import('../../packages/node/index.mjs');db=await open({stateDir});
  const count=1000;
  const program={version:'actql/0.1',id:'finalization-cut',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{v:{type:'number',nullable:false}},rows:Array.from({length:count},(_,v)=>({v}))}}],results:{rows:{from:'v',fields:['v']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
  const run=await db.start(program);const outcome=await run.wait({signal:AbortSignal.timeout(60000)});
  assert.equal(outcome.status,'succeeded',JSON.stringify(outcome));
  let rows=0;for await(const row of run.result('answer').rows()){assert.deepEqual(row,{v:rows});rows++;}assert.equal(rows,count);
  await db.close();db=undefined;
  const publication=samples.filter(x=>x.phase==='publication');assert.equal(publication.length,1);
  assert.ok(publication[0].held>0n,'published output retains its original holding');
  assert.ok(publication[0].tokenE>0n,'publication constructors remain funded');
  assert.equal(publication[0].reservedE,publication[0].tokenE,'completed Compute scratch must be retired, not carried into publication');
  const stopped=samples.filter(x=>x.phase==='stopped');assert.equal(stopped.length,1);
  for(const field of ['reservedR','reservedE','held','tokenR','tokenE'])assert.equal(stopped[0][field],0n);
  success=true;
 }finally{
  try{if(db)await db.close();}finally{loader.deregister();delete globalThis[key];}
  assertSourceRuntimeReceiptCurrent(coherence);
  if(success)await rm(stateDir,{recursive:true,force:true});
 }
});

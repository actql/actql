import assert from 'node:assert/strict';
import test, {before} from 'node:test';
import {registerHooks} from 'node:module';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const hookKey=Symbol.for('actql.test.snapshot-original');
let open,coherence,loader;
before(async()=>{
 coherence=await verifyLocalSourceRuntime(root);
 const target=new URL('../../packages/local-node/adapters/host-common/runtime-core.mjs',import.meta.url).href;
 loader=registerHooks({load(url,context,next){
  const loaded=next(url,context);if(url!==target)return loaded;
  const original=String(loaded.source);
  const begin='    const snapshot = checked(moon.clientProgramBeginSnapshot(publication, output));';
  assert.equal(original.split(begin).length,2,'one exact typed snapshot issuer seam');
  const source=original.replace(begin,`    const snapshot = checked(globalThis[Symbol.for('actql.test.snapshot-original')].begin(moon,publication,output));\n    await globalThis[Symbol.for('actql.test.snapshot-original')].afterBegin(snapshot);`);
  console.log(JSON.stringify({testInstrumentation:'snapshot-original-negative',path:target,originalSha256:createHash('sha256').update(original).digest('hex'),instrumentedSha256:createHash('sha256').update(source).digest('hex')}));
  return {...loaded,source};
 }});
 ({open}=await import('../../packages/node/index.mjs'));
});

// Actual Core originals from two simultaneous public submissions. The loader
// inserts only a test-owned scheduling/fault boundary; it cannot fabricate a
// successful issuer or alter original guards. This is an instrumented negative
// regression, separate from the unmodified public acceptance suite.
test('two live equal-CID outputs cannot cross original publication owners', {timeout:60000}, async()=>{
 const stateDir=await mkdtemp(join(tmpdir(),'actql-snapshot-original-'));
 let db=await open({stateDir}),success=false,first,releaseFirst;
 const held=new Promise(resolve=>{releaseFirst=resolve;});let calls=0,foreignRejected=0;
 globalThis[hookKey]={
  begin(moon,publication,output){
   calls++;
   const schema=checked(moon.strategyHostOutputExportResultSchemaCid(output));
   const relation=checked(moon.strategyHostOutputExportLogicalRelationCid(output));
   if(first===undefined){const result=moon.clientProgramBeginSnapshot(publication,output);first={publication,output,snapshot:checked(result),schema,relation};return result;}
   assert.notEqual(publication,first.publication);assert.notEqual(output,first.output);
   assert.equal(schema,first.schema);assert.equal(relation,first.relation);
   try{
    const foreign=moon.clientProgramBeginSnapshot(publication,first.output);
    if(!runtimeIsError(foreign))moon.clientProgramCancelSnapshot(checked(foreign));
    assert.equal(runtimeIsError(foreign),true,'same schema/CID is not original Run authority');foreignRejected++;
    // Foreign rejection must not consume this owner's exact Result occurrence.
    const own=moon.clientProgramBeginSnapshot(publication,output);checked(own);return own;
   }finally{releaseFirst();}
  },
  async afterBegin(snapshot){if(snapshot===first.snapshot)await held;},
 };
 try{
  const count=1000;
  const program={version:'actql/0.1',id:'snapshot-original',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:Array.from({length:count},(_,x)=>({x}))}}],results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
  const runs=await Promise.all([db.start(program),db.start(program)]);
  const outcomes=await Promise.all(runs.map(run=>run.wait({signal:AbortSignal.timeout(30000)})));
  assert.deepEqual(outcomes.map(value=>value.status),['succeeded','succeeded']);
  assert.equal(calls,2);assert.equal(foreignRejected,1);
  for(const run of runs)assert.deepEqual(await run.result('answer').all(),Array.from({length:count},(_,x)=>({x})));
  await db.close();db=undefined;success=true;
 }finally{
  releaseFirst();
  try{if(db)await db.close();}finally{delete globalThis[hookKey];loader?.deregister();}
  assertSourceRuntimeReceiptCurrent(coherence);
  if(success)await rm(stateDir,{recursive:true,force:true});
 }
});

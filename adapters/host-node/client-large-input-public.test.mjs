import assert from 'node:assert/strict';
import {before,test} from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime,assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
let open,coherence;
before(async()=>{
  coherence=await verifyLocalSourceRuntime(root);
  ({open}=await import('../../packages/node/index.mjs'));
});
function fixture(width,count){
 const fields=Array.from({length:width},(_,i)=>`v${i}`);
 const rows=Array.from({length:count},(_,r)=>Object.fromEntries(fields.map((name,c)=>[name,r+c])));
 return {rows,program:{version:'actql/0.1',id:'static-limit-acceptance',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:Object.fromEntries(fields.map(name=>[name,{type:'number',nullable:false}])),rows}}],results:{rows:{from:'v',fields}}}],results:{answer0:{from:{stage:'main',result:'rows'}}}}};
}
for(const [width,count] of [[1,1],[100,99],[100,100],[101,1]]){
 test(`ordinary public Values ${width}x${count} publishes exact rows and closes`,async()=>{
  const {program,rows}=fixture(width,count);
  if(width===100&&count===99)assert.equal(Buffer.byteLength(JSON.stringify(program)),98034);
  const directory=await mkdtemp(join(tmpdir(),'actql-public-input-'));
  let db=await open({stateDir:directory});
  let completed=false;
  try{
   const run=await db.start(program);
   const observed=await run.wait({signal:AbortSignal.timeout(60000)});
   assert.equal(observed.status,'succeeded',JSON.stringify(observed));
   assert.deepEqual(await run.result('answer0').all(),rows);
   console.log(JSON.stringify({width,count,readbackRows:rows.length,status:observed}));
   // Publication may precede physical cleanup; Host close is the lifecycle barrier.
   const ref=run.ref;
   await db.close();db=undefined;
   db=await open({stateDir:directory});
   const restored=await db.attach(ref);
   const final=await restored.status();
   assert.equal(final.control.physical_stop,'confirmed',JSON.stringify(final));
   assert.deepEqual(await restored.result('answer0').all(),rows);
   completed=true;
  }finally{
   if(db)await db.close();
   assertSourceRuntimeReceiptCurrent(coherence);
   // Keep failing evidence; successful tests leave no persistent user data.
   if(completed)await rm(directory,{recursive:true,force:true});
  }
 });
}

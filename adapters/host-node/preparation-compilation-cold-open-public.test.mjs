import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime,assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';

// Node runs this file in its own process. No earlier query or compilation test
// can warm the module's interpreted compiler manifests for this installation.
test('cold ordinary installation prepares the original Values compilation before its first query', {timeout:30000}, async()=>{
 const root=fileURLToPath(new URL('../../',import.meta.url));
 const coherence=await verifyLocalSourceRuntime(root);
 const {open}=await import('../../packages/node/index.mjs');
 const stateDir=await mkdtemp(join(tmpdir(),'actql-compilation-cold-'));
 let db,success=false;
 const program={version:'actql/0.1',id:'cold-compile',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:[{x:17}]}}],results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
 try {
  db=await open({stateDir});
  const run=await db.start(program);
  assert.equal((await run.wait({signal:AbortSignal.timeout(10000)})).status,'succeeded');
  assert.deepEqual(await run.result('answer').all(),[{x:17}]);
  await db.close();db=undefined;success=true;
 } finally {
  if(db)await db.close().catch(error=>console.error('original compilation cleanup remains pending',error));
  assertSourceRuntimeReceiptCurrent(coherence);
  if(success)await rm(stateDir,{recursive:true,force:true});
  else console.error('preserved cold compilation state',stateDir);
 }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {open} from '../../packages/node/index.mjs';
const cases=JSON.parse(await readFile(new URL('./fixtures/right-join.json',import.meta.url)));
test('authored JSON RIGHT preserves multiplicity original sides and right-major order',async()=>{
 const stateDir=await mkdtemp('/tmp/actql-right-join-');const client=await open({stateDir});
 try {
  for(const c of cases){const run=await client.start(c.program);assert.equal((await run.wait()).status,'succeeded',c.id);assert.deepEqual(await run.result('answer').all(),c.expected,c.id);}
  const limited=structuredClone(cases[0].program);limited.stages[0].steps[2].join.max_output_rows=1;
  let run;try{run=await client.start(limited);}catch(e){assert.equal(e.code,'SubmissionNotAccepted');}
  if(run){assert.equal((await run.wait()).status,'failed');await assert.rejects(run.result('answer').all());}
  assert.deepEqual(await client.sql('SELECT 9 AS healthy').all(),[{healthy:9}]);
 }finally{await client.close();await rm(stateDir,{recursive:true,force:true});}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open} from '../../packages/node/index.mjs';
const program = n => ({version:'actql/0.1',id:'custody-public',stages:[{id:'main',inputs:{},
  steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:[{x:n}]}}],
  results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
test('retired Pure preparation preserves saved plan and original lookup after reopen', async () => {
  const stateDir = await mkdtemp(join(tmpdir(),'actql-preparation-retire-'));
  let db = await open({stateDir});
  try {
    const original = program(7), submissionRef = db.newSubmission({nonce:'preparation-custody-original'});
    const run = await db.start(original,{submissionRef,attemptId:'first'});
    assert.equal((await run.wait()).status,'succeeded');
    const before = await run.plan();
    const ref = run.ref;
    assert.deepEqual(await run.result('answer').all(),[{x:7}]);
    await db.close(); db = await open({stateDir});
    const retained = await db.attach(ref);
    assert.deepEqual(await retained.plan(),before);
    assert.deepEqual(await retained.result('answer').all(),[{x:7}]);
    const lookup = await db.lookupSubmission(submissionRef);
    assert.equal(lookup.kind,'ready'); assert.deepEqual(lookup.admission.ref,ref);
    assert.equal(original.stages[0].steps[0].values.rows[0].x,7);
  } finally {await db.close();await rm(stateDir,{recursive:true,force:true});}
});
test('concurrent Pure preparation owners cannot retire each other', async () => {
  const stateDir = await mkdtemp(join(tmpdir(),'actql-preparation-concurrent-'));
  const db = await open({stateDir});
  try {
    const runs = await Promise.all(Array.from({length:4},(_,n)=>db.start(program(n))));
    await Promise.all(runs.map(async(run,n)=>{
      assert.equal((await run.wait()).status,'succeeded');
      assert.deepEqual(await run.result('answer').all(),[{x:n}]);
      await run.plan();
    }));
  } finally {await db.close();await rm(stateDir,{recursive:true,force:true});}
});
test('demanded scalar failure retires the same Pure preparation without poisoning the next query', async () => {
  const stateDir = await mkdtemp(join(tmpdir(),'actql-preparation-failure-'));
  const db = await open({stateDir});
  try {
    const run = await db.startSource('SELECT 1 / 0 AS x',{format:'sql'});
    assert.equal((await run.wait({signal:AbortSignal.timeout(10000)})).status,'failed');
    await run.plan();
    assert.deepEqual(await db.sql('SELECT 9 AS x').all(),[{x:9}]);
  } finally {await db.close();await rm(stateDir,{recursive:true,force:true});}
});

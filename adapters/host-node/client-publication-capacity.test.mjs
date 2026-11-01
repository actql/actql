import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {open} from '../../packages/node/index.mjs';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

test('public Local publishes every one of 100 aliases including distinct projections and empty rows',async()=>{
 const stateDir=await mkdtemp('/tmp/actql-publication-capacity-');
 const db=await open({stateDir});let complete=false;
 try {
  for(const n of [0,1]){
   const rows=Array.from({length:n},()=>({x:7,y:9}));
   const p={version:'actql/0.1',id:'publication-capacity-'+n,
    stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false},y:{type:'number',nullable:false}},rows}}],results:{x:{from:'v',fields:['x']},y:{from:'v',fields:['y']}}}],
    results:Object.fromEntries(Array.from({length:100},(_,i)=>['r'+i,{from:{stage:'main',result:i%2?'y':'x'}}]))};
   const run=await db.start(p),state=await run.wait({signal:AbortSignal.timeout(60000)});
   assert.equal(state.status,'succeeded');
   for(let i=0;i<100;i++){const field=i%2?'y':'x';assert.deepEqual(await run.result('r'+i).all(),rows.map(row=>({[field]:row[field]})));}
  }
  complete=true;
 } finally {await db.close();if(complete)await rm(stateDir,{recursive:true,force:true});else console.error('Preserved failed capacity test state:',stateDir);}
});

test('normal Local close preserves accepted publication through immediate prewait and sibling paths', {timeout: 60000}, async t => {
  for (const mode of ['immediate', 'prewait', 'sibling']) {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-close-' + mode + '-',
      label: 'Accepted Run graceful publication'});
    let first = await open({stateDir: scratch.path}), sibling, reopened;
    try {
      if (mode === 'sibling') sibling = await open({stateDir: scratch.path});
      const run = await first.startSource('SELECT 7 AS v', {format: 'sql'});
      if (mode === 'prewait') assert.equal((await run.wait()).status, 'succeeded');
      await first.close();
      await assert.rejects(first.startSource('SELECT 8 AS v', {format: 'sql'}));
      if (sibling !== undefined) {
        const original = await sibling.attach(run.ref);
        assert.equal((await original.wait()).status, 'succeeded');
        assert.deepEqual(await original.result('main').all(), [{v: 7}]);
        await sibling.close();
      }
      reopened = await open({stateDir: scratch.path});
      const original = await reopened.attach(run.ref);
      const state = await original.wait({signal: AbortSignal.timeout(15000)});
      assert.equal(state.status, 'succeeded', mode);
      assert.equal(state.result_available, true, mode);
      assert.equal(state.control.cancellation_requested, false, mode);
      assert.deepEqual(await original.result('main').all(), [{v: 7}], mode);
      await reopened.close(); scratch.passed();
    } finally {await first.close(); await sibling?.close(); await reopened?.close();}
  }
});

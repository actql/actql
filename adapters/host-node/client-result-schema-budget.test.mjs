import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {open} from '../../packages/node/index.mjs';

test('checked schema budgets preserve wide producer projection and escaped Unicode Results',async()=>{
 const stateDir=await mkdtemp('/tmp/actql-schema-budget-guard-');
 const db=await open({stateDir});let complete=false;
 try {
  for(const name of ['x','日本😀"\\']) for(const empty of [false,true]) {
   const names=[name,...Array.from({length:99},(_,i)=>'long_source_字段_'+i)];
   const schema=Object.fromEntries(names.map(n=>[n,{type:'number',nullable:false}]));
   const rows=empty?[]:[Object.fromEntries(names.map((n,i)=>[n,i]))];
   const step='original_step_'+'長'.repeat(80);
   const p={version:'actql/0.1',id:'schema-projection',stages:[{id:'s',inputs:{},steps:[{as:step,values:{schema,rows}}],results:{r:{from:step,fields:[name]}}}],results:{a:{from:{stage:'s',result:'r'}},b:{from:{stage:'s',result:'r'}}}};
   const run=await db.start(p),status=await run.wait({signal:AbortSignal.timeout(60000)});
   assert.equal(status.status,'succeeded');
   for(const alias of ['a','b']) assert.deepEqual(await run.result(alias).all(),empty?[]:[{[name]:0}]);
  }
  assert.deepEqual(await db.sql('SELECT x FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 3 AS x) ORDER BY x DESC LIMIT 1').all(),[{x:3}]);
  complete=true;
 } finally {await db.close();if(complete)await rm(stateDir,{recursive:true,force:true});else console.error('Preserved schema budget guard:',stateDir);}
});

// Regression: producer metadata traversal formerly reused row workspace and
// failed with Config(Execution(InputSet)) before publication. The original
// schema now supplies a separate checked traversal demand.
test('single-task SQL 50-column producer preserves its execution input set',async()=>{
 const stateDir=await mkdtemp('/tmp/actql-schema-sql50-regression-');
 const db=await open({stateDir});let complete=false;
 try {
  const wide='SELECT '+Array.from({length:50},(_,i)=>`${i+1} AS c${i}`).join(', ');
  assert.deepEqual(await db.sql(`SELECT c0 FROM (${wide}) ORDER BY c0 DESC LIMIT 1`).all(),[{c0:1}]);
  complete=true;
 } finally {await db.close();if(complete)await rm(stateDir,{recursive:true,force:true});else console.error('Preserved SQL50 execution regression:',stateDir);}
});

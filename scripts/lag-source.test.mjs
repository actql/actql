import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {lagSourceSuccesses as successes,lagSourceRefusals as refusals} from './fixtures/lag-source-input.mjs';
test('Lag independent controls distinguish navigation order, offset, partitions and typed empty output',()=>{
  assert.equal(successes.length,8);
  assert.equal(refusals.length,6);
  for(let i=0;i<successes.length;i+=2){
    const json=successes[i],text=successes[i+1],program=JSON.parse(json.text);
    assert.deepEqual(text.results,{main:json.results.answer});
    assert.deepEqual(program.stages[0].steps[1].assert_rows,{unique_by:['id']});
    assert.deepEqual(program.stages[0].steps.at(-1).select,['id','amount','previous']);
    assert.deepEqual(json.results.answer.columns,[{name:'id',contract:{type:'number',nullable:false}},
      {name:'amount',contract:{type:'number',nullable:true}},{name:'previous',contract:{type:'number',nullable:true}}]);
    assert.equal(json.sourceReadCount,0);
  }
  const result=name=>successes.find(c=>c.name==='lag-json-'+name).results.answer;
  assert.deepEqual(result('default').rows.map(r=>r.previous),[30,null,10]);
  assert.deepEqual(result('offset-two').rows.map(r=>r.previous),[null,null,30]);
  assert.deepEqual(result('repeated-partition').rows.map(r=>r.previous),[null,null,null]);
  assert.deepEqual(result('empty').rows,[]);
  assert.deepEqual(result('empty').columns,result('default').columns);
  assert.equal(new Set([...successes,...refusals].map(c=>c.name)).size,14);
});
test('Lag fixtures reach both ordinary and focused installed public consumers',()=>{
  const packed=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const installer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  for(const symbol of ['lagSourceSuccesses','lagSourceRefusals'])assert.ok(packed.includes('...'+symbol));
  assert.ok(packed.includes('process.env.ACTQL_TEST_LAG_ONLY'));
  assert.ok(installer.includes("['scripts/fixtures/lag-source-input.mjs', 'lag-source-input.mjs']"));
  assert.ok(installer.includes("if (process.argv.includes('--lag-only')) return;"));
  assert.ok(packed.includes("await lagReceipts.record(item, mode)"));
  assert.ok(packed.includes('await lagReceipts.complete()'));
  assert.ok(installer.includes("['lag-receipts.local.json', 'lag-receipts.remote.json']"));
});

test('Lag registration adds exactly the independent eight successes and six refusals',async()=>{
  const before=JSON.parse(readFileSync('scripts/fixtures/pre-lag-public-query-inventory.json','utf8'));
  const {registeredPublicQueryInventory}=await import('./public-query-inventory.mjs');
  const actual=await registeredPublicQueryInventory();
  assert.equal(actual.totalCases,before.totalCases+14);
  assert.deepEqual(actual.counts,{...before.counts,successes:before.counts.successes+8,refusals:before.counts.refusals+6});
  assert.deepEqual(actual.profiles.slice(1),before.profiles.slice(1));
  assert.deepEqual(actual.repeatedFailures,before.repeatedFailures);
});

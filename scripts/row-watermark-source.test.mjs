import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {rowWatermarkSourceSuccesses as successes,rowWatermarkSourceRefusals as refusals} from './fixtures/row-watermark-source-input.mjs';
test('row watermark independent controls distinguish equality and prefix-only late rows',()=>{
  assert.equal(successes.length,8);
  assert.equal(refusals.length,6);
  for(let i=0;i<successes.length;i+=2){
    const json=successes[i],text=successes[i+1],program=JSON.parse(json.text);
    assert.deepEqual(text.results,{main:json.results.answer});
    assert.equal(json.results.answer.columns.length,5);
    assert.ok(json.results.answer.columns.every(c=>c.contract.nullable===false));
    assert.deepEqual(program.stages[0].steps.at(-1).select,json.results.answer.columns.map(c=>c.name));
  }
  const result=name=>successes.find(c=>c.name==='row-watermark-json-'+name).results.answer;
  assert.deepEqual(result('fixed-mark').rows.map(r=>r.watermark_late),[false,false,false]);
  assert.deepEqual(result('prefix-mark').rows.map(r=>r.watermark_late),[false,true,false]);
  assert.deepEqual(result('prefix-drop').rows.map(r=>r.id),[1,3]);
  assert.deepEqual(result('empty').rows,[]);
  assert.deepEqual(result('empty').columns,result('prefix-mark').columns);
  assert.equal(new Set([...successes,...refusals].map(c=>c.name)).size,14);
});
test('row watermark fixtures are registered for normal and bounded packed acceptance',()=>{
  const packed=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const installer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  for(const symbol of ['rowWatermarkSourceSuccesses','rowWatermarkSourceRefusals'])assert.ok(packed.includes('...'+symbol));
  assert.ok(packed.includes('process.env.ACTQL_TEST_ROW_WATERMARK_ONLY'));
  assert.ok(installer.includes("['scripts/fixtures/row-watermark-source-input.mjs', 'row-watermark-source-input.mjs']"));
  assert.ok(installer.includes("if (process.argv.includes('--row-watermark-only')) return;"));
});

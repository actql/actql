import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']'
  :value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}'
    :JSON.stringify(value);
const hash=text=>'sha256:'+createHash('sha256').update(text).digest('hex');
const before=read('scripts/fixtures/quantize-source/predecessor.json');

test('explicit QUANTIZE source rules retain the complete preceding grammar and all existing machine shapes',()=>{
  assert.equal(before.grammar_manifest_cid,'sha256:3abf093320bb0d121bc40361af879d001bf3f282d7a153e502588374f3302c2c');
  const current=read('scripts/fixtures/decimal-division-source/predecessor.json');
  for(const grammar of [before,current]){
    const {grammar_manifest_cid,...body}=grammar;assert.equal(hash(canonical(body)),grammar_manifest_cid);
  }
  assert.deepEqual({...current,grammar_manifest_cid:before.grammar_manifest_cid,query_text_rules_sha256:before.query_text_rules_sha256},before);
  assert.notEqual(current.grammar_manifest_cid,before.grammar_manifest_cid);
});

test('explicit QUANTIZE retains complete independent existing-operation preimages',()=>{
  const records=read('scripts/fixtures/quantize-source/expressions.json');
  assert.equal(records.length,5);
  for(const record of records){
    assert.equal(canonical(record.value),record.preimage);
    assert.equal(hash(record.preimage),record.cid);
    assert.deepEqual(Object.keys(record.value),['quantize']);
    assert.deepEqual(Object.keys(record.value.quantize).sort(),['precision','rounding','scale','value']);
    assert.equal(Number.isInteger(record.value.quantize.precision),true);
    assert.equal(Number.isInteger(record.value.quantize.scale),true);
  }
  // Later query-time operations extended both current expression embeddings.
  // Keep this explicit-quantize oracle bound to its complete retained bodies.
  const history=read('scripts/fixtures/query-time-source/predecessor.json');
  const contracts=Object.fromEntries(history.contracts.map(record=>[record.id,record]));
  assert.equal(before.expression_contract_cid,contracts.expression_contract.cid);
  assert.equal(hash(canonical(contracts.expression_contract.body)),before.expression_contract_cid);
  const program=contracts.executable_plan.body.properties.execution_material.properties.program;
  assert.equal(hash(canonical(program)),before.source_grammar_cid);
});

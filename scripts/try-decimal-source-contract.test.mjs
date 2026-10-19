import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']'
  :value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}'
    :JSON.stringify(value);
const hash=text=>'sha256:'+createHash('sha256').update(text).digest('hex');
const before=read('scripts/fixtures/try-decimal-source/predecessor.json');

test('explicit TRY_DECIMAL source rules retain the complete preceding grammar and all existing machine shapes',()=>{
  assert.equal(before.grammar_manifest_cid,'sha256:32d4f59d843f3a00bb84256816a1be2f11fa58c37387619ca14a8d4ab6064ba3');
  const current=read('spec/manifests/actql-grammar-0.1.json');
  for(const grammar of [before,current]){
    const {grammar_manifest_cid,...body}=grammar;assert.equal(hash(canonical(body)),grammar_manifest_cid);
  }
  assert.deepEqual({...current,grammar_manifest_cid:before.grammar_manifest_cid,query_text_rules_sha256:before.query_text_rules_sha256},before);
  assert.notEqual(current.grammar_manifest_cid,before.grammar_manifest_cid);
  assert.equal(current.query_text_rules_sha256,hash(readFileSync('docs/spec/query-text.md')).slice(7));
});

test('explicit TRY_DECIMAL retains complete independent existing-operation preimages',()=>{
  const records=read('scripts/fixtures/try-decimal-source/expressions.json');
  assert.equal(records.length,2);
  for(const record of records){
    assert.equal(canonical(record.value),record.preimage);
    assert.equal(hash(record.preimage),record.cid);
    assert.deepEqual(Object.keys(record.value),['try_decimal']);
    assert.deepEqual(Object.keys(record.value.try_decimal).sort(),['precision','scale','value']);
    assert.equal(Number.isInteger(record.value.try_decimal.precision),true);
    assert.equal(Number.isInteger(record.value.try_decimal.scale),true);
  }
  assert.equal(before.expression_contract_cid,read('spec/manifests/actql-grammar-0.1.json').expression_contract_cid);
  assert.equal(before.source_grammar_cid,read('spec/manifests/actql-grammar-0.1.json').source_grammar_cid);
});

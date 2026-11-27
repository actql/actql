import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
type Grammar = {grammar_manifest_cid: string; query_text_rules_sha256: string;
  expression_contract_cid: string; source_grammar_cid: string};
type Successor = {query_rules: string; contracts: {id: string; body: Grammar}[]};
type Preimage = {value: {decimal_divide: {precision: number; scale: number}}; preimage: string; cid: string};
const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
const canonical=(value: unknown): string=>Array.isArray(value)?'['+value.map(canonical).join(',')+']'
  :value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical((value as Record<string, unknown>)[key])).join(',')+'}'
    :JSON.stringify(value);
const hash=(text: string)=>'sha256:'+createHash('sha256').update(text).digest('hex');
const before=read<Grammar>('scripts/fixtures/decimal-division-source/predecessor.json');
const successor=read<Successor>('scripts/fixtures/query-time-source/predecessor.json');
const grammarRecord = successor.contracts.find(item => item.id === 'grammar_manifest');
assert.ok(grammarRecord);
const grammarBeforeQueryTime = grammarRecord.body;

test('explicit DECIMAL_DIVIDE source rules retain the complete preceding grammar and all existing machine shapes',()=>{
  assert.equal(before.grammar_manifest_cid,'sha256:3364a6382a8a3dd3a8ccc3c50fb38fd9c9ac706fec74b4e0f1b438a68dc739f9');
  const current=grammarBeforeQueryTime;
  for(const grammar of [before,current]){
    const {grammar_manifest_cid,...body}=grammar;assert.equal(hash(canonical(body)),grammar_manifest_cid);
  }
  assert.deepEqual({...current,grammar_manifest_cid:before.grammar_manifest_cid,query_text_rules_sha256:before.query_text_rules_sha256},before);
  assert.notEqual(current.grammar_manifest_cid,before.grammar_manifest_cid);
  assert.equal(current.query_text_rules_sha256,hash(successor.query_rules).slice(7));
});

test('explicit DECIMAL_DIVIDE retains complete independent existing-operation preimages',()=>{
  const records=read<Preimage[]>('scripts/fixtures/decimal-division-source/expressions.json');
  assert.equal(records.length,5);
  for(const record of records){
    assert.equal(canonical(record.value),record.preimage);
    assert.equal(hash(record.preimage),record.cid);
    assert.deepEqual(Object.keys(record.value),['decimal_divide']);
    assert.deepEqual(Object.keys(record.value.decimal_divide).sort(),['left','precision','right','rounding','scale']);
    assert.equal(Number.isInteger(record.value.decimal_divide.precision),true);
    assert.equal(Number.isInteger(record.value.decimal_divide.scale),true);
  }
  assert.equal(before.expression_contract_cid,grammarBeforeQueryTime.expression_contract_cid);
  assert.equal(before.source_grammar_cid,grammarBeforeQueryTime.source_grammar_cid);
});

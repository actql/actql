import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const vector=JSON.parse(readFileSync('scripts/fixtures/initial-from-join/independent-vector.json'));
const canonical=value=>Array.isArray(value)?`[${value.map(canonical).join(',')}]`:
  value!==null&&typeof value==='object'?`{${Object.keys(value).sort().map(key=>`${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`:JSON.stringify(value);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const seal=manifest=>{const {grammar_manifest_cid,...body}=manifest;return ['sha256:'+sha(canonical(body)),grammar_manifest_cid];};
test('initial FROM/JOIN grammar identity is independently bound without resealing history',()=>{
  assert.deepEqual(vector.before,JSON.parse(execFileSync('git',['show',`${vector.parent_source}:spec/manifests/actql-grammar-0.1.json`])));
  for(const value of [vector.before,vector.after]){const [computed,pin]=seal(value);assert.equal(computed,pin);}
  assert.equal(vector.after.query_text_grammar_sha256,sha(readFileSync('spec/grammar/actql-query-0.1.ebnf')));
  assert.equal(vector.after.query_text_rules_sha256,sha(readFileSync('docs/spec/query-text.md')));
  assert.deepEqual(vector.after,JSON.parse(readFileSync('spec/manifests/actql-grammar-0.1.json')));
  assert.notEqual(vector.before.grammar_manifest_cid,vector.after.grammar_manifest_cid);
  for(const key of Object.keys(vector.before))if(!['query_text_grammar_sha256','query_text_rules_sha256','grammar_manifest_cid'].includes(key))assert.deepEqual(vector.after[key],vector.before[key],key);
});
test('only the two existing initial FROM productions gain their existing JOIN repetition',()=>{
  let before=execFileSync('git',['show',`${vector.parent_source}:spec/grammar/actql-query-0.1.ebnf`],{encoding:'utf8'});
  for(const production of ['cte_pipe      =','pipe_query    ='])before=before.replace(`${production} "FROM", carrier_source, { "|>",`,`${production} "FROM", carrier_source, { join }, { "|>",`);
  assert.equal(readFileSync('spec/grammar/actql-query-0.1.ebnf','utf8'),before);
});
test('independent initial JOIN oracle retains NULL duplicate rows and public field order',()=>{
  const rows=vector.left_rows.flatMap(left=>vector.right_rows.filter(right=>left.id===right.id).map(right=>({id:left.id,amount:left.amount,tag:right.tag})));
  rows.sort((a,b)=>a.amount===b.amount?(a.tag<b.tag?-1:a.tag>b.tag?1:0):a.amount===null?-1:b.amount===null?1:a.amount-b.amount);
  assert.deepEqual(rows,vector.expected_rows);assert.equal(rows.length,4);
  for(const row of rows)assert.deepEqual(Object.keys(row),vector.expected_fields.map(field=>field.name));
  assert.deepEqual(vector.expected_fields,[{name:'id',type:'number',nullable:false},{name:'amount',type:'number',nullable:true},{name:'tag',type:'string',nullable:false}]);
});

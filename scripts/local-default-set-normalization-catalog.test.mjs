import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const prefix='actql-effect-free-local-bounded-relation-completion-free-';
const load=s=>JSON.parse(readFileSync(new URL('../spec/contracts/'+prefix+s,import.meta.url),'utf8'));
const hash=s=>'sha256:'+createHash('sha256').update(s,'utf8').digest('hex');
// Complete literal expectations from accepted SET and Default bodies plus the
// explicit original-binding capability delta; never from Common execution.
const expected={
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"append_order\":\"original-left-then-right\",\"audit_work_limit\":10000,\"binary_set_roots\":\"all-original-Values-roots-audited-under-same-work-limit; maximum-one-selected-Source\",\"binary_set_rows\":\"existing-complete-typed-row-admission-and-comparison-owners\",\"binary_set_scope\":\"original-same-pipeline-step-both-targets-schemas-and-typed-alignment\",\"binary_set_stage_scope\":\"complete-original-units; prepass-and-every-unit-step-alignment-visit-charged-to-same-audit-work-limit\",\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"append\",\"derive\",\"distinct\",\"except\",\"filter\",\"group\",\"intersect\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":10000,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"original-checked-owner-audit\",\"set_duplicates\":[\"all\",\"distinct\"],\"set_order\":\"original-earliest-left-occurrences-no-new-total-order\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45",
  "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:09ac554868a1d4a15b7ea357702b7da4b633024d38a2537fa6aea8f560866b81"
};
const sorted={
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"append_order\":\"original-left-then-right\",\"audit_work_limit\":10000,\"binary_set_roots\":\"all-original-Values-roots-audited-under-same-work-limit; maximum-one-selected-Source\",\"binary_set_rows\":\"existing-complete-typed-row-admission-and-comparison-owners\",\"binary_set_scope\":\"original-same-pipeline-step-both-targets-schemas-and-typed-alignment\",\"binary_set_stage_scope\":\"complete-original-units; prepass-and-every-unit-step-alignment-visit-charged-to-same-audit-work-limit\",\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"append\",\"derive\",\"distinct\",\"except\",\"filter\",\"group\",\"intersect\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":10000,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"original-checked-owner-audit\",\"set_duplicates\":[\"all\",\"distinct\"],\"set_order\":\"original-earliest-left-occurrences-no-new-total-order\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45",
  "journal_preimage": "{\"entries\":[{\"authored\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"canonical\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"},{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"key\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"path\":\"$.stages[0].steps[6].sort\",\"rule\":\"sort.candidate_key_completion\"}],\"rule_catalog_cid\":\"sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:13721f13c13d6ec3ce58e32ccb9e9bfce1cdf8dce311cddff9259b12c1cbcbef"
};
test('combined original SET and Default capability has complete independent identities',()=>{
  for(const value of [expected,sorted]){
    assert.equal(hash(value.catalog_preimage),value.catalog_cid);
    assert.equal(hash(value.journal_preimage),value.journal_cid);
  }
  assert.deepEqual(load('fixture.json'),expected);
  assert.deepEqual(load('default-set-sort-fixture.json'),sorted);
  const body=JSON.parse(expected.catalog_preimage);
  assert.deepEqual(load('catalog.json'),body);
  const schema=load('catalog.schema.json');
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(schema.properties.applicability,{const:body.applicability});
  assert.deepEqual(schema.properties.rules,{const:body.rules});
  assert.deepEqual(JSON.parse(expected.journal_preimage).entries,[]);
  assert.equal(body.rules.length,1);
  assert.equal(body.rules[0].id,'sort.candidate_key_completion');
  assert.equal(JSON.parse(sorted.journal_preimage).entries[0].path,'$.stages[0].steps[6].sort');
  assert.notEqual(sorted.journal_cid,expected.journal_cid);
});
test('both complete preceding capabilities remain exact and independently selected',()=>{
  const prior=load('pre-defaulted-set-fixture.json');
  const priorDefault=load('pre-set-default-fixture.json');
  assert.equal(prior.catalog_cid,'sha256:0f0003ec6a1ec4520a7b9615b916d903dafc138e94145e5a57d45a1bf7937f33');
  assert.equal(priorDefault.catalog_cid,'sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d');
  for(const [tag,value]of [['pre-defaulted-set-',prior],['pre-set-default-',priorDefault]]){
    assert.equal(hash(value.catalog_preimage),value.catalog_cid);
    assert.equal(hash(value.journal_preimage),value.journal_cid);
    assert.deepEqual(load(tag+'catalog.json'),JSON.parse(value.catalog_preimage));
  }
  const body=JSON.parse(expected.catalog_preimage),a=body.applicability;
  delete a.parameter_origins;delete a.parameter_default_correspondence;
  a.parameter_declarations='none-or-all-supplied-original-values';
  a.take_parameter_resolution='original-same-pipeline-step-SafeInteger-supplied-owner';
  assert.deepEqual(body,JSON.parse(prior.catalog_preimage));
  const schema=load('catalog.schema.json');schema.properties.applicability={const:body.applicability};
  assert.deepEqual(schema,load('pre-defaulted-set-catalog.schema.json'));
  const noSet=JSON.parse(expected.catalog_preimage);
  for(const key of ['binary_set_scope','binary_set_roots','binary_set_rows','append_order','set_duplicates','set_order','binary_set_stage_scope'])delete noSet.applicability[key];
  noSet.applicability.checked_operations=noSet.applicability.checked_operations.filter(x=>!['append','except','intersect'].includes(x));
  noSet.applicability.max_stages=3;
  assert.deepEqual(noSet,JSON.parse(priorDefault.catalog_preimage));
  const issuer=readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt',import.meta.url),'utf8');
  for(const value of [expected,prior,priorDefault])assert(issuer.includes('"'+value.catalog_cid+'"'));
});

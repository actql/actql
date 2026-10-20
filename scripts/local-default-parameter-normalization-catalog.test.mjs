import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const prefix='actql-effect-free-local-bounded-relation-completion-free-';
const load=s=>JSON.parse(readFileSync(new URL('../spec/contracts/'+prefix+s,import.meta.url),'utf8'));
const hash=s=>'sha256:'+createHash('sha256').update(s,'utf8').digest('hex');
const expected={
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"distinct\",\"filter\",\"group\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"original-checked-owner-audit\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d",
  "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:44e145d70edf8d9e3c00055d5b5dce68a59daa2ab4ca148b48c28ae330533b69"
};
const sorted={
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"distinct\",\"filter\",\"group\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"original-checked-owner-audit\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d",
  "journal_preimage": "{\"entries\":[{\"authored\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"canonical\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"},{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"key\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"path\":\"$.stages[0].steps[3].sort\",\"rule\":\"sort.candidate_key_completion\"}],\"rule_catalog_cid\":\"sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:872840bf3ca6315ca1826a3ab17a78bbc14a5ee2d4d18aa4db56626460c7032a"
};
test('original Default capability has complete independent catalog and empty source-journal identities',()=>{
  assert.equal(hash(expected.catalog_preimage),expected.catalog_cid);
  assert.equal(hash(expected.journal_preimage),expected.journal_cid);
  assert.deepEqual(load('pre-set-default-fixture.json'),expected);
  const body=JSON.parse(expected.catalog_preimage);
  assert.deepEqual(load('pre-set-default-catalog.json'),body);
  const schema=load('pre-set-default-catalog.schema.json');
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(schema.properties.applicability,{const:body.applicability});
  assert.deepEqual(schema.properties.rules,{const:body.rules});
  assert.deepEqual(JSON.parse(expected.journal_preimage).entries,[]);
  assert.equal(body.version,'actql-normalization-rule-catalog/0.1');
  assert.equal(body.rules.length,1);
  assert.equal(body.rules[0].id,'sort.candidate_key_completion');
  const issuer=readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt',import.meta.url),'utf8');
  assert(issuer.includes('"'+expected.catalog_cid+'"'));
});
test('only original binding capability changes the complete preceding catalog',()=>{
  const prior=load('pre-default-fixture.json');
  assert.equal(hash(prior.catalog_preimage),prior.catalog_cid);
  assert.equal(hash(prior.journal_preimage),prior.journal_cid);
  assert.equal(prior.catalog_cid,'sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8');
  assert.deepEqual(load('pre-default-catalog.json'),JSON.parse(prior.catalog_preimage));
  const body=JSON.parse(expected.catalog_preimage);
  assert.deepEqual(body.applicability.parameter_origins,['supplied','default']);
  assert.equal(body.applicability.parameter_default_correspondence,'same-original-BoundValues-declaration-name-type-and-checked-default-value');
  delete body.applicability.parameter_origins;
  delete body.applicability.parameter_default_correspondence;
  body.applicability.parameter_declarations='none-or-all-supplied-original-values';
  body.applicability.take_parameter_resolution='original-same-pipeline-step-SafeInteger-supplied-owner';
  assert.deepEqual(body,JSON.parse(prior.catalog_preimage));
  const schema=load('pre-set-default-catalog.schema.json');
  schema.properties.applicability={const:JSON.parse(prior.catalog_preimage).applicability};
  assert.deepEqual(schema,load('pre-default-catalog.schema.json'));
  assert.notEqual(expected.catalog_cid,prior.catalog_cid);
});
test('Default never replaces an actual original Sort completion with empty entries',()=>{
  assert.equal(hash(sorted.catalog_preimage),sorted.catalog_cid);
  assert.equal(hash(sorted.journal_preimage),sorted.journal_cid);
  assert.deepEqual(load('default-sort-fixture.json'),sorted);
  const wire=JSON.parse(sorted.journal_preimage);
  assert.equal(wire.entries.length,1);
  assert.equal(wire.entries[0].path,'$.stages[0].steps[3].sort');
  assert.equal(wire.entries[0].rule,'sort.candidate_key_completion');
  assert.notEqual(sorted.journal_cid,expected.journal_cid);
});

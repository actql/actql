import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Complete independent accepted predecessor and intended extension preimages.
// These are not captured issuer output or regenerated runtime expectations.
const expected = {
  "predecessor": {
    "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"append_order\":\"original-left-then-right\",\"audit_work_limit\":10000,\"binary_set_roots\":\"all-original-Values-roots-audited-under-same-work-limit; maximum-one-selected-Source\",\"binary_set_rows\":\"existing-complete-typed-row-admission-and-comparison-owners\",\"binary_set_scope\":\"original-same-pipeline-step-both-targets-schemas-and-typed-alignment\",\"binary_set_stage_scope\":\"complete-original-units; prepass-and-every-unit-step-alignment-visit-charged-to-same-audit-work-limit\",\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"append\",\"derive\",\"distinct\",\"except\",\"filter\",\"group\",\"intersect\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":10000,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"original-checked-owner-audit\",\"set_duplicates\":[\"all\",\"distinct\"],\"set_order\":\"original-earliest-left-occurrences-no-new-total-order\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:09ac554868a1d4a15b7ea357702b7da4b633024d38a2537fa6aea8f560866b81"
  },
  "projection": {
    "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"append_order\":\"original-left-then-right\",\"audit_work_limit\":10000,\"binary_set_roots\":\"all-original-Values-roots-audited-under-same-work-limit; maximum-one-selected-Source\",\"binary_set_rows\":\"existing-complete-typed-row-admission-and-comparison-owners\",\"binary_set_scope\":\"original-same-pipeline-step-both-targets-schemas-and-typed-alignment\",\"binary_set_stage_scope\":\"complete-original-units; prepass-and-every-unit-step-alignment-visit-charged-to-same-audit-work-limit\",\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"append\",\"derive\",\"distinct\",\"drop\",\"except\",\"filter\",\"group\",\"intersect\",\"rename\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":10000,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-original-supplied-or-declared-default-values\",\"parameter_default_correspondence\":\"same-original-BoundValues-declaration-name-type-and-checked-default-value\",\"parameter_origins\":[\"supplied\",\"default\"],\"projection_expansion\":\"original-same-pipeline-step-CheckedOperation-complete-schema-and-owned-projection; actual-authored-path-and-semantic-journal-entry\",\"proof\":\"original-checked-owner-audit\",\"set_duplicates\":[\"all\",\"distinct\"],\"set_order\":\"original-earliest-left-occurrences-no-new-total-order\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-bound-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored drop body\",\"canonical\":\"canonical JSON of existing REL.select params from the original checked projection in canonical input-name order\",\"id\":\"relation.drop_projection\",\"path\":\"original decoded Program drop body\",\"requires\":\"original same-pipeline same-step CheckedOperation and its complete checked input schema; no caller mapping or replacement declaration\"},{\"authored\":\"canonical JSON of the original authored rename body\",\"canonical\":\"canonical JSON of existing REL.select params from the original checked projection in canonical input-name order\",\"id\":\"relation.rename_projection\",\"path\":\"original decoded Program rename body\",\"requires\":\"original same-pipeline same-step CheckedOperation and its complete checked input schema; no caller mapping or replacement declaration\"},{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:eaaf8fc464b5079e782f5dbcbdd7ef0c8b2934ef0a01c7e465907f8c6f850923",
    "journal_preimage": "{\"entries\":[{\"authored\":\"[\\\"id\\\",\\\"other\\\"]\",\"canonical\":\"{\\\"columns\\\":[\\\"value\\\"]}\",\"path\":\"$.stages[0].steps[2].drop\",\"rule\":\"relation.drop_projection\"}],\"rule_catalog_cid\":\"sha256:eaaf8fc464b5079e782f5dbcbdd7ef0c8b2934ef0a01c7e465907f8c6f850923\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:2da1ae14420b3f98d3b676f8d403a9bb0ecb5576608720ab3832ad7b32b7b434"
  }
};
const prefix = 'actql-effect-free-local-bounded-relation-completion-free-';
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + prefix + name, import.meta.url), 'utf8'));
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';

test('projection catalogue retains complete predecessor and independent semantic identities', () => {
  for (const item of Object.values(expected)) {
    assert.equal(cid(item.catalog_preimage), item.catalog_cid);
    assert.equal(cid(item.journal_preimage), item.journal_cid);
    assert.equal(canonical(JSON.parse(item.catalog_preimage)), item.catalog_preimage);
    assert.equal(canonical(JSON.parse(item.journal_preimage)), item.journal_preimage);
  }
  assert.deepEqual(load('pre-projection-fixture.json'), expected.predecessor);
  assert.deepEqual(load('pre-projection-catalog.json'), JSON.parse(expected.predecessor.catalog_preimage));
  assert.deepEqual(load('fixture.json'), expected.projection);
  assert.deepEqual(load('catalog.json'), JSON.parse(expected.projection.catalog_preimage));
});

test('one closed projection extension preserves the whole Default and SET capability', () => {
  const body = JSON.parse(expected.projection.catalog_preimage);
  assert.deepEqual(body.rules.map(rule => rule.id), ['relation.drop_projection', 'relation.rename_projection', 'sort.candidate_key_completion']);
  assert.deepEqual(body.applicability.parameter_origins, ['supplied', 'default']);
  assert.deepEqual(body.applicability.normalization_journal_limits, {max_wire_bytes: 1024, max_nodes: 32, max_depth: 8});
  body.applicability.checked_operations = body.applicability.checked_operations.filter(tag => tag !== 'rename' && tag !== 'drop');
  delete body.applicability.projection_expansion;
  body.rules = body.rules.filter(rule => !rule.id.startsWith('relation.'));
  assert.deepEqual(body, JSON.parse(expected.predecessor.catalog_preimage));
  assert.notEqual(expected.projection.catalog_cid, expected.predecessor.catalog_cid);
  const schema = load('catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(body).toSorted());
  schema.properties.applicability = {const: body.applicability};
  schema.properties.rules = {const: body.rules};
  assert.deepEqual(schema, load('pre-projection-catalog.schema.json'));
});

test('actual projection occurrence has an explicit original path and nonempty semantic entry', () => {
  const journal = JSON.parse(expected.projection.journal_preimage);
  assert.equal(journal.rule_catalog_cid, expected.projection.catalog_cid);
  assert.deepEqual(journal.entries, [{authored: '["id","other"]', canonical: '{"columns":["value"]}', path: '$.stages[0].steps[2].drop', rule: 'relation.drop_projection'}]);
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + expected.projection.catalog_cid + '"'));
  const empty = {...journal, entries: []};
  assert.notEqual(cid(canonical(empty)), expected.projection.journal_cid);
  assert.notEqual(cid(canonical({...journal, entries: [{...journal.entries[0], rule: 'sort.candidate_key_completion'}]})), expected.projection.journal_cid);
});

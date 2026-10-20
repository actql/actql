import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Full independent preimages retained from the preceding catalog and the selected extension.
const expected = {
  "predecessor": {
    "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"group\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:36ee9950b74a43a5403eda628c3d5cc1bc147283e6bca6710b1c079181467d09"
  },
  "current": {
    "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"group\",\"select\",\"take\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-supplied-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:2e87dfc12f59f5755bc3a41b61fc0a9b5b5cc0c0f7861128924c852c13ce7d03",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:2e87dfc12f59f5755bc3a41b61fc0a9b5b5cc0c0f7861128924c852c13ce7d03\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:84b650b308e19adb41fc508e306e85c65a6db547711f9ac9303f536814cdca95"
  }
};
expected.ordered = {
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"group\",\"select\",\"sort\",\"take\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"sort_appended_identity_terms\":\"requires-semantic-journal-not-completion-free\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-supplied-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:aa08e331a77f389359583e74ce6d7c801ad76a21d13520e55571f71a237ff24e",
  "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:aa08e331a77f389359583e74ce6d7c801ad76a21d13520e55571f71a237ff24e\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:288f55dc38776acf2f073c2ddbaaaa563dd95ad717157dc845274ad0c3ad86de"
};
const prefix = 'actql-effect-free-local-bounded-relation-completion-free-';
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('bounded relation catalog and journal match the complete independent identities', () => {
  for (const value of Object.values(expected)) {
    assert.equal(cid(value.catalog_preimage), value.catalog_cid);
    assert.equal(cid(value.journal_preimage), value.journal_cid);
  }
  assert.deepEqual(load(prefix + 'pre-completion-fixture.json'), expected.ordered);
  assert.deepEqual(load(prefix + 'pre-order-fixture.json'), expected.current);
  assert.deepEqual(load(prefix + 'pre-completion-catalog.json'), JSON.parse(expected.ordered.catalog_preimage));
  assert.deepEqual(load(prefix + 'pre-order-catalog.json'), JSON.parse(expected.current.catalog_preimage));
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + expected.current.catalog_cid + '"'));
  assert(issuer.includes('"' + expected.ordered.catalog_cid + '"'));
});

test('Take adds only bounded original role resolution to the preceding full Group body', () => {
  const body = JSON.parse(expected.current.catalog_preimage);
  const schema = load(prefix + 'pre-order-catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(body).toSorted());
  for (const key of ['applicability', 'profile', 'version']) assert.deepEqual(schema.properties[key], {const: body[key]});
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  const a = body.applicability;
  assert.equal(a.take_count_minimum, 1);
  assert.equal(a.take_offset_minimum, 0);
  assert.equal(a.take_maximum, 9007199254740991);
  assert.equal(a.take_parameter_resolution, 'original-same-pipeline-step-SafeInteger-supplied-owner');
  for (const k of ['take_count_minimum','take_offset_minimum','take_maximum','take_parameter_resolution']) delete a[k];
  a.checked_operations = a.checked_operations.filter(x => x !== 'take');
  assert.deepEqual(body, JSON.parse(expected.predecessor.catalog_preimage));
  assert.deepEqual(load('actql-effect-free-local-group-completion-free-fixture.json'), expected.predecessor);
});

test('all six preceding catalogs keep their complete distinct bytes and identities', () => {
  for (const suffix of ['', 'supplied-parameters-', 'explicit-cast-', 'supplied-parameters-explicit-cast-', 'checked-expressions-', 'group-']) {
    const p = 'actql-effect-free-local-' + suffix + 'completion-free-';
    const prior = load(p + 'fixture.json');
    assert.equal(cid(prior.catalog_preimage), prior.catalog_cid);
    assert.equal(cid(prior.journal_preimage), prior.journal_cid);
    assert.deepEqual(load(p + 'catalog.json'), JSON.parse(prior.catalog_preimage));
    assert.notEqual(prior.catalog_cid, expected.current.catalog_cid);
    assert.notEqual(prior.journal_cid, expected.current.journal_cid);
  }
});


test('resolved Sort extends the same bounded relation catalogue without hiding real completion', () => {
  const body = JSON.parse(expected.ordered.catalog_preimage);
  const schema = load(prefix + 'pre-completion-catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(body).toSorted());
  for (const key of ['applicability', 'profile', 'version']) assert.deepEqual(schema.properties[key], {const: body[key]});
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  assert.deepEqual(body.rules, []);
  const a = body.applicability;
  assert.equal(a.sort_empty, 'original-identity-no-new-order');
  assert.equal(a.sort_resolution, 'original-same-pipeline-step-covered-candidate-key-or-existing-total');
  assert.equal(a.sort_appended_identity_terms, 'requires-semantic-journal-not-completion-free');
  for (const name of ['sort_empty', 'sort_resolution', 'sort_appended_identity_terms']) delete a[name];
  a.checked_operations = a.checked_operations.filter(x => x !== 'sort');
  assert.deepEqual(body, JSON.parse(expected.current.catalog_preimage));
  assert.notEqual(expected.ordered.catalog_cid, expected.current.catalog_cid);
  assert.notEqual(expected.ordered.journal_cid, expected.current.journal_cid);
});

const completed = {
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"group\",\"select\",\"sort\",\"take\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-supplied-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57",
  "journal_preimage": "{\"entries\":[{\"authored\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"canonical\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"},{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"key\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"path\":\"$.stages[0].steps[2].sort\",\"rule\":\"sort.candidate_key_completion\"}],\"rule_catalog_cid\":\"sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:e4285d4c0c7eab9889e52a5d3774575846c7dd2ddf221f2e41ff8a95786f0847"
};

test('actual Sort completion uses its frozen rule and complete independent journal preimage', () => {
  assert.equal(cid(completed.catalog_preimage), completed.catalog_cid);
  assert.equal(cid(completed.journal_preimage), completed.journal_cid);
  assert.deepEqual(load(prefix + 'pre-distinct-fixture.json'), completed);
  const body = JSON.parse(completed.catalog_preimage);
  assert.deepEqual(load(prefix + 'pre-distinct-catalog.json'), body);
  const schema = load(prefix + 'pre-distinct-catalog.schema.json');
  assert.deepEqual(schema.properties.rules, {const: body.rules});
  assert.equal(schema.additionalProperties, false);
  assert.equal(body.rules.length, 1);
  assert.equal(body.rules[0].id, 'sort.candidate_key_completion');
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + completed.catalog_cid + '"'));
  const journal = JSON.parse(completed.journal_preimage);
  assert.equal(journal.rule_catalog_cid, completed.catalog_cid);
  assert.equal(journal.entries.length, 1);
  assert.equal(journal.entries[0].rule, body.rules[0].id);
  assert.equal(journal.entries[0].path, '$.stages[0].steps[2].sort');
  assert.deepEqual(JSON.parse(journal.entries[0].canonical), [
    {dir: 'asc', field: 'n', nulls: 'last'},
    {dir: 'asc', field: 'key', nulls: 'last'},
  ]);
  const prior = JSON.parse(expected.ordered.catalog_preimage);
  body.rules = [];
  delete body.applicability.normalization_journal_limits;
  body.applicability.sort_appended_identity_terms = prior.applicability.sort_appended_identity_terms;
  assert.deepEqual(body, prior);
  assert.notEqual(completed.catalog_cid, expected.ordered.catalog_cid);
});

const distinct = {
  "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"distinct\",\"filter\",\"group\",\"select\",\"sort\",\"take\",\"values\"],\"distinct_input\":\"complete-original-row-and-presence-admission-remains-with-execution\",\"distinct_order\":\"existing-first-occurrence-no-new-total-order\",\"distinct_scope\":\"original-same-pipeline-step-whole-row-or-authored-required-key-projection\",\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"normalization_journal_limits\":{\"max_depth\":8,\"max_nodes\":32,\"max_wire_bytes\":1024},\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"sort_appended_identity_terms\":\"original-owned-semantic-journal-entry\",\"sort_empty\":\"original-identity-no-new-order\",\"sort_resolution\":\"original-same-pipeline-step-covered-candidate-key-or-existing-total\",\"source_selection\":\"explicit\",\"take_count_minimum\":1,\"take_maximum\":9007199254740991,\"take_offset_minimum\":0,\"take_parameter_resolution\":\"original-same-pipeline-step-SafeInteger-supplied-owner\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[{\"authored\":\"canonical JSON of the original authored Sort array\",\"canonical\":\"original authored keys in priority followed by actual missing selected candidate-key fields ascending with nulls last\",\"id\":\"sort.candidate_key_completion\",\"path\":\"original decoded Program Sort body\",\"requires\":\"original same-pipeline same-step SortOrder and selected candidate-key proof with nonzero appended_count\"}],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8",
  "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:ddf6bca88c86504be01ba9c34baa5391d8cea27028475268c24ef2b3fdce0031"
};

test('original DISTINCT extends only the existing bounded catalogue and keeps real Sort entries', () => {
  assert.equal(cid(distinct.catalog_preimage), distinct.catalog_cid);
  assert.equal(cid(distinct.journal_preimage), distinct.journal_cid);
  assert.deepEqual(load(prefix + 'pre-default-fixture.json'), distinct);
  const body = JSON.parse(distinct.catalog_preimage);
  assert.deepEqual(load(prefix + 'pre-default-catalog.json'), body);
  const schema = load(prefix + 'pre-default-catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.applicability, {const: body.applicability});
  assert.deepEqual(schema.properties.rules, {const: body.rules});
  assert.deepEqual(body.rules, JSON.parse(completed.catalog_preimage).rules);
  assert.deepEqual(body.applicability.normalization_journal_limits, {max_depth:8,max_nodes:32,max_wire_bytes:1024});
  assert.equal(body.applicability.distinct_scope, 'original-same-pipeline-step-whole-row-or-authored-required-key-projection');
  assert.equal(body.applicability.distinct_input, 'complete-original-row-and-presence-admission-remains-with-execution');
  assert.equal(body.applicability.distinct_order, 'existing-first-occurrence-no-new-total-order');
  for (const key of ['distinct_scope','distinct_input','distinct_order']) delete body.applicability[key];
  body.applicability.checked_operations = body.applicability.checked_operations.filter(x => x !== 'distinct');
  assert.deepEqual(body, JSON.parse(completed.catalog_preimage));
  const journal = JSON.parse(distinct.journal_preimage);
  assert.deepEqual(journal.entries, []);
  assert.equal(journal.rule_catalog_cid, distinct.catalog_cid);
  assert.notEqual(distinct.catalog_cid, completed.catalog_cid);
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  for (const value of [completed, distinct]) assert(issuer.includes('"' + value.catalog_cid + '"'));
});

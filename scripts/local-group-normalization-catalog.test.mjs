import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Complete independently authored preimages; never derived from the issuer.
const expected = {
  "predecessor": {
    "catalog_preimage": "{\"applicability\":{\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:56a751c1140b78d0f2330ad7ec5c9f4517bdf00bfa2a921758e7af0318f3b48a"
  },
  "current": {
    "catalog_preimage": "{\"applicability\":{\"additional_group_prefix\":\"none\",\"aggregate_functions\":[\"count\",\"count_if\",\"max\",\"min\"],\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"group\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"group_key_selection\":\"authored\",\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:36ee9950b74a43a5403eda628c3d5cc1bc147283e6bca6710b1c079181467d09"
  }
};
const prefix = 'actql-effect-free-local-group-completion-free-';
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('closed Group catalog and journal match complete independent preimages', () => {
  for (const value of Object.values(expected)) {
    assert.equal(cid(value.catalog_preimage), value.catalog_cid);
    assert.equal(cid(value.journal_preimage), value.journal_cid);
  }
  assert.deepEqual(load(prefix + 'fixture.json'), expected.current);
  assert.deepEqual(load(prefix + 'catalog.json'), JSON.parse(expected.current.catalog_preimage));
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + expected.current.catalog_cid + '"'));
});

test('Group applicability adds only the selected checked reductions to the complete predecessor', () => {
  const body = JSON.parse(expected.current.catalog_preimage);
  const schema = load(prefix + 'catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(body).toSorted());
  for (const key of ['applicability', 'profile', 'version']) assert.deepEqual(schema.properties[key], {const: body[key]});
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  const a = body.applicability;
  assert.deepEqual(a.aggregate_functions, ['count', 'count_if', 'max', 'min']);
  assert.equal(a.additional_group_prefix, 'none');
  assert.equal(a.group_key_selection, 'authored');
  delete a.aggregate_functions;
  delete a.additional_group_prefix;
  delete a.group_key_selection;
  a.checked_operations = a.checked_operations.filter(value => value !== 'group');
  assert.deepEqual(body, JSON.parse(expected.predecessor.catalog_preimage));
  assert.deepEqual(load('actql-effect-free-local-checked-expressions-completion-free-fixture.json'), expected.predecessor);
});

test('all five preceding catalogs retain their distinct complete identities', () => {
  for (const suffix of ['', 'supplied-parameters-', 'explicit-cast-', 'supplied-parameters-explicit-cast-', 'checked-expressions-']) {
    const p = 'actql-effect-free-local-' + suffix + 'completion-free-';
    const prior = load(p + 'fixture.json');
    assert.equal(cid(prior.catalog_preimage), prior.catalog_cid);
    assert.equal(cid(prior.journal_preimage), prior.journal_cid);
    assert.deepEqual(load(p + 'catalog.json'), JSON.parse(prior.catalog_preimage));
    assert.notEqual(prior.catalog_cid, expected.current.catalog_cid);
    assert.notEqual(prior.journal_cid, expected.current.journal_cid);
  }
});

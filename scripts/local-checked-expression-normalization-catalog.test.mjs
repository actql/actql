import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Complete independent authoring preimages, not expectations from an issuer.
const expected = {
  "catalog_preimage": "{\"applicability\":{\"audit_work_limit\":10000,\"checked_auxiliary_nodes\":[\"membership_list\"],\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"abs\",\"acos\",\"acosh\",\"add\",\"and\",\"array\",\"asin\",\"asinh\",\"atan\",\"atan2\",\"atanh\",\"between\",\"byte_length\",\"case\",\"cast\",\"cbrt\",\"chr\",\"coalesce\",\"concat\",\"concat_strict\",\"contains\",\"cos\",\"cosh\",\"date_add\",\"date_diff\",\"date_trunc\",\"decimal_divide\",\"divide\",\"empty_array\",\"ends_with\",\"eq\",\"exp\",\"field\",\"floor\",\"greatest\",\"gt\",\"gte\",\"if\",\"in\",\"instr\",\"is_distinct_from\",\"is_false\",\"is_null\",\"is_true\",\"is_unknown\",\"least\",\"left\",\"len\",\"literal\",\"ln\",\"log\",\"log10\",\"lower\",\"lpad\",\"lt\",\"lte\",\"ltrim\",\"modulo\",\"multiply\",\"negate\",\"neq\",\"not\",\"not_in\",\"not_null\",\"nullif\",\"object\",\"or\",\"pow\",\"property\",\"quantize\",\"repeat\",\"replace\",\"reverse\",\"right\",\"round\",\"rpad\",\"rtrim\",\"safe_add\",\"safe_divide\",\"safe_multiply\",\"safe_negate\",\"safe_subtract\",\"sign\",\"sin\",\"sinh\",\"split\",\"sqrt\",\"starts_with\",\"strpos\",\"subscript\",\"substring\",\"subtract\",\"tan\",\"tanh\",\"timestamp_add\",\"timestamp_sub\",\"translate\",\"trim\",\"trunc\",\"try_decimal\",\"try_number\",\"typed_literal\",\"unicode\",\"upper\",\"utf8_truncate\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none-or-all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
  "catalog_cid": "sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74",
  "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74\",\"version\":\"actql-normalization-journal/0.1\"}",
  "journal_cid": "sha256:56a751c1140b78d0f2330ad7ec5c9f4517bdf00bfa2a921758e7af0318f3b48a"
};
const prefix = 'actql-effect-free-local-checked-expressions-completion-free-';
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('one closed checked-expression catalog binds complete independent identities', () => {
  assert.equal(cid(expected.catalog_preimage), expected.catalog_cid);
  assert.equal(cid(expected.journal_preimage), expected.journal_cid);
  assert.deepEqual(load(prefix + 'fixture.json'), expected);
  assert.deepEqual(load(prefix + 'catalog.json'), JSON.parse(expected.catalog_preimage));
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + expected.catalog_cid + '"'));
});

test('closed schema admits no unknown expression or semantic completion', () => {
  const body = JSON.parse(expected.catalog_preimage);
  const schema = load(prefix + 'catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(body).toSorted());
  for (const key of ['applicability', 'profile', 'version']) assert.deepEqual(schema.properties[key], {const: body[key]});
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  const nodes = body.applicability.expression_nodes;
  assert.deepEqual(nodes, [...new Set(nodes)].toSorted());
  for (const tag of ['template', 'current_timestamp', 'vector_score', 'vector_concat', 'unknown']) assert(!nodes.includes(tag));
  assert.deepEqual(body.applicability.checked_auxiliary_nodes, ['membership_list']);
  assert.equal(body.applicability.parameter_declarations, 'none-or-all-supplied-original-values');
});

test('each preceding catalog remains a complete distinct subset with original bytes', () => {
  const current = JSON.parse(expected.catalog_preimage);
  for (const suffix of ['', 'supplied-parameters-', 'explicit-cast-', 'supplied-parameters-explicit-cast-']) {
    const prior = load('actql-effect-free-local-' + suffix + 'completion-free-fixture.json');
    const body = JSON.parse(prior.catalog_preimage);
    assert.equal(cid(prior.catalog_preimage), prior.catalog_cid);
    assert.equal(cid(prior.journal_preimage), prior.journal_cid);
    assert.notEqual(prior.catalog_cid, expected.catalog_cid);
    assert.notEqual(prior.journal_cid, expected.journal_cid);
    assert.deepEqual(load('actql-effect-free-local-' + suffix + 'completion-free-catalog.json'), body);
    for (const tag of body.applicability.expression_nodes) assert(current.applicability.expression_nodes.includes(tag));
    for (const key of ['audit_work_limit', 'checked_operations', 'effect_kind', 'max_source_inputs', 'max_stages', 'proof', 'source_selection']) assert.deepEqual(current.applicability[key], body.applicability[key]);
  }
});

// Bind the independent closed artifact to the audited source dispatch, rather
// than accepting a catalog whose added tags the inventory never traverses.
test('original audit dispatch exactly matches the independently frozen closed set', () => {
  const source = readFileSync(new URL('../src/program_check/local_completion_free_inventory.mbt', import.meta.url), 'utf8');
  const helper = source.split('fn local_completion_free_checked_expression(tag : String) -> Bool {')[1]?.split('\n///|')[0];
  assert(helper);
  const added = [...helper.matchAll(/"([a-z0-9_]+)"/gu)].map(match => match[1]);
  const old = JSON.parse(load('actql-effect-free-local-supplied-parameters-explicit-cast-completion-free-fixture.json').catalog_preimage);
  assert.deepEqual([...new Set([...old.applicability.expression_nodes, ...added])].toSorted(), JSON.parse(expected.catalog_preimage).applicability.expression_nodes);
  assert(source.includes('ImplicitNull => return CompletionObserved'));
  assert(source.includes('Expression("template", _) => return CompletionObserved'));
  assert(source.includes('MembershipList(_) => checked_expressions = true'));
});

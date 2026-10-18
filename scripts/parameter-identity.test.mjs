import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {verifyIdentity} from './check-canonical-json.mjs';
import { generateIdentityTests, projectedBody, project, identityDefinitions, valuesSchema, checkIdentitySchema } from './parameter-identity.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = () => read('portability/corpus/parameter-identities.json');

test('fixed Parameter identities are reproducible and do not silently follow changed expectations', () => {
  assert.equal(generateIdentityTests(corpus()), generateIdentityTests(structuredClone(corpus())));
  for (const change of [
    c => { c.cases[0].expected_cid = 'sha256:' + '0'.repeat(64); },
    c => { c.cases[0].expected_canonical_json += ' '; },
    c => { delete c.cases[0].expected_canonical_json; },
    c => { delete c.cases[0].expected_cid; },
    c => { c.cases.push(c.cases[0]); },
    c => { c.cases[0].supplied.s = 'changed'; },
  ]) {
    const c = corpus(); change(c); assert.throws(() => generateIdentityTests(c));
  }
});

test('projection separates special values from business markers and excludes provenance', () => {
  const duration = { type: 'string', format: 'duration' };
  const baseline = project(duration, '1s');
  for (const text of ['01S', '1000ms', '01000MS']) assert.deepEqual(project(duration, text), baseline);
  assert.notDeepEqual(project(duration, '1001ms'), baseline);
  for (const text of ['0ms', '1.5s', '-1s', '1e3ms', '9007199254740992ms', '1s\n']) assert.throws(() => project(duration, text));
  const ordinary = project({ type: 'object', fields: { $actql_value: { type: 'string' } } }, { $actql_value: 'duration' });
  assert.deepEqual(ordinary, { $actql_value: ['object', [['$actql_value', 'duration']]] });
  assert.deepEqual(projectedBody({ n: { type: 'number', default: 2, integer: true, meta: { note: 'x' } } }, {}),
    projectedBody({ n: { type: 'number' } }, { n: 2 }));
  assert.throws(() => project({ type: 'decimal', precision: 1, scale: 2 }, '0.01'));
  assert.throws(() => project({ type: 'decimal', precision: 2, scale: 1 }, '-0.0'));
  assert.throws(() => project({ type: 'decimal', precision: 2, scale: 0 }, '100'));
});

test('identity schema closes tag tuples and preserves recursive references and decimal bounds', () => {
  const definitions = identityDefinitions();
  const branches = definitions.projected_value.oneOf;
  const tag = kind => branches.find(b => b.properties?.$actql_value?.prefixItems[0].const === kind);
  for (const kind of ['decimal', 'duration', 'object']) {
    const b = tag(kind);
    assert.equal(b.additionalProperties, false);
    assert.deepEqual(b.required, ['$actql_value']);
    assert.equal(b.properties.$actql_value.minItems, 2);
    assert.equal(b.properties.$actql_value.maxItems, 2);
    assert.equal(b.properties.$actql_value.items, false);
  }
  assert.deepEqual(branches[4].items, { $ref: '#/$defs/projected_value' });
  assert.deepEqual(branches[5].propertyNames.allOf[1], { not: { const: '$actql_value' } });
  const decimal = tag('decimal').properties.$actql_value.prefixItems[1];
  assert.equal(decimal.properties.version.const, 'aoa-decimal-value/0.1');
  assert.equal(decimal.allOf.length, 38);
  for (let p = 1; p <= 38; p++) {
    const branch = decimal.allOf[p - 1];
    assert.deepEqual(branch.if, { properties: { precision: { const: p } }, required: ['precision'] });
    assert.equal(branch.then.properties.scale.maximum, p);
    const pattern = new RegExp(branch.then.properties.coefficient.pattern);
    for (const s of ['0', '9'.repeat(p), '-' + '9'.repeat(p)]) assert.ok(pattern.test(s));
    for (const s of ['-0', '01', '+1', '1\n', '1\r', '1\u2028', '9'.repeat(p + 1)]) assert.ok(!pattern.test(s));
  }
  const escaped = tag('object').properties.$actql_value.prefixItems[1];
  assert.equal(escaped.contains.prefixItems[0].const, '$actql_value');
  assert.equal(escaped.minContains, 1);
  assert.equal(escaped.maxContains, 1);
  assert.deepEqual(escaped.items.prefixItems[1], { $ref: '#/$defs/projected_value' });
  assert.deepEqual(valuesSchema().additionalProperties, { $ref: '#/$defs/projected_value' });
});

test('identity schema checker rejects representation drift and stale artifact pins', () => {
  for (const change of [
    r => { delete r.artifact_schemas.parameter_values.$defs; },
    r => { r.artifact_schemas.parameter_values.properties.values = { type: 'object' }; },
    r => { r.artifact_schema_cids.parameter_values = 'sha256:' + '0'.repeat(64); },
    r => { r.artifact_registry_cid = 'sha256:' + '0'.repeat(64); },
  ]) {
    const r = read('spec/contracts/actql-protocol-schemas.json');
    change(r); assert.throws(() => checkIdentitySchema(r));
  }
});


test('independent signed64 identity projection preserves exact range and adjacent binary64 integers', () => {
  const type = {type: 'int64'};
  const identities = read('portability/corpus/signed64-identities.json').parameterIdentities;
  for (const vector of identities) {
    assert.deepEqual(projectedBody({n: type}, {n: vector.integer}), vector.body);
    verifyIdentity(vector.body, vector.cid, vector.canonicalPreimage);
  }
  assert.equal(new Set(identities.map(value => value.cid)).size, 5);
  for (const value of ['-9223372036854775808', '0', '9223372036854775807', '9007199254740992', '9007199254740993']) {
    assert.deepEqual(project(type, value), {$actql_value: ['int64', value]});
    assert.notDeepEqual(project(type, value), project({type: 'string'}, value));
  }
  assert.notDeepEqual(project(type, '9007199254740992'), project(type, '9007199254740993'));
  for (const value of [0, 9007199254740992, '-0', '+1', '00', '01', '-01', '1e3', '1.0', ' 1', '1\n', '9223372036854775808', '-9223372036854775809']) {
    assert.throws(() => project(type, value));
  }
  const ordinary = { $actql_value: ['int64', '1'] };
  const escaped = project({type: 'object', fields: {$actql_value: {type: 'array', items: {type: 'string'}}}}, ordinary);
  assert.deepEqual(escaped, {$actql_value: ['object', [['$actql_value', ['int64', '1']]]]});
  assert.notDeepEqual(escaped, project(type, '1'));
});

test('signed64 identity adds one closed tag without changing legacy alternatives', () => {
  const prior = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-signed64-type-closure.json.gz'))).records;
  const old = prior['spec/contracts/actql-protocol-schemas.json'].artifact_schemas.parameter_values.$defs;
  const current = identityDefinitions();
  const branches = current.projected_value.oneOf;
  assert.deepEqual(branches.slice(0, -1), old.projected_value.oneOf);
  const tag = branches.at(-1);
  assert.equal(tag.properties.$actql_value.prefixItems[0].const, 'int64');
  assert.equal(tag.additionalProperties, false);
  assert.equal(tag.properties.$actql_value.items, false);
  const value = tag.properties.$actql_value.prefixItems[1];
  assert.equal(value.type, 'string');
  assert.equal(value.maxLength, 20);
  const pattern = new RegExp(value.pattern, 'u');
  for (const valid of ['0', '-1', '9007199254740993']) assert(pattern.test(valid));
  for (const invalid of ['-0', '+1', '01', '1\n', '1\r', '1\u2028']) assert(!pattern.test(invalid));
});

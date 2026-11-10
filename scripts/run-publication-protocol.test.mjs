import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {occurrences, violations} from './check-owned-contract-versions.mjs';
import {emitSchema, shareProtocolRuleConstructors} from './run-publication-protocol.mjs';

test('Run review singleton claim is exact without admitting arbitrary tuple literals', () => {
  assert.doesNotThrow(() => emitSchema({const: ['invocation_scope_approved']}));
  for (const schema of [
    {const: []}, {const: ['a', 'b']}, {const: [null]},
    {type: 'string', const: ['a']}, {const: ['a'], minItems: 2},
  ]) assert.throws(() => emitSchema(schema), /Unsupported/);
});

test('generator rejects unsupported number constraints', () => {
  for (const schema of [
    {type: 'number', const: 1},
    {type: 'number', enum: [1, 2]},
    {type: 'number', minimum: 0, maximum: 1},
  ]) {
    assert.throws(() => emitSchema(schema), /Unsupported number/);
  }
});

test('generator rejects silently ignored constraints in other branches', () => {
  for (const schema of [
    {type: 'null', minLength: 1},
    {type: 'boolean', minimum: 0},
    {type: 'string', minimum: 0},
    {type: 'integer', minLength: 1},
    {type: 'array', minProperties: 1},
    {type: 'object', minItems: 1},
    {type: 'object', propertyNames: {
      not: {pattern: '^actql_', minLength: 2},
    }},
    {type: 'string', const: 1},
    {type: 'integer', enum: ['1']},
  ]) {
    assert.throws(() => emitSchema(schema), /Unsupported|Conflicting/);
  }
});

test('generator retains supported literal and property-name constraints', () => {
  for (const schema of [
    {type: 'integer', minimum: 0, maximum: 1},
    {type: 'string', const: 'value', minLength: 1},
    {type: 'boolean', const: false},
    {type: 'object', propertyNames: {not: {pattern: '^actql_'}}},
  ]) {
    assert.doesNotThrow(() => emitSchema(schema));
  }
});

test('generator preserves operation-specific array ceilings', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'array', items: {}, maxItems: 4096,
  }));
});

test('generator retains the existing Lookup receipt contains obligations', () => {
  const lookup = JSON.parse(readFileSync(new URL('../spec/contracts/actql-lookup-identities.json', import.meta.url), 'utf8'));
  assert.doesNotThrow(() => emitSchema(lookup.schemas.attempt_receipt));
  assert.doesNotThrow(() => emitSchema({contains: {const: 'accounting'}}));
  for (const schema of [
    {contains: false}, {contains: []},
    {contains: {}, minContains: 2}, {contains: {}, maxContains: 1},
  ]) assert.throws(() => emitSchema(schema), /Unsupported/);
});

test('generator admits the existing lookup UTC-millisecond spelling without a permissive pattern fallback', () => {
  assert.doesNotThrow(() => emitSchema({type: 'string',
    pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$'}));
  assert.throws(() => emitSchema({type: 'string',
    pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'}), /Unsupported publication schema pattern/);
});

test('generator preserves exact positional records without permissive tuple fallback', () => {
  const exact = {type: 'array', prefixItems: [{type: 'string'}, {type: 'boolean'}],
    items: false, minItems: 2, maxItems: 2};
  assert.doesNotThrow(() => emitSchema(exact));
  assert.doesNotThrow(() => emitSchema({type: 'array', prefixItems: [],
    items: false, minItems: 0, maxItems: 0}));
  for (const change of [{items: {}}, {minItems: 1}, {maxItems: 3},
    {prefixItems: {}}, {uniqueItems: true}]) {
    assert.throws(() => emitSchema({...exact, ...change}), /Unsupported tuple/);
  }
});

test('generator keeps object-scoped Effect branch constraints', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'object',
    properties: {kind: {enum: ['command', 'create']}},
    allOf: [{oneOf: [
      {properties: {kind: {const: 'command'}}, required: ['contract']},
      {properties: {kind: {const: 'create'}}, required: ['mapping']},
    ]}],
  }));
  assert.throws(() => emitSchema({
    allOf: [{properties: {kind: {const: 'command'}}}],
  }), /Unsupported typeless/);
});

test('generator keeps Effect receipt conditional and exclusion rules', () => {
  assert.doesNotThrow(() => emitSchema({
    type: 'object',
    properties: {state: {enum: ['unknown', 'applied']}},
    allOf: [{if: {properties: {state: {const: 'unknown'}},
      required: ['state']}, then: {required: ['reason']},
    else: {not: {required: ['reason']}}}],
    oneOf: [{required: ['command_id'],
      not: {required: ['operation_ref']}},
    {required: ['operation_ref'],
      not: {anyOf: [{required: ['command_id']},
        {required: ['idempotency_key']}]}}],
  }));
  assert.throws(() => emitSchema({then: {required: ['reason']}}),
    /requires if/);
  assert.throws(() => emitSchema({anyOf: []}), /Empty.*anyOf/);
});


test('generated immutable rules share only exact prior constructors and preserve every slot', () => {
  const original = [
    'protocol_string_rule(None, [], 0, 1)',
    'protocol_string_rule(None, [], 1, 0)',
    'protocol_string_rule(None, [], 0, 1)',
    'protocol_object_rule([], [], -1, 0, None)',
    'protocol_object_rule([], [], -2, 0, None)',
    'protocol_object_rule([], [], -1, 0, None)',
    'protocol_array_rule(0, 0, false, -1)',
    'protocol_array_rule(2, 0, false, -1)',
    'protocol_string_rule(Some("a b"), [], 0, 0)',
    'protocol_string_rule(Some("ab"), [], 0, 0)',
  ];
  const untouched = [...original];
  const shared = shareProtocolRuleConstructors(original);
  assert.deepEqual(original, untouched);
  assert.equal(shared.length, original.length);
  assert.equal(shared[2], 'nodes[0]');
  assert.equal(shared[5], 'nodes[3]');
  const resolve = (index) => {
    const prior = /^nodes\[(\d+)\]$/.exec(shared[index]);
    if (!prior) return shared[index];
    assert.ok(Number(prior[1]) < index);
    return resolve(Number(prior[1]));
  };
  assert.deepEqual(shared.map((_, index) => resolve(index)), original);
  // Generator calls do not retain another invocation's table indices.
  assert.deepEqual(shareProtocolRuleConstructors([original[2]]), [original[2]]);
});


test('shared table retains only the two original legacy literal contexts', () => {
  const path = 'src/run_publication/protocol_schema.generated.mbt';
  const source = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const found = occurrences(source, path);
  const entries = inventory.entries.filter(value => value.path === path);
  assert.equal(found.length, 2);
  assert.deepEqual(found.map(value => value.token).sort(),
    ['actql-model-capture-bundle', 'actql-model-invocation-evidence']
      .map(name => `${name}/${['0', '2'].join('.')}`).sort());
  assert.equal(entries.length, 2);
  assert(entries.every(value => value.count === 1));
  assert.deepEqual(violations(found, inventory), []);
  assert.equal(violations([...found, ...found], inventory).length, 2);
  assert.equal(violations(occurrences(source, 'src/run_publication/foreign_writer.mbt'), inventory).length, 2);
  assert.equal(violations(occurrences(source.replaceAll('protocol_string_rule(', 'foreign_rule('), path), inventory).length, 2);
});

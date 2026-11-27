import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {verifyContentSerializationSchemas} from './content-serialization-contract.mjs';

type AuthoredCount = {oneOf: readonly [{minimum: number}, object]};

const registry = () => JSON.parse(readFileSync(
  'spec/contracts/actql-production-profile-schemas.json', 'utf8'));

test('Content source and executable serialization are closed distinct contracts', () => {
  const {source, serialization} = verifyContentSerializationSchemas();
  assert.equal(source.additionalProperties, false);
  assert.equal(serialization.additionalProperties, false);
  assert.deepEqual(source.required, ['format', 'fields', 'name']);
  assert.deepEqual(serialization.required,
    ['format', 'fields', 'name', 'encoding', 'line_ending', 'bounds']);
  for (const schema of [source, serialization]) {
    assert.deepEqual(schema.oneOf, [
      {required: ['order_by'], not: {required: ['preserve_order']}},
      {required: ['preserve_order'], not: {required: ['order_by']}},
    ]);
    assert.deepEqual(schema.properties.preserve_order, {const: true});
    for (const retired of ['logical_name', 'csv', 'quote']) {
      assert.ok(!Object.hasOwn(schema.properties, retired));
    }
  }
  assert.notEqual(source.$id, serialization.$id);
});

test('CSV requires explicit header and NULL marker; JSONL forbids CSV options', () => {
  const {source, serialization} = verifyContentSerializationSchemas();
  for (const [schema, required] of [[source, ['header', 'null_marker']],
    [serialization, ['header', 'null_marker', 'field_delimiter']]] as const) {
    const rule = schema.allOf[0];
    assert.deepEqual(rule.if, {properties: {format: {const: 'csv'}},
      required: ['format']});
    assert.deepEqual(rule.then.required, required);
    assert.deepEqual(rule.else.not.anyOf,
      ['header', 'null_marker', 'field_delimiter'].map(name => ({required: [name]})));
    assert.deepEqual(schema.properties.null_marker, {enum: ['', '\\N']});
    assert.deepEqual(schema.properties.field_delimiter.enum, [',', ';']);
    assert.ok(!Object.hasOwn(schema.properties.header, 'default'));
    assert.ok(!Object.hasOwn(schema.properties.null_marker, 'default'));
  }
  assert.equal(source.properties.field_delimiter.default, ',');
  assert.equal(source.properties.encoding.default, 'utf-8');
  assert.equal(source.properties.line_ending.default, 'lf');
});

test('authored uppercase profile tokens do not broaden resolved machine tokens', () => {
  const {source, serialization} = verifyContentSerializationSchemas();
  assert.deepEqual(source.properties.encoding.enum, ['utf-8', 'utf-8-bom', 'UTF-8', 'UTF-8-BOM']);
  assert.deepEqual(source.properties.line_ending.enum, ['lf', 'crlf', 'LF', 'CRLF']);
  assert.deepEqual(serialization.properties.encoding.enum, ['utf-8', 'utf-8-bom']);
  assert.deepEqual(serialization.properties.line_ending.enum, ['lf', 'crlf']);
});

test('finite resolved limits permit typed empty input but retain author guards', () => {
  const {source, serialization} = verifyContentSerializationSchemas();
  assert.equal((source.properties.bounds as {minProperties: number}).minProperties, 1);
  assert.deepEqual((serialization.properties.bounds as {required: string[]}).required, ['max_rows', 'max_bytes']);
  for (const key of ['max_rows', 'max_bytes'] as const) {
    assert.equal((source.properties.bounds.properties[key] as AuthoredCount).oneOf[0].minimum, 1);
    assert.deepEqual((source.properties.bounds.properties[key] as AuthoredCount).oneOf[1], {
      type: 'object', additionalProperties: false, required: ['$param'],
      properties: {$param: {type: 'string', pattern: '^[A-Za-z_][A-Za-z0-9_]*$'}},
    });
    assert.deepEqual(serialization.properties.bounds.properties[key], {
      type: 'integer', minimum: 0, maximum: 9007199254740991,
    });
  }
  const evidence = registry().schemas.content_evidence;
  assert.ok(evidence.required.includes('name'));
  assert.ok(!evidence.required.includes('logical_name'));
});

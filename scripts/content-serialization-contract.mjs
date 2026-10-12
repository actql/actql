import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-production-profile-schemas.json';
const safeCount = minimum => ({type: 'integer', minimum,
  maximum: 9007199254740991});

// The author grammar retains guards; an executable barrier contains finite
// resolved ceilings and explicit defaults. Neither schema proves order or
// grants input custody, byte issuance or publication authority.
export function contentSerializationSchema(resolved = false) {
  const count = resolved ? safeCount(0) : {oneOf: [safeCount(1), {
    type: 'object', additionalProperties: false, required: ['$param'],
    properties: {$param: {type: 'string', pattern: '^[A-Za-z_][A-Za-z0-9_]*$'}},
  }]};
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: resolved
      ? 'https://smooth.dev/schemas/actql-content-serialization-0.1.json'
      : 'https://smooth.dev/schemas/actql-content-source-0.1.json',
    type: 'object', additionalProperties: false,
    required: ['format', 'fields', 'name',
      ...(resolved ? ['encoding', 'line_ending', 'bounds'] : [])],
    properties: {
      format: {enum: ['csv', 'jsonl']},
      fields: {type: 'array', minItems: 1, uniqueItems: true,
        items: {type: 'string', minLength: 1}},
      order_by: {type: 'array', minItems: 1, items: {
        type: 'object', minProperties: 1, maxProperties: 1,
        additionalProperties: {enum: ['asc', 'desc']},
      }},
      preserve_order: {const: true},
      name: {type: 'string', minLength: 1, pattern: '^[^\\u0000]+$'},
      header: {type: 'boolean'},
      null_marker: {enum: ['', '\\N']},
      field_delimiter: {enum: [',', ';'], ...(resolved ? {} : {default: ','})},
      encoding: {enum: ['utf-8', 'utf-8-bom', ...(resolved ? [] : ['UTF-8', 'UTF-8-BOM'])],
        ...(resolved ? {} : {default: 'utf-8'})},
      line_ending: {enum: ['lf', 'crlf', ...(resolved ? [] : ['LF', 'CRLF'])],
        ...(resolved ? {} : {default: 'lf'})},
      bounds: {type: 'object', additionalProperties: false,
        ...(resolved ? {required: ['max_rows', 'max_bytes']} : {minProperties: 1}),
        properties: {max_rows: structuredClone(count),
          max_bytes: structuredClone(count)}},
    },
    oneOf: [
      {required: ['order_by'], not: {required: ['preserve_order']}},
      {required: ['preserve_order'], not: {required: ['order_by']}},
    ],
    allOf: [{
      if: {properties: {format: {const: 'csv'}}, required: ['format']},
      then: {required: ['header', 'null_marker',
        ...(resolved ? ['field_delimiter'] : [])]},
      else: {not: {anyOf: ['header', 'null_marker', 'field_delimiter']
        .map(name => ({required: [name]}))}},
    }],
  };
}

export function verifyContentSerializationSchemas(write = false) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  const source = contentSerializationSchema();
  const serialization = contentSerializationSchema(true);
  if (write) {
    registry.schemas.content_source = source;
    registry.schemas.content_barrier.properties.serialization = serialization;
    const evidence = registry.schemas.content_evidence;
    if (Object.hasOwn(evidence.properties, 'logical_name')) {
      assert.ok(!Object.hasOwn(evidence.properties, 'name'));
      evidence.required = evidence.required.map(name =>
        name === 'logical_name' ? 'name' : name);
      evidence.properties.name = evidence.properties.logical_name;
      delete evidence.properties.logical_name;
    }
    for (const name of ['content_source', 'content_barrier', 'content_evidence']) {
      registry.schema_cids[name] = machineCid(registry.schemas[name]);
    }
    const {registry_cid: _previous, ...body} = registry;
    registry.registry_cid = machineCid(body);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  assert.deepEqual(registry.schemas.content_source, source,
    'Stale Content source grammar');
  assert.deepEqual(registry.schemas.content_barrier.properties.serialization,
    serialization, 'Stale resolved Content serialization grammar');
  assert.ok(registry.schemas.content_evidence.required.includes('name'));
  assert.ok(!Object.hasOwn(registry.schemas.content_evidence.properties, 'logical_name'));
  for (const name of ['content_source', 'content_barrier', 'content_evidence']) {
    assert.equal(registry.schema_cids[name], machineCid(registry.schemas[name]),
      `Stale ${name} identity`);
  }
  const {registry_cid: registryCid, ...body} = registry;
  assert.equal(registryCid, machineCid(body), 'Stale production registry identity');
  return {source, serialization,
    barrierCid: registry.schema_cids.content_barrier,
    serializationCid: machineCid(serialization)};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = verifyContentSerializationSchemas(process.argv.includes('--write'));
  console.log(JSON.stringify({barrier_cid: result.barrierCid,
    serialization_contract_cid: result.serializationCid}));
}

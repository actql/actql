import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {sourceTypedLiteral, nodeTypedLiteral, updateTypedJsonContracts} from './typed-json-literal-contract.mjs';

test('typed literal has explicit JSON domain and opaque source data', () => {
  assert.equal(sourceTypedLiteral.additionalProperties, false);
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.required, ['type', 'value']);
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.properties.type, {const:'json'});
  assert.deepEqual(sourceTypedLiteral.properties.typed_literal.properties.value, {type:'string'});
  assert.equal(nodeTypedLiteral.properties.body.additionalProperties, false);
  assert.deepEqual(nodeTypedLiteral.properties.body.required, ['$json']);
  assert.deepEqual(nodeTypedLiteral.properties.body.properties.$json, {});
});

test('every embedded source/node schema and complete artifact pin is current', () => {
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  updateTypedJsonContracts(expressions, protocol);
  const damaged = structuredClone(expressions);
  const typed = damaged.schemas.expression.$defs.expression.oneOf.find(v => v.properties?.typed_literal);
  typed.properties.typed_literal.properties.type = {type:'string'};
  assert.throws(() => updateTypedJsonContracts(damaged, protocol), /stale source/);
  const changed = structuredClone(protocol);
  changed.artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);
  assert.throws(() => updateTypedJsonContracts(expressions, changed));
});

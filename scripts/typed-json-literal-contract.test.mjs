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

test('ordered derive and expression fragments bind the integrated expression law', async () => {
  const {createHash} = await import('node:crypto');
  const canonical = value => Array.isArray(value) ? `[${value.map(canonical)}]`
    : value !== null && typeof value === 'object'
      ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
      : JSON.stringify(value);
  const expressions = JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  const aoa = JSON.parse(readFileSync('spec/contracts/actql-aoa.json'));
  const expected = `sha256:${createHash('sha256').update(canonical(expressions)).digest('hex')}`;
  assert.equal(aoa.execution_contracts['REL.derive.ordered'].dependencies.expression_contract.cid, expected);
  assert.equal(aoa.execution_contracts['ACTQL.expression_fragment/0.1'].dependencies.expression_contract.cid, expected);
});

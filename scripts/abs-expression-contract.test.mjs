import assert from 'node:assert/strict';
import test from 'node:test';
import {absLaw, updateAbsContracts} from './abs-expression-contract.mjs';

function bodies() {
  const source = {oneOf: [{type: 'object', additionalProperties: false,
    required: ['sqrt'], properties: {sqrt: {$ref: '#/$defs/source_expression'}}}]};
  const node = {oneOf: [{type: 'object', additionalProperties: false,
    required: ['op', 'body'], properties: {op: {const: 'sqrt'},
      body: {$ref: '#/$defs/machine_expression'}}}]};
  return [{schemas: {source, node}, laws: {}, grammar_sha256: ''},
    {artifact_schemas: {program: structuredClone(source)}, artifact_schema_cids: {}}];
}
const grammar = 'function_name = "sqrt" | "abs" | "floor" ;\n';

test('ABS schemas retain one child and each embedding reference without changing SQRT', () => {
  const [expression, protocol] = bodies();
  const sqrtSource = structuredClone(expression.schemas.source.oneOf[0]);
  const counts = updateAbsContracts(expression, protocol, grammar, true);
  assert.deepEqual(counts, {source: 2, node: 1});
  assert.deepEqual(expression.schemas.source.oneOf[0], sqrtSource);
  assert.deepEqual(expression.schemas.source.oneOf[1], {
    type: 'object', additionalProperties: false, required: ['abs'],
    properties: {abs: {$ref: '#/$defs/source_expression'}},
  });
  assert.deepEqual(expression.schemas.node.oneOf[1], {
    type: 'object', additionalProperties: false, required: ['op', 'body'],
    properties: {op: {const: 'abs'}, body: {$ref: '#/$defs/machine_expression'}},
  });
  assert.deepEqual(expression.laws.abs, absLaw);
  const prepared = structuredClone([expression, protocol]);
  updateAbsContracts(expression, protocol, grammar, true);
  assert.deepEqual([expression, protocol], prepared);
  updateAbsContracts(expression, protocol, grammar);
});

test('ABS verification rejects stale laws, schema shapes, grammar and artifact pins', () => {
  for (const mutate of [
    expression => { expression.laws.abs.value = 'approximation'; },
    expression => { expression.schemas.source.oneOf[1].additionalProperties = true; },
    expression => { expression.schemas.node.oneOf[1].properties.body = {type: 'array'}; },
    expression => { expression.grammar_sha256 = '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_registry_cid = 'sha256:' + '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_schema_cids.program = 'sha256:' + '0'.repeat(64); },
  ]) {
    const [expression, protocol] = bodies();
    updateAbsContracts(expression, protocol, grammar, true);
    mutate(expression, protocol);
    assert.throws(() => updateAbsContracts(expression, protocol, grammar));
  }
  assert.throws(() => updateAbsContracts(...bodies(), 'function_name = "sqrt" ;', true));
});

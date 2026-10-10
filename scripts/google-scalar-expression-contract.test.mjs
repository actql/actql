import assert from 'node:assert/strict';
import test from 'node:test';
import {googleScalarLaws, updateGoogleScalarContracts} from './google-scalar-expression-contract.mjs';

function bodies() {
  const source = {oneOf: ['contains', 'abs'].map(name => ({type: 'object',
    additionalProperties: false, required: [name], properties: {[name]: name === 'abs'
      ? {$ref: '#/$defs/source_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/source_expression'}}}}))};
  const node = {oneOf: ['contains', 'abs'].map(name => ({type: 'object',
    additionalProperties: false, required: ['op', 'body'], properties: {
      op: {const: name}, body: name === 'abs' ? {$ref: '#/$defs/machine_expression'}
        : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/machine_expression'}}}}))};
  return [{schemas: {source, node}, laws: {}, grammar_sha256: ''},
    {artifact_schemas: {program: structuredClone(source)}, artifact_schema_cids: {}}];
}
const grammar = 'function_name = "contains" | "starts_with" | "ends_with" | "abs" | "sign" ;\n';

test('GoogleSQL scalar schemas preserve exact arities, local references and original operators', () => {
  const [expression, protocol] = bodies();
  const original = structuredClone(expression.schemas);
  assert.deepEqual(updateGoogleScalarContracts(expression, protocol, grammar, true), {
    starts_with: {source: 2, node: 1}, ends_with: {source: 2, node: 1}, sign: {source: 2, node: 1},
  });
  for (const [kind, schema] of Object.entries(original)) {
    for (const shape of schema.oneOf) assert.ok(expression.schemas[kind].oneOf
      .some(candidate => JSON.stringify(candidate) === JSON.stringify(shape)));
  }
  for (const name of ['starts_with', 'ends_with']) {
    const source = expression.schemas.source.oneOf.find(shape => shape.required[0] === name);
    assert.deepEqual(source.properties[name], {type: 'array', minItems: 2, maxItems: 2,
      items: {$ref: '#/$defs/source_expression'}});
    const node = expression.schemas.node.oneOf.find(shape => shape.properties.op.const === name);
    assert.deepEqual(node.properties.body.items, {$ref: '#/$defs/machine_expression'});
  }
  assert.deepEqual(expression.laws, googleScalarLaws);
  const prepared = structuredClone([expression, protocol]);
  updateGoogleScalarContracts(expression, protocol, grammar, true);
  assert.deepEqual([expression, protocol], prepared);
  updateGoogleScalarContracts(expression, protocol, grammar);
});

test('GoogleSQL scalar verification rejects missing, duplicate, widened and stale contracts', () => {
  for (const mutate of [
    expression => { expression.laws.starts_with.value = 'case-insensitive'; },
    expression => { expression.laws.ends_with.signature = 'any value'; },
    expression => { expression.laws.sign.value = 'negative zero'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'starts_with').properties.starts_with.maxItems = 3; },
    expression => { expression.schemas.node.oneOf.find(s => s.properties.op.const === 'sign').properties.body = {type: 'array'}; },
    expression => { expression.schemas.source.oneOf.push(structuredClone(expression.schemas.source.oneOf.find(s => s.required[0] === 'ends_with'))); },
    expression => { expression.grammar_sha256 = '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_registry_cid = 'sha256:' + '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_schema_cids.program = 'sha256:' + '0'.repeat(64); },
  ]) {
    const [expression, protocol] = bodies();
    updateGoogleScalarContracts(expression, protocol, grammar, true);
    mutate(expression, protocol);
    assert.throws(() => updateGoogleScalarContracts(expression, protocol, grammar));
  }
  for (const name of Object.keys(googleScalarLaws)) {
    assert.throws(() => updateGoogleScalarContracts(...bodies(), grammar.replace(`| "${name}" `, ''), true));
  }
});

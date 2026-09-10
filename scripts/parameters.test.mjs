import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-parameters.mjs';
import { parameterSchema, checkParameterSchemas, parameterPrograms } from './parameter-schema.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('Decimal schemas constrain scale to precision in declarations and recursive types', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const schemas = [parameterSchema(true), parameterSchema(), ...parameterPrograms(registry).flatMap(program =>
    [program.properties.params.additionalProperties, program.$defs.parameter_type])];
  for (const schema of schemas) {
    const decimal = schema.oneOf.find(branch => branch.properties.type.const === 'decimal');
    assert.equal(decimal.allOf.length, 38);
    // Check the exact conditional schemas, then their scale bounds for every
    // precision/scale pair. This is not a general JSON Schema evaluator.
    for (let precision = 1; precision <= 38; precision++) {
      const rule = decimal.allOf[precision - 1];
      assert.deepEqual(rule, {
        if: { properties: { precision: { const: precision } }, required: ['precision'] },
        then: { properties: { scale: { maximum: precision } } },
      });
      for (let scale = 0; scale <= 39; scale++) {
        assert.equal(scale <= rule.then.properties.scale.maximum, scale <= precision);
      }
    }
    const invalid = { type: 'decimal', precision: 1, scale: 2 };
    const applicable = decimal.allOf.find(rule => rule.if.properties.precision.const === invalid.precision);
    assert.ok(invalid.scale > applicable.then.properties.scale.maximum);
  }
});
test('Parameter schema keeps recursive constraints separate from declaration metadata and defaults', () => {
  for (const [index, branch] of parameterSchema().oneOf.entries()) {
    const declaration = parameterSchema(true).oneOf[index];
    assert.deepEqual(Object.keys(declaration.properties).filter(k => !(k in branch.properties)), ['default', 'meta']);
    assert.deepEqual(branch.properties.nullable, { type: 'boolean', default: false });
    if (branch.properties.type.const === 'array') assert.equal(branch.properties.items.$ref, '#/$defs/parameter_type');
    if (branch.properties.type.const === 'object') assert.equal(branch.properties.fields.additionalProperties.$ref, '#/$defs/parameter_type');
  }
});
test('Parameter schema checker detects drift in either embedded Program', () => {
  const stages = read('spec/contracts/actql-stage-contracts.json');
  for (const index of [0, 1]) {
    const registry = read('spec/contracts/actql-protocol-schemas.json');
    delete parameterPrograms(registry)[index].$defs.parameter_type.oneOf[0].properties.integer;
    assert.throws(() => checkParameterSchemas(registry, stages));
  }
});
test('Parameter vectors reject ambiguous states and remain reproducible', () => {
  const corpus = read('portability/corpus/parameters.json');
  assert.equal(generate(corpus), generate(structuredClone(corpus)));
  for (const mutate of [c => c.cases.push(c.cases[0]), c => { delete c.cases[0].supplied; }, c => { c.cases[0].expected = 'maybe'; }, c => { c.cases[0].missing = ['x']; }, c => { c.cases.find(v => v.missing).missing = []; }]) {
    const copy = structuredClone(corpus); mutate(copy); assert.throws(() => generate(copy));
  }
});

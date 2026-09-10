import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-relation-nest.mjs';
import { checkNestSchemas } from './nest-schema.mjs';
import { parameterPrograms } from './parameter-schema.mjs';
const load = path => JSON.parse(readFileSync(path, 'utf8'));

test('nest projection schema and pins stay consistent in both Program copies', () => {
  const registry = load('spec/contracts/actql-protocol-schemas.json');
  checkNestSchemas(registry);
  for (const index of [0, 1]) {
    const r = structuredClone(registry);
    parameterPrograms(r)[index].properties.steps.items.properties.nest.properties.fields.items.oneOf.push({type:'object',required:['from','to']});
    assert.throws(() => checkNestSchemas(r));
  }
});

test('nest fixed expectations regenerate without evaluating product code', () => {
  const c = load('portability/corpus/actql-relation-nest-v0.1.json');
  assert.equal(generate(c), readFileSync('src/relation_nest/corpus.generated_test.mbt', 'utf8'));
  for (const mutate of [c => delete c.cases[0].output, c => c.cases[0].issue = 'InvalidBody', c => c.cases.push(c.cases[0]), c => c.types = {}]) {
    const next = structuredClone(c); mutate(next); assert.throws(() => generate(next));
  }
});

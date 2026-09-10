import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-relation-typing.mjs';
import { machineCid } from './actql-spec-family.mjs';
const fixture = () => JSON.parse(readFileSync('portability/corpus/actql-relation-typing-v0.1.json', 'utf8'));

test('embedded derive map schemas admit empty maps and keep artifact pins current', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  const a = registry.artifact_schemas;
  const programs = [a.executable_plan.properties.execution_material.properties.program,
    a.plan_document.properties.plan.properties.execution_material.properties.program];
  for (const p of programs) {
    assert.deepEqual(p.properties.steps.items.properties.derive, {
      type: 'object', additionalProperties: { $ref: '#/$defs/value_expression' },
    });
  }
  for (const name of ['executable_plan', 'plan_document']) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(a[name]));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(a));
});

test('fixed relation expectations reproduce committed tests', () => {
  const c = fixture(), before = structuredClone(c);
  assert.equal(generate(c), readFileSync('src/relation_typing/corpus.generated_test.mbt', 'utf8'));
  assert.deepEqual(c, before);
  assert.match(generate(c), /__proto__/);
  c.types.number.nullable = true;
  assert.notEqual(generate(c), generate(before));
});

test('generation rejects missing expectations and unknown or duplicate cases', () => {
  for (const mutate of [
    c => { c.version = 'wrong'; },
    c => { delete c.accepted[0].output; },
    c => { delete c.accepted[0].body; },
    c => { c.accepted[0].operation = 'join'; },
    c => { c.accepted.push(c.accepted[0]); },
    c => { c.rejected[0].issue = 'wrong'; },
    c => { c.types = {}; },
  ]) {
    const c = fixture(); mutate(c); assert.throws(() => generate(c));
  }
});

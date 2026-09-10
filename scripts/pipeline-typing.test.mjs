import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-pipeline-typing.mjs';
const fixture = () => JSON.parse(readFileSync('portability/corpus/actql-relation-pipeline-v0.1.json', 'utf8'));
test('pipeline generation preserves fixed expectations and source escaping', () => {
  const c = fixture(), copy = structuredClone(c);
  assert.equal(generate(c), readFileSync('src/pipeline_typing/corpus.generated_test.mbt','utf8'));
  assert.deepEqual(c, copy);
  assert.match(generate(c), /__proto__/);
  assert.match(generate(c), /\\u\{e9\}/);
});
test('pipeline generation rejects incomplete or ambiguous fixtures', () => {
  for (const edit of [c => c.version = 'bad', c => c.cases.push(c.cases[0]),
    c => delete c.cases[0].current, c => delete c.cases[0].fields,
    c => c.cases[0].edges = ['input:0'], c => c.cases[8].issue = 'bad']) {
    const c = fixture(); edit(c); assert.throws(() => generate(c));
  }
});

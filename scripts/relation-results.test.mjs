import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-relation-results.mjs';
const fixture = () => JSON.parse(readFileSync('portability/corpus/actql-relation-results-v0.1.json','utf8'));
test('Result expectations regenerate exactly without evaluation', () => {
  const c=fixture(), copy=structuredClone(c);
  assert.equal(generate(c),readFileSync('src/relation_results/corpus.generated_test.mbt','utf8'));
  assert.deepEqual(c,copy);
});
test('Result generation rejects missing expectations and invalid order tuples', () => {
  for (const edit of [c=>c.version='bad',c=>c.cases.push(c.cases[0]),c=>delete c.cases[0].fields,
    c=>delete c.cases[0].target,c=>c.cases[3].order[0][2]='auto',c=>c.cases[7].issue='bad']) {
    const c=fixture(); edit(c); assert.throws(()=>generate(c));
  }
});

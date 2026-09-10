import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { generate } from './check-relation-join.mjs';
const fixture = () => JSON.parse(readFileSync('portability/corpus/actql-relation-join-v0.1.json', 'utf8'));
test('fixed join schemas and failures regenerate exactly', () => {
  assert.equal(generate(fixture()), readFileSync('src/relation_join/corpus.generated_test.mbt', 'utf8'));
});
test('missing and contradictory expectations cannot generate acceptance', () => {
  for (const modify of [c => delete c.cases[0].nullable, c => c.cases[0].key_count = 0,
    c => c.cases.push(c.cases[0]), c => c.cases[0].issue = 'UnknownField',
    c => c.cases[0].fields.push(c.cases[0].fields[0])]) {
    const c = fixture(); modify(c); assert.throws(() => generate(c));
  }
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { generate } from './check-relation-append.mjs';

const fixture = () => JSON.parse(readFileSync('portability/corpus/actql-relation-append-v0.1.json', 'utf8'));
test('fixed append expectations regenerate independently of product output', () => {
  assert.equal(generate(fixture()), readFileSync('src/relation_append/corpus.generated_test.mbt', 'utf8'));
});
test('append vectors require one explicit and known expectation', () => {
  for (const change of [c => delete c.output, c => c.issue = 'MissingField', c => c.output = {x:'missing'}]) {
    const c = fixture(); change(c.cases[0]);
    assert.throws(() => generate(c));
  }
});

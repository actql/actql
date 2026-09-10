import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-expression-typing.mjs';

const fixture = () => ({
  version: 'actql-expression-typing-corpus/0.1', fields: {}, parameters: {},
  types: { number: { type: 'number', nullable: false } },
  positive: [{ source: '1', type: 'number' }],
  negative: [{ source: 'NULL', issue: 'NullTypeUnresolved' }],
});

test('generation preserves independent fixed types and stable failures', () => {
  const corpus = fixture();
  const before = structuredClone(corpus);
  const output = generate(corpus);
  assert.match(output, /assert_type/);
  assert.match(output, /assert_rejected/);
  assert.match(output, /NullTypeUnresolved/);
  assert.deepEqual(corpus, before);
  assert.equal(generate(corpus), output);
  corpus.types.number.nullable = true;
  assert.notEqual(generate(corpus), output);
});

test('generation rejects missing expectations, duplicate cases and unknown issues', () => {
  for (const mutate of [
    c => { c.version = 'unknown'; },
    c => { delete c.positive[0].source; },
    c => { delete c.types.number; },
    c => { delete c.types.number.nullable; },
    c => { c.negative[0].issue = 'unknown'; },
    c => { c.negative[0].source = '1'; },
    c => { c.positive = []; },
    c => { c.negative = []; },
  ]) {
    const corpus = fixture(); mutate(corpus);
    assert.throws(() => generate(corpus));
  }
});

test('MoonBit generation escapes Unicode, controls and interpolation', () => {
  const corpus = fixture();
  corpus.positive[0].source = { literal: '\\{name}\n😀' };
  const output = generate(corpus);
  assert.ok(output.includes('\\u{1f600}'));
  assert.ok(output.includes('\\\\{name}'));
});

test('committed tests exactly match the fixed corpus', () => {
  const corpus = JSON.parse(readFileSync('portability/corpus/actql-expression-typing-v0.1.json', 'utf8'));
  assert.equal(readFileSync('src/expression_typing/corpus.generated_test.mbt', 'utf8'), generate(corpus));
});

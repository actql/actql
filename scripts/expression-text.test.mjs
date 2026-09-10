import assert from 'node:assert/strict';
import { test } from 'node:test';
import { generate } from './check-expression-text.mjs';

const fixture = () => ({
  version: 'actql-expression-text-corpus/0.1',
  positive: [{ source: "'a'", tree: { literal: 'a' } }],
  negative: ['eval(x)'],
});

test('generation preserves fixed expectations without executing expressions', () => {
  const corpus = fixture();
  const before = structuredClone(corpus);
  assert.match(generate(corpus), /assert_tree/);
  assert.match(generate(corpus), /is Err/);
  assert.deepEqual(corpus, before);
  assert.equal(generate(corpus), generate(corpus));
});

test('generation encodes MoonBit strings including interpolation and Unicode', () => {
  const corpus = fixture();
  corpus.positive = [{ source: "'\\{x}\n😀'", tree: { literal: '\\{x}\n😀' } }];
  const output = generate(corpus);
  assert.ok(output.includes('\\\\{x}'));
  assert.ok(output.includes('\\u{1f600}'));
  assert.ok(output.includes('\\u{a}'));
});

test('generation rejects missing expectations, wrong versions and duplicates', () => {
  for (const mutate of [
    c => { c.version = 'unknown'; },
    c => { delete c.positive[0].tree; },
    c => { c.negative.push(c.positive[0].source); },
    c => { c.positive = []; },
    c => { c.negative = []; },
  ]) {
    const corpus = fixture();
    mutate(corpus);
    assert.throws(() => generate(corpus));
  }
});

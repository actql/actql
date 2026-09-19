import assert from 'node:assert/strict';
import {test} from 'node:test';
import {
  checkVectorNumericCorpus,
  readVectorNumericCorpus,
  renderVectorNumericFixture,
} from './vector-numeric.mjs';

test('vector numeric corpus is independent and structurally complete', () => {
  const corpus = readVectorNumericCorpus();
  checkVectorNumericCorpus(corpus);
  const fixture = renderVectorNumericFixture(corpus);
  assert.match(fixture, /quantize_tie_to_even_lower/);
  assert.match(fixture, /normalize_sqrt_boundary/);
  assert.match(fixture, /score_dimension_order_rounding/);
  assert.doesNotMatch(fixture, /Math\.fround|Math\.sqrt/);
});

test('vector numeric corpus rejects missing and rewritten expectations', () => {
  const corpus = readVectorNumericCorpus();
  const missing = structuredClone(corpus);
  delete missing.cases.find(item => item.id === 'score_dot').expected;
  assert.throws(() => checkVectorNumericCorpus(missing));

  const malformed = structuredClone(corpus);
  malformed.cases[0].expected = '0';
  assert.throws(() => checkVectorNumericCorpus(malformed));

  const duplicate = structuredClone(corpus);
  duplicate.cases.push(structuredClone(duplicate.cases[0]));
  assert.throws(() => checkVectorNumericCorpus(duplicate));
});

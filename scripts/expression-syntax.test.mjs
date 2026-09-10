import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { generate } from './check-expression-syntax.mjs';

const corpus = JSON.parse(readFileSync('portability/corpus/actql-expression-syntax-v0.1.json'));
const textCorpus = JSON.parse(readFileSync('portability/corpus/actql-expression-text-v0.1.json'));

test('generation covers fixed structured and existing text expectations', () => {
  const output = generate(corpus, textCorpus);
  const count = corpus.positive.length + corpus.negative.length + textCorpus.positive.length + textCorpus.negative.length;
  assert.equal((output.match(/^test /gm) ?? []).length, count);
  assert.match(output, /parameter_references/);
});

test('malformed versions, expectations and duplicate cases are rejected', () => {
  assert.throws(() => generate({ ...corpus, version: 'other' }, textCorpus));
  assert.throws(() => generate(corpus, { ...textCorpus, version: 'other' }));
  assert.throws(() => generate({ ...corpus, positive: [{ ...corpus.positive[0], tree: null }] }, textCorpus));
  assert.throws(() => generate({ ...corpus, positive: [{ ...corpus.positive[0], parameters: null }] }, textCorpus));
  assert.throws(() => generate({ ...corpus, negative: [...corpus.negative, corpus.positive[0].source] }, textCorpus));
});

test('fixed corpus retains quotation, opaque data and the IN-list exception', () => {
  const quoted = corpus.positive.find(entry => entry.source === '"left".name');
  assert.deepEqual(quoted.tree, { property: { value: { field: 'left' }, name: 'name' } });
  for (const side of ['left', 'right']) {
    const expected = { join_field: { side, name: 'id' } };
    for (const source of [`${side}.id`, `"${side}.id"`, { field: `${side}.id` }]) {
      const entry = corpus.positive.find(entry => JSON.stringify(entry.source) === JSON.stringify(source));
      assert.deepEqual(entry.tree, expected);
    }
  }
  assert.ok(!corpus.negative.includes('"left.name"'));
  assert.deepEqual(corpus.positive[0].parameters, []);
  assert.ok(corpus.positive.some(entry => entry.source.in && entry.parameters.includes('v')));
});

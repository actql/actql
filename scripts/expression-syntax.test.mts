import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { generate } from './check-expression-syntax.mjs';

const corpus: Parameters<typeof generate>[0] = JSON.parse(readFileSync('portability/corpus/actql-expression-syntax-v0.1.json', 'utf8'));
const textCorpus: Parameters<typeof generate>[1] = JSON.parse(readFileSync('portability/corpus/actql-expression-text-v0.1.json', 'utf8'));

test('generation covers fixed structured and existing text expectations', () => {
  const output = generate(corpus, textCorpus);
  const count = corpus.positive.length + corpus.negative.length + textCorpus.positive.length + textCorpus.negative.length;
  assert.equal((output.match(/^test /gm) ?? []).length, count);
  assert.match(output, /parameter_references/);
});

test('malformed versions, expectations and duplicate cases are rejected', () => {
  const [first] = corpus.positive;
  assert.ok(first);
  assert.throws(() => generate({ ...corpus, version: 'other' }, textCorpus));
  assert.throws(() => generate(corpus, { ...textCorpus, version: 'other' }));
  assert.throws(() => generate({ ...corpus, positive: [{ ...first, tree: null }] }, textCorpus));
  assert.throws(() => generate({ ...corpus, positive: [{ ...first, parameters: null }] }, textCorpus));
  assert.throws(() => generate({ ...corpus, negative: [...corpus.negative, first.source] }, textCorpus));
});

test('fixed corpus retains quotation, opaque data and the IN-list exception', () => {
  const quoted = corpus.positive.find(entry => entry.source === '"left".name');
  assert.ok(quoted);
  assert.deepEqual(quoted.tree, { property: { value: { field: 'left' }, name: 'name' } });
  for (const side of ['left', 'right']) {
    const expected = { join_field: { side, name: 'id' } };
    for (const source of [`${side}.id`, `"${side}.id"`, { field: `${side}.id` }]) {
      const entry = corpus.positive.find(entry => JSON.stringify(entry.source) === JSON.stringify(source));
      assert.ok(entry);
      assert.deepEqual(entry.tree, expected);
    }
  }
  assert.ok(!corpus.negative.includes('"left.name"'));
  assert.deepEqual(corpus.positive[0]?.parameters, []);
  assert.ok(corpus.positive.some(({source, parameters}) => source && typeof source === 'object' &&
    'in' in source && source.in && Array.isArray(parameters) && parameters.includes('v')));
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {compositeVectorSuccesses, compositeVectorRefusals,
  compositeVectorResults} from './fixtures/composite-vector-source-input.mjs';

const path = new URL('../src/query_integration/composite_vector_source_preparation_cases_wbtest.mbt', import.meta.url);
const envelope = c => ({kind: c.format === 'json' ? 'program' : 'aql',
  input: c.format === 'json' ? JSON.parse(c.text) : {format: c.format, text: c.text},
  parameters: null});
// Decode only the independently authored single-line string snapshots. This
// does not implement MoonBit parsing or produce expectations from the product.
const strings = text => [...text.matchAll(/^\s*("(?:[^"\\]|\\.)*")[,]?$/gmu)]
  .map(match => JSON.parse(match[1]));

test('common preparation snapshots preserve all original five normal and two refusal envelopes', async () => {
  const text = await readFile(path, 'utf8');
  const values = strings(text);
  assert.equal(values.length, 8);
  assert.deepEqual(values.slice(0, 5).map(JSON.parse), compositeVectorSuccesses.map(envelope));
  assert.deepEqual(values.slice(5, 7).map(JSON.parse), compositeVectorRefusals.map(envelope));
});

test('common preparation expected schema remains the independent public full typed object', async () => {
  const values = strings(await readFile(path, 'utf8'));
  const schema = JSON.parse(values.at(-1));
  assert.deepEqual(schema, Object.fromEntries(
    compositeVectorResults.answer.columns.map(c => [c.name, c.contract])));
  for (const field of ['query_key', 'candidate_key']) {
    assert.deepEqual(schema.hit.fields[field].fields, {
      a: {type: 'string', nullable: false, max_utf8_bytes: 1},
      b: {type: 'number', nullable: false}});
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {compositeVectorSchema, compositeVectorFacts, compositeVectorRows,
  compositeVectorResults, compositeVectorProgram, compositeVectorSuccesses,
  compositeVectorRefusals} from './fixtures/composite-vector-source-input.mjs';

test('composite source keys require both original typed fields, not a scalar replacement', () => {
  assert.deepEqual(compositeVectorFacts, {relation_keys: {candidate_keys: [['b', 'a']]}});
  assert.deepEqual(compositeVectorSchema.b, {type: 'number', nullable: false});
  assert.deepEqual(compositeVectorSchema.a, {type: 'string', nullable: false, max_utf8_bytes: 1});
  for (const rows of Object.values(compositeVectorRows)) {
    assert.equal(new Set(rows.map(row => row.b)).size, 1);
    assert.equal(new Set(rows.map(row => JSON.stringify([row.b, row.a]))).size, 2);
    for (const row of rows) assert.deepEqual(row.embedding, row.a === 'a' ? [1, 0] : [0, 1]);
  }
});
test('authored singleton pooling and existing nearest wiring preserve ordered composite roles', () => {
  const stages = compositeVectorProgram.stages;
  for (const [index, resource] of ['queries', 'candidates'].entries()) {
    assert.deepEqual(stages[index].inputs, {remote: {connector: 'composite_fixture', resource}});
    assert.deepEqual(stages[index].steps, [{from: 'remote', filter: 'true', as: 'all_rows'},
      {from: 'all_rows', select: ['a', 'b', 'embedding'], as: 'captured'}]);
  }
  const steps = stages[2].steps;
  assert.deepEqual(steps.slice(0, 3), [
    {from: 'queries', pool_vectors: {by: ['b', 'a'], method: 'mean', vector: 'embedding'}, as: 'qv'},
    {from: 'candidates', pool_vectors: {by: ['b', 'a'], method: 'mean', vector: 'embedding'}, as: 'cv'},
    {from: 'cv', nearest: {queries: 'qv', metric: 'cosine', k: 1}, as: 'matches'},
  ]);
  for (const field of ['query_id', 'candidate_id']) {
    const key = steps[3].derive.hit.object[field === 'query_id' ? 'query_key' : 'candidate_key'];
    assert.deepEqual(key.object, {b: {property: {value: {field}, name: '0'}},
      a: {property: {value: {field}, name: '1'}}});
  }
  assert.deepEqual(steps.at(-1), {from: 'ordered', select: ['hit'], as: 'out'});
  assert.ok(!JSON.stringify(steps).includes('to_vectors'));
});
test('independent nearest values schemas and rejection texts preserve the F04 distinction', () => {
  assert.deepEqual(compositeVectorResults.answer.rows, [
    {hit: {query_key: {b: 1, a: 'a'}, candidate_key: {b: 1, a: 'a'}, score: 1, rank: 1}},
    {hit: {query_key: {b: 1, a: 'b'}, candidate_key: {b: 1, a: 'b'}, score: 1, rank: 1}},
  ]);
  const key = {type: 'object', nullable: false, additional_properties: false, fields: {
    a: {type: 'string', nullable: false, max_utf8_bytes: 1}, b: {type: 'number', nullable: false}}};
  assert.deepEqual(compositeVectorResults.answer.columns, [{name: 'hit', contract: {
    type: 'object', nullable: false, additional_properties: false,
    fields: {query_key: key, candidate_key: key, score: {type: 'number', nullable: false},
      rank: {type: 'number', nullable: false}}}}]);
  assert.equal(compositeVectorSuccesses.length, 5); assert.equal(compositeVectorRefusals.length, 2);
  for (const item of compositeVectorSuccesses) {
    assert.equal(item.results, compositeVectorResults); assert.equal(item.sourceReadSessionCount, 2);
    if (item.format !== 'json') {
      assert.match(item.text, /by: \[b, a\]/u);
      assert.match(item.text, /ORDER BY hit\.query_key\.a, hit\.candidate_key\.a$/u);
      if (item.format === 'sql') assert.match(item.text, /\) SELECT hit FROM hits ORDER BY/u);
    }
  }
  for (const item of compositeVectorRefusals) {
    assert.match(item.text, /QUERY KEY \(a, b\) VECTOR embedding/u);
    assert.match(item.text, /CANDIDATE KEY \(corpus\.b, corpus\.a\)/u);
    assert.equal(item.sourceReadCount, 0);
  }
});
test('the existing rejected array-ID control is retained without changing its contract', async () => {
  const old = JSON.parse(await readFile(new URL('../spec/frontend/fixtures/nearest-keep/composite-bridge.program.json', import.meta.url), 'utf8'));
  assert.deepEqual(old.stages[0].steps[1].to_vectors.id, ['tenant', 'id']);
  assert.equal(compositeVectorProgram.stages.some(stage => stage.steps.some(step => step.to_vectors)), false);
});

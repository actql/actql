import assert from 'node:assert/strict';
import test from 'node:test';
import {vectorPoolSourceSuccesses, vectorPoolSourceRefusals} from './fixtures/vector-pool-source-input.mjs';

test('prepared pool public inputs retain independent two-member folds and ordered contracts', () => {
  assert.equal(vectorPoolSourceSuccesses.length, 11);
  for (const method of ['sum', 'mean', 'max']) {
    const json = vectorPoolSourceSuccesses.find(c => c.name === 'vector-pool-json-' + method);
    const program = JSON.parse(json.text);
    assert.deepEqual(program.stages[0].steps[0].values.rows,
      [{item_id: 'b', embedding: [0, 1], label: 'second'}, {item_id: 'a', embedding: [1, 0], label: 'first'}]);
    assert.deepEqual(program.stages[0].steps[3].assert_rows, {unique_by: ['item_id']});
    assert.deepEqual(program.stages[0].steps[4].pool_vectors,
      {vector: 'embedding', by: ['cohort'], method, output_id: 'pooled_id'});
    assert.deepEqual(json.results.answer.rows, [{cohort: 1, pooled_id: 1,
      embedding: method === 'mean' ? [0.5, 0.5] : [1, 1], member_count: 2}]);
    assert.deepEqual(json.results.answer.columns, [
      {name: 'cohort', contract: {type: 'number', nullable: false}},
      {name: 'pooled_id', contract: {type: 'number', nullable: false}},
      {name: 'embedding', contract: {type: 'vector', dimensions: 2, nullable: false}},
      {name: 'member_count', contract: {type: 'number', nullable: false}},
    ]);
    for (const carrier of ['relation', 'vectors']) {
      const source = vectorPoolSourceSuccesses.find(c => c.name === 'vector-pool-' + carrier + '-' + method);
      assert.deepEqual(source.results, json.results);
      assert.equal(source.sourceReadSessionCount, 1);
      assert.ok(source.text.includes(carrier === 'relation'
        ? 'ASSERT UNIQUE BY (item_id)' : 'to_vectors(id: item_id, vector: embedding)'));
      assert.ok(source.text.includes('method: ' + JSON.stringify(method)));
    }
  }
});

test('prepared pool empty and refusal cases preserve schema and pre-admission boundaries', () => {
  assert.equal(vectorPoolSourceRefusals.length, 5);
  const empty = vectorPoolSourceSuccesses.filter(c => c.name.endsWith('empty'));
  for (const item of empty) {
    assert.deepEqual(item.results.answer.rows, []);
    assert.deepEqual(item.results.answer.columns, vectorPoolSourceSuccesses[0].results.answer.columns);
  }
  assert.ok(empty.find(c => c.format === 'aql-text').text.includes('WHERE FALSE'));
  for (const item of vectorPoolSourceRefusals) assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  const missingKey = vectorPoolSourceRefusals.find(c => c.name.endsWith('missing-key'));
  assert.ok(!missingKey.text.includes('ASSERT') && !missingKey.text.includes('to_vectors'));
  assert.equal(new Set([...vectorPoolSourceSuccesses, ...vectorPoolSourceRefusals].map(c => c.name)).size, 16);
});

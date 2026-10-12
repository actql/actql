import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import test from 'node:test';
import {nearestPublicInputFixtures} from './fixtures/nearest-public-input.mjs';

const directory = resolve('spec/frontend/fixtures/nearest-keep');

test('nearest member public controls retain independent values and complete column contracts', async () => {
  const {successes} = await nearestPublicInputFixtures(directory);
  for (const [sourceName, controlName, rows, columns] of [
    ['nearest-source-member-case', 'nearest-json-member-control',
      [{label: 'first', score: 1}, {label: 'second', score: 0}],
      [{name: 'label', contract: {type: 'string', nullable: false}},
        {name: 'score', contract: {type: 'number', nullable: false}}]],
    ['nearest-source-key-member-case', 'nearest-json-key-member-control',
      [{request_id: 'q1', item_id: 'a', rank: 1}, {request_id: 'q1', item_id: 'b', rank: 2}],
      [{name: 'request_id', contract: {type: 'string', nullable: false}},
        {name: 'item_id', contract: {type: 'string', nullable: false}},
        {name: 'rank', contract: {type: 'number', nullable: false}}]],
  ]) {
    const source = successes.find(item => item.name === sourceName);
    const control = successes.find(item => item.name === controlName);
    assert.deepEqual(source.results.answer.rows, rows);
    assert.deepEqual(source.results.answer.columns, columns);
    assert.deepEqual(control.results, source.results);
    assert.equal(control.results.answer.unordered, false);
    const stage = JSON.parse(control.text).stages[0];
    assert.deepEqual(stage.results.rows.fields, columns.map(column => column.name));
    assert.equal(stage.results.rows.from, 'projected');
    assert.equal(stage.steps[2].nearest.k, 2);
    assert.equal(stage.steps[3].join.cardinality, 'many_to_one');
    assert.equal(stage.steps[4].join.cardinality, 'many_to_one');
  }
});

test('nearest source keeps authored member spelling and explicit unknown-member refusal', async () => {
  const {successes, refusals} = await nearestPublicInputFixtures(directory);
  const names = [...successes, ...refusals].map(item => item.name);
  assert.equal(new Set(names).size, names.length);
  assert.match(successes.find(item => item.name === 'nearest-source-member-case').text, /neighbor\.SCORE/u);
  assert.match(successes.find(item => item.name === 'nearest-source-key-member-case').text, /QUERY_KEY\.REQUEST_ID/u);
  assert.match(refusals.find(item => item.name === 'nearest-unknown-result-member').text, /neighbor\.MISSING/u);
  // Existing nullable/empty/omitted KEEP and dropped-input cases remain present.
  for (const name of ['nearest-json-empty', 'nearest-source-keep', 'nearest-source-empty',
    'nearest-source-omitted-keep', 'nearest-data-source-keep',
    'nearest-source-query-vector-expression']) assert.ok(successes.some(item => item.name === name));
  assert.match(successes.find(item => item.name === 'nearest-data-source-keep').text,
    /WITH qs AS \(FROM queries\) , cs AS \(FROM candidates\)[\s\S]*NEAREST cs AS c/u);
  assert.match(successes.find(item => item.name === 'nearest-source-query-vector-expression').text,
    /VECTOR IF\(TRUE, q\.embedding, q\.embedding\)/u);
  assert.ok(refusals.some(item => item.name === 'nearest-data-forward-candidate'));
  assert.ok(refusals.some(item => item.name === 'nearest-dropped-input'));
});

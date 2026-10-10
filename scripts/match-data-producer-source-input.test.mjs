import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {matchDataProducerSuccesses as successes, matchDataProducerRefusals as refusals}
  from './fixtures/match-data-producer-source-input.mjs';

test('MATCH DATA has ordinary independent controls with NULL and empty contracts', () => {
  assert.equal(successes.length, 10);
  const find = name => successes.find(item => item.name === 'match-data-' + name);
  for (const [source, control] of [['nodes-source', 'nodes-json'], ['empty-source', 'empty-json'],
    ['parallel-trail-source', 'parallel-trail-json'], ['acquired-reused-source', 'reused-json']]) {
    assert.deepEqual(find(source).results, find(control).results);
    assert.equal(find(control).format, 'json');
    assert.ok(JSON.parse(find(control).text).stages[0].steps.some(step => step.graph));
  }
  assert.deepEqual(find('nodes-source').results.matched, {
    rows: [{value: null, key: 1}, {value: 7, key: 2}], columns: [
      {name: 'value', contract: {type: 'number', nullable: true}},
      {name: 'key', contract: {type: 'number', nullable: false}},
    ],
  });
  assert.deepEqual(find('empty-source').results.matched.rows, []);
  assert.deepEqual(find('empty-source').results.matched.columns, find('nodes-source').results.matched.columns);
  assert.match(find('quoted-relation-star').text, /SELECT \*/);
});

test('MATCH DATA preserves keyed edge multiplicity and acquired producer reuse', () => {
  const trail = successes.find(item => item.name === 'match-data-parallel-trail-json');
  const control = JSON.parse(trail.text);
  assert.deepEqual(control.stages[0].steps[1].values.rows, [
    {edge_key: 11, src: 1, dst: 1}, {edge_key: 10, src: 1, dst: 1},
  ]);
  assert.equal(control.stages[0].steps[4].traverse.path_mode, 'trail');
  assert.deepEqual(trail.results.matched.rows, [{value: 2}, {value: 2}]);
  const reused = successes.find(item => item.name === 'match-data-acquired-reused-source');
  assert.equal(reused.sourceReadCount, 2);
  assert.equal(reused.sourceReadSessionCount, 1);
  assert.match(reused.text, /FROM records \|> WHERE id = 2/);
  assert.equal((reused.text.match(/FROM records/g) ?? []).length, 1);
  assert.deepEqual(reused.results.original, reused.results.matched);
  assert.deepEqual(reused.results.matched.rows, [{value: 20, key: 2}]);
  for (const item of successes) {
    for (const output of Object.values(item.results)) {
      assert.ok(output.columns.every(column => !column.name.startsWith('aql_')));
    }
  }
});

test('MATCH DATA refusals pin scope and supported-surface classifications', () => {
  assert.equal(refusals.length, 7);
  assert.deepEqual(refusals.map(item => item.expectedCode), [
    'ClientProgramInvalidInput', 'ClientProgramInvalidInput', 'ClientProgramInvalidInput',
    'ClientProgramImplementationLimit', 'ClientProgramImplementationLimit', 'ClientProgramImplementationLimit',
    'ClientProgramInvalidInput',
  ]);
});

test('MATCH DATA is copied and registered in ordinary packed acceptance', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...matchDataProducerSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...matchDataProducerRefusals)'));
  assert.ok(driver.includes("['scripts/fixtures/match-data-producer-source-input.mjs', 'match-data-producer-source-input.mjs']"));
  assert.ok(driver.includes('--match-data-producer-only'));
});

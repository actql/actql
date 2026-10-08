import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphProjectionPropertySuccesses as successes,
  graphProjectionPropertyRefusals as refusals}
  from './fixtures/graph-projection-property-source-input.mjs';

test('Graph member source counterexamples retain independently authored rows and contracts', () => {
  const expected = [{id: 1, score: 20}, {id: 2, score: 10},
    {id: 3, score: null}, {id: 4, score: null}];
  const columns = [{name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'score', contract: {type: 'number', nullable: true}}];
  for (const suffix of ['folded-qualified-member', 'folded-quoted-member',
    'folded-projected-receiver']) {
    const item = successes.find(value => value.name.endsWith(suffix));
    assert.ok(item, suffix);
    assert.deepEqual(item.results.matched, {rows: expected, columns});
    assert.equal(item.sourceReadCount, 0);
    assert.match(item.text, /PROPERTY GRAPH/);
    assert.match(item.text, /ORDER BY id \|> RESULT matched$/);
  }
  const control = JSON.parse(successes.find(item => item.format === 'json').text);
  assert.deepEqual(control.stages[0].steps[3].derive.score,
    {property: {name: 'score', value: {field: 'payload'}}});
});

test('Graph nullable, empty and unknown-member cases retain their separate obligations', () => {
  const nullable = successes.find(item => item.name.endsWith('folded-null-receiver-and-member'));
  assert.deepEqual(nullable.results.matched.rows,
    [{id: 3, score: null}, {id: 4, score: null}]);
  const empty = successes.find(item => item.name.endsWith('folded-typed-empty'));
  assert.deepEqual(empty.results.matched.rows, []);
  assert.deepEqual(empty.results.matched.columns, nullable.results.matched.columns);
  assert.ok(refusals.some(item => item.text.includes('a.payload.MISSING')));
  assert.ok(refusals.some(item => item.name.endsWith('removed-graph-variable')));
  assert.ok(refusals.some(item => item.name.endsWith('scalar-receiver')));
});

test('Graph member fixtures remain in the normal public acceptance consumer', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes('fixtures/graph-projection-property-source-input.mjs'));
  assert.ok(driver.includes('--graph-projection-property-only'));
});

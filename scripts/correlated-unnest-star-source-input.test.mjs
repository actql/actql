import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {correlatedUnnestStarSuccesses as successes, correlatedUnnestStarRefusals as refusals,
  correlatedUnnestScalarStarProgram, correlatedUnnestObjectStarProgram}
  from './fixtures/correlated-unnest-star-source-input.mjs';
import {correlatedUnnestSuccesses, correlatedUnnestRefusals}
  from './fixtures/correlated-unnest-source-input.mjs';

test('nullable object star retains duplicates, NULL receivers and declared empty schema', () => {
  const byName = new Map(successes.map(item => [item.name, item]));
  const control = byName.get('correlated-unnest-star-object-json-control');
  assert.deepEqual(JSON.parse(control.text), correlatedUnnestObjectStarProgram);
  assert.deepEqual(control.expected, [{id: 1, code: 10, label: 'a', position: 0},
    {id: 2, code: 20, label: null, position: 0}, {id: 2, code: null, label: null, position: 1},
    {id: 2, code: 20, label: null, position: 2}]);
  assert.deepEqual(control.columns.map(column => [column.name, column.contract.nullable]),
    [['id', false], ['code', true], ['label', true], ['position', false]]);
  for (const name of ['object-sql', 'object-pipe', 'quoted-parenthesized', 'immutable-range', 'data']) {
    const source = byName.get('correlated-unnest-star-' + name);
    assert.deepEqual(source.expected, control.expected);
    assert.deepEqual(source.columns, control.columns);
  }
  for (const name of ['empty-parents', 'empty-arrays']) {
    const source = byName.get('correlated-unnest-star-' + name);
    assert.deepEqual(source.expected, []);
    assert.deepEqual(source.columns, control.columns);
  }
  const current = byName.get('correlated-unnest-star-current-column');
  assert.deepEqual(current.expected, [1, 2, 3, 4].map(id => ({id, items: [9], e: 9, position: 0})));
  assert.deepEqual(current.columns.map(column => column.name), ['id', 'items', 'e', 'position']);
  assert.equal(current.columns[1].contract.items.nullable, false);
  assert.equal(current.columns[2].contract.nullable, false);
});

test('scalar and object controls use ordinary parameter, UNNEST, property, sort and select owners', () => {
  for (const [program, name] of [[correlatedUnnestScalarStarProgram, 'scalar'],
    [correlatedUnnestObjectStarProgram, 'object']]) {
    const control = successes.find(item => item.name === `correlated-unnest-star-${name}-json-control`);
    assert.deepEqual(JSON.parse(control.text), program);
    assert.equal(control.parameterDeclarations, undefined);
    assert.deepEqual(control.columns.map(column => column.name), program.stages[0].results.rows.fields);
    assert.deepEqual(program.stages[0].steps[5],
      {unnest: {column: 'array', as: 'element', with_index: 'position'}});
    assert.equal(control.expected.length, 4);
  }
  assert.equal(correlatedUnnestObjectStarProgram.params.parents.items.fields.items.items.nullable, true);
  assert.equal(correlatedUnnestObjectStarProgram.params.parents.items.fields.items.items.fields.code.nullable, false);
});

test('star cases are in the existing normal/focused cohort with precise preparation refusals', () => {
  for (const item of successes) assert.equal(correlatedUnnestSuccesses.filter(value => value === item).length, 1);
  for (const item of refusals) {
    assert.equal(correlatedUnnestRefusals.filter(value => value === item).length, 1);
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size,
    successes.length + refusals.length);
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/correlated-unnest-star-source-input.mjs', 'correlated-unnest-star-source-input.mjs']"));
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setInnerByNameSuccesses, setInnerByNameRefusals, setInnerByNameProgram} from './fixtures/set-inner-by-name-source-input.mjs';

test('INNER matching has independent row, type, scope and multiplicity controls', () => {
  assert.equal(setInnerByNameSuccesses.length, 12);
  assert.equal(setInnerByNameRefusals.length, 8);
  const union = setInnerByNameSuccesses.find(x => x.name === 'set-inner-by-name-sql-union-all');
  assert.deepEqual(union.expected, [{id: 2, amount: 20}, {id: 2, amount: 20},
    {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 1, amount: null}]);
  assert.deepEqual(union.columns.map(x => x.name), ['id', 'amount']);
  assert.deepEqual(setInnerByNameSuccesses.find(x => x.name === 'set-inner-by-name-data-on-quoted-case').columns.map(x => x.name), ['AMOUNT', 'ID']);
  assert.deepEqual(setInnerByNameProgram.stages[1].steps[0].filter, {gt: [{field: 'id'}, {literal: 1}]});
  assert.deepEqual(setInnerByNameProgram.stages[1].steps[2].filter, {lte: [{field: 'id'}, {literal: 2}]});
  assert.deepEqual(setInnerByNameSuccesses.find(x => x.name === 'set-inner-by-name-sql-global-common-type').expected, [{x: 1}, {x: 3}, {x: 4}]);
});

test('INNER matching participates in both normal and narrow packed acceptance', () => {
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/set-inner-by-name-source-input.mjs', 'set-inner-by-name-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SET_INNER_BY_NAME_ONLY = '1'"));
  assert.ok(corpus.includes('setInnerByNameOnly ? {successes: setInnerByNameSuccesses, refusals: setInnerByNameRefusals}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...setInnerByNameSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...setInnerByNameRefusals)'));
});

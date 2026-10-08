import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setCorrespondingSuccesses, setCorrespondingRefusals, setCorrespondingProgram} from './fixtures/set-corresponding-source-input.mjs';

test('CORRESPONDING matching has independent row, type, scope and multiplicity controls', () => {
  assert.equal(setCorrespondingSuccesses.length, 12);
  assert.equal(setCorrespondingRefusals.length, 8);
  const union = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-default');
  assert.deepEqual(union.expected, [{id: 2, amount: 20}, {id: 2, amount: 20},
    {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 1, amount: null}]);
  assert.deepEqual(union.columns.map(x => x.name), ['id', 'amount']);
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-data-by-case').columns.map(x => x.name), ['AMOUNT', 'ID']);
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[0].filter, {gt: [{field: 'id'}, {literal: 1}]});
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[2].filter, {lte: [{field: 'id'}, {literal: 2}]});
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-global-common-type').expected, [{x: 1}, {x: 3}, {x: 4}]);
});

test('CORRESPONDING matching participates in both normal and narrow packed acceptance', () => {
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/set-corresponding-source-input.mjs', 'set-corresponding-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SET_CORRESPONDING_ONLY = '1'"));
  assert.ok(corpus.includes('setCorrespondingOnly ? {successes: setCorrespondingSuccesses, refusals: setCorrespondingRefusals}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...setCorrespondingSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...setCorrespondingRefusals)'));
});

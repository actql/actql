import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setByNameListSuccesses, setByNameListRefusals, setByNameListProgram} from './fixtures/set-by-name-list-source-input.mjs';

test('BY NAME ON expectations distinguish names, order, NULL and duplicates', () => {
  assert.equal(setByNameListSuccesses.length, 10);
  assert.equal(setByNameListRefusals.length, 8);
  const rows = setByNameListSuccesses.find(x => x.name === 'set-by-name-list-sql-union-all').expected;
  assert.deepEqual(rows, [{amount:20,id:2}, {amount:20,id:2}, {amount:30,id:3}, {amount:30,id:3}, {amount:null,id:1}]);
  assert.deepEqual(setByNameListSuccesses.find(x => x.name === 'set-by-name-list-sql-union-distinct').expected,
    [{amount:20,id:2}, {amount:30,id:3}, {amount:null,id:1}]);
  assert.deepEqual(setByNameListSuccesses.find(x => x.name === 'set-by-name-list-data-quoted-case').columns.map(x=>x.name), ['AMOUNT','ID']);
  assert.deepEqual(setByNameListProgram.stages[1].steps[0].filter, {gt:[{field:'id'},{literal:1}]});
  assert.deepEqual(setByNameListProgram.stages[1].steps[2].filter, {lte:[{field:'id'},{literal:2}]});
});

test('BY NAME ON is copied and selected in narrow and normal public acceptance', () => {
  const driver=readFileSync(new URL('./test-packed-public-query.mjs',import.meta.url),'utf8');
  const corpus=readFileSync(new URL('./fixtures/packed-public-query.mjs',import.meta.url),'utf8');
  assert.ok(driver.includes("['scripts/fixtures/set-by-name-list-source-input.mjs', 'set-by-name-list-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SET_BY_NAME_LIST_ONLY = '1'"));
  assert.ok(corpus.includes('setByNameListOnly ? {successes: setByNameListSuccesses, refusals: setByNameListRefusals}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...setByNameListSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...setByNameListRefusals)'));
});

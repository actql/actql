import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {shortRowsProgram, shortRowsSuccesses, shortRowsRefusals} from './fixtures/short-rows-source-input.mjs';

test('short ROWS independent control distinguishes moving cumulative and current rows', () => {
  const cases = new Map(shortRowsSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('short-rows-independent-json').text), shortRowsProgram);
  assert.deepEqual(shortRowsProgram.stages[1].steps[0].analytic.frame,
    {start: {preceding: 1}, end: 'current_row'});
  assert.deepEqual(cases.get('short-rows-sql-preceding').expected,
    [{id: 1, total: null}, {id: 2, total: 20}, {id: 3, total: 30}, {id: 4, total: 30}, {id: 5, total: 20}]);
  assert.notDeepEqual(cases.get('short-rows-sql-preceding').expected,
    cases.get('short-rows-unbounded-preceding').expected);
  assert.notDeepEqual(cases.get('short-rows-sql-preceding').expected,
    cases.get('short-rows-current-row').expected);
  assert.deepEqual(cases.get('short-rows-typed-empty').columns, cases.get('short-rows-sql-preceding').columns);
  assert.ok(shortRowsRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('ordinary packed corpus and narrow short ROWS selection retain the same cases', async () => {
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('scopeInputs.successes.push(...shortRowsSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...shortRowsRefusals)'));
  assert.ok(corpus.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('shortRowsOnly'));
  assert.ok(corpus.includes('shortRowsOnly ? {successes: shortRowsSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SHORT_ROWS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/short-rows-source-input.mjs', 'short-rows-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--short-rows-only'"));
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /process\.argv\.includes\('--short-rows-only'\).*?return;/su);
});

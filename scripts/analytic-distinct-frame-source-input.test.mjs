import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticDistinctFrameProgram, analyticDistinctFrameSuccesses, analyticDistinctFrameRefusals}
  from './fixtures/analytic-distinct-frame-source-input.mjs';

test('independent cumulative and grouped DISTINCT retain duplicate observations', () => {
  const cases = new Map(analyticDistinctFrameSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('analytic-distinct-frame-independent-json').text), analyticDistinctFrameProgram);
  assert.deepEqual(cases.get('analytic-distinct-frame-ordinary-sql').expected,
    [{id: 1, n: 0, total: null, average: null}, {id: 2, n: 1, total: 2, average: 2},
      {id: 3, n: 2, total: 4, average: 2}, {id: 4, n: 3, total: 12, average: 4}]);
  assert.deepEqual(cases.get('analytic-distinct-frame-grouped-distinct').expected, [{n: 2, total: 10, average: 5}]);
  assert.deepEqual(cases.get('analytic-distinct-frame-ordinary-empty').columns,
    cases.get('analytic-distinct-frame-ordinary-sql').columns);
  assert.equal(analyticDistinctFrameRefusals.length, 10);
  assert.ok(analyticDistinctFrameRefusals.every(item => item.expectedCode === 'ClientProgramImplementationLimit'));
});

test('ordinary and narrow packed selections retain the same analytic boundary', async () => {
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('scopeInputs.successes.push(...analyticDistinctFrameSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...analyticDistinctFrameRefusals)'));
  assert.ok(corpus.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('analyticDistinctFrameOnly'));
  assert.ok(corpus.includes('analyticDistinctFrameOnly ? {successes: analyticDistinctFrameSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_DISTINCT_FRAME_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-distinct-frame-source-input.mjs', 'analytic-distinct-frame-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--analytic-distinct-frame-only'"));
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /process\.argv\.includes\('--analytic-distinct-frame-only'\).*?return;/su);
});

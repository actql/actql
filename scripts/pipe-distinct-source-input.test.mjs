import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeDistinctProgram, pipeDistinctSuccesses, pipeDistinctRefusals}
  from './fixtures/pipe-distinct-source-input.mjs';
const cases = new Map(pipeDistinctSuccesses.map(item => [item.name, item]));
test('visible-row DISTINCT expectations discriminate private old slots and NULL duplicates', () => {
  assert.deepEqual(cases.get('pipe-distinct-set-prunes-displaced-slot').expected,
    [{amount: 20, id: 0}, {amount: 30, id: 0}, {amount: null, id: 0}]);
  assert.deepEqual(cases.get('pipe-distinct-drop-preserves-surviving-range').expected,
    [{amount: 20}, {amount: 30}, {amount: null}]);
  assert.deepEqual(pipeDistinctProgram.stages[1].steps[0], {from: 'records', distinct: ['amount']});
  assert.deepEqual(cases.get('pipe-distinct-typed-empty').columns,
    cases.get('pipe-distinct-drop-preserves-surviving-range').columns);
  assert.deepEqual(cases.get('pipe-distinct-scalar-value-table').expected,
    [{value: 1}, {value: 2}, {value: null}]);
  assert.equal(pipeDistinctSuccesses.length, 13);
  assert.equal(pipeDistinctRefusals.length, 8);
});
test('Pipe DISTINCT is included in the ordinary packed corpus and focused cohort', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...pipeDistinctSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...pipeDistinctRefusals)'));
  assert.ok(fixture.includes('pipeDistinctOnly ? {successes: pipeDistinctSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_DISTINCT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/pipe-distinct-source-input.mjs', 'pipe-distinct-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--pipe-distinct-only'/u);
});

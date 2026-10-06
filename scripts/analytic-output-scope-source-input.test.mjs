import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticOutputScopeProgram as program, analyticOutputScopeSuccesses as successes,
  analyticOutputScopeRefusals as refusals} from './fixtures/analytic-output-scope-source-input.mjs';

test('analytic scope expectations distinguish evaluated aliases from input values and star', () => {
  const cases = new Map(successes.map(item => [item.name, item]));
  assert.deepEqual(cases.get('analytic-output-scope-sql-collision').expected.map(row => row.id), [3,4,1,2]);
  assert.deepEqual(cases.get('analytic-output-scope-sql-qualified-input').expected.map(row => row.id), [1,3,4,2]);
  assert.deepEqual(cases.get('analytic-output-scope-star').columns.map(field => field.name), ['amount','id','pos']);
  assert.deepEqual(cases.get('analytic-output-scope-empty').expected, []);
  assert.equal(cases.get('analytic-output-scope-empty').columns[0].contract.nullable, false);
  assert.deepEqual(JSON.parse(successes[0].text), program);
  assert.deepEqual(program.stages[1].steps[1].select, ['id',{amount:'rank'},{original:'amount'}]);
  assert.equal(new Set([...successes,...refusals].map(item => item.name)).size, successes.length + refusals.length);
});

test('analytic scope acceptance is registered once in the normal packed corpus', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes','analyticOutputScopeSuccesses'],['refusals','analyticOutputScopeRefusals']]) {
    assert.equal(fixture.split(`scopeInputs.${kind}.push(...${group})`).length - 1, 1);
  }
  assert.ok(fixture.includes('analyticOutputScopeOnly ? {successes: analyticOutputScopeSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ANALYTIC_OUTPUT_SCOPE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/analytic-output-scope-source-input.mjs', 'analytic-output-scope-source-input.mjs']"));
});

import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {ifnullSuccesses, ifnullRefusals, ifnullExecutionFailures}
  from './fixtures/ifnull-source-input.mjs';

test('IFNULL fixtures distinguish NULL, false, empty text and demanded fallback failure', () => {
  const byName = new Map(ifnullSuccesses.map(value => [value.name, value]));
  assert.deepEqual(byName.get('ifnull-null-fallback').expected, [{value: 7}]);
  assert.deepEqual(byName.get('ifnull-false-and-empty').expected, [{flag: false, value: ''}]);
  assert.deepEqual(byName.get('ifnull-false-and-empty').columns, [
    {name: 'flag', contract: {type: 'boolean', nullable: false}},
    {name: 'value', contract: {type: 'string', nullable: false, max_utf8_bytes: 8}},
  ]);
  assert.deepEqual(byName.get('ifnull-typed-null').expected, [{value: null}]);
  assert.deepEqual(byName.get('ifnull-typed-null').columns,
    [{name: 'value', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(byName.get('ifnull-empty').expected, []);
  assert.deepEqual(byName.get('ifnull-empty').columns,
    [{name: 'value', contract: {type: 'number', nullable: false}}]);
  const control = JSON.parse(byName.get('ifnull-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].derive.value,
    {coalesce: [{literal: null}, {literal: 7}]});
  const all = [...ifnullSuccesses, ...ifnullRefusals, ...ifnullExecutionFailures];
  assert.equal(new Set(all.map(value => value.name)).size, all.length);
  assert.ok(ifnullRefusals.some(value => value.text.includes('unknown_function')));
  assert.deepEqual(ifnullExecutionFailures[0].resultNames, ['answer']);
});

test('ordinary packed corpus includes IFNULL and its narrow selection excludes unrelated campaigns', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'ifnullSuccesses'], ['refusals', 'ifnullRefusals'],
    ['executionFailures', 'ifnullExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  const scopeGate = fixture.match(/^const scopeOnly = (.+);$/mu);
  assert.ok(scopeGate, 'the packed profile scope gate is present');
  assert.ok(scopeGate[1].split(/\s*\|\|\s*/u).includes('ifnullOnly'));
  assert.ok(fixture.includes('ifnullOnly ? {successes: ifnullSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_IFNULL_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/ifnull-source-input.mjs', 'ifnull-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--ifnull-only'/u);
  const afterCampaign = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.ok(afterCampaign.includes("process.argv.includes('--ifnull-only')) return;"));
});

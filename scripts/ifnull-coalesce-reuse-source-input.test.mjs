import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {ifnullCoalesceReuseSuccesses as successes, ifnullCoalesceReuseRefusals as refusals,
  ifnullCoalesceReuseExecutionFailures as failures} from './fixtures/ifnull-coalesce-reuse-source-input.mjs';

test('coalesce controls retain ordered operands, duplicate counts and typed parameters', () => {
  const byName = new Map(successes.map(item => [item.name.replace('ifnull-coalesce-reuse-', ''), item]));
  const group = byName.get('group-json-control');
  assert.deepEqual(JSON.parse(group.text).stages[1].steps[0].derive.computed,
    {coalesce: [{field: 'amount'}, {literal: 0}]});
  assert.deepEqual(group.expected, [{value: 0, n: 1}, {value: 1, n: 1}, {value: 2, n: 2}, {value: 3, n: 1}]);
  assert.deepEqual(byName.get('parameter-json-control').expected, byName.get('parameter-value').expected);
  assert.deepEqual(byName.get('parameter-null').expected[0], {value: null, n: 1});
  assert.deepEqual(byName.get('nullable-value').columns,
    [{name: 'value', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(byName.get('empty').expected, []);
  assert.deepEqual(byName.get('lazy-json-control').expected, [{value: 1, n: 5}]);
  assert.ok(failures[0].text.includes('CAST(NULL AS FLOAT64), 1 / 0'));
  assert.equal(new Set([...successes, ...refusals, ...failures].map(item => item.name)).size,
    successes.length + refusals.length + failures.length);
});

test('output alias and qualified input have independent reverse order expectations', () => {
  const alias = successes.find(item => item.name.endsWith('-output-alias'));
  const input = successes.find(item => item.name.endsWith('-qualified-input'));
  assert.deepEqual(alias.expected.map(row => row.id), [4, 2, 3, 1, 5]);
  assert.deepEqual(input.expected.map(row => row.id), [5, 1, 2, 3, 4]);
  assert.ok(alias.text.includes('IFNULL(amount, 0) AS original, -amount AS amount'));
  assert.ok(input.text.includes('ORDER BY COALESCE(records.amount, 0)'));
  assert.equal(refusals.length, 9);
  // These are the seven semantic scope/arity/namespace refusals in the
  // existing Core coalesce-reuse test, not unsupported implementation paths.
  assert.deepEqual(refusals.filter(item => item.name.includes('order-refusal')), [
    'COALESCE(amount, 1)', 'COALESCE(0, amount)', 'COALESCE(id, 0)',
    'COALESCE(amount)', 'COALESCE(amount, 0, 1)', 'NULLIF(amount, 0)',
    'ACTQL.COALESCE(amount, 0)',
  ].map((ordered, index) => ({name: 'ifnull-coalesce-reuse-order-refusal-' + index, format: 'sql',
    text: 'SELECT DISTINCT IFNULL(amount, 0) AS value FROM records ORDER BY ' + ordered,
    expectedCode: 'ClientProgramInvalidInput'})));
});

test('normal packed corpus and narrow selection both include coalesce reuse', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'ifnullCoalesceReuseSuccesses'], ['refusals', 'ifnullCoalesceReuseRefusals'],
    ['executionFailures', 'ifnullCoalesceReuseExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.match(fixture, /^const scopeOnly = [^;]*\bifnullCoalesceReuseOnly\b[^;]*;$/mu);
  assert.ok(fixture.includes('ifnullCoalesceReuseOnly ? {successes: ifnullCoalesceReuseSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_IFNULL_COALESCE_REUSE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/ifnull-coalesce-reuse-source-input.mjs', 'ifnull-coalesce-reuse-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--ifnull-coalesce-reuse-only'/u);
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /if \(plannerSelectionOnly[^;]+process\.argv\.includes\('--ifnull-coalesce-reuse-only'\)[^;]*\) return;/u);
});

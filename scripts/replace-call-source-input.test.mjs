import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {replaceCallProgram, replaceCallSuccesses as successes, replaceCallRefusals as refusals,
  replaceCallExecutionFailures as failures} from './fixtures/replace-call-source-input.mjs';

test('REPLACE expectations independently distinguish overlap normalization NULL and input scopes', () => {
  const get = suffix => successes.find(item => item.name === 'replace-call-' + suffix);
  assert.deepEqual(JSON.parse(get('independent-json').text), replaceCallProgram);
  assert.deepEqual(get('non-overlapping-all-occurrences').expected, [{value: 'bXna bXna'}]);
  assert.deepEqual(get('unicode-and-line-endings').expected,
    [{decomposed: 'e\u0301\r\n', composed: '\u00e9', lines: 'aR\nb'}]);
  assert.deepEqual(get('empty-search-and-replacement').expected, [{unchanged: 'aba', removed: 'bna'}]);
  assert.deepEqual(get('current-and-qualified-original').expected[1],
    {id: 2, current_value: 'X1', original_value: 'X0'});
  assert.deepEqual(get('typed-empty').columns, get('input-null-and-duplicates').columns);
  assert.deepEqual(get('typed-empty').expected, []);
  assert.equal(new Set([...successes, ...refusals, ...failures].map(item => item.name)).size,
    successes.length + refusals.length + failures.length);
});

test('REPLACE cases join the ordinary corpus and isolate the bounded packed selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...replaceCallSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...replaceCallRefusals)'));
  assert.ok(fixture.includes('scopeInputs.executionFailures.push(...replaceCallExecutionFailures)'));
  assert.match(fixture, /replaceCallOnly \? \{successes: replaceCallSuccesses, refusals: replaceCallRefusals, executionFailures: replaceCallExecutionFailures\}/);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_REPLACE_CALL_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/replace-call-source-input.mjs', 'replace-call-source-input.mjs']"));
  assert.match(driver, /if \(plannerSelectionOnly[^;]*process\.argv\.includes\('--replace-call-only'\)[^;]*\) return;/);
});

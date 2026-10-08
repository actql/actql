import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {groupByAllProgram, groupByAllSuccesses, groupByAllRefusals} from './fixtures/group-by-all-source-input.mjs';

test('GROUP BY ALL fixtures discriminate key inference and preserve multiplicity', () => {
  const cases = new Map(groupByAllSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('group-by-all-independent-json').text), groupByAllProgram);
  assert.deepEqual(cases.get('group-by-all-aggregate-alias-collision').expected,
    [{id: 2, original: 1}, {id: 2, original: 3}]);
  assert.deepEqual(cases.get('group-by-all-nullable-key').expected,
    [{amount: null, n: 2}, {amount: 0, n: 1}, {amount: 10, n: 1}, {amount: 20, n: 2}]);
  assert.deepEqual(cases.get('group-by-all-no-aggregate-empty-input').expected, [{marker: 1}]);
  assert.deepEqual(cases.get('group-by-all-typed-empty-groups').expected, []);
  assert.deepEqual(cases.get('group-by-all-nullable-property-prefix').expected,
    [{score: null, next: null, n: 1}, {score: 10, next: 11, n: 2}]);
  assert.ok(groupByAllRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  const all = [...groupByAllSuccesses, ...groupByAllRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('GROUP BY ALL is included in ordinary and focused public acceptance', () => {
  const fixture = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...groupByAllSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...groupByAllRefusals)'));
  assert.ok(fixture.includes('groupByAllOnly ? {successes: [...groupByAllSuccesses, ...groupPropertyReceiverSuccesses]'));
  assert.match(fixture, /const scopeOnly = [^;]*groupByAllOnly/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GROUP_BY_ALL_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/group-by-all-source-input.mjs', 'group-by-all-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--group-by-all-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--group-by-all-only')) return;"));
});

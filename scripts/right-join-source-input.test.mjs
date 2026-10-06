import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {rightJoinProgram, rightJoinSuccesses, rightJoinRefusals}
  from './fixtures/right-join-source-input.mjs';

test('RIGHT JOIN oracles retain preserved-side rows types and multiplicity', () => {
  const cases = new Map(rightJoinSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('right-join-independent-json').text), rightJoinProgram);
  const join = rightJoinProgram.stages[1].steps[1];
  assert.equal(join.from, 'preserved');
  assert.equal(join.join.with, 'records');
  assert.equal(join.join.kind, 'left');
  assert.equal(join.join.max_output_rows, 10);
  assert.deepEqual(cases.get('right-join-using-star-order').columns.map(column => column.name), ['id', 'amount']);
  assert.deepEqual(cases.get('right-join-using-qualified-sides').expected,
    [{id: 4, original: null, preserved: 4, amount: null}]);
  assert.deepEqual(cases.get('right-join-alias-order-collision').expected.map(row => row.id), [-3, -3, -3, -3, -2, -1]);
  assert.deepEqual(cases.get('right-join-qualified-order-control').expected.map(row => row.id), [-1, -2, -3, -3, -3, -3]);
  assert.equal(cases.get('right-join-empty-left').expected[0].preserved, 4);
  assert.equal(cases.get('right-join-duplicate-matches').expected.length, 2);
  assert.deepEqual(cases.get('right-join-empty-right').expected, []);
  const all = [...rightJoinSuccesses, ...rightJoinRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('RIGHT JOIN remains in normal and focused packed acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...rightJoinSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...rightJoinRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*rightJoinOnly/u);
  assert.ok(fixture.includes('rightJoinOnly ? {successes: rightJoinSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_RIGHT_JOIN_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--right-join-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--right-join-only'\)\) return;/u);
});

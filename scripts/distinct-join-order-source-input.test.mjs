import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {distinctJoinOrderSuccesses, distinctJoinOrderRefusals, distinctJoinOrderExecutionFailures}
  from './fixtures/distinct-join-order-source-input.mjs';
import {requireDistinctJoinOrderInventory, requireDistinctJoinOrderReports}
  from './fixtures/distinct-join-order-inventory.mjs';
import {validatePackedPublicQueryArguments} from './packed-public-query-options.mjs';

const groups = {
  successes: ['independent-json', 'sql-alias-collision', 'pipe-limit-offset',
    'cte-shared-producer', 'selected-qualified-input', 'selected-expression-reuse', 'typed-empty'],
  executionFailures: ['demanded-sort-failure'],
  refusals: ['dropped-input-0', 'dropped-input-1', 'dropped-input-2'],
};
const names = values => values.map(value => value.name.replace('distinct-join-order-', ''));

test('original DISTINCT JOIN corpus retains authored bytes except implicit result metadata', async () => {
  const source = await readFile(new URL('./fixtures/distinct-join-order-source-input.mjs', import.meta.url), 'utf8');
  assert.equal(source.split("resultNames: ['main']").length - 1, 1);
  const bytes = Buffer.from(source.replace("resultNames: ['main']", "resultNames: ['answer']"));
  const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  assert.equal(blob, '7f4bebce4e3a8340b59661b1ad695c9b24021fdd',
    'original fixture at 57c5ce979025c57ac8d2dc65affaa9bedb83b0b7');
  assert.deepEqual(names(distinctJoinOrderSuccesses), groups.successes);
  assert.deepEqual(names(distinctJoinOrderExecutionFailures), groups.executionFailures);
  assert.deepEqual(names(distinctJoinOrderRefusals), groups.refusals);
});

test('DISTINCT JOIN retains independent LIMIT rows, nullable schema and demanded failure input', () => {
  const pipe = distinctJoinOrderSuccesses.find(value => value.name.endsWith('-pipe-limit-offset'));
  const rows = [{id: 3, amount: 2}, {id: 1, amount: 2}, {id: 2, amount: 1},
    {id: 4, amount: null}, {id: 0, amount: 99}];
  assert.equal(pipe.text, 'FROM records AS l |> JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 25'
    + ' |> WHERE l.id > 0 |> SELECT DISTINCT -l.amount AS amount |> ORDER BY -amount |> LIMIT 2 OFFSET 1');
  assert.deepEqual(pipe.sourceRows, rows);
  assert.deepEqual(pipe.expected, [{amount: -1}, {amount: -2}]);
  assert.deepEqual(pipe.columns, [{name: 'amount', contract: {type: 'number', nullable: true}}]);
  assert.equal(pipe.sourceReadSessionCount, 1);
  const failed = distinctJoinOrderExecutionFailures[0];
  assert.deepEqual(failed.sourceRows, rows);
  assert.equal(failed.sourceReadSessionCount, 1);
  assert.deepEqual(failed.resultNames, ['main']);
  assert.ok(failed.text.endsWith('WHERE l.id > 0 ORDER BY 1 / (amount + 2)'));
  const empty = distinctJoinOrderSuccesses.find(value => value.name.endsWith('-typed-empty'));
  assert.deepEqual(empty.sourceRows, []);
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, pipe.columns);
});

test('unknown arguments and conflicting DISTINCT JOIN selections fail closed', () => {
  validatePackedPublicQueryArguments([], {});
  validatePackedPublicQueryArguments(['--distinct-join-order-only', '--keep-artifacts'], {});
  validatePackedPublicQueryArguments(['--distinct-join-order-only'],
    {ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY: '1'});
  for (const args of [['--distinct-join-order-onyl'], ['--unknown-only'],
    ['--distinct-join-order-only', '--unknown-only']]) {
    assert.throws(() => validatePackedPublicQueryArguments(args, {}), /UnknownPackedPublicQueryArgument/u);
  }
  assert.throws(() => validatePackedPublicQueryArguments(
    ['--distinct-join-order-only', '--graph-diagnostics-only'], {}), /SelectionMustBeExclusive/u);
  assert.throws(() => validatePackedPublicQueryArguments(['--distinct-join-order-only'],
    {ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY: '1'}), /SelectionConflictsWithEnvironment/u);
  for (const args of [[], ['--graph-native-only']]) {
    assert.throws(() => validatePackedPublicQueryArguments(args,
      {ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY: '1'}), /SelectionRequiresExplicitArgument/u);
  }
});

// Synthetic reports test the existing coordinator's selection gate only.
// They are not product Run or external installation evidence.
const inventory = Object.entries(groups).flatMap(([kind, values]) => values.map((name, position) =>
  JSON.stringify(['standard', kind, position, 'distinct-join-order-' + name, 'a'.repeat(64)])));
const reports = () => ['local', 'remote'].map(mode => ({mode, complete: true,
  expectedInventory: [...inventory], completedInventory: [...inventory],
  expectedRetainedCohorts: 1, needsTail: false}));

test('selected transport gate requires the exact original eleven identities on both entrances', () => {
  requireDistinctJoinOrderInventory(inventory);
  requireDistinctJoinOrderReports(reports());
  for (const changed of [inventory.slice(1), [...inventory, inventory[0]], [...inventory].reverse(),
    inventory.map((value, index) => index ? value : JSON.stringify(
      ['standard', 'successes', 0, 'foreign-case', 'a'.repeat(64)]))]) {
    assert.throws(() => requireDistinctJoinOrderInventory(changed));
  }
  for (const mutate of [
    values => values.pop(),
    values => values.reverse(),
    values => { values[1].completedInventory.pop(); },
    values => { values[1].needsTail = true; },
    values => { values[0].complete = false; },
    values => { values[0].expectedRetainedCohorts = 2; },
    values => { values[1].completedInventory[0] = inventory[0].replace('a'.repeat(64), 'b'.repeat(64)); },
  ]) {
    const values = reports(); mutate(values);
    assert.throws(() => requireDistinctJoinOrderReports(values));
  }
});

test('ordinary packed driver selects the original corpus before unrelated work', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const coordinator = await readFile(new URL('./fixtures/packed-query-transports.mjs', import.meta.url), 'utf8');
  const validate = driver.indexOf('validatePackedPublicQueryArguments(process.argv.slice(2));');
  assert.ok(validate >= 0 && validate < driver.indexOf("spawnSync('git'"),
    'unknown arguments stop before source lookup, packing or consumer dispatch');
  // Every current literal driver argument remains accepted by the closed list.
  for (const [, flag] of driver.matchAll(/process\.argv\.includes\('([^']+)'\)/gu)) {
    validatePackedPublicQueryArguments([flag], {});
  }
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY = '1'"));
  const narrow = driver.indexOf('const narrowPublicQuery =');
  const narrowEnd = driver.indexOf('.includes(flag));', narrow);
  assert.ok(driver.slice(narrow, narrowEnd).includes("'--distinct-join-order-only'"));
  const acceptance = driver.indexOf("['packed-query-transports.mjs']", narrowEnd);
  const end = driver.indexOf("if (process.argv.includes('--distinct-join-order-only')) return;", acceptance);
  assert.ok(acceptance >= 0 && end > acceptance && end < driver.indexOf('await exerciseRetainedQueryRestart();'),
    'selected acceptance finishes before unrelated retained String restart');
  for (const name of ['distinct-join-order-source-input', 'distinct-join-order-inventory']) {
    assert.ok(driver.includes(`['scripts/fixtures/${name}.mjs', '${name}.mjs']`));
  }
  assert.match(fixture, /const scopeOnly = distinctJoinOrderOnly \|\|/u);
  assert.ok(fixture.includes('const scopeInputs = distinctJoinOrderOnly ? {successes: distinctJoinOrderSuccesses,'));
  assert.ok(fixture.includes('refusals: distinctJoinOrderRefusals, executionFailures: distinctJoinOrderExecutionFailures}'));
  assert.ok(fixture.includes('if (distinctJoinOrderOnly) requireDistinctJoinOrderInventory(expectedInventory);'));
  assert.ok(coordinator.includes("if (process.env.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY === '1')"));
  assert.ok(coordinator.indexOf('requireDistinctJoinOrderReports(reports);') < coordinator.indexOf('if (reports[0].needsTail)'),
    'both exact eleven-case completion reports are checked before any tail');
  // This restoration is explicit narrow preparation, not unreviewed full-suite expansion.
  for (const group of ['Successes', 'Refusals', 'ExecutionFailures']) {
    assert.equal(fixture.includes(`push(...distinctJoinOrder${group})`), false);
  }
});

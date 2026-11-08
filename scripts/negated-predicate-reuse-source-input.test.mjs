import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {negatedPredicateGroupProgram, negatedPredicateDistinctProgram, negatedPredicateParameterProgram,
  negatedPredicateReuseSuccesses, negatedPredicateReuseRefusals}
  from './fixtures/negated-predicate-reuse-source-input.mjs';

test('independent negated IS Programs retain their exact common operations and argument contracts', () => {
  assert.deepEqual(negatedPredicateGroupProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(negatedPredicateGroupProgram.stages[1].steps, [
    {from: 'records', derive: {value: {not: {is_null: {field: 'amount'}}}}},
    {group: {by: ['value'], aggregates: {n: {fn: 'count'}}}},
    {select: ['value', 'n']},
    {sort: [{field: 'value', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ]);
  assert.deepEqual(negatedPredicateDistinctProgram.stages[1].steps.slice(0, 3), [
    {from: 'records', derive: {value: {not: {is_distinct_from: [{field: 'amount'}, {literal: 2}]}}}},
    {select: ['value']}, {distinct: ['value']},
  ]);
  assert.deepEqual(negatedPredicateParameterProgram.params, {p: {type: 'number', nullable: true}});
  assert.deepEqual(negatedPredicateParameterProgram.stages[1].steps[0].derive,
    {value: {not: {is_distinct_from: [{field: 'amount'}, {$param: 'p'}]}}});
  assert.deepEqual(negatedPredicateReuseSuccesses[0].columns,
    [{name: 'value', contract: {type: 'boolean', nullable: false}},
      {name: 'n', contract: {type: 'number', nullable: false}}]);
});

test('NULL and receiver counterexamples distinguish exact IS truth tables from ordinary NOT', () => {
  const cases = new Map(negatedPredicateReuseSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('negated-predicate-reuse-group-true-direct').expected,
    [{value: false, n: 3}, {value: true, n: 2}]);
  assert.deepEqual(cases.get('negated-predicate-reuse-group-false').expected,
    [{value: false, n: 1}, {value: true, n: 4}]);
  assert.deepEqual(cases.get('negated-predicate-reuse-parameter-source').expected,
    [{value: false, n: 4}, {value: true, n: 1}]);
  assert.deepEqual(cases.get('negated-predicate-reuse-output-alias-receiver').expected.map(row => row.id),
    [1,2,3,4,5]);
  assert.deepEqual(cases.get('negated-predicate-reuse-qualified-input-receiver').expected.map(row => row.id),
    [5,1,2,3,4]);
  assert.deepEqual(cases.get('negated-predicate-reuse-group-empty').expected, []);
  assert.deepEqual(cases.get('negated-predicate-reuse-group-limit-offset').expected, [{value: true, n: 4}]);
  assert.equal(negatedPredicateReuseSuccesses.length, 19);
  assert.equal(negatedPredicateReuseRefusals.length, 8);
  assert.ok(negatedPredicateReuseRefusals.slice(0, 7)
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(negatedPredicateReuseRefusals.at(-1).expectedCode, 'ClientProgramInvalidInput');
  assert.ok(negatedPredicateReuseSuccesses.every(item => item.sourceReadSessionCount === 1));
  const names = [...negatedPredicateReuseSuccesses, ...negatedPredicateReuseRefusals].map(item => item.name);
  assert.equal(new Set(names).size, names.length);
});

test('negated predicate reuse enters both ordinary packed acceptance and its narrow selector', () => {
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  for (const [kind, group] of [['successes', 'negatedPredicateReuseSuccesses'],
    ['refusals', 'negatedPredicateReuseRefusals']]) {
    assert.equal(app.split(`scopeInputs.${kind}.push(...${group})`).length - 1, 1);
  }
  assert.match(app, /const scopeOnly = [^;]*\bnegatedPredicateReuseOnly\b/u);
  assert.ok(app.includes('negatedPredicateReuseOnly ? {successes: negatedPredicateReuseSuccesses, refusals: negatedPredicateReuseRefusals}'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/negated-predicate-reuse-source-input.mjs', 'negated-predicate-reuse-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_NEGATED_PREDICATE_REUSE_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--negated-predicate-reuse-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--negated-predicate-reuse-only')) return;"));
});

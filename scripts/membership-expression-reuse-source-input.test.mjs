import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {membershipGroupProgram, membershipDistinctProgram, membershipParameterProgram,
  membershipReuseSuccesses, membershipReuseRefusals}
  from './fixtures/membership-expression-reuse-source-input.mjs';

test('independent membership controls retain ordered atoms predicate grouping and parameters', () => {
  assert.deepEqual(membershipGroupProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(membershipGroupProgram.stages[1].steps, [
    {from: 'records', derive: {included: {in: [{field: 'amount'}, {literal: [1,2,2]}]}}},
    {group: {by: ['included'], aggregates: {n: {fn: 'count'}}}},
    {select: ['included', 'n']},
    {sort: [{field: 'included', dir: 'asc', nulls: 'last'}], as: 'ordered'},
  ]);
  assert.deepEqual(membershipDistinctProgram.stages[1].steps.slice(0, 3), [
    {from: 'records', derive: {included: {not_in: [{field: 'amount'}, {literal: [1,2,2]}]}}},
    {select: ['included']}, {distinct: ['included']},
  ]);
  assert.deepEqual(membershipParameterProgram.params, {p: {type: 'number', nullable: true}});
  assert.deepEqual(membershipParameterProgram.stages[1].steps[0].derive,
    {included: {in: [{field: 'amount'}, {literal: [{$param: 'p'},2,2,null]}]}});
  assert.deepEqual(membershipReuseSuccesses[0].expected,
    [{included: false, n: 1}, {included: true, n: 3}, {included: null, n: 1}]);
  assert.deepEqual(membershipReuseSuccesses[0].columns,
    [{name: 'included', contract: {type: 'boolean', nullable: true}},
      {name: 'n', contract: {type: 'number', nullable: false}}]);
});

test('receiver and parameter counterexamples distinguish scope and three-valued membership', () => {
  const cases = new Map(membershipReuseSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('membership-reuse-output-alias-receiver').expected.map(row => row.id),
    [2,3,4,1,5]);
  assert.deepEqual(cases.get('membership-reuse-qualified-input-receiver').expected.map(row => row.id),
    [1,4,2,3,5]);
  assert.deepEqual(cases.get('membership-reuse-parameter-source').expected,
    [{included: true, n: 3}, {included: null, n: 2}]);
  assert.deepEqual(cases.get('membership-reuse-parameter-null').expected,
    [{included: true, n: 2}, {included: null, n: 3}]);
  assert.deepEqual(cases.get('membership-reuse-group-empty').expected, []);
  assert.deepEqual(cases.get('membership-reuse-group-limit-offset').expected, [{included: true, n: 3}]);
  assert.equal(membershipReuseSuccesses.length, 14);
  assert.equal(membershipReuseRefusals.length, 10);
  assert.ok(membershipReuseRefusals.slice(0, 6)
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(membershipReuseRefusals.at(-1).expectedCode, 'ClientProgramInvalidInput');
  assert.ok(membershipReuseSuccesses.every(item => item.sourceReadSessionCount === 1));
  const names = [...membershipReuseSuccesses, ...membershipReuseRefusals].map(item => item.name);
  assert.equal(new Set(names).size, names.length);
});

test('membership reuse enters ordinary and selected packed acceptance with the same corpus', () => {
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  for (const [kind, name] of [['successes', 'membershipReuseSuccesses'], ['refusals', 'membershipReuseRefusals']]) {
    assert.equal(app.split(`scopeInputs.${kind}.push(...${name})`).length - 1, 1);
  }
  assert.match(app, /const scopeOnly = [^;]*\bmembershipReuseOnly\b/u);
  assert.ok(app.includes('membershipReuseOnly ? {successes: membershipReuseSuccesses, refusals: membershipReuseRefusals}'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/membership-expression-reuse-source-input.mjs', 'membership-expression-reuse-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_MEMBERSHIP_REUSE_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--membership-expression-reuse-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--membership-expression-reuse-only')) return;"));
});

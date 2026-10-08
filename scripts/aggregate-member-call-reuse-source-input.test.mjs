import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {aggregateMemberCallProgram, aggregateMemberAliasProgram,
  aggregateMemberCallSuccesses, aggregateMemberCallRefusals}
  from './fixtures/aggregate-member-call-reuse-source-input.mjs';
import {havingObjectPropertySuccesses, havingObjectPropertyRefusals}
  from './fixtures/having-object-property-source-input.mjs';

test('independent member aggregate control retains one observation and the original capture predicate', () => {
  const steps = aggregateMemberCallProgram.stages[1].steps;
  assert.deepEqual(aggregateMemberCallProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(steps[2], {group: {by: [], aggregates: {n: {fn: 'count',
    expr: {property: {name: 'score', value: {field: 'payload'}}}}}}});
  assert.deepEqual(steps[3], {filter: {gt: [{field: 'n'}, {literal: 0}]}});
  assert.deepEqual(steps[4], {select: ['n'], as: 'out'});
  assert.deepEqual(JSON.parse(aggregateMemberCallSuccesses[0].text), aggregateMemberCallProgram);
  assert.deepEqual(aggregateMemberAliasProgram.stages[1].steps[4],
    {derive: {published_payload: {$param: 'p3'}}});
});

test('receiver and modifier counterexamples retain independent NULL duplicate and empty expectations', () => {
  const cases = new Map(aggregateMemberCallSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('aggregate-member-call-alias-null-contrast').expected, []);
  assert.deepEqual(cases.get('aggregate-member-call-qualified-input-contrast').expected,
    [{n: 3, payload: null}]);
  assert.equal(cases.get('aggregate-member-call-qualified-input-contrast').parameters.p3, null);
  assert.deepEqual(cases.get('aggregate-member-call-empty-global').expected, [{n: 0}]);
  assert.deepEqual(cases.get('aggregate-member-call-empty-global').columns,
    cases.get('aggregate-member-call-selected-property').columns);
  assert.deepEqual(cases.get('aggregate-member-call-range-object-contrast').expected, [{n: 3}]);
  assert.deepEqual(cases.get('aggregate-member-call-distinct-contrast').expected, [{n: 3}]);
  assert.deepEqual(cases.get('aggregate-member-call-filter-contrast').expected, []);
  assert.deepEqual(cases.get('aggregate-member-call-order-contrast').expected, [{names: 'b|b|a|c'}]);
  assert.ok(aggregateMemberCallSuccesses.every(item => item.sourceReadSessionCount === 1));
  assert.ok(aggregateMemberCallRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('aggregate member obligations are copied and registered in the existing normal and focused Host cohorts', () => {
  for (const item of aggregateMemberCallSuccesses) assert.ok(havingObjectPropertySuccesses.includes(item));
  for (const item of aggregateMemberCallRefusals) assert.ok(havingObjectPropertyRefusals.includes(item));
  const all = [...havingObjectPropertySuccesses, ...havingObjectPropertyRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(app.includes('scopeInputs.successes.push(...havingObjectPropertySuccesses)'));
  assert.ok(app.includes('havingObjectPropertyOnly ? {successes: havingObjectPropertySuccesses'));
  assert.ok(driver.includes("['scripts/fixtures/aggregate-member-call-reuse-source-input.mjs', 'aggregate-member-call-reuse-source-input.mjs']"));
});

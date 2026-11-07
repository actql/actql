import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {concatGroupProgram, concatDistinctProgram, concatReuseSuccesses,
  concatReuseRefusals} from './fixtures/concat-expression-reuse-source-input.mjs';

test('independent concatenation Programs preserve predicate operands grouping and order', () => {
  assert.deepEqual(concatGroupProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(concatGroupProgram.stages[1].steps.slice(2), [
    {derive: {value: {concat_strict: [{field: 'x'}, {field: 'y'}]}}},
    {group: {by: ['value'], aggregates: {n: {fn: 'count'}}}},
    {select: ['value', 'n']},
    {sort: [{field: 'value', dir: 'asc', nulls: 'last'}], as: 'ordered'},
  ]);
  assert.deepEqual(concatDistinctProgram.stages[1].steps[3], {select: ['value']});
  assert.deepEqual(concatDistinctProgram.stages[1].steps[4], {distinct: ['value']});
  assert.deepEqual(concatReuseSuccesses[0].expected,
    [{value: 'az', n: 1}, {value: 'za', n: 2}, {value: null, n: 1}]);
  assert.deepEqual(concatReuseSuccesses[0].columns,
    [{name: 'value', contract: {type: 'string', nullable: true}},
      {name: 'n', contract: {type: 'number', nullable: false}}]);
});

test('receiver collision reverses ordered IDs while empty and rejected inputs stay explicit', () => {
  const cases = new Map(concatReuseSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('concat-reuse-output-alias-receiver').expected.map(row => row.id), [2, 3, 1, 4]);
  assert.deepEqual(cases.get('concat-reuse-qualified-input-receiver').expected.map(row => row.id), [1, 2, 3, 4]);
  assert.deepEqual(cases.get('concat-reuse-group-empty').expected, []);
  assert.deepEqual(cases.get('concat-reuse-distinct-empty').expected, []);
  assert.equal(concatReuseRefusals.length, 4);
  assert.ok(concatReuseRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(concatReuseSuccesses.every(item => item.sourceReadSessionCount === 1));
});

test('concatenation fixtures enter both ordinary and selected packed acceptance', () => {
  const app = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(app.includes('scopeInputs.successes.push(...concatReuseSuccesses)'));
  assert.ok(app.includes('scopeInputs.refusals.push(...concatReuseRefusals)'));
  assert.ok(app.includes('concatReuseOnly ? {successes: concatReuseSuccesses, refusals: concatReuseRefusals}'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/concat-expression-reuse-source-input.mjs', 'concat-expression-reuse-source-input.mjs']"));
  assert.ok(driver.includes('ACTQL_TEST_CONCAT_REUSE_ONLY'));
});

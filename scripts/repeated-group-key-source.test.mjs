import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {groupOrdinalSuccesses, groupOrdinalRefusals, repeatedGroupKeySuccesses}
  from './fixtures/group-ordinal-source-input.mjs';

test('repeated grouping control contains one independently authored computed key', () => {
  const control = repeatedGroupKeySuccesses[0];
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[1].steps.slice(0, 2), [
    {from: 'records', derive: {key: {add: [{field: 'amount'}, {$param: 'increment'}]}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
  ]);
  assert.deepEqual(control.expected, [{bucket: null, n: 1}, {bucket: 21, n: 1}, {bucket: 31, n: 2}]);
  assert.deepEqual(control.columns, [
    {name: 'bucket', contract: {type: 'number', nullable: true}},
    {name: 'n', contract: {type: 'number', nullable: false}},
  ]);
  assert.deepEqual(program.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.equal(control.sourceReadSessionCount, 1);
});

test('repeated-key corpus keeps distinct receivers and Pipe aliases observable', () => {
  const cases = new Map(repeatedGroupKeySuccesses.map(value => [value.name, value]));
  assert.deepEqual(cases.get('group-ordinal-repeated-key-distinct-property-receivers').expected,
    [{score: 1, other: 10, n: 1}, {score: 1, other: 20, n: 3}]);
  assert.deepEqual(cases.get('group-ordinal-repeated-key-alias-input-collision').expected,
    [{amount: -30, n: 2}, {amount: -20, n: 1}, {amount: null, n: 1}]);
  assert.deepEqual(cases.get('group-ordinal-pipe-repeated-value-separate-names').columns.map(column => column.name),
    ['first', 'second', 'n']);
  assert.deepEqual(cases.get('group-ordinal-repeated-key-empty').expected, []);
  assert.equal(repeatedGroupKeySuccesses.length, 8);
  assert.equal(groupOrdinalSuccesses.length, 25);
  const all = [...groupOrdinalSuccesses, ...groupOrdinalRefusals];
  assert.equal(new Set(all.map(value => value.name)).size, all.length);
  assert.equal(groupOrdinalRefusals.length, 9);
  assert.ok(groupOrdinalRefusals.slice(0, 6).every(value => value.expectedCode === 'ClientProgramImplementationLimit'));
});

test('normal and focused public consumers retain the complete ordinal corpus', () => {
  const fixture = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(fixture.includes('groupOrdinalOnly ? {successes: groupOrdinalSuccesses, refusals: groupOrdinalRefusals}'));
  assert.ok(fixture.includes('...groupStarSuccesses, ...groupOrdinalSuccesses]'));
  assert.ok(fixture.includes('...groupStarRefusals, ...groupOrdinalRefusals]'));
  assert.ok(driver.includes("['scripts/fixtures/group-ordinal-source-input.mjs', 'group-ordinal-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GROUP_ORDINAL_ONLY = '1'"));
});

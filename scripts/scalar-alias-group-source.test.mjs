import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {scalarAliasGroupProgram, scalarAliasCeilingProgram,
  scalarAliasGroupSuccesses as cases, scalarAliasGroupRefusals as refusals}
  from './fixtures/scalar-alias-group-source-input.mjs';
import {groupOrdinalSuccesses, groupOrdinalRefusals}
  from './fixtures/group-ordinal-source-input.mjs';

test('scalar aliases use independently authored typed group controls', () => {
  assert.deepEqual(scalarAliasGroupProgram.stages[1].steps[1],
    {derive: {key: {len: {field: 'name'}}}});
  assert.deepEqual(scalarAliasGroupProgram.stages[1].steps[2],
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}});
  assert.deepEqual(cases[0].expected,
    [{width: 1, total: 3}, {width: 2, total: 3}, {width: null, total: null}]);
  assert.deepEqual(cases[0].columns, ['width', 'total'].map(name =>
    ({name, contract: {type: 'number', nullable: true}})));
  assert.equal(cases[0].parameters.b, 'e\u0301');
  assert.equal(cases[0].parameters.c, '😀');
  assert.deepEqual(JSON.parse(cases[0].text), scalarAliasGroupProgram);
  assert.deepEqual(JSON.parse(cases[5].text), scalarAliasCeilingProgram);
  assert.deepEqual(cases[5].expected,
    [{bucket: -1, n: 1}, {bucket: 2, n: 2}, {bucket: null, n: 1}]);
  assert.deepEqual(cases[4].expected, []);
  assert.deepEqual(cases[4].columns, cases[1].columns);
});

test('normal and focused consumers retain scalar alias source and refusal cases', () => {
  assert.equal(cases.length, 8);
  assert.equal(refusals.length, 3);
  assert.ok(cases.every(value => groupOrdinalSuccesses.includes(value)));
  assert.ok(refusals.every(value => groupOrdinalRefusals.includes(value)));
  assert.ok(cases.every(value => value.sourceReadSessionCount === 1));
  assert.ok(refusals.every(value => value.expectedCode === 'ClientProgramInvalidInput'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/scalar-alias-group-source-input.mjs', 'scalar-alias-group-source-input.mjs']"));
  const consumer = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(consumer.includes('...groupStarSuccesses, ...groupOrdinalSuccesses]'));
  assert.ok(consumer.includes('...groupStarRefusals, ...groupOrdinalRefusals]'));
});

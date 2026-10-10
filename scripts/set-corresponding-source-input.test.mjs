import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setCorrespondingSuccesses, setCorrespondingRefusals, setCorrespondingProgram, positionalAggregateProgram} from './fixtures/set-corresponding-source-input.mjs';

test('CORRESPONDING matching has independent row, type, scope and multiplicity controls', () => {
  assert.equal(setCorrespondingSuccesses.length, 24);
  assert.equal(setCorrespondingRefusals.length, 15);
  const union = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-default');
  assert.deepEqual(union.expected, [{id: 2, amount: 20}, {id: 2, amount: 20},
    {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 1, amount: null}]);
  assert.deepEqual(union.columns.map(x => x.name), ['id', 'amount']);
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-data-by-case').columns.map(x => x.name), ['AMOUNT', 'ID']);
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[0].filter, {gt: [{field: 'id'}, {literal: 1}]});
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[2].filter, {lte: [{field: 'id'}, {literal: 2}]});
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-global-common-type').expected, [{x: 1}, {x: 3}, {x: 4}]);
});

test('duplicate aggregate aliases retain different COUNT arguments and empty global rows', () => {
  const counts = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-aggregate-distinct-count-inputs');
  assert.deepEqual(counts.expected, [{a: 0, b: 0}, {a: 1, b: 0}]);
  assert.deepEqual(counts.columns, [{name: 'a', contract: {type: 'number', nullable: false}},
    {name: 'b', contract: {type: 'number', nullable: false}}]);
  assert.equal(counts.sourceReadSessionCount, 0);
  assert.deepEqual(positionalAggregateProgram.stages[0].steps[1].group.aggregates,
    {one: {fn: 'count'}, zero: {fn: 'count', field: 'nullable_input'}});
  const empty = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-aggregate-empty-global');
  assert.deepEqual(empty.expected, [{a: 0, b: 0}, {a: 0, b: 0}]);
  const input = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-aggregate-qualified-input-having');
  assert.ok(input.text.includes('GROUP BY n.x HAVING n.x > 0'));
  const qualify = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-aggregate-undemanded-qualify-aliases');
  assert.deepEqual(qualify.expected, [{a: 0, b: 0, c: 0}, {a: 1, b: 0, c: 1}]);
  assert.deepEqual(qualify.columns.map(x => [x.name, x.contract.nullable]),
    [['a', false], ['b', false], ['c', false]]);
  for (const fixture of setCorrespondingRefusals.filter(x => x.name.includes('aggregate-'))) {
    assert.equal(fixture.expectedCode, 'ClientProgramInvalidInput');
  }
});

test('positional duplicate controls retain both values, types and scope', () => {
  const control = JSON.parse(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-json-control').text);
  assert.equal(control.stages[0].steps[0].as, 'seed');
  assert.equal(control.stages[0].steps[1].from, 'seed');
  assert.deepEqual(control.stages[0].steps[0].values.rows, [{a: 0, b: 0}, {a: 1, b: null}]);
  const scalar = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-duplicate-aliases');
  assert.deepEqual(scalar.expected, [{a: 0, b: 0}, {a: 1, b: null}]);
  assert.deepEqual(scalar.columns.map(x => [x.name, x.contract.nullable]), [['a', false], ['b', true]]);
  assert.equal(scalar.sourceReadSessionCount, 0);
  const scoped = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-scoped-current-and-original');
  assert.equal(scoped.format, 'aql-text');
  assert.deepEqual(scoped.expected, [{a: 0, b: 0}, {a: 1, b: 2}]);
  assert.ok(scoped.text.includes('original.x AS x, x AS `X`'));
  const empty = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-typed-empty');
  assert.equal(empty.format, 'aql-text');
  assert.deepEqual(empty.expected, []);
  const shared = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-positional-shared-source');
  assert.equal(shared.sourceReadSessionCount, 1);
  assert.deepEqual(shared.expected.slice(-2), [{a: 3, b: 30}, {a: 3, b: 30}]);
  for (const f of setCorrespondingRefusals.filter(x => x.name.includes('positional-'))) {
    assert.equal(f.expectedCode, 'ClientProgramInvalidInput');
  }
});

test('CORRESPONDING matching participates in both normal and narrow packed acceptance', () => {
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/set-corresponding-source-input.mjs', 'set-corresponding-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SET_CORRESPONDING_ONLY = '1'"));
  assert.ok(corpus.includes('setCorrespondingOnly ? {successes: [...setCorrespondingSuccesses, ...setJoinSuccesses], refusals: [...setCorrespondingRefusals, ...setJoinRefusals]}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...setCorrespondingSuccesses, ...setJoinSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...setCorrespondingRefusals, ...setJoinRefusals)'));
});

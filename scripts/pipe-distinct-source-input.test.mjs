import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeDistinctProgram, joinPipeDistinctProgram, crossPipeDistinctProgram,
  pipeDistinctSuccesses, pipeDistinctRefusals}
  from './fixtures/pipe-distinct-source-input.mjs';
const cases = new Map(pipeDistinctSuccesses.map(item => [item.name, item]));
test('visible-row DISTINCT expectations discriminate private old slots and NULL duplicates', () => {
  assert.deepEqual(cases.get('pipe-distinct-set-prunes-displaced-slot').expected,
    [{amount: 20, id: 0}, {amount: 30, id: 0}, {amount: null, id: 0}]);
  assert.deepEqual(cases.get('pipe-distinct-drop-preserves-surviving-range').expected,
    [{amount: 20}, {amount: 30}, {amount: null}]);
  assert.deepEqual(pipeDistinctProgram.stages[1].steps[0], {from: 'records', distinct: ['amount']});
  assert.deepEqual(cases.get('pipe-distinct-typed-empty').columns,
    cases.get('pipe-distinct-drop-preserves-surviving-range').columns);
  assert.deepEqual(cases.get('pipe-distinct-scalar-value-table').expected,
    [{value: 1}, {value: 2}, {value: null}]);
  assert.equal(pipeDistinctSuccesses.length, 20);
  assert.equal(pipeDistinctRefusals.length, 10);
});
test('post-JOIN DISTINCT preserves full-row multiplicity before projection', () => {
  const before = cases.get('pipe-distinct-join-before-projection');
  const after = cases.get('pipe-distinct-join-after-sql-projection');
  assert.deepEqual(before.expected,
    [{amount: 20}, {amount: 20}, {amount: 30}, {amount: null}]);
  assert.deepEqual(after.expected, [{amount: 20}, {amount: 30}, {amount: null}]);
  assert.deepEqual(cases.get('pipe-distinct-join-independent-json').expected, before.expected);
  assert.deepEqual(cases.get('pipe-distinct-join-quoted-surviving-ranges').expected, before.expected);
  const {inputs, steps} = joinPipeDistinctProgram.stages[1];
  assert.deepEqual(inputs.left_rows, inputs.right_rows);
  assert.equal(steps[0].join.max_output_rows, 20);
  assert.deepEqual(steps[0].join.on, [{left: 'id', right: 'id'}]);
  assert.deepEqual(steps[1].distinct,
    ['left_amount', 'left_id', 'right_amount', 'right_id']);
  assert.deepEqual(steps[3].select, [{amount: 'left_amount'}]);
  assert.deepEqual(cases.get('pipe-distinct-join-typed-empty').columns, before.columns);
  assert.equal(before.sourceReadSessionCount, 1);
});
test('CROSS JOIN control preserves eight rows and its explicit output ceiling', () => {
  const source = cases.get('pipe-distinct-cross-join-before-projection');
  assert.deepEqual(source.expected, [{amount: 20}, {amount: 20}, {amount: 20}, {amount: 20},
    {amount: 30}, {amount: 30}, {amount: null}, {amount: null}]);
  assert.deepEqual(cases.get('pipe-distinct-cross-join-independent-json').expected, source.expected);
  const {steps} = crossPipeDistinctProgram.stages[1];
  assert.equal(steps[1].cross_join.max_output_rows, 15);
  assert.deepEqual(steps[2].distinct, ['amount', 'id', 'match_id']);
  assert.deepEqual(steps[4].select, ['amount']);
  assert.equal(source.sourceReadSessionCount, 1);
  assert.deepEqual(pipeDistinctRefusals.filter(item => item.name.startsWith('pipe-distinct-refuse-join-'))
    .map(item => item.expectedCode), ['ClientProgramInvalidInput', 'ClientProgramInvalidInput']);
});
test('Pipe DISTINCT is included in the ordinary packed corpus and focused cohort', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...pipeDistinctSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...pipeDistinctRefusals)'));
  assert.ok(fixture.includes('pipeDistinctOnly ? {successes: pipeDistinctSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_DISTINCT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/pipe-distinct-source-input.mjs', 'pipe-distinct-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--pipe-distinct-only'/u);
});

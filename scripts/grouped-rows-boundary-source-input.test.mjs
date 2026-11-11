import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {groupedRowsBoundarySuccesses, groupedRowsBoundaryRefusals}
  from './fixtures/grouped-rows-boundary-source-input.mjs';
import {analyticFrameParameterProgram} from './fixtures/analytic-frame-parameter-source-input.mjs';

test('grouped ROWS operand refusals retain the original parser failure phase', () => {
  const operands = ['(id)', '+(@before + 1)', '+(-1)', '(+1.5)', '(9007199254740992)'];
  assert.deepEqual(groupedRowsBoundaryRefusals.slice(0, 5), operands.map((operand, index) => ({
    name: 'grouped-rows-refuse-operand-' + index,
    format: 'sql',
    text: 'SELECT FIRST_VALUE(amount) OVER '
      + `(ORDER BY id ROWS ${operand} PRECEDING) AS first FROM records`,
    parameterDeclarations: {before: {type: 'number', nullable: false}},
    parameters: {before: 1},
    expectedCode: 'ClientProgramInvalidInput',
  })));
});

test('grouped ROWS fixtures retain independent JSON intervals values and full ordered schema', () => {
  assert.equal(groupedRowsBoundarySuccesses.length, 7);
  const cases = new Map(groupedRowsBoundarySuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('grouped-rows-independent-json').text), analyticFrameParameterProgram);
  assert.deepEqual(analyticFrameParameterProgram.stages[1].steps[0].analytic.frame,
    {start: {preceding: {$param: 'before'}}, end: {following: {$param: 'after'}}});
  assert.deepEqual(cases.get('grouped-rows-sql-distinct-widths').parameters, {before: 1, after: 2});
  assert.deepEqual(cases.get('grouped-rows-sql-distinct-widths').expected,
    [{id: 1, first: null, last: 20}, {id: 2, first: null, last: 30},
      {id: 3, first: 10, last: 40}, {id: 4, first: 20, last: 40}, {id: 5, first: 30, last: 40}]);
  assert.deepEqual(cases.get('grouped-rows-zero-current').expected,
    [{id: 1, first: null, last: null}, {id: 2, first: 10, last: 10},
      {id: 3, first: 20, last: 20}, {id: 4, first: 30, last: 30}, {id: 5, first: 40, last: 40}]);
  assert.deepEqual(cases.get('grouped-rows-typed-empty').expected, []);
  assert.deepEqual(cases.get('grouped-rows-zero-current').columns, [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'first', contract: {type: 'number', nullable: true}},
    {name: 'last', contract: {type: 'number', nullable: true}},
  ]);
  assert.ok(groupedRowsBoundarySuccesses.every(item => item.sourceReadSessionCount === 1));
  assert.equal(groupedRowsBoundaryRefusals.length, 7);
  assert.equal(groupedRowsBoundaryRefusals[5].parameters.before, 0);
});

test('grouped ROWS cases use both the narrow and ordinary public registration', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...groupedRowsBoundarySuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...groupedRowsBoundaryRefusals)'));
  assert.ok(packed.includes('groupedRowsBoundaryOnly ? {successes: groupedRowsBoundarySuccesses, refusals: groupedRowsBoundaryRefusals}'));
  assert.ok(driver.includes('ACTQL_TEST_GROUPED_ROWS_BOUNDARY_ONLY'));
  assert.ok(driver.includes("if (process.argv.includes('--grouped-rows-boundary-only')) return;"));
});

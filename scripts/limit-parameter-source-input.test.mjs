import assert from 'node:assert/strict';
import test from 'node:test';
import {limitParameterProgram, joinLimitTailProgram, joinCurrentRowAfterTakeProgram, joinCurrentRowBeforeTakeProgram, joinCurrentRowVisibleProgram, limitParameterSuccesses, limitParameterRefusals}
  from './fixtures/limit-parameter-source-input.mjs';
import {positiveLimitRefusals} from './fixtures/positive-limit-source-input.mjs';

test('integer-slot syntax refusals retain complete original LIMIT and OFFSET inputs', () => {
  const prefix = 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id';
  const number = {type: 'number', nullable: false};
  const original = (name, text) => ({format: 'sql', text,
    parameterDeclarations: {count: number, skip: number},
    parameters: {count: 2, skip: 1}, name, expectedCode: 'ClientProgramInvalidInput'});
  const grouped = [
    ['grouped-row-operand', prefix + ' LIMIT (id) OFFSET @skip'],
    ['grouped-arithmetic', prefix + ' LIMIT (@count + 1) OFFSET @skip'],
    ['grouped-zero-count', prefix + ' LIMIT ((0)) OFFSET @skip'],
    ['grouped-overflow', prefix + ' LIMIT @count OFFSET (9007199254740992)'],
  ].map(([name, text]) => original('limit-parameter-refuse-' + name, text));
  assert.deepEqual(grouped.map(expected => limitParameterRefusals.find(item =>
    item.name === expected.name)), grouped);
  assert.deepEqual(positiveLimitRefusals.slice(0, 5),
    ['+id', '+(@count + 1)', '+NULL', '+0', '+2.5'].map((operand, index) =>
      original('positive-limit-refuse-operand-' + index,
        prefix + ` LIMIT ${operand} OFFSET +@skip`)));
  assert.deepEqual(limitParameterRefusals.find(item =>
    item.name === 'limit-parameter-refuse-ambiguous-source-declarations'), {
    format: 'sql', text: prefix + ' LIMIT @count OFFSET @skip',
    parameterDeclarations: {count: number, COUNT: number, skip: number},
    parameters: {count: 2, COUNT: 2, skip: 1},
    expectedCode: 'ClientProgramRejected',
    name: 'limit-parameter-refuse-ambiguous-source-declarations',
  });
});

test('LIMIT fixture binds different take roles in an independent Program', () => {
  assert.deepEqual(limitParameterProgram.stages[1].steps[2].take,
    {count: {$param: 'count'}, offset: {$param: 'skip'}});
  assert.deepEqual(limitParameterSuccesses[1].expected,
    [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.deepEqual(limitParameterSuccesses[2].parameters, {count: 1, skip: 2});
  assert.deepEqual(limitParameterSuccesses[2].expected, [{amount: 30, id: 3}]);
});
test('LIMIT fixture keeps NULL duplicates column order and empty schemas', () => {
  const item = limitParameterSuccesses.find(item => item.name.endsWith('zero-offset-null-and-duplicates'));
  assert.deepEqual(item.expected, [{amount: null, id: 1}, {amount: 20, id: 2},
    {amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(item.columns.map(column => column.name), ['amount', 'id']);
  assert.equal(item.columns[0].contract.nullable, true);
  assert.deepEqual(limitParameterSuccesses.find(item => item.name.endsWith('typed-empty')).expected, []);
});
test('LIMIT public cases have distinct names and ordinary refusal inputs', () => {
  const cases = [...limitParameterSuccesses, ...limitParameterRefusals];
  assert.equal(new Set(cases.map(item => item.name)).size, cases.length);
  assert.equal(limitParameterSuccesses.length, 37);
  assert.equal(limitParameterRefusals.length, 24);
  assert.ok(limitParameterRefusals.some(item => item.parameters?.count === 0));
  assert.ok(limitParameterRefusals.some(item => item.parameters?.skip === null));
});

test('source parameter lookup does not rewrite machine declaration or value keys', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const quoted = cases.get('limit-parameter-quoted-parameter-names');
  assert.ok(quoted.text.includes('@`COUNT`'));
  assert.ok(quoted.text.includes('@`\\x53kip`'));
  const exact = cases.get('limit-parameter-exact-declaration-spelling');
  assert.deepEqual(Object.keys(exact.parameterDeclarations), ['COUNT', 'SKIP']);
  assert.deepEqual(exact.parameters, {COUNT: 2, SKIP: 1});
  assert.deepEqual(exact.expected, [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.ok(limitParameterRefusals.some(item => item.name.endsWith('wrong-machine-value-case')));
});

test('grouped take operands retain independently authored rows schema and distinct roles', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const grouped = cases.get('limit-parameter-grouped-sql-bindings');
  assert.equal(grouped.text, 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT ((@count)) OFFSET (@skip)');
  assert.deepEqual(grouped.parameters, {count: 2, skip: 1});
  assert.deepEqual(grouped.expected, [{amount: 20, id: 2}, {amount: 30, id: 3}]);
  assert.deepEqual(grouped.columns, [
    {name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'id', contract: {type: 'number', nullable: false}},
  ]);
  assert.deepEqual(cases.get('limit-parameter-grouped-pipe-different-bindings').parameters, {count: 1, skip: 2});
  assert.deepEqual(cases.get('limit-parameter-grouped-pipe-different-bindings').expected, [{amount: 30, id: 3}]);
  assert.deepEqual(cases.get('limit-parameter-grouped-zero-offset-null-and-duplicates').expected,
    [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(cases.get('limit-parameter-grouped-typed-empty').expected, []);
  for (const item of [...cases.values()].filter(item => item.name.includes('-grouped-'))) {
    assert.equal(item.sourceReadSessionCount, 1);
    assert.deepEqual(item.columns, grouped.columns);
  }
  const refused = limitParameterRefusals.filter(item => item.name.includes('-grouped-'));
  assert.equal(refused.length, 5);
  assert.ok(refused.some(item => item.text.includes('OFFSET (9007199254740992)')));
  assert.ok(refused.some(item => item.parameters?.count === null));
});


test('JOIN continuation retains both take operand pairs and independent multiplicity', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const control = cases.get('limit-parameter-join-tail-independent-json');
  assert.deepEqual(JSON.parse(control.text), joinLimitTailProgram);
  assert.deepEqual(joinLimitTailProgram.stages[1].steps[3].take,
    {count: {$param: 'first_count'}, offset: {$param: 'first_skip'}});
  assert.deepEqual(joinLimitTailProgram.stages[1].steps[4].take,
    {count: {$param: 'count'}, offset: {$param: 'skip'}});
  assert.equal(joinLimitTailProgram.stages[1].steps[1].join.max_output_rows, 10);
  assert.deepEqual(control.expected, [{amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(cases.get('limit-parameter-join-tail-pipe').expected, control.expected);
  assert.deepEqual(cases.get('limit-parameter-join-tail-pipe').columns, control.columns);
  assert.deepEqual(cases.get('limit-parameter-join-tail-empty').expected, []);
  assert.deepEqual(cases.get('limit-parameter-join-tail-where-projection').columns.map(column => column.name), ['id', 'amount']);
  assert.deepEqual(cases.get('limit-parameter-join-tail-different-operands').expected, [{amount: null, id: 1}]);
  assert.ok(limitParameterRefusals.some(item => item.parameters?.first_count === 0));
  assert.ok(limitParameterRefusals.some(item => item.name.endsWith('join-tail-removed-input-range')));
  assert.ok(limitParameterRefusals.filter(item => item.name.includes('join-tail-'))
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('JOIN prefix controls distinguish filtering before and after the take', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  assert.deepEqual(joinCurrentRowAfterTakeProgram.stages[1].steps.slice(2, 5), [
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
    {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}},
    {filter: {eq: [{field: 'k'}, {literal: 3}]}}]);
  assert.deepEqual(joinCurrentRowBeforeTakeProgram.stages[1].steps.slice(2, 5), [
    {filter: {eq: [{field: 'k'}, {literal: 3}]}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
    {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}}]);
  for (const [position, program, expected] of [
    ['after', joinCurrentRowAfterTakeProgram, []],
    ['before', joinCurrentRowBeforeTakeProgram, [{amount: 30, id: 3}]],
  ]) {
    const control = cases.get('limit-parameter-join-prefix-' + position + '-take-independent-json');
    assert.deepEqual(JSON.parse(control.text), program);
    assert.deepEqual(control.expected, expected);
    assert.deepEqual(cases.get('limit-parameter-join-prefix-where-' + position + '-take').expected, expected);
    assert.equal(program.stages[1].steps[1].join.max_output_rows, 10);
  }
  assert.equal(cases.get('limit-parameter-join-prefix-consecutive-where').parameterDeclarations, undefined);
  assert.equal(cases.get('limit-parameter-join-prefix-consecutive-where').parameters, undefined);
  assert.deepEqual(cases.get('limit-parameter-join-prefix-consecutive-where').expected,
    [{amount: 30, id: 3}, {amount: 30, id: 3}]);
  assert.deepEqual(cases.get('limit-parameter-join-prefix-quoted-as-nullable').expected,
    [{amount: null, id: 1}]);
  assert.deepEqual(cases.get('limit-parameter-join-prefix-typed-empty').expected, []);
  assert.ok(limitParameterRefusals.filter(item => item.name.includes('join-prefix-'))
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('JOIN without projection retains all current columns in authored order', () => {
  const cases = new Map(limitParameterSuccesses.map(item => [item.name, item]));
  const control = cases.get('limit-parameter-join-prefix-visible-independent-json');
  const source = cases.get('limit-parameter-join-prefix-visible-without-select');
  assert.deepEqual(JSON.parse(control.text), joinCurrentRowVisibleProgram);
  assert.deepEqual(control.expected, [{amount: 20, id: 2, k: 2}, {amount: 30, id: 3, k: 3}]);
  assert.deepEqual(source.expected, control.expected);
  assert.deepEqual(source.columns, control.columns);
  assert.deepEqual(source.columns.map(column => column.name), ['amount', 'id', 'k']);
  assert.deepEqual(joinCurrentRowVisibleProgram.stages[1].steps.at(-1).select, ['amount', 'id', 'k']);
});

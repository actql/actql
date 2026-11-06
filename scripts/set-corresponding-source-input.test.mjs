import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setCorrespondingSuccesses, setCorrespondingRefusals, setCorrespondingProgram, positionalAggregateProgram, positionalWindowProgram, positionalOrderLimitProgram, positionalStarProgram, positionalFilterProgram, positionalExclusionProgram, positionalReplacementProgram, positionalWindowReplacementProgram, positionalDropProgram, positionalRenameProgram, positionalExtendProgram, positionalAsProgram, positionalOrderWindowProgram, positionalDistinctProgram, positionalUnnestProgram, positionalUnpivotProgram, positionalUnpivotCollisionProgram, positionalAssertProgram, positionalPivotProgram, setCorrespondingExecutionFailures} from './fixtures/set-corresponding-source-input.mjs';

test('CORRESPONDING matching has independent row, type, scope and multiplicity controls', () => {
  assert.equal(setCorrespondingSuccesses.length, 196);
  assert.equal(setCorrespondingRefusals.length, 133);
  const union = setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-default');
  assert.deepEqual(union.expected, [{id: 2, amount: 20}, {id: 2, amount: 20},
    {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 1, amount: null}]);
  assert.deepEqual(union.columns.map(x => x.name), ['id', 'amount']);
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-data-by-case').columns.map(x => x.name), ['AMOUNT', 'ID']);
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[0].filter, {gt: [{field: 'id'}, {literal: 1}]});
  assert.deepEqual(setCorrespondingProgram.stages[1].steps[2].filter, {lte: [{field: 'id'}, {literal: 2}]});
  assert.deepEqual(setCorrespondingSuccesses.find(x => x.name === 'set-corresponding-sql-global-common-type').expected, [{x: 1}, {x: 3}, {x: 4}]);
});

test('positional windows retain opposing order keys and different functions', () => {
  const windows = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-window-'));
  assert.equal(windows.length, 6);
  const source = windows.find(x => x.name.endsWith('-source-orders'));
  assert.equal(source.sourceReadSessionCount, 1);
  assert.deepEqual(source.expected, [{a: 0, b: 0}, {a: 1, b: 2}, {a: 2, b: 1}]);
  assert.deepEqual(windows.find(x => x.name.endsWith('-different-functions')).expected,
    [{a: 0, b: 0}, {a: 1, b: 1}, {a: 2, b: 1}]);
  assert.deepEqual(windows.find(x => x.name.endsWith('-typed-empty')).expected, []);
  const aggregates = windows.find(x => x.name.endsWith('-aggregate-functions'));
  assert.deepEqual(aggregates.expected, [{a: 0, b: 0}, {a: 1, b: 1}, {a: 3, b: 2}]);
  for (const item of windows) {
    assert.deepEqual(item.columns.map(x => [x.name, x.contract.type, x.contract.nullable]),
      [['a', 'number', item === aggregates], ['b', 'number', false]]);
  }
  const steps = positionalWindowProgram.stages[0].steps;
  assert.deepEqual(steps[1].analytic.order_by, [{field: 'x', dir: 'asc', nulls: 'first'}]);
  assert.deepEqual(steps[2].analytic.order_by, [{field: 'x', dir: 'desc', nulls: 'last'}]);
  assert.deepEqual(steps[3].select, [{a: 'up'}, {b: 'down'}]);
  const windowRefusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-window-'));
  assert.equal(windowRefusals.length, 2);
  for (const item of windowRefusals) {
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
    assert.equal(item.format, 'aql-text');
  }
});

test('anonymous analytic ordinals retain scope without authored private receivers', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.includes('-anonymous-analytic-'));
  assert.equal(cases.length, 5);
  for (const item of cases) {
    assert.deepEqual(item.columns.map(x => [x.name, x.contract.type, x.contract.nullable]),
      [['a', 'number', false], ['b', 'number', false]]);
    assert.deepEqual(item.expected, item.name.endsWith('-typed-empty') ? []
      : [{a: 0, b: 0}, {a: 1, b: 2}, {a: 2, b: 1}]);
  }
  const pipe = cases.find(x => x.name.endsWith('-scoped-pipe'));
  assert.ok(pipe.text.includes('SET x = -x'));
  assert.ok(pipe.text.includes('ORDER BY original.x'));
  assert.ok(pipe.text.includes('OVER (ORDER BY x)'));
  assert.equal(cases.find(x => x.name.endsWith('-source-orders')).sourceReadSessionCount, 1);
  const refusals = setCorrespondingRefusals.filter(x => x.name.includes('-anonymous-analytic-'));
  assert.equal(refusals.length, 2);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(refusals.some(x => x.text.includes('QUALIFY aql_analytic_output_1')));
  assert.ok(refusals.some(x => x.text.includes('QUALIFY aql_set_anonymous_3')));
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
  assert.ok(corpus.includes('setCorrespondingOnly ? {successes: [...setCorrespondingSuccesses, ...setJoinSuccesses], refusals: [...setCorrespondingRefusals, ...setJoinRefusals], executionFailures: setCorrespondingExecutionFailures}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...setCorrespondingSuccesses, ...setJoinSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...setCorrespondingRefusals, ...setJoinRefusals)'));
});


test('parenthesized operands preserve independent ordinal values and private scopes', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-parenthesized-'));
  assert.equal(normals.length, 6);
  for (const f of normals.filter(x => !x.name.endsWith('anonymous-aggregate'))) assert.deepEqual(f.columns, [{name: 'a', contract: {type: 'number', nullable: false}},
    {name: 'b', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(normals.find(x => x.name.endsWith('anonymous-aggregate')).columns,
    [{name: 'a', contract: {type: 'number', nullable: true}},
      {name: 'b', contract: {type: 'number', nullable: false}}]);
  const nested = normals.find(x => x.name.endsWith('nested-set'));
  assert.deepEqual(nested.expected, [{a: 0, b: 0}, {a: 1, b: 2}, {a: 2, b: 1}, {a: 3, b: 4}]);
  const scoped = normals.find(x => x.name.endsWith('scoped-windows'));
  assert.ok(scoped.text.includes('SET x = x + 10'));
  assert.ok(scoped.text.includes('ORDER BY original.x'));
  assert.ok(scoped.text.includes('ORDER BY x DESC'));
  assert.deepEqual(scoped.expected, [{a: 0, b: 0}, {a: 1, b: 2}, {a: 2, b: 1}]);
  assert.deepEqual(normals.find(x => x.name.endsWith('anonymous-aggregate')).expected, [{a: 0, b: 0}, {a: 3, b: 2}]);
  assert.deepEqual(normals.find(x => x.name.endsWith('anonymous-scalars')).expected, [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}]);
  const source = normals.find(x => x.name.endsWith('source-windows'));
  assert.equal(source.sourceReadSessionCount, 1);
  assert.equal(source.format, 'sql');
  assert.deepEqual(normals.find(x => x.name.endsWith('typed-empty')).expected, []);
  assert.equal(setCorrespondingRefusals.filter(x => x.name.includes('refuse-parenthesized-')).length, 3);
});

test('positional inner ORDER LIMIT has independent values and opposite alias controls', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-limited-') && !x.name.includes('-filtered-'));
  assert.equal(normals.length, 9);
  const find = suffix => normals.find(x => x.name.endsWith('-' + suffix));
  assert.deepEqual(find('source-scalar').expected, [{a: -2}, {a: 0}]);
  for (const name of ['ordinal-scalar', 'output-alias', 'parameter-offset']) {
    assert.deepEqual(find(name).expected, [{a: -1}, {a: 0}]);
  }
  assert.deepEqual(find('qualified-input').expected, [{a: -2}, {a: 0}]);
  assert.deepEqual(find('source-window').expected, [{a: 0}, {a: 2}]);
  assert.deepEqual(find('duplicate-ordinal').expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.deepEqual(find('source-aggregate').columns.map(x => [x.name, x.contract.nullable]),
    [['a', true], ['b', false]]);
  assert.deepEqual(find('parameter-offset').parameters, {take: 1, skip: 1});
  assert.ok(find('parameter-offset').text.includes('LIMIT @take OFFSET @skip) ORDER BY a'));
  const steps = positionalOrderLimitProgram.stages[0].steps;
  assert.deepEqual(steps[1].derive, {neg: {negate: {field: 'x'}}});
  assert.deepEqual(steps[2].sort, [{field: 'x', dir: 'desc', nulls: 'last'}]);
  assert.deepEqual(steps[3].take, {count: 1, offset: 0});
  assert.deepEqual(steps[4].select, [{a: 'neg'}]);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-limited-'));
  assert.equal(refusals.length, 4);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional star fixtures preserve values nullable schema DISTINCT and scope', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-star-'));
  assert.equal(normals.length, 9);
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.deepEqual(find('source-scalar').expected, [{a: -2}, {a: -1}, {a: 0}]);
  assert.deepEqual(find('distinct').sourceRows.map(x => x.id), [2, 2, 1]);
  assert.deepEqual(find('distinct').expected, find('source-scalar').expected);
  assert.deepEqual(find('repeated-star-limit').expected, [{a: -1}, {a: 0}]);
  assert.deepEqual(find('window').expected, [{a: 0}, {a: 2}]);
  assert.deepEqual(find('aggregate').columns.map(x => [x.name, x.contract.nullable]), [['a', true], ['b', false]]);
  assert.deepEqual(find('nullable').expected, [{a: -10}, {a: 0}, {a: null}]);
  assert.equal(find('nullable').columns[0].contract.nullable, true);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.deepEqual(find('typed-empty').columns, [{name: 'a', contract: {type: 'number', nullable: false}}]);
  const steps = positionalStarProgram.stages[0].steps;
  assert.deepEqual(steps[1].derive, {neg: {negate: {field: 'x'}}});
  assert.deepEqual(steps.slice(2, 5).map(x => x.select), [['neg'], ['neg'], [{a: 'neg'}]]);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-star-'));
  assert.equal(refusals.length, 4);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});

test('postprojection filters retain only current names and stay before append', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.includes('-limited-filtered-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 7);
  for (const name of ['json-control', 'false', 'null-predicate']) {
    assert.deepEqual(find(name).expected, [{a: 0}]);
  }
  assert.deepEqual(find('true').expected, [{a: -2}, {a: -1}, {a: 0}]);
  assert.deepEqual(find('kept-alias').expected, [{a: 0, b: 0}, {a: 1, b: -1}]);
  for (const name of ['window', 'duplicate-ordinal']) {
    assert.deepEqual(find(name).expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
    assert.ok(find(name).text.includes('WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1)'));
  }
  assert.ok(find('kept-alias').text.includes('SELECT id AS kept, -id |> WHERE kept = 1'));
  assert.ok(find('null-predicate').text.includes('WHERE CAST(NULL AS BOOL)'));
  assert.deepEqual(positionalFilterProgram.stages[0].steps[2].select, [{a: 'neg'}]);
  assert.deepEqual(positionalFilterProgram.stages[0].steps[3], {filter: {literal: false}, as: 'right'});
  assert.deepEqual(positionalFilterProgram.stages[0].steps[5], {from: 'left', append: {with: 'right'}});
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-filtered-'));
  assert.equal(refusals.length, 4);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional exclusions use authored names without exposing anonymous slots', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-exclusion-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 9);
  assert.deepEqual(find('source-scalar').expected, [{a: -2}, {a: -1}, {a: 0}]);
  assert.deepEqual(find('duplicate-aliases').expected, [{a: 0}, {a: 11}, {a: 12}]);
  assert.ok(find('duplicate-aliases').text.includes('id AS v, -id AS `V`, id + 10'));
  assert.deepEqual(find('quoted-repeated-limit').expected, [{a: -1}, {a: 0}]);
  assert.deepEqual(find('analytic').expected, [{a: 0}, {a: 2}]);
  assert.deepEqual(find('distinct').sourceRows.map(x => x.id), [2, 2, 1]);
  assert.deepEqual(find('distinct').expected, find('source-scalar').expected);
  assert.deepEqual(find('nullable').expected, [{a: -10}, {a: 0}, {a: null}]);
  assert.equal(find('nullable').columns[0].contract.nullable, true);
  assert.equal(find('global').columns[0].contract.nullable, true);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.equal(find('typed-empty').columns[0].contract.nullable, false);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const steps = positionalExclusionProgram.stages[0].steps;
  assert.deepEqual(steps[1].derive, {neg: {negate: {field: 'x'}}});
  assert.deepEqual(steps.slice(2, 5).map(x => x.select), [[{kept: 'x'}, 'neg'], ['neg'], [{a: 'neg'}]]);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-exclusion-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional replacement preserves snapshots anonymous values and column types', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-replacement-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 10);
  assert.deepEqual(find('source-scalar').expected, [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}]);
  assert.deepEqual(find('quoted-chain-limit').expected, [{a: 0, b: 0}, {a: 12, b: -2}]);
  assert.ok(find('simultaneous').text.includes('second AS first, first AS second'));
  assert.deepEqual(find('simultaneous').expected, [{a: 0, b: 0, c: 0}, {a: 10, b: 1, c: -1}, {a: 20, b: 2, c: -2}]);
  assert.deepEqual(find('simultaneous').columns.map(x => [x.name, x.contract.nullable]), [['a', true], ['b', false], ['c', false]]);
  assert.deepEqual(find('retained-duplicates').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 12}, {a: 2, b: -2, c: 13}]);
  assert.deepEqual(find('distinct').expected, [{a: 0, b: -2}, {a: 0, b: -1}, {a: 0, b: 0}]);
  assert.deepEqual(find('distinct').sourceRows.map(x => x.id), [2, 2, 1]);
  assert.deepEqual(find('nullable').expected, [{a: 0, b: 0}, {a: 11, b: -10}, {a: 12, b: null}]);
  assert.equal(find('nullable').columns[1].contract.nullable, true);
  assert.equal(Buffer.byteLength('anchor', 'utf8'), 6);
  assert.equal(Buffer.byteLength('changed', 'utf8'), 7);
  assert.deepEqual(find('value-type').columns[0], {name: 'a', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}});
  assert.deepEqual(find('value-type').expected, [{a: 'anchor', b: 0}, {a: 'changed', b: -2}, {a: 'changed', b: -1}]);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.deepEqual(find('typed-empty').columns.map(x => x.contract.nullable), [false, false]);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const steps = positionalReplacementProgram.stages[0].steps;
  assert.deepEqual(steps[1].derive, {neg: {negate: {field: 'x'}}});
  assert.deepEqual(steps[3].derive, {changed: {add: [{field: 'kept'}, {literal: 10}]}});
  assert.deepEqual(steps.slice(4, 6).map(x => x.select), [[{kept: 'changed'}, 'neg'], [{a: 'kept'}, {b: 'neg'}]]);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-replacement-'));
  assert.equal(refusals.length, 8);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('window replacement uses current names with opposing keys and retained anonymous values', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-analytic-replacement-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 6);
  assert.deepEqual(find('source').expected, [{a: 0, b: 0}, {a: 1, b: -2}, {a: 2, b: -1}]);
  assert.deepEqual(find('expression').expected, [{a: 0, b: 0}, {a: 6, b: -2}, {a: 7, b: -1}]);
  assert.deepEqual(find('named-window-filter').expected, [{a: 0, b: 0}, {a: 2, b: -1}]);
  assert.deepEqual(find('opposing-windows').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: 2, c: -2}, {a: 2, b: 1, c: -1}]);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.ok(normals.every(x => x.columns.every(column => column.contract.type === 'number' && !column.contract.nullable)));
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  assert.deepEqual(positionalWindowReplacementProgram.stages[0].steps[3].analytic,
    {partition_by: [], order_by: [{field: 'kept', dir: 'desc', nulls: 'last'}], functions: {rank: {fn: 'row_number'}}});
  assert.deepEqual(positionalWindowReplacementProgram.stages[0].steps[4].select, [{a: 'rank'}, {b: 'neg'}]);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-analytic-replacement-'));
  assert.equal(refusals.length, 3);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional SET retains pre-assignment values, nullability and private scope', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-set-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 8);
  assert.deepEqual(JSON.parse(find('json-control').text), positionalReplacementProgram);
  assert.deepEqual(find('source').expected, [{a: 0, b: 0}, {a: 11, b: -1}, {a: 12, b: -2}]);
  assert.deepEqual(find('current-expression-limit').expected, [{a: -1, b: -1}, {a: 0, b: 0}]);
  assert.ok(find('current-expression-limit').text.includes('SET id = -id |> ORDER BY -id |> LIMIT 1'));
  assert.deepEqual(find('quoted-chain-limit').expected, [{a: 0, b: 0}, {a: 12, b: -2}]);
  assert.ok(find('simultaneous').text.includes('SET first = second, second = first'));
  assert.deepEqual(find('simultaneous').expected, [{a: 0, b: 0, c: 0}, {a: 10, b: 1, c: -1}, {a: 20, b: 2, c: -2}]);
  assert.deepEqual(find('simultaneous').columns.map(x => [x.name, x.contract.nullable]), [['a', true], ['b', false], ['c', false]]);
  assert.deepEqual(find('retained-duplicates').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 12}, {a: 2, b: -2, c: 13}]);
  assert.deepEqual(find('nullable').expected, [{a: 0, b: 0}, {a: 11, b: -10}, {a: 12, b: null}]);
  assert.equal(find('nullable').columns[1].contract.nullable, true);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-set-'));
  assert.equal(refusals.length, 7);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional DROP removes authored duplicates and retains unnamed values and current scope', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-drop-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 8);
  assert.deepEqual(JSON.parse(find('json-control').text), positionalDropProgram);
  const steps = positionalDropProgram.stages[0].steps;
  assert.deepEqual(steps[3], {drop: ['removed']});
  assert.deepEqual(steps[4], {select: [{a: 'kept'}, {b: 'neg'}], as: 'right'});
  assert.deepEqual(find('source').expected, [{a: 0, b: 0}, {a: 1, b: -1}, {a: 2, b: -2}]);
  assert.deepEqual(find('duplicates-removed').expected, [{a: 0}, {a: 11}, {a: 12}]);
  assert.deepEqual(find('duplicates-retained').expected, find('source').expected);
  assert.ok(find('duplicates-removed').text.includes('DROP `v`'));
  assert.deepEqual(find('chain-ordinal-limit').expected, [{a: -1}, {a: 0}]);
  assert.ok(find('chain-ordinal-limit').text.includes('ORDER BY 1 DESC |> LIMIT 1'));
  assert.deepEqual(find('filter-expression-limit').expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.ok(find('filter-expression-limit').text.includes('WHERE kept > 1 |> ORDER BY -kept |> LIMIT 1'));
  assert.deepEqual(find('nullable').expected, [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: null}]);
  assert.equal(find('nullable').columns[1].contract.nullable, true);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-drop-'));
  assert.equal(refusals.length, 7);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional RENAME preserves values while changing current authored lookup', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-rename-'));
  const find = name => normals.find(x => x.name.endsWith('-' + name));
  assert.equal(normals.length, 10);
  assert.deepEqual(JSON.parse(find('json-control').text), positionalRenameProgram);
  assert.deepEqual(positionalRenameProgram.stages[0].steps[3], {select: [{renamed: 'kept'}, 'neg']});
  assert.deepEqual(positionalRenameProgram.stages[0].steps[4], {select: [{a: 'renamed'}, {b: 'neg'}], as: 'right'});
  assert.deepEqual(find('source').expected, [{a: 0, b: 0}, {a: 1, b: -1}, {a: 2, b: -2}]);
  assert.deepEqual(find('current-expression-limit').expected, [{a: -1, b: 11}, {a: 0, b: 0}]);
  assert.ok(find('current-expression-limit').text.includes('RENAME kept AS id |> WHERE id < 0 |> ORDER BY -id |> LIMIT 1'));
  assert.deepEqual(find('quoted-chain').expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.deepEqual(find('introduced-duplicates').expected, [{a: 0, b: 0, c: 0}, {a: 2, b: 20, c: -2}]);
  assert.deepEqual(find('introduced-duplicates').columns.map(x => [x.name, x.contract.nullable]), [['a', false], ['b', true], ['c', false]]);
  assert.deepEqual(find('private-shaped-anonymous-destination').expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.ok(find('private-shaped-anonymous-destination').text.includes('RENAME kept AS `AQL_SET_ANONYMOUS_4`'));
  assert.deepEqual(find('private-shaped-duplicate-destination').expected, [{a: 0, b: 0, c: 0}, {a: 2, b: -2, c: 12}]);
  assert.ok(find('private-shaped-duplicate-destination').text.includes('RENAME kept AS `AQL_SET_DUPLICATE_5`'));
  assert.deepEqual(find('introduced-duplicates-drop').expected, [{a: -2}, {a: -1}, {a: 0}]);
  assert.deepEqual(find('nullable').expected, [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: null}]);
  assert.equal(find('nullable').columns[1].contract.nullable, true);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-rename-'));
  assert.equal(refusals.length, 10);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('pure Pipe tails retain ordinal values and only expose authored range names', () => {
  const normals = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pure-tail-'));
  const find = name => normals.find(x => x.name === 'set-corresponding-positional-pure-tail-' + name);
  assert.equal(normals.length, 14);
  assert.deepEqual(JSON.parse(find('extend-json-control').text), positionalExtendProgram);
  assert.deepEqual(JSON.parse(find('as-json-control').text), positionalAsProgram);
  assert.deepEqual(positionalExtendProgram.stages[0].steps[3], {derive: {extra: {add: [{field: 'kept'}, {literal: 10}]}}});
  assert.deepEqual(positionalAsProgram.stages[0].steps[3], {filter: {gt: [{field: 'kept'}, {literal: 1}]}});
  assert.deepEqual(find('extend-source').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 11}, {a: 2, b: -2, c: 12}]);
  assert.deepEqual(find('as-source').expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.deepEqual(find('extend-current-parameter-limit').expected, [{a: -1, b: 11, c: 9}, {a: 0, b: 0, c: 0}]);
  assert.deepEqual(find('extend-current-parameter-limit').parameterDeclarations, {bump: {type: 'number', nullable: false}});
  assert.deepEqual(find('extend-current-parameter-limit').parameters, {bump: 10});
  assert.ok(find('extend-current-parameter-limit').text.includes('ORDER BY -kept |> LIMIT 1'));
  assert.deepEqual(find('extend-siblings').expected, [{a: 0, b: 0, c: 0, d: 0}, {a: 1, b: -1, c: 2, d: 11}, {a: 2, b: -2, c: 3, d: 12}]);
  assert.deepEqual(find('extend-private-shaped-anonymous-destination').expected, [{a: 0, b: 0, c: 0}, {a: 2, b: -2, c: 12}]);
  assert.deepEqual(find('extend-private-shaped-duplicate-destination').expected, [{a: 0, b: 0, c: 0, d: 0}, {a: 2, b: -2, c: 12, d: 13}]);
  assert.deepEqual(find('as-immutable-set').expected, [{a: 0, b: 0}, {a: 12, b: -2}]);
  assert.ok(find('as-immutable-set').text.includes('SET kept = kept + 10 |> WHERE r.kept = 2'));
  assert.deepEqual(find('as-quoted-rebind').expected, find('as-source').expected);
  assert.deepEqual(find('as-private-shaped-authored-column').expected, find('as-source').expected);
  assert.deepEqual(find('extend-window').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -1, c: 2}, {a: 2, b: -2, c: 1}]);
  assert.deepEqual(find('nullable').expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 11}, {a: 2, b: null, c: 12}]);
  assert.deepEqual(find('nullable').columns.map(x => [x.name, x.contract.nullable]), [['a', false], ['b', true], ['c', false]]);
  assert.deepEqual(find('typed-empty').expected, []);
  assert.ok(normals.every(x => x.sourceReadSessionCount === (x.format === 'json' ? 0 : 1)));
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pure-tail-'));
  assert.equal(refusals.length, 15);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional ORDER windows retain named snapshots without publishing hidden keys', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-order-window-'));
  assert.equal(cases.length, 8);
  const source = cases.find(x => x.name.endsWith('-source'));
  assert.deepEqual(source.expected, [{a: 0, b: 0}, {a: 2, b: -2}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-immutable-range')).expected, [{a: -2, b: -2}, {a: 0, b: 0}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-nullable')).columns,
    [{name: 'a', contract: {type: 'number', nullable: false}}, {name: 'b', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  const limited = cases.find(x => x.name.endsWith('-scalar-parameter-offset'));
  assert.deepEqual(limited.parameters, {shift: 10});
  assert.ok(limited.text.includes('LIMIT 1 OFFSET 1'));
  assert.ok(limited.text.includes('ORDER BY kept) + @shift DESC'));
  const steps = positionalOrderWindowProgram.stages[0].steps;
  assert.deepEqual(steps[3].analytic.order_by, [{field: 'kept', dir: 'desc', nulls: 'last'}]);
  assert.deepEqual(steps[5].take, {count: 1, offset: 0});
  assert.deepEqual(steps[6].select, [{a: 'kept'}, {b: 'neg'}]);
  assert.deepEqual(positionalOrderWindowProgram.stages[0].results.rows.fields, ['a', 'b']);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-order-window-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional DISTINCT compares anonymous values and preserves later DROP multiplicity', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-distinct-'));
  assert.equal(cases.length, 9);
  const source = cases.find(x => x.name.endsWith('-anonymous-source'));
  assert.deepEqual(source.sourceRows, [{id: 1, amount: 10}, {id: 1, amount: 20}, {id: 1, amount: 10}]);
  assert.deepEqual(source.expected, [{a: 0, b: 0}, {a: 1, b: -20}, {a: 1, b: -10}]);
  assert.deepEqual(source.columns, [{name: 'a', contract: {type: 'number', nullable: false}},
    {name: 'b', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-displaced-value-not-an-equality-key')).expected,
    [{a: 0, b: 0}, {a: 1, b: -10}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-drop-keeps-result-multiplicity')).expected,
    [{a: 0}, {a: 11}, {a: 11}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-nullable')).expected,
    [{a: 0, b: 0}, {a: 1, b: -10}, {a: 1, b: null}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  const limited = cases.find(x => x.name.endsWith('-parameter-order-limit'));
  assert.deepEqual(limited.parameters, {min: 0, skip: 1});
  assert.ok(limited.text.includes('ORDER BY -kept, 2 ASC NULLS LAST'));
  assert.ok(limited.text.includes('LIMIT 1 OFFSET @skip'));
  assert.deepEqual(positionalDistinctProgram.stages[0].steps[3].distinct, ['kept', 'neg']);
  assert.deepEqual(positionalDistinctProgram.stages[0].steps[4].select, [{a: 'kept'}, {b: 'neg'}]);
  assert.deepEqual(positionalDistinctProgram.stages[0].steps[0].values.schema.y,
    {type: 'number', nullable: true});
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-distinct-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional UNNEST preserves anonymous occurrences, child multiplicity and immutable range values', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-unnest-'));
  assert.equal(cases.length, 12);
  const source = cases.find(x => x.name.endsWith('-anonymous-source'));
  assert.deepEqual(source.sourceRows, [{id: 1, amount: 10}, {id: 2, amount: 20}]);
  assert.deepEqual(source.expected, [{a: 0, b: 0, c: 0}, {a: 1, b: -10, c: 10},
    {a: 1, b: -10, c: 20}, {a: 2, b: -20, c: 10}, {a: 2, b: -20, c: 20}]);
  assert.deepEqual(source.columns, [{name: 'a', contract: {type: 'number', nullable: false}},
    {name: 'b', contract: {type: 'number', nullable: true}}, {name: 'c', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-immutable-range')).expected,
    [{a: 0, b: 0, c: 0}, {a: 7, b: -20, c: 2}, {a: 7, b: -10, c: 1}]);
  const duplicate = cases.find(x => x.name.endsWith('-duplicate-elements'));
  assert.deepEqual(duplicate.expected.slice(1, 3), [{a: 1, b: -10, c: 10}, {a: 1, b: -10, c: 10}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  assert.ok(cases.find(x => x.name.endsWith('-private-shaped-element')).text.includes('AS aql_set_anonymous_4'));
  assert.ok(cases.find(x => x.name.endsWith('-private-shaped-offset')).text.includes('WITH OFFSET aql_set_duplicate_2'));
  assert.deepEqual(positionalUnnestProgram.stages[0].steps[4].unnest, {column: 'items', as: 'element'});
  assert.deepEqual(positionalUnnestProgram.stages[0].steps[5].select, [{a: 'kept'}, {b: 'neg'}, {c: 'element'}]);
  assert.deepEqual(positionalUnnestProgram.stages[0].steps[0].values.schema.y, {type: 'number', nullable: true});
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-unnest-'));
  assert.equal(refusals.length, 7);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});

test('positional UNPIVOT retains anonymous values, generated current labels and repeated-row multiplicity', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-unpivot-'));
  assert.equal(cases.length, 9);
  const source = cases.find(x => x.name.endsWith('-anonymous-source'));
  assert.deepEqual(source.expected, [{a: -20, b: 2, c: 'kept'}, {a: -10, b: 1, c: 'kept'}, {a: 0, b: 0, c: 'anchor'}]);
  assert.deepEqual(source.columns, [{name: 'a', contract: {type: 'number', nullable: true}},
    {name: 'b', contract: {type: 'number', nullable: false}}, {name: 'c', contract: {type: 'string', nullable: false}}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-current-renamed-label')).expected,
    [{a: -20, b: 7, c: 'renamed'}, {a: -10, b: 7, c: 'renamed'}, {a: 0, b: 0, c: 'anchor'}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-repeated-selected-column')).expected.slice(0,2),
    [{a: -20, b: 2, c: 'kept'}, {a: -20, b: 2, c: 'kept'}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  assert.ok(cases.find(x => x.name.endsWith('-private-shaped-destination')).text.includes('INCLUDE NULLS(aql_set_anonymous_4'));
  assert.deepEqual(positionalUnpivotProgram.stages[0].steps[3].unpivot,
    {columns: ['kept'], keep: ['neg'], value_column: 'value', name_column: 'label'});
  assert.deepEqual(positionalUnpivotProgram.stages[0].steps[4].select, [{a: 'neg'}, {b: 'value'}, {c: 'label'}]);
  assert.deepEqual(positionalUnpivotProgram.stages[0].steps[0].values.schema.y, {type: 'number', nullable: true});
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-unpivot-'));
  assert.equal(refusals.length, 5);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('UNPIVOT generated-name collisions keep old and new values as separate positional occurrences', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-unpivot-name-collision-'));
  assert.equal(cases.length, 9);
  const source = cases.find(x => x.name.endsWith('-value-column'));
  assert.deepEqual(source.expected, [{a: 0, b: 0, c: 0, d: 'anchor'},
    {a: 10, b: -10, c: 1, d: 'kept'}, {a: 20, b: -20, c: 2, d: 'kept'}]);
  assert.notEqual(source.expected[1].a, source.expected[1].c);
  const labelCollision = cases.find(x => x.name.endsWith('-name-column'));
  assert.deepEqual(labelCollision.columns[0], {name: 'a', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}});
  assert.equal(Buffer.byteLength('anchor', 'utf8'), 6);
  assert.equal(Buffer.byteLength('user', 'utf8'), 4);
  assert.deepEqual(cases.find(x => x.name.endsWith('-immutable-star')).expected, source.expected);
  assert.ok(cases.find(x => x.name.endsWith('-immutable-star')).text.includes("SET label = 'changed'"));
  assert.deepEqual(cases.find(x => x.name.endsWith('-distinct-complete-row')).expected,
    [{a: 0, b: 0, c: 0, d: 'anchor'}, {a: 10, b: -10, c: 1, d: 'kept'}, {a: 10, b: -10, c: 2, d: 'kept'}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-drop-all-matching-occurrences')).expected,
    [{a: -20, b: 'kept'}, {a: -10, b: 'kept'}, {a: 0, b: 'anchor'}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  assert.deepEqual(positionalUnpivotCollisionProgram.stages[0].steps[3].unpivot,
    {columns: ['kept'], keep: ['extra', 'neg'], value_column: 'expanded', name_column: 'label'});
  assert.deepEqual(positionalUnpivotCollisionProgram.stages[0].steps[4].select,
    [{a: 'extra'}, {b: 'neg'}, {c: 'expanded'}, {d: 'label'}]);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-unpivot-name-collision-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});


test('positional ASSERT retains values and validates explicit current/range keys through the common Owner', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-assert-'));
  assert.equal(cases.length, 9);
  const source = cases.find(x => x.name.endsWith('-anonymous-source'));
  assert.deepEqual(source.sourceRows, [{id: 1, amount: 10}, {id: 2, amount: 20}]);
  assert.deepEqual(source.expected, [{a: 0, b: 0}, {a: 1, b: -10}, {a: 2, b: -20}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-immutable-key')).expected,
    [{a: 0, b: 0}, {a: 7, b: -20}, {a: 7, b: -10}]);
  assert.ok(cases.find(x => x.name.endsWith('-immutable-key')).text.includes('ASSERT UNIQUE BY(r.kept)'));
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty')).expected, []);
  assert.deepEqual(cases.find(x => x.name.endsWith('-parameter-filter-limit')).parameters, {min: 0});
  assert.deepEqual(positionalAssertProgram.stages[0].steps[3].assert_rows, {unique_by: ['kept']});
  assert.deepEqual(positionalAssertProgram.stages[0].steps[0].values.schema.y, {type: 'number', nullable: true});
  assert.deepEqual(positionalAssertProgram.stages[0].steps[4].select, [{a: 'kept'}, {b: 'neg'}]);
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-assert-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(setCorrespondingExecutionFailures.length, 2);
  assert.deepEqual(setCorrespondingExecutionFailures[1].sourceRows, [{id: 1, amount: 10}, {id: 1, amount: 20}]);
  assert.deepEqual(setCorrespondingExecutionFailures.map(x => x.resultNames), [['answer'], ['main']]);
  const packed = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('executionFailures: setCorrespondingExecutionFailures'));
  assert.ok(packed.includes('scopeInputs.executionFailures.push(...setCorrespondingExecutionFailures)'));
});


test('positional PIVOT keeps anonymous group keys, immutable receivers and authored bucket order', () => {
  const cases = setCorrespondingSuccesses.filter(x => x.name.startsWith('set-corresponding-positional-pipe-pivot-'));
  assert.equal(cases.length, 9);
  const source = cases.find(x => x.name.endsWith('-anonymous-group'));
  assert.deepEqual(source.expected, [{a: -20, b: 2}, {a: -10, b: 4}, {a: 0, b: 0}]);
  assert.deepEqual(source.columns, [{name: 'a', contract: {type: 'number', nullable: true}},
    {name: 'b', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-immutable-aggregate-current-key')).expected,
    [{a: 0, b: 0, c: 0}, {a: 7, b: -20, c: 2}, {a: 7, b: -10, c: 4}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-current-aggregate')).expected,
    [{a: -20, b: 7}, {a: -10, b: 14}, {a: 0, b: 0}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-bucket-declaration-order')).expected,
    [{a: -20, b: 0, c: 1}, {a: -10, b: 0, c: 2}, {a: 0, b: 0, c: 0}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-nullable-group-key')).expected,
    [{a: 0, b: 0}, {a: null, b: 1}]);
  assert.deepEqual(cases.find(x => x.name.endsWith('-typed-empty-keyed')).expected, []);
  assert.deepEqual(positionalPivotProgram.stages[0].steps[3].pivot,
    {index: ['neg'], column: 'axis', value: 'amount', values: ['A'], aggregate: 'sum'});
  assert.deepEqual(positionalPivotProgram.stages[0].steps[4].select, [{a: 'neg'}, {b: 'A'}]);
  assert.deepEqual(positionalPivotProgram.stages[0].steps[0].values.schema.y, {type: 'number', nullable: true});
  const refusals = setCorrespondingRefusals.filter(x => x.name.startsWith('set-corresponding-refuse-pipe-pivot-'));
  assert.equal(refusals.length, 7);
  assert.ok(refusals.every(x => x.expectedCode === 'ClientProgramInvalidInput'));
});

// Previous authored bytes preserve all independent expectations and controls.
test('WITH set cutover preserves full independent fixture inventories and JSON bytes', async () => {
  const retained = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/with-set-current-original-callers.json', import.meta.url), 'utf8'));
  for (const name of ['set-by-name-list', 'set-inner-by-name', 'set-corresponding']) {
    const file = 'scripts/fixtures/' + name + '-source-input.mjs';
    const old = await import('data:text/javascript;base64,' + Buffer.from(retained.files[file].text).toString('base64'));
    const current = await import(new URL('./fixtures/' + name + '-source-input.mjs', import.meta.url));
    assert.deepEqual(Object.keys(current), Object.keys(old));
    for (const key of Object.keys(current)) {
      if (!Array.isArray(current[key])) {
        assert.deepEqual(current[key], old[key]);
        continue;
      }
      const retainedMetadata = old[key].map(({text, ...item}) =>
        name === 'set-corresponding' && key === 'setCorrespondingExecutionFailures' &&
          item.name === 'set-corresponding-positional-assert-duplicate-source'
          ? {...item, resultNames: ['main']} : item);
      assert.deepEqual(current[key].map(({text, ...item}) => item), retainedMetadata);
      for (let index = 0; index < current[key].length; index++) {
        const before = old[key][index];
        const after = current[key][index];
        if (before.format === 'json') assert.equal(after.text, before.text);
        if (/\bDATA\b/.test(before.text ?? '')) {
          assert.match(after.text, /^WITH /);
          assert.doesNotMatch(after.text, /\bDATA\b/);
        } else assert.equal(after.text, before.text);
      }
    }
  }
});

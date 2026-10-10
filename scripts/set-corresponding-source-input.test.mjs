import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setCorrespondingSuccesses, setCorrespondingRefusals, setCorrespondingProgram, positionalAggregateProgram, positionalWindowProgram, positionalOrderLimitProgram, positionalStarProgram, positionalFilterProgram, positionalExclusionProgram, positionalReplacementProgram, positionalWindowReplacementProgram} from './fixtures/set-corresponding-source-input.mjs';

test('CORRESPONDING matching has independent row, type, scope and multiplicity controls', () => {
  assert.equal(setCorrespondingSuccesses.length, 91);
  assert.equal(setCorrespondingRefusals.length, 51);
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
  for (const item of setCorrespondingRefusals.filter(x => x.name.includes('-window-'))) {
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
  assert.ok(corpus.includes('setCorrespondingOnly ? {successes: [...setCorrespondingSuccesses, ...setJoinSuccesses], refusals: [...setCorrespondingRefusals, ...setJoinRefusals]}'));
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
  assert.deepEqual(find('value-type').columns[0], {name: 'a', contract: {type: 'string', nullable: false}});
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

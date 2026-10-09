import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {unnestSuccesses, unnestRefusals, unnestReceiverProgram,
  unnestReceiverSuccesses, unnestReceiverRefusals} from './fixtures/unnest-source-input.mjs';

test('OFFSET keeps its range until ordinary projection or a whole-column edit', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-offset-rename-json-control');
  assert.deepEqual(JSON.parse(control.text).stages[0].steps.at(-1).select,
    ['element', {next: 'position'}]);
  assert.deepEqual(control.expected,
    [{element: 2, next: 0}, {element: null, next: 1}, {element: 2, next: 2}]);
  for (const name of ['rename-after-select', 'rename-after-as', 'default-after-select']) {
    const actual = byName.get('unnest-offset-' + name);
    assert.equal(actual.format, 'aql-text');
    assert.deepEqual(actual.expected, control.expected);
    assert.deepEqual(actual.columns, control.columns);
  }
  assert.deepEqual(byName.get('unnest-offset-rename-after-set').expected.map(row => row.next), [10, 11, 12]);
  assert.deepEqual(byName.get('unnest-offset-rename-empty').expected, []);
  assert.deepEqual(byName.get('unnest-offset-rename-empty').columns, control.columns);
  assert.ok(byName.get('unnest-scalar-drop-removes-range').text.includes('DROP element |> SELECT position |> RENAME'));
  for (let index = 0; index < 8; index++) {
    const actual = unnestRefusals.find(item => item.name === 'unnest-refusal-offset-range-' + index);
    assert.equal(actual.format, 'aql-text');
    assert.equal(actual.expectedCode, 'ClientProgramInvalidInput');
  }
});

test('value-table ordinal fixtures distinguish physical columns from projected members', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const get = name => byName.get('unnest-struct-ordinal-' + name);
  const control = get('json-control');
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[2],
    {unnest: {column: 'array', as: 'whole', with_index: 'position'}});
  assert.deepEqual(program.stages[0].steps[4],
    {sort: [{field: 'position', dir: 'asc', nulls: 'first'}]});
  assert.deepEqual(control.expected.map(row => row.position), [0, 1, 2]);
  for (const name of ['offset-before-select', 'signed-quoted']) {
    assert.deepEqual(get(name).expected, control.expected);
    assert.deepEqual(get(name).columns, control.columns);
  }
  assert.deepEqual(get('projected-members').expected.map(row => row.position), [1, 2, 0]);
  assert.deepEqual(get('reordered-projection').columns.map(column => column.name), ['position', 'id', 'label']);
  assert.deepEqual(get('same-named-offset').expected,
    [{original: 2, position: 0}, {original: null, position: 1}, {original: 1, position: 2}]);
  assert.deepEqual(get('extend-column').expected.map(row => row.position), [2, 1, 0]);
  assert.deepEqual(get('set-offset').expected.map(row => row.position), [8, 9, 10]);
  assert.deepEqual(get('join-remapping').expected.map(row => row.position), [0, 2]);
  assert.deepEqual(get('empty-objects').expected, [{position: 1}, {position: 0}]);
  assert.deepEqual(get('null-array').expected, []);
  assert.deepEqual(get('null-array').columns, control.columns);
  for (const name of ['outside-actual-columns', 'without-offset', 'after-drop']) {
    const value = unnestRefusals.find(item => item.name === 'unnest-refusal-ordinal-' + name);
    assert.equal(value.expectedCode, 'ClientProgramImplementationLimit');
    assert.equal(value.format, 'aql-text');
  }
});

test('scalar value-table RENAME distinguishes range names from projected columns', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-scalar-rename-json-control');
  assert.deepEqual(JSON.parse(control.text).stages[0].steps.at(-1).select,
    [{next: 'element'}, 'position']);
  for (const name of ['after-select', 'after-as']) {
    const actual = byName.get('unnest-scalar-rename-' + name);
    assert.equal(actual.format, 'aql-text');
    assert.deepEqual(actual.expected, control.expected);
    assert.deepEqual(actual.columns, control.columns);
  }
  assert.deepEqual(byName.get('unnest-scalar-rename-after-set').expected.map(row => row.next), [100, 100, 100]);
  assert.deepEqual(byName.get('unnest-scalar-drop-removes-range').columns,
    [{name: 'next', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(byName.get('unnest-scalar-distinct-keeps-values').expected,
    [{next: 2}, {next: null}]);
  for (const name of ['scalar-rename-range-0', 'scalar-rename-range-1',
    'scalar-rename-range-2', 'scalar-rename-range-after-join', 'scalar-range-duplicate-unnest']) {
    assert.equal(unnestRefusals.find(item => item.name === 'unnest-refusal-' + name).format, 'aql-text');
    assert.equal(unnestRefusals.find(item => item.name === 'unnest-refusal-' + name).expectedCode,
      'ClientProgramInvalidInput');
  }
});

test('UNNEST independent fixtures preserve multiplicity, NULL and offset order on empty schemas', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  assert.deepEqual(byName.get('unnest-sql-duplicates-and-null').expected,
    [{element: 2, position: 0}, {element: null, position: 1}, {element: 2, position: 2}]);
  for (const name of ['unnest-empty', 'unnest-null-array']) {
    assert.deepEqual(byName.get(name).expected, []);
    assert.deepEqual(byName.get(name).columns, [
      {name: 'element', contract: {type: 'number', nullable: true}},
      {name: 'position', contract: {type: 'number', nullable: false}},
    ]);
  }
  const control = JSON.parse(byName.get('unnest-json-control').text);
  assert.deepEqual(control.stages[0].steps[2],
    {unnest: {column: 'array', as: 'element', with_index: 'position'}});
  assert.deepEqual(control.params.items.items, {type: 'number', nullable: true});
  assert.deepEqual(byName.get('unnest-default-offset').expected.map(row => row.offset), [2, 1, 0]);
  assert.ok(unnestRefusals.some(value => value.name === 'unnest-refusal-array-bound'));
  assert.equal(new Set([...unnestSuccesses, ...unnestRefusals].map(value => value.name)).size,
    unnestSuccesses.length + unnestRefusals.length);
});

test('ordinary packed corpus and narrow consumer both execute UNNEST source cases', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...unnestSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...unnestRefusals)'));
  assert.ok(fixture.includes('unnestOnly ? {successes: unnestSuccesses'));
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('unnestOnly'));
  assert.ok(driver.includes("['scripts/fixtures/unnest-source-input.mjs', 'unnest-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNNEST_SOURCE_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--unnest-source-only'/u);
  assert.ok(driver.includes("process.argv.includes('--unnest-source-only')) return;"));
});

test('range/field collision controls distinguish receiver NULLs and current stars', () => {
  const byName = new Map(unnestReceiverSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-receiver-json-control');
  assert.deepEqual(JSON.parse(control.text), unnestReceiverProgram);
  assert.deepEqual(unnestReceiverProgram.stages[0].steps[5].select,
    [{original: 'receiver'}, {field_value: 'member'}, 'position']);
  assert.equal(control.columns[0].contract.type, 'object');
  assert.equal(control.columns[0].contract.nullable, true);
  assert.equal(control.columns[0].contract.fields.id.nullable, false);
  assert.deepEqual(byName.get('unnest-receiver-null-predicate').expected.map(row => row.position), [0, 2, 3]);
  assert.deepEqual(control.expected[0], {original: {element: null, id: 2}, field_value: null, position: 0});
  assert.deepEqual(control.expected[1], {original: null, field_value: null, position: 1});
  assert.deepEqual(byName.get('unnest-receiver-set-retains-original').expected,
    control.expected.map(row => ({...row, position: row.position + 10})));
  assert.ok(byName.get('unnest-receiver-set-retains-original').text.includes('SET position = position + 10'));
  assert.deepEqual(byName.get('unnest-receiver-set-current-star').columns.map(value => value.name),
    ['element', 'position']);
  const star = byName.get('unnest-receiver-star');
  assert.deepEqual(star.columns.map(value => value.name), ['element', 'id', 'position']);
  assert.equal(star.columns[0].contract.type, 'number');
  assert.deepEqual(byName.get('unnest-receiver-qualified-star').expected, star.expected);
  assert.deepEqual(byName.get('unnest-receiver-set-current-star').expected.map(row => row.element), [100, 100, 100, 100]);
  for (const item of unnestReceiverSuccesses) {
    assert.ok(unnestSuccesses.includes(item));
    assert.equal(item.sourceReadCount, 0);
    assert.equal(item.sourceReadSessionCount, 0);
  }
  for (const item of unnestReceiverRefusals) {
    assert.ok(unnestRefusals.includes(item));
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
});

test('scalar stars have independent typed empty expectations and preserve the DATA source', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-json-control');
  for (const name of ['scalar-star-sql', 'scalar-star-pipe', 'scalar-star-data-binding']) {
    assert.deepEqual(byName.get('unnest-' + name).expected, control.expected);
    assert.deepEqual(byName.get('unnest-' + name).columns, control.columns);
    assert.equal(byName.get('unnest-' + name).sourceReadCount, 0);
  }
  for (const name of ['scalar-star-empty', 'scalar-star-null-array']) {
    assert.deepEqual(byName.get('unnest-' + name).expected, []);
    assert.deepEqual(byName.get('unnest-' + name).columns, control.columns);
  }
  const struct = unnestRefusals.find(value => value.name === 'unnest-refusal-struct-missing-field');
  assert.deepEqual(struct.parameters.items, []);
  assert.equal(struct.parameterDeclarations.items.items.type, 'object');
  assert.ok(unnestRefusals.some(value => value.name === 'unnest-refusal-scalar-qualified-star'));
});


test('STRUCT stars use declared fields and a distinct original value receiver', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-struct-json-control');
  assert.deepEqual(control.expected, [
    {id: 2, label: null, position: 0}, {id: null, label: null, position: 1},
    {id: 2, label: null, position: 2},
  ]);
  for (const name of ['star-sql', 'star-pipe', 'qualified-star', 'data-binding']) {
    assert.deepEqual(byName.get('unnest-struct-' + name).expected, control.expected);
    assert.deepEqual(byName.get('unnest-struct-' + name).columns, control.columns);
  }
  assert.deepEqual(control.columns.map(value => value.name), ['id', 'label', 'position']);
  assert.equal(byName.get('unnest-struct-whole-value').columns[0].contract.type, 'object');
  const nonNullString = byName.get('unnest-struct-non-null-string');
  assert.deepEqual(nonNullString.expected, [{id: 2, label: 'kept', position: 0},
    {id: null, label: null, position: 1}, {id: 2, label: null, position: 2}]);
  assert.deepEqual(nonNullString.columns, control.columns);
  assert.equal(byName.get('unnest-struct-whole-value').columns[0].contract.additional_properties, false);
  assert.equal(byName.get('unnest-struct-nested-top-level').columns[1].contract.additional_properties, false);
  assert.deepEqual(byName.get('unnest-struct-immutable-range').expected[0],
    {current: 12, original: 2, position: 0});
  assert.equal(unnestRefusals.filter(value => value.name.startsWith('unnest-refusal-struct-')).length, 4);
});


test('value-table edits preserve one column, sibling input scope and exact refusals', () => {
  const byName = new Map(unnestReceiverSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-receiver-set-json-control');
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[3], {derive: {replacement: {literal: 100}}});
  assert.deepEqual(program.stages[0].results.rows.fields, ['element', 'position']);
  assert.deepEqual(byName.get('unnest-receiver-set-current-star').expected, control.expected);
  assert.deepEqual(byName.get('unnest-receiver-set-current-star').columns, control.columns);
  assert.deepEqual(byName.get('unnest-receiver-set-quoted-whole').columns, control.columns);
  assert.deepEqual(byName.get('unnest-receiver-set-siblings-original-object').expected,
    [{element: 100, position: 1}, {element: 100, position: 1},
      {element: 100, position: 2}, {element: 100, position: null}]);
  assert.deepEqual(byName.get('unnest-receiver-set-empty-object-elements').expected,
    [{element: 100, position: 0}, {element: 100, position: 1}]);
  assert.deepEqual(byName.get('unnest-receiver-drop-whole').columns.map(column => column.name), ['position']);
  for (const name of ['set-implicit-field', 'drop-implicit-field', 'rename-implicit-field', 'set-scalar-member']) {
    assert.equal(unnestReceiverRefusals.find(item => item.name === 'unnest-receiver-refusal-' + name).expectedCode,
      'ClientProgramInvalidInput');
  }
});


test('scalar receivers distinguish elements and offsets from parent columns', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const control = byName.get('unnest-scalar-receiver-json-control');
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[4],
    {unnest: {column: 'array', as: 'element', with_index: 'position'}});
  assert.deepEqual(program.stages[0].steps.at(-1).select,
    ['element', 'original', 'position', 'original_position']);
  assert.deepEqual(control.expected.map(row => row.element), [2, null, 1]);
  assert.deepEqual(control.expected.map(row => row.position), [0, 1, 2]);
  for (const name of ['pipe', 'sql', 'quoted']) {
    const item = byName.get('unnest-scalar-receiver-' + name);
    assert.deepEqual(item.expected, control.expected);
    assert.deepEqual(item.columns, control.columns);
  }
  for (const name of ['predicate', 'computed-predicate', 'join-remapping']) {
    assert.deepEqual(byName.get('unnest-scalar-receiver-' + name).expected,
      [{element: 2, original: 100, position: 0, original_position: 50}]);
  }
  assert.deepEqual(byName.get('unnest-scalar-receiver-offset-predicate').expected,
    [{element: null, original: 100, position: 1, original_position: 50}]);
  assert.deepEqual(byName.get('unnest-scalar-receiver-receiver-order').expected.map(row => row.position), [2, 0, 1]);
  for (const name of ['empty', 'null-parent-array']) {
    const item = byName.get('unnest-scalar-receiver-' + name);
    assert.deepEqual(item.expected, []);
    assert.deepEqual(item.columns, control.columns);
  }
  for (const name of ['group-sql', 'group-pipe']) {
    assert.deepEqual(byName.get('unnest-scalar-receiver-' + name).expected,
      [{element: 1, n: 1}, {element: 2, n: 1}, {element: null, n: 1}]);
  }
  for (const item of unnestRefusals.filter(value => value.name.startsWith('unnest-refusal-scalar-receiver-'))) {
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
});


test('AS independently preserves whole values, star layouts and nullable empty schemas', () => {
  const byName = new Map(unnestSuccesses.map(value => [value.name, value]));
  const get = name => byName.get('unnest-struct-as-' + name);
  const scalar = byName.get('unnest-as-scalar-json-control');
  assert.deepEqual(JSON.parse(scalar.text).stages[0].steps[2],
    {unnest: {column: 'array', as: 'element'}});
  assert.deepEqual(byName.get('unnest-as-scalar-repeated').expected, scalar.expected);
  const control = get('whole-json-control');
  assert.deepEqual(JSON.parse(control.text).stages[0].steps.at(-1).select,
    [{original: 'element'}, 'position']);
  for (const name of ['mixed-qualified-whole', 'mixed-renamed-whole',
    'qualified-original-after-rename', 'repeated-object']) {
    assert.deepEqual(get(name).expected, control.expected);
    assert.deepEqual(get(name).columns, control.columns);
  }
  assert.deepEqual(get('single-whole').expected.map(row => row.id), [1, 2, null]);
  const star = get('star-0');
  assert.deepEqual(star.columns.map(item => item.name), ['id', 'label', 'position']);
  assert.deepEqual(get('star-1').expected, star.expected);
  assert.deepEqual(get('immutable-star-after-set').expected, star.expected);
  assert.deepEqual(get('set-whole-current-star').columns.map(item => item.name), ['element', 'position']);
  assert.deepEqual(get('qualified-star-after-join').expected, [star.expected[0]]);
  for (const name of ['typed-empty', 'typed-null-array']) {
    assert.deepEqual(get(name).expected, []);
    assert.deepEqual(get(name).columns, control.columns);
  }
  assert.deepEqual(get('empty-objects').expected, [{original: {}, position: 0}, {original: null, position: 1}]);
  assert.equal(get('empty-objects').columns[0].contract.nullable, true);
  assert.deepEqual(get('empty-objects').columns[0].contract.fields, {});
  for (const name of ['single-rename-range', 'implicit-member-edit', 'select-removed-range']) {
    assert.equal(unnestRefusals.find(item => item.name === 'unnest-refusal-as-' + name).expectedCode,
      'ClientProgramInvalidInput');
  }
});

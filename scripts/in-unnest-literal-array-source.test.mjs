import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inUnnestLiteralArraySuccesses, inUnnestLiteralArrayRefusals, inUnnestLiteralArrayExecutionFailures}
  from './fixtures/in-unnest-literal-array-source-input.mjs';

test('SQL signed zero membership preserves its canonical-zero success and independent oracle', () => {
  const name = 'in-unnest-literal-array-negative-zero';
  const fixture = inUnnestLiteralArraySuccesses.find(value => value.name === name);
  assert.ok(fixture, 'signed SQL zero follows the existing numeric normalization rule');
  assert.equal(fixture.text, 'SELECT 2 IN UNNEST([-(0)]) AS found');
  assert.equal(fixture.format, 'sql');
  assert.deepEqual(fixture.expected, [{found: false}]);
  assert.deepEqual(fixture.columns, [{name: 'found', contract: {type: 'boolean', nullable: false}}]);
  assert.deepEqual(fixture.results, {main: {rows: [{found: false}], columns: fixture.columns}});
  assert.equal(fixture.sourceReadCount, 0);
  assert.equal(fixture.sourceReadSessionCount, 0);
  assert.ok(!inUnnestLiteralArrayRefusals.some(value => value.name === name));
  for (const suffix of ['annotation-not-erased', 'mixed-types', 'undeclared',
    'wrong-parameter-value', 'nonfinite']) {
    assert.ok(inUnnestLiteralArrayRefusals.some(value =>
      value.name === 'in-unnest-literal-array-' + suffix), suffix);
  }
});

test('literal membership controls distinguish matching, unknown and empty sets', () => {
  const cases = new Map(inUnnestLiteralArraySuccesses.map(value => [value.name, value]));
  const control = cases.get('in-unnest-literal-array-json-control');
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[1].derive, {
    included: {in: [{literal: 2}, {literal: [null, 2, 2]}]},
    excluded: {not_in: [{literal: 2}, {literal: [null, 2, 2]}]},
    unknown: {in: [{literal: 1}, {literal: [2, null, {$param: 'p'}]}]},
    null_left: {not_in: [{cast: {value: {literal: null}, target: {type: 'number'}}},
      {literal: [2, 3]}]},
  });
  assert.deepEqual(control.expected,
    [{included: true, excluded: false, unknown: null, null_left: null}]);
  assert.deepEqual(program.stages[0].results.rows.fields,
    control.columns.map(column => column.name));
  assert.deepEqual(cases.get('in-unnest-literal-array-empty-set-with-null-left').expected,
    [{included: false, excluded: true}]);
  assert.ok(cases.get('in-unnest-literal-array-empty-set-with-null-left').columns
    .every(column => column.contract.nullable === false));
  assert.deepEqual(cases.get('in-unnest-literal-array-empty-input').expected, []);
  const source = cases.get('in-unnest-literal-array-where-source-once');
  assert.deepEqual(source.expected, [{id: 2}, {id: 3}, {id: 3}]);
  assert.equal(source.sourceReadCount, 1);
  assert.equal(source.sourceReadSessionCount, 1);
  const all = [...inUnnestLiteralArraySuccesses, ...inUnnestLiteralArrayRefusals, ...inUnnestLiteralArrayExecutionFailures];
  assert.equal(inUnnestLiteralArraySuccesses.length, 26);
  assert.equal(inUnnestLiteralArrayRefusals.length, 12);
  assert.equal(inUnnestLiteralArrayExecutionFailures.length, 1);
  assert.equal(new Set(all.map(value => value.name)).size, all.length);
});

test('normal packed acceptance and its narrow selector register the same literal membership corpus', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'inUnnestLiteralArraySuccesses'],
    ['refusals', 'inUnnestLiteralArrayRefusals'], ['executionFailures', 'inUnnestLiteralArrayExecutionFailures']]) {
    const registration = `scopeInputs.${kind}.push(...${group})`;
    assert.equal(fixture.split(registration).length - 1, 1);
  }
  assert.match(fixture, /const scopeOnly = [^;]*\binUnnestLiteralArrayOnly\b/u);
  assert.ok(fixture.includes('inUnnestLiteralArrayOnly ? {successes: inUnnestLiteralArraySuccesses'));
  assert.ok(fixture.includes(': arrayLiteralOnly ? {successes: arrayLiteralSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_IN_UNNEST_LITERAL_ARRAY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/in-unnest-literal-array-source-input.mjs', 'in-unnest-literal-array-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--in-unnest-literal-array-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--in-unnest-literal-array-only')) return;"));
});

// These are authored public-boundary expectations, not observed runtime output.
test('general ARRAY membership corpus fixes field, conditional and lazy results', () => {
  const cases = new Map(inUnnestLiteralArraySuccesses.map(value => [value.name, value]));
  for (const name of ['array-field', 'conditional-array', 'lazy-array-branch']) {
    const value = cases.get('in-unnest-literal-array-' + name);
    assert.deepEqual(value.expected, [{included: true}]);
    assert.deepEqual(value.columns, [{name: 'included', contract: {type: 'boolean', nullable: false}}]);
    assert.equal(value.sourceReadCount, 0);
    assert.equal(value.sourceReadSessionCount, 0);
  }
  for (const name of ['array-field', 'conditional-array']) {
    const value = cases.get('in-unnest-literal-array-' + name);
    assert.deepEqual(value.parameters, {xs: [2], ys: [7]});
    assert.deepEqual(value.parameterDeclarations, {
      xs: {type: 'array', nullable: false, max_items: 2, items: {type: 'number', nullable: false}},
      ys: {type: 'array', nullable: false, max_items: 2, items: {type: 'number', nullable: false}},
    });
  }
  assert.deepEqual(cases.get('in-unnest-literal-array-general-element').expected, [{found: true}]);
  assert.ok(!inUnnestLiteralArrayRefusals.some(value => value.name.endsWith('-general-element')));
});

test('active membership corpus retains exact public and explicitly authored Result names', () => {
  for (const item of inUnnestLiteralArraySuccesses) {
    if (item.format === 'json') {
      assert.deepEqual(Object.keys(JSON.parse(item.text).results), ['answer']);
      assert.equal(item.results, undefined);
    } else {
      const name = item.name === 'in-unnest-literal-array-pipe-signed-atoms' ? 'answer' : 'main';
      assert.deepEqual(item.results, {[name]: {rows: item.expected, columns: item.columns}}, item.name);
    }
  }
  assert.deepEqual(inUnnestLiteralArrayExecutionFailures[0].resultNames, ['main']);
});

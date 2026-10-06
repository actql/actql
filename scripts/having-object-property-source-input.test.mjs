import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {havingObjectPropertyProgram, havingObjectPropertySuccesses,
  havingObjectPropertyRefusals, havingObjectPropertyExecutionFailures}
  from './fixtures/having-object-property-source-input.mjs';

test('HAVING object fixtures keep NULL, multiplicity and resolved alias meanings', () => {
  const cases = new Map(havingObjectPropertySuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('having-object-property-computed-alias').expected.map(row => [row.id, row.n]), [[1, 1], [3, 2]]);
  assert.deepEqual(cases.get('having-object-property-null-receiver').expected, []);
  assert.deepEqual(cases.get('having-object-property-null-field').expected, []);
  assert.deepEqual(cases.get('having-object-property-empty-input').columns,
    cases.get('having-object-property-computed-alias').columns);
  assert.deepEqual(cases.get('having-object-property-alias-input-collision').expected.map(row => row.original_id), [1]);
  assert.deepEqual(cases.get('having-object-property-qualified-input-control').expected.map(row => row.original_id), [2, 3]);
  const control = JSON.parse(cases.get('having-object-property-independent-json').text);
  assert.deepEqual(control, havingObjectPropertyProgram);
  assert.deepEqual(control.stages[1].steps[0].group, {by: ['id'], aggregates: {n: {fn: 'count'}}});
  assert.deepEqual(control.stages[1].steps[2].filter, {gt: [{property: {value: {field: 'assessment'}, name: 'score'}}, {literal: 10}]});
});

test('HAVING object regressions run in the ordinary packed corpus and focused selection', async () => {
  const all = [...havingObjectPropertySuccesses, ...havingObjectPropertyRefusals,
    ...havingObjectPropertyExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'havingObjectPropertySuccesses'],
    ['refusals', 'havingObjectPropertyRefusals'], ['executionFailures', 'havingObjectPropertyExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.ok(fixture.includes('havingObjectPropertyOnly ? {successes: havingObjectPropertySuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_HAVING_OBJECT_PROPERTY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/having-object-property-source-input.mjs', 'having-object-property-source-input.mjs']"));
  assert.ok(driver.includes("if (process.argv.includes('--having-object-property-only')) return;"));
});

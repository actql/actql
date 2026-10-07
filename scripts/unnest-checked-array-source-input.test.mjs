import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {unnestCheckedArraySuccesses as successes, unnestCheckedArrayRefusals as refusals,
  unnestCheckedArrayPrograms as programs} from './fixtures/unnest-checked-array-source-input.mjs';
import {unnestSuccesses, unnestRefusals} from './fixtures/unnest-source-input.mjs';

test('checked ARRAY controls retain empty schema and NULL elements independently of source output', () => {
  const byName = new Map(successes.map(item => [item.name, item]));
  const named = name => byName.get('unnest-checked-array-' + name);
  assert.deepEqual(JSON.parse(named('numeric-json').text), programs.numeric);
  assert.deepEqual(named('numeric-sql').expected, [
    {element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}]);
  assert.deepEqual(programs.empty.stages[0].steps[1].derive.array,
    {empty_array: {items: {type: 'string', nullable: false}}});
  assert.deepEqual(named('empty-sql').columns, [
    {name: 'element', contract: {type: 'string', nullable: false}},
    {name: 'position', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(named('nullable-sql').expected, [{element: null, position: 0}]);
  assert.deepEqual(programs.computed.stages[0].steps[1].derive.array,
    {if: [{literal: true}, {$param: 'items'}, {$param: 'items'}]});
  assert.deepEqual(named('computed-sql').expected, [
    {id: 2, label: 'kept', position: 0}, {id: null, label: null, position: 1},
    {id: 2, label: null, position: 2}]);
  for (const name of ['computed-empty', 'computed-null']) {
    assert.deepEqual(named(name).expected, []);
    assert.deepEqual(named(name).columns, named('computed-sql').columns);
  }
  assert.deepEqual(refusals.map(item => item.name.split('refusal-')[1]),
    ['untyped-empty', 'unresolved-null', 'mixed-types', 'declared-wrong-type', 'scalar-qualified-star']);
});

test('checked ARRAY cases are registered in the ordinary corpus and its public consumer', () => {
  for (const [cases, corpus] of [[successes, unnestSuccesses], [refusals, unnestRefusals]]) {
    for (const item of cases) assert.equal(corpus.filter(value => value.name === item.name).length, 1);
  }
  const fixture = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...unnestSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...unnestRefusals)'));
  assert.ok(fixture.includes('unnestCheckedArrayOnly ? {successes: unnestCheckedArraySuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bunnestCheckedArrayOnly\b/u);
  assert.ok(driver.includes("['scripts/fixtures/unnest-checked-array-source-input.mjs', 'unnest-checked-array-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNNEST_CHECKED_ARRAY_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--unnest-checked-array-only'/u);
  assert.ok(driver.includes("process.argv.includes('--unnest-checked-array-only')) return;"));
});

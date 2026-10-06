import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {unnestSuccesses, unnestRefusals} from './fixtures/unnest-source-input.mjs';

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

import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {unnestParameterPathSuccesses, unnestParameterPathRefusals, unnestParameterPathProgram}
  from './fixtures/unnest-parameter-path-source-input.mjs';
import {unnestSuccesses, unnestRefusals} from './fixtures/unnest-source-input.mjs';

test('parameter path expansion retains independent value type NULL and duplicate obligations', () => {
  const cases = new Map(unnestParameterPathSuccesses.map(item => [item.name, item]));
  const control = cases.get('unnest-parameter-path-json-control');
  assert.deepEqual(JSON.parse(control.text), unnestParameterPathProgram);
  assert.deepEqual(control.expected, [{id: 2, label: 'kept', position: 0},
    {id: null, label: null, position: 1}, {id: 2, label: null, position: 2}]);
  assert.deepEqual(unnestParameterPathProgram.stages[0].steps[1].derive.array,
    {property: {value: {property: {value: {$param: 'payload'}, name: 'nested'}}, name: 'items'}});
  for (const name of ['null-parent', 'null-container', 'null-array', 'empty-array']) {
    const item = cases.get('unnest-parameter-path-' + name);
    assert.deepEqual(item.expected, []);
    assert.deepEqual(item.columns, [
      {name: 'id', contract: {type: 'number', nullable: true}},
      {name: 'label', contract: {type: 'string', nullable: true}},
      {name: 'position', contract: {type: 'number', nullable: false}},
    ]);
  }
  for (const item of [...unnestParameterPathSuccesses, ...unnestParameterPathRefusals]) {
    const corpus = item.name.includes('-refusal-') ? unnestRefusals : unnestSuccesses;
    assert.equal(corpus.filter(value => value.name === item.name).length, 1);
  }
});

test('parameter path cases use the normal corpus and its existing Local HTTPS consumer', () => {
  const fixture = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...unnestSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...unnestRefusals)'));
  assert.ok(fixture.includes('unnestParameterPathOnly ? {successes: unnestParameterPathSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bunnestParameterPathOnly\b/u);
  assert.ok(driver.includes("['scripts/fixtures/unnest-parameter-path-source-input.mjs', 'unnest-parameter-path-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNNEST_PARAMETER_PATH_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--unnest-parameter-path-only'/u);
  assert.ok(driver.includes("process.argv.includes('--unnest-parameter-path-only')) return;"));
});

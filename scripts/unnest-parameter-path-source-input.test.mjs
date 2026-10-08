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

test('proven UNNEST input violations cannot pass as implementation limits', () => {
  for (const name of ['undeclared', 'unknown-property', 'non-array']) {
    const item = unnestParameterPathRefusals.find(value => value.name === 'unnest-parameter-path-refusal-' + name);
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput', name);
  }
  assert.deepEqual(unnestParameterPathRefusals.map(value => value.name), [
    'unnest-parameter-path-refusal-undeclared',
    'unnest-parameter-path-refusal-unknown-property',
    'unnest-parameter-path-refusal-non-array',
    'unnest-parameter-path-refusal-bound',
    'unnest-parameter-path-refusal-field-type',
    'unnest-parameter-path-refusal-member-case-collision',
  ]);
});


test('member spelling is syntax binding while declared names and JSON data stay exact', () => {
  const cases = new Map(unnestParameterPathSuccesses.map(item => [item.name, item]));
  const baseline = cases.get('unnest-parameter-path-sql');
  for (const name of ['case-insensitive-members', 'quoted-case-insensitive-members']) {
    const item = cases.get('unnest-parameter-path-' + name);
    assert.ok(item.text.includes('NESTED'));
    assert.deepEqual(item.parameterDeclarations, baseline.parameterDeclarations);
    assert.deepEqual(item.parameters, baseline.parameters);
    assert.deepEqual(item.expected, baseline.expected);
    assert.deepEqual(item.columns, baseline.columns);
  }
  const text = cases.get('unnest-parameter-path-mixed-declaration-members');
  const json = JSON.parse(cases.get('unnest-parameter-path-mixed-declaration-json-control').text);
  assert.deepEqual(Object.keys(json.params.payload.fields), ['Nested']);
  assert.deepEqual(Object.keys(json.params.payload.fields.Nested.fields), ['Items']);
  assert.deepEqual(json.stages[0].steps[1].derive.array, {property: {name: 'Items',
    value: {property: {name: 'Nested', value: {$param: 'payload'}}}}});
  assert.deepEqual(text.parameters, {payload: {Nested: {Items: [
    {id: 2, label: 'kept'}, null, {id: 2, label: null},
  ]}}});
  assert.equal(text.text, baseline.text);
  const collision = unnestParameterPathRefusals.find(item => item.name.endsWith('member-case-collision'));
  assert.deepEqual(Object.keys(collision.parameterDeclarations.payload.fields), ['nested', 'NESTED']);
  assert.equal(collision.expectedCode, 'ClientProgramInvalidInput');
});

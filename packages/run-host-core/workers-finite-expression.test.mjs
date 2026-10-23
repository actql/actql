import assert from 'node:assert/strict';
import test from 'node:test';
import {createWorkersFiniteRuntime} from './dist/workers_finite.js';
import {exerciseWorkersFinitePackage} from '../../scripts/fixtures/workers-finite-package-acceptance.mjs';
import {finiteExpressionConfiguration, finiteExpressionInput, finiteCountDocument, finiteNumericProfileCid} from './fixtures/finite-expression.mjs';

const expected = [{region: 'east', order_count: 2}, {region: 'west', order_count: 1}];

test('finite package executes filter and derive before COUNT through the original Run', async () => {
  const input = finiteExpressionInput(finiteCountDocument());
  const result = await exerciseWorkersFinitePackage(createWorkersFiniteRuntime, input, 128);
  assert.deepEqual(result.rows, expected);
  assert.equal(result.measurement.rowCount, 2);
});

test('the original 100-row filter and COUNT shape preserves every input row', async () => {
  const document = JSON.parse(finiteCountDocument());
  const regions = ['central', 'east', 'north', 'south', 'west'];
  document.stages[0].steps[0].values.rows = Array.from({length: 100}, (_, index) =>
    ({region: regions[index % 5], amount: (17 * index) % 100 + 1, quantity: index % 5 + 1}));
  document.stages[0].steps[1].filter = 'amount >= 50';
  // Independently tallied from the finite arithmetic input generator.
  const expected = [{region: 'central', order_count: 10}, {region: 'east', order_count: 10},
    {region: 'north', order_count: 11}, {region: 'south', order_count: 10},
    {region: 'west', order_count: 10}];
  const result = await exerciseWorkersFinitePackage(createWorkersFiniteRuntime,
    finiteExpressionInput(JSON.stringify(document)), 128);
  assert.deepEqual(result.rows, expected);
});

test('finite package executes SUM after filter and derive with the explicit numeric contract', async () => {
  const configuration = finiteExpressionConfiguration();
  configuration.environment.numeric_profile_cid = finiteNumericProfileCid;
  const document = JSON.parse(finiteCountDocument());
  document.stages[0].steps[3].group.aggregates.total = {fn: 'sum', field: 'net'};
  document.stages[0].results.rows.fields.push('total');
  const result = await exerciseWorkersFinitePackage(createWorkersFiniteRuntime,
    finiteExpressionInput(JSON.stringify(document), configuration), 128);
  assert.deepEqual(result.rows, [{region: 'east', order_count: 2, total: 100},
    {region: 'west', order_count: 1, total: 60}]);
});

test('finite expression installation cannot infer missing contracts or partial budgets', async () => {
  const configuration = finiteExpressionConfiguration();
  delete configuration.fragments;
  const input = finiteExpressionInput(finiteCountDocument(), configuration);
  await assert.rejects(exerciseWorkersFinitePackage(createWorkersFiniteRuntime, input, 128));
  for (const mutate of [value => {delete value.fragments.limits.logical.max_work;},
    value => {value.fragments.contract = '{}';},
    value => {value.fragments.ordered = '{}';},
    value => {value.fragments = undefined;},
    value => {value.fragments.limits.logical.max_input_rows = 100;}]) {
    const changed = finiteExpressionConfiguration(); mutate(changed);
    assert.throws(() => createWorkersFiniteRuntime(0, changed));
  }
});

test('finite expression execution preserves explicit selected row and work ceilings', async () => {
  for (const mutate of [value => {value.fragments.limits.logical.max_input_rows = 1n;},
    value => {value.fragments.limits.logical.max_work = 1n;}]) {
    const configuration = finiteExpressionConfiguration(); mutate(configuration);
    const input = finiteExpressionInput(finiteCountDocument(), configuration);
    await assert.rejects(exerciseWorkersFinitePackage(createWorkersFiniteRuntime, input, 128));
  }
});

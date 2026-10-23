import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open} from '../../packages/node/index.mjs';
import {CapturedRunExecutionError, CapturedRunPublicationError} from './entry.mjs';

function program(rows, steps, fields) {
  return {version: 'actql/0.1', id: 'values-fragment-capacity', stages: [{
    id: 'main', inputs: {}, steps: [{as: 'input', values: {
      schema: {id: {type: 'number', nullable: false}}, rows,
    }}, ...steps], results: {rows: {from: steps.at(-1)?.as ?? 'input', fields}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

test('execution failure wrapper retains the exact first failure and cleanup handle', () => {
  const cleanupHandle = Object.freeze({status: () => 'pending', retry() {}});
  const failure = Object.assign(new Error('original typed failure'), {
    cleanupPending: true, cleanupHandle,
  });
  const execution = Object.freeze({status: 'host-tasks-failed', failure});
  const error = new CapturedRunExecutionError(execution);
  assert.equal(error instanceof CapturedRunPublicationError, true);
  assert.equal(error.execution, execution);
  assert.equal(error.cause, failure);
  assert.equal(error.primaryFailure, failure);
  assert.equal(error.cleanupHandle, cleanupHandle);
  assert.equal(error.cleanupPending, true);
});

async function withClient(valuesMaxRows, run, installation = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-fragment-capacity-'));
  const client = await open({stateDir: directory, installation: {...installation, valuesMaxRows}});
  let closed = false;
  try { await run(client); }
  finally {
    // Retain the original Client while the independent bounded cleanup owner
    // advances. A terminal Run is not evidence that physical release finished.
    for (let attempt = 0; attempt < 256; attempt++) {
      try { await client.close(); closed = true; break; }
      catch (error) {
        if (error.code !== 'ClientCleanupPending') throw error;
        await new Promise(resolve => setTimeout(resolve, 1));
      }
    }
    assert.equal(closed, true, 'original Client cleanup must settle');
    if (closed) await rm(directory, {recursive: true, force: true});
  }
}

for (const count of [100, 500, 1000]) {
  test(`admitted ${count}-row direct Values remains unchanged`, async () => {
    const rows = Array.from({length: count}, (_, id) => ({id}));
    await withClient(2000, async client => {
      const run = await client.start(program(rows, [], ['id']));
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), rows);
    });
  });

  test(`admitted ${count}-row Values filter retains the configured fragment row ceiling`, async () => {
    const rows = Array.from({length: count}, (_, id) => ({id}));
    await withClient(2000, async client => {
      const input = program(rows, [{from: 'input', filter: 'id >= 50', as: 'filtered'}], ['id']);
      const run = await client.start(input);
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), rows.filter(row => row.id >= 50));
    });
  });
}

for (const count of [500, 1000]) {
  test(`${count}-row multi-column filter/derive/group/sort matches independent totals`, async () => {
    const regions = ['central', 'east', 'north', 'south', 'west'];
    const rows = Array.from({length: count}, (_, index) => ({
      customer_id: index % 100, amount: (index * 17) % 100 + 1,
      quantity: index % 5 + 1, region: regions[index % 5],
    }));
    const input = program(rows, [
      {from: 'input', filter: 'amount >= 50', as: 'filtered'},
      {from: 'filtered', derive: {net: 'amount * quantity'}, as: 'derived'},
      {from: 'derived', group: {by: ['region'], aggregates: {
        order_count: {fn: 'count'}, revenue: {fn: 'sum', field: 'net'},
      }}, as: 'aggregated'},
      {from: 'aggregated', sort: [{field: 'region', dir: 'asc', nulls: 'last'}], as: 'sorted'},
    ], ['region', 'order_count', 'revenue']);
    input.stages[0].steps[0].values.schema = {
      customer_id: {type: 'number', nullable: false},
      amount: {type: 'number', nullable: false},
      quantity: {type: 'number', nullable: false},
      region: {type: 'string', nullable: false},
    };
    // Independent fixed totals for each repeating 100-row input cycle.
    // These are not regenerated from ActQL output or a second query engine.
    const expected = [[10, 735], [10, 1510], [11, 2475], [10, 2980], [10, 3825]]
      .map(([order_count, revenue], index) => ({region: regions[index],
        order_count: order_count * count / 100, revenue: revenue * count / 100}));
    await withClient(2000, async client => {
      const run = await client.start(input);
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), expected);
    });
  });
}

test('ordered derive uses the same admitted row ceiling and independent values', async () => {
  const rows = Array.from({length: 500}, (_, id) => ({id}));
  await withClient(500, async client => {
    const input = program(rows, [{from: 'input', derive: [{twice: 'id * 2'}], as: 'derived'}], ['id', 'twice']);
    const run = await client.start(input);
    assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), rows.map(({id}) => ({id, twice: id * 2})));
  });
});

test('a configured row ceiling still prevents admission of an over-limit Values input', async () => {
  await withClient(100, async client => {
    const input = program(Array.from({length: 101}, (_, id) => ({id})),
      [{from: 'input', filter: 'id >= 50', as: 'filtered'}], ['id']);
    // This capacity regression does not establish the separate submission
    // outcome classification; it must never obtain an accepted Run.
    await assert.rejects(client.start(input));
  });
});

test('a demanded expression failure retains its original typed dispatch cause', async () => {
  const failures = [];
  await withClient(100, async client => {
    const input = program([{id: 0}], [
      {from: 'input', derive: {quotient: '1 / id'}, as: 'derived'},
    ], ['quotient']);
    const run = await client.start(input);
    const state = await run.wait({signal: AbortSignal.timeout(10000)});
    assert.notEqual(state.status, 'succeeded');
    assert.equal(state.result_available, false);
    assert.equal(failures.length, 1);
    assert.equal(failures[0].code, 'CapturedRunExecutionFailed');
    assert.equal(failures[0].primaryCode, 'MoonBitHostFailure');
    assert.equal(Number.isInteger(failures[0].issueTag), true);
    assert.equal(Number.isInteger(failures[0].nestedIssueTag), true);
  }, {authorization: {observe(event, detail) {
    if (event === 'dispatch_failed') failures.push(detail);
  }}});
});

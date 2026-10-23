import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionAttempt, getSubmissionOutcome} from '../../packages/sdk/index.mjs';

const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: false};
const order = {customer_id: 0, amount: 60, quantity: 1};
const customer = {customer_id: 0, region: 'central'};

function program({orders = [order], customers = [customer], filtered = true,
  aggregate = false, maxOutputRows = 100} = {}) {
  const steps = [
    {as: 'orders', values: {schema: {customer_id: number, amount: number, quantity: number}, rows: orders}},
    {as: 'customers', values: {schema: {customer_id: number, region: string}, rows: customers}},
    ...(filtered ? [{from: 'orders', filter: 'amount >= 50', as: 'filtered'}] : []),
    {from: filtered ? 'filtered' : 'orders', join: {
      with: 'customers', kind: 'inner', on: [{left: 'customer_id', right: 'customer_id'}],
      max_output_rows: maxOutputRows,
      select: {region: 'right.region', amount: 'left.amount', quantity: 'left.quantity'},
    }, as: 'joined'},
    ...(aggregate ? [
      {from: 'joined', derive: {net: 'amount * quantity'}, as: 'derived'},
      {from: 'derived', group: {by: ['region'], aggregates: {
        order_count: {fn: 'count'}, revenue: {fn: 'sum', field: 'net'},
      }}, as: 'aggregated'},
      {from: 'aggregated', sort: [{field: 'region', dir: 'asc', nulls: 'last'}], as: 'sorted'},
    ] : []),
  ];
  return {version: 'actql/0.1', id: 'bounded-values-join-profile', stages: [{
    id: 'main', inputs: {}, steps, results: {rows: {
      from: aggregate ? 'sorted' : 'joined',
      fields: aggregate ? ['region', 'order_count', 'revenue'] : ['region', 'amount', 'quantity'],
    }},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

async function withClient(run, installation = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-values-join-profile-'));
  let client, closed = false;
  try {
    client = await open({stateDir: directory, installation});
    await run(client, async () => {
      await client.close();
      client = await open({stateDir: directory, installation});
      return client;
    });
  } finally {
    if (client) {await client.close(); closed = true;}
    if (closed) await rm(directory, {recursive: true, force: true});
  }
}

async function preflight(client, input) {
  const checked = await client.check(input, {kind: 'program', scope: 'bound_input'});
  assert.equal(checked.outcome, 'completed');
  assert.equal(checked.report.verdict, 'verified');
  assert.equal(checked.report.runnable.verdict, 'yes');
}

async function execute(client, input, options) {
  await preflight(client, input);
  const run = await client.start(input, options);
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  return {run, rows: await run.result('answer').all()};
}

test('ordinary direct Values JOIN retains original submission and conflict custody', async () => {
  await withClient(async client => {
    const input = program({filtered: false});
    const original = await execute(client, input, {requestId: 'join-original'});
    assert.deepEqual(original.rows, [{region: 'central', amount: 60, quantity: 1}]);
    const outcome = getSubmissionOutcome(original.run);
    assert.deepEqual((await client.lookupSubmission(outcome.submissionRef)).admission.ref, original.run.ref);
    assert.deepEqual((await execute(client, input, {requestId: 'join-original'})).run.ref, original.run.ref);
    await assert.rejects(client.start(program({filtered: false, orders: [{...order, amount: 70}]}),
      {requestId: 'join-original'}), error => {
      assert.equal(error.code, 'RequestConflict');
      assert.equal(getSubmissionAttempt(error).kind, 'conflict');
      return true;
    });
  });
});

test('ordinary Values filter then JOIN executes the one-row reported Program', async () => {
  await withClient(async client => {
    assert.deepEqual((await execute(client, program())).rows,
      [{region: 'central', amount: 60, quantity: 1}]);
  });
});

test('ordinary bounded Values JOIN derive group and sort execute at the shared row ceiling', async () => {
  const regions = ['central', 'east', 'north', 'south', 'west'];
  const orders = Array.from({length: 90}, (_, i) => ({
    customer_id: i % 10, amount: (i * 17) % 100 + 1, quantity: i % 5 + 1,
  }));
  const customers = Array.from({length: 10}, (_, i) => ({customer_id: i, region: regions[i % 5]}));
  await withClient(async client => {
    assert.deepEqual((await execute(client, program({orders, customers, aggregate: true}))).rows, [
      {region: 'central', order_count: 10, revenue: 735},
      {region: 'east', order_count: 10, revenue: 1510},
      {region: 'north', order_count: 9, revenue: 2130},
      {region: 'south', order_count: 8, revenue: 2384},
      {region: 'west', order_count: 8, revenue: 2910},
    ]);
  });
});

test('ordinary inner JOIN excludes unmatched rows without dropping duplicate matches', async () => {
  await withClient(async client => {
    const input = program({orders: [order, {...order, customer_id: 99}],
      customers: [customer, {...customer, region: 'east'}]});
    const result = await execute(client, input);
    assert.deepEqual(result.rows.sort((a, b) => a.region.localeCompare(b.region)), [
      {region: 'central', amount: 60, quantity: 1}, {region: 'east', amount: 60, quantity: 1},
    ]);
  });
});

test('ordinary filtered JOIN publishes an empty complete result', async () => {
  await withClient(async client => {
    assert.deepEqual((await execute(client, program({orders: [{...order, amount: 49}]}))).rows, []);
  });
});

test('JOIN output guard never publishes a truncated successful result', async () => {
  await withClient(async client => {
    const input = program({orders: [order, {...order, amount: 70}], maxOutputRows: 1});
    await preflight(client, input);
    const run = await client.start(input);
    const status = await run.wait({signal: AbortSignal.timeout(10000)});
    // Failure reconciliation is a separate lifecycle contract. Neither a
    // failed nor an unresolved execution may publish one truncated match.
    assert.ok(['failed', 'needs_reconciliation'].includes(status.status));
    assert.equal(status.result_available, false);
    await assert.rejects(run.result('answer').all(), {code: 'ResultAccessDenied', rowsYielded: 0});
  });
});

for (const named of [false, true]) {
  test(`explicit single-task Values profile retains ${named ? 'named' : 'anonymous'} multi-task refusal`, async () => {
    await withClient(async (client, reopen) => {
      const input = program();
      await preflight(client, input);
      let original;
      await assert.rejects(client.start(input, named ? {requestId: 'join-refusal'} : {}), error => {
        assert.equal(error.code, named ? 'SubmissionPreparationFailed' : 'SubmissionNotAccepted');
        original = getSubmissionOutcome(error);
        assert.equal(original.kind, named ? 'preparation_failed' : 'not_accepted');
        assert.deepEqual(original.problem, {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
        assert.equal('admission' in original, false);
        return true;
      });
      assert.deepEqual(await client.lookupSubmission(original.submissionRef), original);
      client = await reopen();
      assert.deepEqual(await client.lookupSubmission(original.submissionRef), original);
    }, {valuesMaxRows: 2000});
  });
}

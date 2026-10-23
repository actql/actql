import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

const accounts = [
  {id: '001Acme', name: 'Acme Corp'},
  {id: '001Globex', name: 'Globex Inc'},
];

// The installed catalogue is larger than each query's capture inventory.
// Each case uses a real Host and fresh owned state, never pre-read fixture rows.
async function withMockClient(run) {
  const previous = process.cwd();
  const directory = await mkdtemp(join(tmpdir(), 'actql-mock-occurrences-'));
  const project = join(directory, 'project');
  scaffoldProject(project, 'churn-risk-mock');
  process.chdir(project);
  let client, closed = false;
  try {
    client = await open({stateDir: join(project, '.actql'), profile: 'mock'});
    await run(client);
  } finally {
    try { if (client) await client.close(); closed = true; }
    finally {
      process.chdir(previous);
      if (closed) await rm(directory, {recursive: true, force: true});
    }
  }
}

async function rows(client, text, requestId) {
  const check = await client.check(text, {
    kind: 'text', scope: 'bound_input', format: 'aql-text',
  });
  assert.equal(check.report.verdict, 'verified');
  const run = await client.startSource(text, {format: 'aql-text', requestId});
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  return {run, rows: await run.result('main').all()};
}

test('one Mock Salesforce occurrence retains its original submission', async () => {
  await withMockClient(async client => {
    const text = 'SELECT id, name FROM salesforce.accounts ORDER BY id';
    const original = await rows(client, text, 'single-salesforce');
    assert.deepEqual(original.rows, accounts);
    const submission = getSubmissionOutcome(original.run);
    assert.equal(submission.kind, 'ready');
    const found = await client.lookupSubmission(submission.submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.admission.ref, original.run.ref);
    const replay = await rows(client, text, 'single-salesforce');
    assert.deepEqual(replay.run.ref, original.run.ref);
    assert.deepEqual(replay.rows, accounts);
    const unordered = await rows(client, 'SELECT id, name FROM salesforce.accounts', 'unordered-salesforce');
    assert.deepEqual(unordered.rows.sort((a, b) => a.id.localeCompare(b.id)), accounts);
  });
});

test('one Mock Snowflake occurrence does not use its catalogue ordinal', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT account_id, active_users FROM snowflake.usage_30d ORDER BY account_id',
      'single-snowflake');
    assert.deepEqual(result.rows, [
      {account_id: '001Acme', active_users: '4'},
      {account_id: '001Globex', active_users: '12'},
    ]);
  });
});

test('Mock JOIN occurrences follow checked order, not installed catalogue order', async () => {
  await withMockClient(async client => {
    for (const [name, text] of [
      ['forward', 'SELECT a.id AS id, a.name AS name FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id = u.account_id ORDER BY id'],
      ['reverse', 'SELECT a.id AS id, a.name AS name FROM snowflake.usage_30d AS u JOIN salesforce.accounts AS a ON u.account_id = a.id ORDER BY id'],
    ]) {
      assert.deepEqual((await rows(client, text, name)).rows, accounts);
    }
  });
});

test('repeated Mock Source occurrences keep separate read custody', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT a.id AS id, b.name AS name FROM salesforce.accounts AS a JOIN salesforce.accounts AS b ON a.id = b.id ORDER BY id',
      'repeated-salesforce');
    assert.deepEqual(result.rows, accounts);
  });
});

test('Mock JOIN and INFER retain their original two-Source profile', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT a.id AS id, a.description AS notes, u.active_users, u.trend ' +
      'FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id = u.account_id ' +
      '|> WHERE active_users < 10 ' +
      '|> INFER `model-task:churn-risk.v1` INPUT (notes, active_users, trend) AS risk ' +
      '|> SELECT id, risk', 'mock-infer-control');
    assert.deepEqual(result.rows, [{id: '001Acme', risk: {
      input_key: {id: '001Acme'}, outcome: 'ok',
      value: {level: 'high', reason: 'falling usage and a competitor evaluation'},
    }}]);
  });
});

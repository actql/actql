// Durable defer -> restart -> answer -> same continuation, on the real Local
// Host: every step is a separate CLI process over the same SQLite Checkpoint
// journal and a real DuckDB source. Provider I/O is the number of source
// sessions the example opened (each follows one acquisition dispatch
// decision) and the acquisition receipts it produced.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DuckDBInstance } from '@duckdb/node-api';
import { exampleAccountConfiguration } from '../examples/physical-strategy.mjs';
import { openLocalHost } from '../examples/local-host.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const cliPath = fileURLToPath(new URL('../examples/local-host-cli.mjs', import.meta.url));
const exec = promisify(execFile);
let built;

async function build() {
  built ??= (async () => {
    for (const target of ['src/connectors/duckdb/host_node', 'src/connectors_builtin_node',
      'src/physical_strategy_example', 'src/checkpoint_runtime_node']) {
      await exec('moon', ['build', '--target', 'js', '--release', target], { cwd: root });
    }
  })();
  return built;
}

// One CLI process. stdin is a pipe closed at once: EOF never answers.
function cli(args, { env = {} } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--no-warnings', cliPath, ...args], {
      env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.stdin.end();
    child.on('error', reject);
    child.on('close', (code, signal) => {
      let json;
      try { json = JSON.parse(stdout); } catch {}
      resolve({ code, signal, json, stdout, stderr, pid: child.pid });
    });
    cli.last = child;
  });
}

// Start a CLI process and return its handle together with its completion.
function start(args, options) {
  const done = cli(args, options);
  return { child: cli.last, done };
}

async function fixture(t, { outcome = 'delegate' } = {}) {
  await build();
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'local-host-resume-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const database = join(directory, 'source.duckdb');
  const db = await DuckDBInstance.create(database);
  const connection = await db.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  } finally { connection.closeSync(); db.closeSync(); }
  const files = {
    environment: join(directory, 'environment.json'),
    program: join(directory, 'program.json'),
    parameters: join(directory, 'parameters.json'),
    account: join(directory, 'account-config.json'),
  };
  await Promise.all([
    writeFile(files.environment, JSON.parse(catalog[1])),
    writeFile(files.program, await readFile(join(root,
      'adapters/connectors/duckdb/node/examples/program.json'), 'utf8')),
    writeFile(files.parameters, '{"minimum":1}'),
    writeFile(files.account, exampleAccountConfiguration({ database, outcome })),
  ]);
  const init = await cli(['init', '--directory', join(directory, 'host'),
    '--account-config', files.account, '--reviewer', 'alice']);
  assert.equal(init.code, 0, init.stderr);
  const config = init.json.config;
  const runArgs = ['run', '--config', config, '--database', database,
    '--environment', files.environment, '--environment-cid', catalog[2],
    '--program', files.program, '--parameters', files.parameters];
  const journalPath = join(directory, 'host/state/journal/checkpoint-journal.sqlite3');
  return { directory, database, files, config, signer: init.json.signer, runArgs, journalPath,
    environmentCid: catalog[2],
    // Committed journal rows, read independently of the Host processes.
    rows() {
      const sqlite = new DatabaseSync(journalPath, { readOnly: true });
      try {
        const count = table => sqlite.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
        return {
          runs: count('runs'), checkpoints: count('checkpoints'),
          resolutions: count('resolutions'), intents: count('resume_intents'),
          runRows: sqlite.prepare('SELECT run_id, status FROM runs').all()
            .map(row => ({ ...row })),
          intentRows: sqlite.prepare(
            'SELECT state, generation, claimant, outcome_status FROM resume_intents').all()
            .map(row => ({ ...row })),
        };
      } finally { sqlite.close(); }
    } };
}

async function waitingRun(input) {
  const run = await cli(input.runArgs);
  assert.equal(run.code, 0, run.stderr);
  assert.equal(run.json.status, 'waiting_checkpoint');
  assert.equal(run.json.counters.provider_sessions, 0);
  return run.json;
}

const approveArgs = (input, references, extra = []) =>
  ['approve', ...references, '--config', input.config, '--signer', input.signer, ...extra];

let allowResultCid;
async function allowResult(t) {
  if (allowResultCid !== undefined) return allowResultCid;
  const input = await fixture(t, { outcome: 'allow' });
  const run = await cli(input.runArgs);
  assert.equal(run.code, 0, run.stderr);
  assert.equal(run.json.status, 'succeeded');
  assert.equal(run.json.counters.provider_sessions, 1);
  assert.equal(run.json.acquisition_receipts, 2);
  assert.equal(input.rows().checkpoints, 0);
  assert.deepEqual(input.rows().runRows.map(row => row.status), ['succeeded']);
  allowResultCid = run.json.result_cid;
  return allowResultCid;
}

test('defer in process A, approve in B, resume in C: same result, one continuation', async t => {
  const expected = await allowResult(t);
  const input = await fixture(t);
  // A: the deferred preparation persists its Checkpoint and exits 0.
  const waiting = await waitingRun(input);
  assert.equal(waiting.checkpoint.kind, 'run_scope');
  assert.equal(waiting.checkpoint.boundary, 'preparation');
  assert.deepEqual({ ...input.rows(), runRows: undefined, intentRows: undefined },
    { runs: 0, checkpoints: 1, resolutions: 0, intents: 0, runRows: undefined, intentRows: undefined });

  // B: safe inspection only, then an explicit signed approval. EOF on stdin
  // and a missing signer never answer.
  const listed = await cli(['list', '--config', input.config]);
  assert.equal(listed.code, 0);
  assert.equal(listed.json.pending.length, 1);
  assert.equal(listed.json.pending[0].checkpointCid, waiting.checkpoint.checkpoint_cid);
  const inspected = await cli(['inspect', waiting.checkpoint.checkpoint_id, '--config', input.config]);
  assert.equal(inspected.code, 0);
  assert.equal(inspected.json.preparation.status, 'waiting_checkpoint');
  // Restricted review contents, captured inputs and keys are not disclosed.
  for (const secret of ['local-example-review', 'minimum', 'private_key', 'tuple']) {
    assert(!inspected.stdout.includes(secret), secret);
    assert(!listed.stdout.includes(secret), secret);
  }
  const unsigned = await cli(['approve', waiting.checkpoint.checkpoint_id, '--config', input.config]);
  assert.equal(unsigned.code, 2);
  assert.equal(input.rows().resolutions, 0);
  const approved = await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  assert.equal(approved.code, 0, approved.stderr);
  assert.equal(approved.json.results[0].status, 'committed');
  assert.equal(input.rows().runs, 0);

  // C: the resumed continuation creates its Run in running and completes.
  const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 0, resumed.stderr);
  assert.equal(resumed.json.status, 'succeeded');
  assert.equal(resumed.json.result_cid, expected);
  assert.equal(resumed.json.counters.continuation_starts, 1);
  assert.equal(resumed.json.counters.provider_sessions, 1);
  assert.equal(resumed.json.acquisition_receipts, 2);
  assert.equal(resumed.json.tasks_completed, 3);
  const rows = input.rows();
  assert.deepEqual(rows.runRows, [{ run_id: resumed.json.run_id, status: 'succeeded' }]);
  assert.deepEqual(rows.intentRows, [{ state: 'completed', generation: 1,
    claimant: rows.intentRows[0].claimant, outcome_status: 'run_created' }]);
  const status = await cli(['status', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(status.json.preparation.status, 'run_created');
  assert.equal(status.json.run.status, 'succeeded');
  // D: the completed intent never starts again.
  const again = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(again.json.status, 'completed');
  assert.equal(again.json.counters.continuation_starts, 0);
  assert.equal(again.json.counters.provider_sessions, 0);
  assert.equal(input.rows().runs, 1);
});

test('reject ends the preparation with no Run and no provider I/O', async t => {
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  const rejected = await cli(['reject', waiting.checkpoint.checkpoint_cid, '--config', input.config,
    '--signer', input.signer]);
  assert.equal(rejected.code, 0, rejected.stderr);
  assert.equal(rejected.json.results[0].status, 'committed');
  assert.equal(rejected.json.results[0].resumeIntentId, null);
  const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 1);
  assert.match(resumed.stderr, /ResumeIntentNotFound/);
  const status = await cli(['status', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(status.json.preparation.status, 'ended');
  assert.equal(status.json.preparation.endReason, 'rejected');
  assert.deepEqual([input.rows().runs, input.rows().intents], [0, 0]);
});

test('duplicate approvals in two processes are idempotent with one intent', async t => {
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  const decidedAt = new Date().toISOString();
  const answers = await Promise.all([1, 2].map(() => cli(approveArgs(input,
    [waiting.checkpoint.checkpoint_id], ['--decided-at', decidedAt]))));
  assert.deepEqual(answers.map(item => item.code), [0, 0]);
  assert.deepEqual(answers.map(item => item.json.results[0].status).sort(),
    ['committed', 'duplicate']);
  assert.equal(answers[0].json.results[0].resolutionCid, answers[1].json.results[0].resolutionCid);
  assert.equal(answers[0].json.results[0].resumeIntentId, answers[1].json.results[0].resumeIntentId);
  assert.deepEqual([input.rows().resolutions, input.rows().intents], [1, 1]);
});

test('a conflicting approve/reject race has exactly one winner', async t => {
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  const [approve, reject] = await Promise.all([
    cli(approveArgs(input, [waiting.checkpoint.checkpoint_id])),
    cli(['reject', waiting.checkpoint.checkpoint_id, '--config', input.config,
      '--signer', input.signer]),
  ]);
  const statuses = [approve.json.results[0].status, reject.json.results[0].status];
  assert.deepEqual(statuses.slice().sort(), ['committed', 'conflicting']);
  const approvedWon = statuses[0] === 'committed';
  assert.equal(input.rows().resolutions, 1);
  assert.equal(input.rows().intents, approvedWon ? 1 : 0);
  const status = await cli(['status', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(status.json.preparation.status, approvedWon ? 'resuming' : 'ended');
  assert.equal(input.rows().runs, 0);
});

test('a superseded claimant cannot complete; a killed one leaves the intent to the next', async t => {
  const expected = await allowResult(t);
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  const claimedBy = async claimant => {
    for (let attempt = 0; attempt < 200; attempt++) {
      const row = input.rows().intentRows[0];
      if (row?.state === 'claimed' && row.claimant === claimant) return row;
      await new Promise(done => setTimeout(done, 50));
    }
    assert.fail(`intent not claimed by ${claimant}`);
  };
  // D claims with a short lease and is killed before completing anything.
  const killed = start(['resume', waiting.prepare_attempt_id, '--config', input.config,
    '--claimant', 'claimant-d', '--lease-ms', '1000'],
  { env: { ACTQL_EXAMPLE_HOLD_AFTER_CLAIM_MS: '60000' } });
  assert.equal((await claimedBy('claimant-d')).generation, 1);
  killed.child.kill('SIGKILL');
  assert.equal((await killed.done).signal, 'SIGKILL');
  // D2 claims after the lease with a higher generation and holds past its own
  // lease; E supersedes it and completes; D2 then cannot complete.
  await new Promise(done => setTimeout(done, 1100));
  const held = start(['resume', waiting.prepare_attempt_id, '--config', input.config,
    '--claimant', 'claimant-d2', '--lease-ms', '1000'],
  { env: { ACTQL_EXAMPLE_HOLD_AFTER_CLAIM_MS: '4000' } });
  assert.equal((await claimedBy('claimant-d2')).generation, 2);
  await new Promise(done => setTimeout(done, 1100));
  const winner = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config,
    '--claimant', 'claimant-e']);
  assert.equal(winner.code, 0, winner.stderr);
  assert.equal(winner.json.status, 'succeeded');
  assert.equal(winner.json.result_cid, expected);
  assert.equal(winner.json.counters.continuation_starts, 1);
  const stale = await held.done;
  assert.equal(stale.code, 1);
  assert.equal(stale.json.status, 'stale_claim');
  assert.equal(stale.json.counters.provider_sessions, 0);
  const rows = input.rows();
  assert.equal(rows.runs, 1);
  assert.deepEqual(rows.intentRows, [{ state: 'completed', generation: 3,
    claimant: 'claimant-e', outcome_status: 'run_created' }]);
});

test('a configuration changed to deny while waiting fails resume revalidation', async t => {
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  await writeFile(input.files.account,
    exampleAccountConfiguration({ database: input.database, outcome: 'deny' }));
  const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 1);
  assert.equal(resumed.json.status, 'ended');
  assert.equal(resumed.json.run_created, false);
  assert.equal(resumed.json.terminal_error_code, 'ACTQL_E_RESUME_REVALIDATION_FAILED');
  assert.equal(resumed.json.counters.provider_sessions, 0);
  assert.equal(resumed.json.counters.continuation_starts, 0);
  const status = await cli(['status', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(status.json.preparation.endReason, 'revalidation_failed');
  assert.equal(input.rows().runs, 0);
});

test('cancel while waiting ends the preparation with no resume intent', async t => {
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  const cancelled = await cli(['cancel', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(cancelled.code, 0, cancelled.stderr);
  assert.equal(cancelled.json.outcome, 'cancelled');
  assert.deepEqual((await cli(['list', '--config', input.config])).json.pending, []);
  const late = await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  assert.equal(late.code, 1);
  assert.equal(late.json.results[0].status, 'cancelled');
  const status = await cli(['status', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(status.json.preparation.endReason, 'cancelled');
  assert.deepEqual([input.rows().runs, input.rows().resolutions, input.rows().intents], [0, 0, 0]);
});

test('resume reads the inputs captured before the Checkpoint, not the changed paths', async t => {
  const expected = await allowResult(t);
  const input = await fixture(t);
  const waiting = await waitingRun(input);
  // The operator-supplied files change while the Checkpoint waits.
  await writeFile(input.files.parameters, '{"minimum":100}');
  await writeFile(input.files.program, '{"not":"a program"}');
  await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  const resumed = await cli(['resume', waiting.checkpoint.checkpoint_id, '--config', input.config]);
  assert.equal(resumed.code, 0, resumed.stderr);
  assert.equal(resumed.json.result_cid, expected);
  assert.equal(resumed.json.counters.provider_sessions, 1);
});

test('one approve command answers several Checkpoints item by item', async t => {
  const expected = await allowResult(t);
  const input = await fixture(t);
  const first = await waitingRun(input);
  const second = await waitingRun(input);
  const batch = await cli(approveArgs(input, [first.checkpoint.checkpoint_id,
    'no-such-checkpoint', second.checkpoint.checkpoint_cid]));
  assert.equal(batch.code, 1);
  assert.deepEqual(batch.json.results.map(item => item.status),
    ['committed', 'invalid', 'committed']);
  assert.equal(batch.json.results[1].reason, 'CheckpointNotFound');
  assert.notEqual(batch.json.results[0].resumeIntentId, batch.json.results[2].resumeIntentId);
  for (const waiting of [first, second]) {
    const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
    assert.equal(resumed.json.status, 'succeeded');
    assert.equal(resumed.json.result_cid, expected);
    assert.equal(resumed.json.counters.continuation_starts, 1);
  }
  assert.equal(input.rows().runs, 2);
});

test('without an account configuration the Host denies before any read', async t => {
  const input = await fixture(t, { outcome: 'allow' });
  const hostConfig = JSON.parse(await readFile(input.config, 'utf8'));
  delete hostConfig.account_config;
  await writeFile(input.config, JSON.stringify(hostConfig));
  const run = await cli(input.runArgs);
  assert.equal(run.code, 1);
  assert.equal(run.json.status, 'refused');
  assert.equal(run.json.runtime_code, 'ACTQL_E_ACCOUNT_CONFIG_INVALID');
  assert.equal(run.json.boundary, 'preparation');
  assert.equal(run.json.counters.provider_sessions, 0);
  assert.deepEqual([input.rows().runs, input.rows().checkpoints], [0, 0]);
});

test('an acquisition deferral after a Host permit resumes past the crossed boundary', async t => {
  const expected = await allowResult(t);
  const input = await fixture(t);
  // An embedding application's decision function permits preparation now
  // and defers acquisition. Its Host process then exits.
  const host = await openLocalHost(input.config);
  let waiting;
  try {
    waiting = await host.run({ database: input.database, environment: input.files.environment,
      environmentCid: input.environmentCid, program: input.files.program,
      parameters: input.files.parameters }, {
      answeringAuthorities: ['application-policy'],
      decide: view => view.boundary === 'preparation'
        ? { decision: 'permit', subject: view.subject, authority: 'application-policy' }
        : { decision: 'defer', subject: view.subject },
    });
  } finally { host.close(); }
  assert.equal(waiting.status, 'waiting_checkpoint');
  assert.equal(waiting.checkpoint.kind, 'read_access');
  assert.equal(waiting.checkpoint.boundary, 'acquisition');
  assert.equal(waiting.counters.provider_sessions, 0);
  assert.equal(input.rows().runs, 0);
  // A later CLI process without a decision function answers and resumes: the
  // permitted preparation is not asked again, the approved read proceeds.
  const approved = await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  assert.equal(approved.json.results[0].status, 'committed');
  const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 0, resumed.stderr);
  assert.equal(resumed.json.status, 'succeeded');
  assert.equal(resumed.json.result_cid, expected);
  assert.equal(resumed.json.counters.provider_sessions, 1);
  assert.equal(resumed.json.counters.continuation_starts, 1);
  assert.equal(input.rows().checkpoints, 1);
});

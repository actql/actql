// Durable defer -> restart -> answer -> same continuation, on the real Local
// Host: every step is a separate CLI process over the same SQLite Checkpoint
// journal and a real DuckDB source. Provider I/O is the number of source
// sessions the example opened (each follows one acquisition dispatch
// decision) and the acquisition receipts it produced.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DuckDBInstance } from '@duckdb/node-api';
import { exampleAccountConfiguration } from '../examples/physical-strategy.mjs';
import { exactApprovedSubject, openLocalHost, readSigner } from '../examples/local-host.mjs';
import { decisionSubjectCid } from '../../../../host-common/authorization-gate.mjs';
import { runtimeCore } from '../../../../host-common/runtime-core.mjs';
import { loadPrivateEvidenceKey, openContinuationEvidence } from
  '../../../../host-node/local-continuation-evidence.mjs';

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
  const state = join(directory, 'host/state');
  const journalPath = join(state, 'journal/checkpoint-journal.sqlite3');
  const holdings = join(state, 'private-store/physical-holdings');
  // Private evidence is read back only through the encrypted Store.
  const evidence = async attempt => {
    const moon = await import(join(root,
      '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'));
    const port = openContinuationEvidence({ stateDirectory: state,
      ...await loadPrivateEvidenceKey(state),
      contractControl: runtimeCore(moon).publicationControl, preparation: () => undefined });
    try { return await port.open(attempt); } finally { await port.close(); }
  };
  const onlyAttempt = () => {
    const sqlite = new DatabaseSync(journalPath, { readOnly: true });
    try {
      return sqlite.prepare('SELECT prepare_attempt_id FROM checkpoints').get().prepare_attempt_id;
    } finally { sqlite.close(); }
  };
  return { directory, database, files, config, signer: init.json.signer, runArgs, journalPath,
    environmentCid: catalog[2], state, evidence,
    // Captured bytes of the only prepare attempt, and how many private
    // evidence holdings the Host Store keeps.
    stored: async cid => (await (await evidence(onlyAttempt()))
      .bytes('captured_input', cid)).toString('utf8'),
    async captured() {
      try { return (await readdir(holdings)).length; }
      catch (error) { if (error.code === 'ENOENT') return 0; throw error; }
    },
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
    },
    // The sealed Checkpoint, its stored decision-subject binding and the
    // committed Resolution, with the continuation and invocation records it
    // names from the Host's encrypted Store.
    async sealed() {
      const sqlite = new DatabaseSync(journalPath, { readOnly: true });
      let row;
      let resolution;
      try {
        row = sqlite.prepare(
          'SELECT checkpoint_wire, decision_subject_cid, prepare_attempt_id FROM checkpoints')
          .get();
        resolution = sqlite.prepare('SELECT verified_resolution_wire FROM resolutions').get();
      } finally { sqlite.close(); }
      const held = await evidence(row.prepare_attempt_id);
      const checkpoint = JSON.parse(row.checkpoint_wire);
      const continuation = await held.record('continuation_record',
        checkpoint.continuation_state_cid);
      return { checkpoint, decisionSubjectCid: row.decision_subject_cid,
        verified: resolution && JSON.parse(resolution.verified_resolution_wire),
        continuation, invocation: await held.record('prepared_invocation',
          continuation.invocation_cid) };
    } };
}

// The approval binds the sealed subject artifact of the boundary itself, and
// the exact decision subject is a separate binding next to the Checkpoint.
function assertRealArtifact(sealed) {
  const required = sealed.checkpoint.required_artifact.artifact_cid;
  assert.match(sealed.decisionSubjectCid, /^sha256:[0-9a-f]{64}$/);
  assert.notEqual(sealed.decisionSubjectCid, required);
  assert.equal(sealed.verified.resolution.required_artifact_cid, required);
  assert.equal(sealed.verified.approval_evidence.compatibility_approval
    .prepared_invocation_cid, required);
  return required;
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
  // Preparation is decided on the invocation request before any path read;
  // only its defer captured the inputs, and the run-scope Checkpoint (and so
  // the approval evidence) requires the captured prepared invocation. The
  // decision-subject binding still names the request.
  const sealed = await input.sealed();
  assert.equal(sealed.checkpoint.kind, 'run_scope');
  assert.equal(sealed.checkpoint.required_artifact.artifact_type, 'prepared_invocation');
  assert.equal(assertRealArtifact(sealed), sealed.continuation.invocation_cid);
  assert.notEqual(sealed.continuation.invocation_cid, sealed.invocation.request_cid);
  assert.equal(sealed.continuation.delegated_subject.boundary, 'preparation');
  assert.equal(sealed.continuation.delegated_subject.subject_cid, sealed.invocation.request_cid);
  assert.equal(sealed.decisionSubjectCid,
    await decisionSubjectCid(sealed.continuation.delegated_subject));
  assert.equal(await input.stored(sealed.invocation.program_cid),
    await readFile(input.files.program, 'utf8'));
  assert.equal(await input.stored(sealed.invocation.parameters_cid), '{"minimum":1}');

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
  // The winner's terminal Run exit permits retiring the continuation's
  // private evidence. D2 is refused as stale at its fence or, when it wakes
  // after that retirement, when it tries to end the continuation: either way
  // in the single JSON `stale_claim` form.
  assert.equal(stale.stderr, '');
  assert.equal(stale.json.status, 'stale_claim');
  assert.equal(stale.json.code, 'ResumeClaimStale');
  assert.equal(stale.json.counters.provider_sessions, 0);
  const rows = input.rows();
  assert.equal(rows.runs, 1);
  assert.deepEqual(rows.intentRows, [{ state: 'completed', generation: 3,
    claimant: 'claimant-e', outcome_status: 'run_created' }]);
});

for (const outcome of ['deny', 'allow']) {
  // D-R5: a configuration now allowing the tuple is still a changed
  // configuration; it does not resume the waiting continuation.
  test(`a configuration changed to ${outcome} while waiting fails resume revalidation`, async t => {
    const input = await fixture(t);
    const waiting = await waitingRun(input);
    await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
    await writeFile(input.files.account,
      exampleAccountConfiguration({ database: input.database, outcome }));
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
}

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
  // The approval bound the prepared invocation captured before the change.
  const sealed = await input.sealed();
  assert.equal(assertRealArtifact(sealed), sealed.continuation.invocation_cid);
  assert.equal(await input.stored(sealed.invocation.parameters_cid), '{"minimum":1}');
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
  } finally { await host.close(); }
  assert.equal(waiting.status, 'waiting_checkpoint');
  assert.equal(waiting.checkpoint.kind, 'read_access');
  assert.equal(waiting.checkpoint.boundary, 'acquisition');
  assert.equal(waiting.counters.provider_sessions, 0);
  assert.equal(input.rows().runs, 0);
  // A later CLI process without a decision function answers and resumes: the
  // permitted preparation is not asked again, the approved read proceeds.
  const approved = await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  assert.equal(approved.json.results[0].status, 'committed');
  // The read Checkpoint requires the captured prepared invocation itself.
  const sealed = await input.sealed();
  assert.equal(sealed.checkpoint.required_artifact.artifact_type, 'read_scope');
  assert.equal(assertRealArtifact(sealed), sealed.continuation.invocation_cid);
  const resumed = await cli(['resume', waiting.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 0, resumed.stderr);
  assert.equal(resumed.json.status, 'succeeded');
  assert.equal(resumed.json.result_cid, expected);
  assert.equal(resumed.json.counters.provider_sessions, 1);
  assert.equal(resumed.json.counters.continuation_starts, 1);
  assert.equal(input.rows().checkpoints, 1);
});

test('an earlier immediate permit is not reused over a current Host answer', async t => {
  // The application permits preparation now and defers acquisition.
  const input = await fixture(t);
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
  } finally { await host.close(); }
  assert.equal(waiting.status, 'waiting_checkpoint');
  await cli(approveArgs(input, [waiting.checkpoint.checkpoint_id]));
  // At resume the application's decision function is present and now
  // rejects preparation: the earlier one-time permit authorizes no new
  // provider I/O, even though the read itself was approved.
  const asked = [];
  const resuming = await openLocalHost(input.config);
  let resumed;
  try {
    resumed = await resuming.resume(waiting.prepare_attempt_id, {
      decide: view => {
        asked.push(view.boundary);
        return { decision: 'reject', subject: view.subject, authority: 'application-policy' };
      },
    });
  } finally { await resuming.close(); }
  assert.deepEqual(asked, ['preparation']);
  assert.equal(resumed.status, 'ended');
  assert.equal(resumed.end_reason, 'failed');
  assert.equal(resumed.runtime_code, 'ACTQL_E_DELEGATION_REJECTED');
  assert.equal(resumed.boundary, 'preparation');
  assert.equal(resumed.counters.provider_sessions, 0);
  assert.equal(input.rows().runs, 0);
});

test('a preparation denial reads and captures no path-backed input', async t => {
  // Every operator-supplied input path is missing: any read would fail.
  const inputs = input => ({ database: input.database,
    environment: join(input.directory, 'missing-environment.json'),
    environmentCid: input.environmentCid,
    program: join(input.directory, 'missing-program.json'),
    parameters: join(input.directory, 'missing-parameters.json') });
  const cases = [
    ['account deny', 'deny', undefined, 'ACTQL_E_ACCOUNT_DENIED'],
    ['immediate Host reject', 'delegate', view => ({ decision: 'reject',
      subject: view.subject, authority: 'application-policy' }),
    'ACTQL_E_DELEGATION_REJECTED'],
  ];
  for (const [label, outcome, decide, code] of cases) {
    const input = await fixture(t, { outcome });
    const host = await openLocalHost(input.config);
    let refused;
    try {
      refused = await host.run(inputs(input), { decide,
        answeringAuthorities: decide === undefined ? undefined : ['application-policy'] });
    } finally { await host.close(); }
    assert.equal(refused.status, 'refused', label);
    assert.equal(refused.runtime_code, code, label);
    assert.equal(refused.boundary, 'preparation', label);
    assert.equal(refused.counters.provider_sessions, 0, label);
    assert.equal(await input.captured(), 0, label);
    assert.deepEqual([input.rows().runs, input.rows().checkpoints], [0, 0], label);
  }
  // The same missing inputs under a deferred decision fail at capture, after
  // the decision and before any Checkpoint: nothing waits on an uncaptured
  // invocation.
  const input = await fixture(t);
  const host = await openLocalHost(input.config);
  let failed;
  try { failed = await host.run(inputs(input)); } finally { await host.close(); }
  assert.equal(failed.status, 'refused');
  assert.equal(failed.runtime_code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
  assert.equal(failed.reason, 'adapter_error');
  assert.deepEqual([input.rows().runs, input.rows().checkpoints], [0, 0]);
});

test('an approval whose permission lapsed resumes no provider session', async t => {
  const input = await fixture(t);
  const clock = { ms: Date.now() };
  const host = await openLocalHost(input.config, { now: () => clock.ms });
  t.after(() => host.close());
  const waiting = await host.run({ database: input.database,
    environment: input.files.environment, environmentCid: input.environmentCid,
    program: input.files.program, parameters: input.files.parameters });
  assert.equal(waiting.status, 'waiting_checkpoint');
  const [answered] = await host.answer([waiting.checkpoint.checkpoint_id], 'approved',
    { signer: await readSigner(input.signer) });
  assert.equal(answered.status, 'committed');
  // The run-scope approval lasts until the Checkpoint deadline; the resume
  // comes after it. The claim itself succeeds (the lease is fresh), but the
  // resume port admits nothing and opens no source.
  clock.ms = Date.parse(waiting.checkpoint.expires_at);
  const resumed = await host.resume(waiting.prepare_attempt_id);
  assert.equal(resumed.status, 'ended');
  assert.equal(resumed.run_created, false);
  assert.equal(resumed.code, 'ApprovalExpired');
  assert.equal(resumed.counters.continuation_starts, 1);
  assert.equal(resumed.counters.provider_sessions, 0);
  // The historical Resolution is kept; no Run was created.
  const rows = input.rows();
  assert.equal(rows.resolutions, 1);
  assert.equal(rows.runs, 0);
  assert.deepEqual(rows.intentRows.map(row => row.outcome_status), ['failed']);
});

// The resume binding stored with a Checkpoint, as the Host claims with it.
function checkpointBinding(input, checkpointCid) {
  const sqlite = new DatabaseSync(input.journalPath, { readOnly: true });
  try {
    const bound = JSON.parse(sqlite.prepare(
      'SELECT binding_json FROM checkpoints WHERE checkpoint_cid = ?').get(checkpointCid)
      .binding_json);
    return { authorizationContextCid: bound.authorization_context_cid,
      environmentBindingCid: bound.environment_binding_cid };
  } finally { sqlite.close(); }
}

test('a later claimant after an entered provider session starts no second one', async t => {
  const input = await fixture(t);
  const clock = { ms: Date.now() };
  const host = await openLocalHost(input.config, { now: () => clock.ms });
  t.after(() => host.close());
  const waiting = await host.run({ database: input.database,
    environment: input.files.environment, environmentCid: input.environmentCid,
    program: input.files.program, parameters: input.files.parameters });
  assert.equal(waiting.status, 'waiting_checkpoint');
  await host.answer([waiting.checkpoint.checkpoint_id], 'approved',
    { signer: await readSigner(input.signer) });
  // Generation 1 claims and enters its protected provider session, then
  // stops before any completion; its lease lapses.
  const first = host.journal.claimPreparationResume(waiting.prepare_attempt_id, {
    claimant: 'claimant-1', leaseMs: 1000,
    binding: checkpointBinding(input, waiting.checkpoint.checkpoint_cid) });
  assert.equal(first.action, 'claimed');
  host.journal.enterResumedDispatch(first.claim,
    { checkpointCid: waiting.checkpoint.checkpoint_cid });
  clock.ms += 1000;
  // Generation 2 is refused a fresh start before any provider session and
  // leaves the intent unresolved for reconciliation or a later completion.
  const second = await host.resume(waiting.prepare_attempt_id, { claimant: 'claimant-2' });
  assert.equal(second.status, 'reconciliation_required');
  assert.equal(second.code, 'PriorAdmissionUnresolved');
  assert.equal(second.prior_generation, 1);
  assert.equal(second.counters.continuation_starts, 1);
  assert.equal(second.counters.provider_sessions, 0);
  const rows = input.rows();
  assert.equal(rows.runs, 0);
  assert.deepEqual(rows.intentRows, [{ state: 'claimed', generation: 2,
    claimant: 'claimant-2', outcome_status: '' }]);
  assert.equal(host.journal.getPreparation(waiting.prepare_attempt_id).status, 'resuming');
});

test('an earlier approval of the attempt that lapsed resumes no provider session', async t => {
  // A Host whose policy answers only exactly approved subjects: the
  // preparation approval does not cover the acquisition, which defers again.
  const scenario = async (t, resumeAt) => {
    const input = await fixture(t);
    const clock = { ms: Date.now() };
    const host = await openLocalHost(input.config, { now: () => clock.ms,
      coverage: exactApprovedSubject });
    t.after(() => host.close());
    const signer = await readSigner(input.signer);
    const waiting = await host.run({ database: input.database,
      environment: input.files.environment, environmentCid: input.environmentCid,
      program: input.files.program, parameters: input.files.parameters });
    assert.equal(waiting.checkpoint.boundary, 'preparation');
    await host.answer([waiting.checkpoint.checkpoint_id], 'approved', { signer });
    // Later, the preparation resumes and its acquisition defers again.
    clock.ms += 60_000;
    const read = await host.resume(waiting.prepare_attempt_id);
    assert.equal(read.status, 'waiting_checkpoint');
    assert.equal(read.checkpoint.boundary, 'acquisition');
    assert.equal(read.counters.provider_sessions, 0);
    assert(Date.parse(read.checkpoint.expires_at) >
      Date.parse(waiting.checkpoint.expires_at));
    await host.answer([read.checkpoint.checkpoint_id], 'approved', { signer });
    clock.ms = resumeAt(Date.parse(waiting.checkpoint.expires_at));
    return { input, resumed: await host.resume(waiting.prepare_attempt_id) };
  };
  // The claimed acquisition approval is current but the earlier preparation
  // approval's own permission lapsed: nothing is admitted.
  const lapsed = await scenario(t, expiry => expiry);
  assert.equal(lapsed.resumed.status, 'ended');
  assert.equal(lapsed.resumed.code, 'ApprovalExpired');
  assert.equal(lapsed.resumed.counters.provider_sessions, 0);
  assert.equal(lapsed.input.rows().runs, 0);
  assert.equal(lapsed.input.rows().resolutions, 2);
  // Just before that expiry both approvals admit the continuation.
  const current = await scenario(t, expiry => expiry - 1);
  assert.equal(current.resumed.status, 'succeeded', JSON.stringify(current.resumed));
  assert.equal(current.resumed.counters.provider_sessions, 1);
});

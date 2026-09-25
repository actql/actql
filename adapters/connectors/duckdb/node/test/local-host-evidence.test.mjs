// Private continuation evidence of the real Local Host: encrypted in the
// Local Store, read back through it after restart, bound to the installation
// key, held per continuation and retired only when no continuation needs it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes } from 'node:crypto';
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DuckDBInstance } from '@duckdb/node-api';
import { exampleAccountConfiguration } from '../examples/physical-strategy.mjs';
import { openLocalHost } from '../examples/local-host.mjs';
import { runtimeCore } from '../../../../host-common/runtime-core.mjs';
import { loadPrivateEvidenceKey, openContinuationEvidence } from
  '../../../../host-node/local-continuation-evidence.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const cliPath = fileURLToPath(new URL('../examples/local-host-cli.mjs', import.meta.url));
const exec = promisify(execFile);
// A private parameter value; `.` never occurs in base64 ciphertext.
const SECRET = '1.000731';
const PARAMETERS = `{"minimum":${SECRET}}`;
// Kinds that occur only inside the private records themselves.
const PRIVATE_MARKERS = [SECRET, 'local-example-review', 'local-example-continuation',
  'local-example-prepared-invocation', 'local-example-invocation-request'];
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

function cli(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--no-warnings', cliPath, ...args],
      { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.stdin.end();
    child.on('error', reject);
    child.on('close', code => {
      let json;
      try { json = JSON.parse(stdout); } catch {}
      resolve({ code, json, stdout, stderr });
    });
  });
}

async function fixture(t) {
  await build();
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'local-host-evidence-'));
  t.after(async () => {
    await chmod(join(directory, 'host/state/private-store/objects'), 0o700).catch(() => {});
    await rm(directory, { recursive: true, force: true });
  });
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
    writeFile(files.parameters, PARAMETERS),
    writeFile(files.account, exampleAccountConfiguration({ database, outcome: 'delegate' })),
  ]);
  const init = await cli(['init', '--directory', join(directory, 'host'),
    '--account-config', files.account, '--reviewer', 'alice']);
  assert.equal(init.code, 0, init.stderr);
  const state = join(directory, 'host/state');
  const store = join(state, 'private-store');
  const journalPath = join(state, 'journal/checkpoint-journal.sqlite3');
  const config = init.json.config;
  const moon = await import(join(root,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'));
  return {
    directory, state, config, init: init.json, files, database,
    keyPath: join(state, 'private-evidence.key'),
    runArgs: ['run', '--config', config, '--database', database,
      '--environment', files.environment, '--environment-cid', catalog[2],
      '--program', files.program, '--parameters', files.parameters],
    options: { database, environment: files.environment, environmentCid: catalog[2],
      program: files.program, parameters: files.parameters },
    approve: reference => cli(['approve', reference, '--config', config,
      '--signer', init.json.signer]),
    // Reads only through the encrypted Store with the installation key.
    async read(attempt, name, cid) {
      const port = openContinuationEvidence({ stateDirectory: state,
        ...await loadPrivateEvidenceKey(state),
        contractControl: runtimeCore(moon).publicationControl,
        preparation: () => undefined });
      try { return (await (await port.open(attempt)).bytes(name, cid)).toString('utf8'); }
      finally { await port.close(); }
    },
    ledger: async attempt =>
      JSON.parse(await readFile(join(state, 'attempts', `${attempt}.json`), 'utf8')),
    async holding(cid) {
      try {
        return JSON.parse(await readFile(join(store, 'physical-holdings',
          `${cid.slice('sha256:'.length)}.json`), 'utf8'));
      } catch (error) { if (error.code === 'ENOENT') return undefined; throw error; }
    },
    objects: async () => (await readdir(join(store, 'objects'))).sort(),
    objectsDirectory: join(store, 'objects'),
    intents() {
      const sqlite = new DatabaseSync(journalPath, { readOnly: true });
      try {
        return sqlite.prepare('SELECT state, generation FROM resume_intents').all()
          .map(row => ({ ...row }));
      } finally { sqlite.close(); }
    },
  };
}

async function filesUnder(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await filesUnder(path));
    else if (entry.isFile()) found.push(path);
  }
  return found;
}

// Every byte under the state directory, including the SQLite journal and WAL.
async function assertNoPlaintext(state) {
  const files = await filesUnder(state);
  assert(files.length > 0);
  for (const path of files) {
    const bytes = await readFile(path);
    for (const marker of PRIVATE_MARKERS) {
      assert.equal(bytes.includes(Buffer.from(marker, 'utf8')), false, `${marker} in ${path}`);
    }
  }
}

async function waiting(input) {
  const run = await cli(input.runArgs);
  assert.equal(run.code, 0, run.stderr);
  assert.equal(run.json.status, 'waiting_checkpoint');
  return run.json;
}

// The parameters holding of one continuation, found through its record.
async function parametersOf(input, attempt, checkpoint) {
  const sqlite = new DatabaseSync(join(input.state, 'journal/checkpoint-journal.sqlite3'),
    { readOnly: true });
  let wire;
  try {
    wire = sqlite.prepare('SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?')
      .get(checkpoint).checkpoint_wire;
  } finally { sqlite.close(); }
  const continuation = JSON.parse(await input.read(attempt, 'continuation_record',
    JSON.parse(wire).continuation_state_cid));
  const invocation = JSON.parse(await input.read(attempt, 'prepared_invocation',
    continuation.invocation_cid));
  const reference = continuation.evidence.find(item => item.name === 'captured_input' &&
    item.semantic_cid === invocation.parameters_cid);
  assert(reference);
  return { continuation, invocation, reference };
}

test('evidence is encrypted, read through the Store after restart and retired at terminal exit',
  async t => {
    const input = await fixture(t);
    assert.equal(input.init.privateEvidenceKey, input.keyPath);
    assert.equal((await stat(input.keyPath)).mode & 0o777, 0o600);
    assert.equal((await readFile(input.keyPath)).byteLength, 32);
    const run = await waiting(input);
    await assertNoPlaintext(input.state);
    // A later process reads the exact captured parameters through the Store.
    const { continuation, invocation, reference } = await parametersOf(input,
      run.prepare_attempt_id, run.checkpoint.checkpoint_cid);
    assert.equal(await input.read(run.prepare_attempt_id, 'captured_input',
      invocation.parameters_cid), PARAMETERS);
    const { keyId } = await loadPrivateEvidenceKey(input.state);
    assert.equal(reference.key_id, keyId);
    const ledger = await input.ledger(run.prepare_attempt_id);
    assert.equal(ledger.key_id, keyId);
    assert(ledger.holdings.some(item => item.holding_cid === reference.holding_cid &&
      item.state === 'held'));
    assert.equal((await input.holding(reference.holding_cid)).namespace,
      'local-continuation-private');
    for (const item of continuation.evidence) {
      assert.equal((await input.holding(item.holding_cid)).manifest_cid, item.semantic_cid);
    }
    // close() and an explicit retire never delete waiting evidence.
    const kept = await cli(['retire', '--config', input.config]);
    assert.equal(kept.code, 0, kept.stderr);
    assert.deepEqual(kept.json, { retired: [], pending: [] });
    assert.equal(await input.read(run.prepare_attempt_id, 'captured_input',
      invocation.parameters_cid), PARAMETERS);

    assert.equal((await input.approve(run.checkpoint.checkpoint_id)).code, 0);
    const resumed = await cli(['resume', run.prepare_attempt_id, '--config', input.config]);
    assert.equal(resumed.code, 0, resumed.stderr);
    assert.equal(resumed.json.status, 'succeeded');
    await assertNoPlaintext(input.state);
    // Terminal Run exit released every holding except the request identity.
    const retired = await input.ledger(run.prepare_attempt_id);
    for (const item of retired.holdings) {
      assert.equal(item.state, item.name === 'invocation_request' ? 'held' : 'retired',
        item.name);
      assert.equal(await input.holding(item.holding_cid) !== undefined,
        item.name === 'invocation_request', item.name);
    }
    assert.equal((await input.objects()).length, 1);
    await assert.rejects(input.read(run.prepare_attempt_id, 'captured_input',
      invocation.parameters_cid), { code: 'ContinuationEvidenceRetired' });
    // The completed preparation still answers from its retained request.
    const again = await cli(['resume', run.prepare_attempt_id, '--config', input.config]);
    assert.equal(again.json.status, 'completed');
  });

test('a different installation key is refused before any decryption or claim', async t => {
  const input = await fixture(t);
  const run = await waiting(input);
  assert.equal((await input.approve(run.checkpoint.checkpoint_id)).code, 0);
  const original = await readFile(input.keyPath);
  await rm(input.keyPath);
  await writeFile(input.keyPath, randomBytes(32), { mode: 0o600, flag: 'wx' });
  const refused = await cli(['resume', run.prepare_attempt_id, '--config', input.config]);
  assert.equal(refused.code, 1);
  assert.equal(JSON.parse(refused.stderr).error, 'PrivateEvidenceKeyMismatch');
  assert.deepEqual(input.intents(), [{ state: 'pending', generation: 0 }]);
  // A missing or exposed key file is not silently replaced.
  await rm(input.keyPath);
  const missing = await cli(['list', '--config', input.config]);
  assert.equal(JSON.parse(missing.stderr).error, 'PrivateEvidenceKeyUnavailable');
  await writeFile(input.keyPath, original, { mode: 0o644, flag: 'wx' });
  await chmod(input.keyPath, 0o644);
  const exposed = await cli(['list', '--config', input.config]);
  assert.equal(JSON.parse(exposed.stderr).error, 'PrivateEvidenceKeyExposed');
  // The installation key resumes the untouched continuation.
  await chmod(input.keyPath, 0o600);
  const resumed = await cli(['resume', run.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.code, 0, resumed.stderr);
  assert.equal(resumed.json.status, 'succeeded');
});

test('continuations hold shared evidence independently', async t => {
  const input = await fixture(t);
  const first = await waiting(input);
  const second = await waiting(input);
  const a = await parametersOf(input, first.prepare_attempt_id,
    first.checkpoint.checkpoint_cid);
  const b = await parametersOf(input, second.prepare_attempt_id,
    second.checkpoint.checkpoint_cid);
  assert.equal(a.reference.semantic_cid, b.reference.semantic_cid);
  assert.notEqual(a.reference.holding_cid, b.reference.holding_cid);
  // One encrypted object, two holdings.
  assert.deepEqual((await input.holding(a.reference.holding_cid)).objects,
    (await input.holding(b.reference.holding_cid)).objects);
  // Cancelling the first continuation retires its holdings only.
  const cancelled = await cli(['cancel', first.prepare_attempt_id, '--config', input.config]);
  assert.equal(cancelled.code, 0, cancelled.stderr);
  assert.equal(cancelled.json.retention, undefined);
  assert.equal(await input.holding(a.reference.holding_cid), undefined);
  assert.equal((await input.ledger(first.prepare_attempt_id)).holdings
    .find(item => item.holding_cid === a.reference.holding_cid).state, 'retired');
  const [object] = (await input.holding(b.reference.holding_cid)).objects;
  assert((await input.objects()).includes(object.cid.slice('sha256:'.length)));
  assert.equal(await input.read(second.prepare_attempt_id, 'captured_input',
    b.invocation.parameters_cid), PARAMETERS);
  // The second continuation still resumes; its terminal exit releases the
  // last hold of the shared object.
  assert.equal((await input.approve(second.checkpoint.checkpoint_id)).code, 0);
  const resumed = await cli(['resume', second.prepare_attempt_id, '--config', input.config]);
  assert.equal(resumed.json.status, 'succeeded', resumed.stderr);
  assert.equal(await input.holding(b.reference.holding_cid), undefined);
  assert.equal((await input.objects()).includes(object.cid.slice('sha256:'.length)), false);
});

test('a failed deletion keeps cleanup ownership and a retry completes it', async t => {
  const input = await fixture(t);
  // In process: the same Host retries its own pending deletion.
  const host = await openLocalHost(input.config);
  let run;
  let reference;
  try {
    run = await host.run(input.options);
    assert.equal(run.status, 'waiting_checkpoint');
    assert.equal(host.cancel(run.prepare_attempt_id).outcome, 'cancelled');
    await chmod(input.objectsDirectory, 0o500);
    const failed = await host.retire();
    await chmod(input.objectsDirectory, 0o700);
    assert.equal(failed.pending.length > 0, true);
    assert(failed.pending.every(item => item.prepare_attempt_id === run.prepare_attempt_id &&
      item.code === 'EACCES'));
    const ledger = await input.ledger(run.prepare_attempt_id);
    reference = ledger.holdings.find(item => item.name === 'captured_input');
    assert.equal(reference.state, 'retiring');
    assert.equal(reference.cleanup_error, 'EACCES');
    const retried = await host.retire();
    assert.deepEqual(retried.pending, []);
    assert(retried.retired.includes(reference.holding_cid));
  } finally { await host.close(); }
  assert.equal((await input.ledger(run.prepare_attempt_id)).holdings
    .find(item => item.holding_cid === reference.holding_cid).state, 'retired');
  assert.equal((await input.objects()).length, 1);

  // Across processes: a failed deletion reported by one command is retried by
  // a later process through the Store's durable deletion record.
  const other = await waiting(input);
  await chmod(input.objectsDirectory, 0o500);
  const cancelled = await cli(['cancel', other.prepare_attempt_id, '--config', input.config]);
  await chmod(input.objectsDirectory, 0o700);
  assert.equal(cancelled.code, 0, cancelled.stderr);
  assert(cancelled.json.retention.pending.length > 0);
  const retry = await cli(['retire', '--config', input.config]);
  assert.equal(retry.code, 0, retry.stderr);
  assert.deepEqual(retry.json.pending, []);
  for (const item of (await input.ledger(other.prepare_attempt_id)).holdings) {
    assert.equal(item.state, item.name === 'invocation_request' ? 'held' : 'retired');
  }
  // Only the (shared) request identity remains.
  assert.equal((await input.objects()).length, 1);
});

// Prepared public CLI acceptance. This command never builds an executable or
// falls back to the Node Host. Run only with an allocated verification window.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, rename, stat, unlink, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {isAbsolute, join, resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import {admitNativeArtifact} from './native-cli-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {inspectNativeLocalJournal, assertNativeLocalJournalUnchanged} from './native-local-journal-observation.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const fixtures = fileURLToPath(new URL('./fixtures/native-local-cli/', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
// Independent expectation identity: values are retained, with sorted keys only.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);

// Check the authored original before any Native process. Do not silently repair
// its bytes: the shared Check Environment Owner requires canonical input.
export function verifyNativeLocalCheckEnvironmentOriginal(bytes) {
  const environment = JSON.parse(bytes.toString('utf8'));
  const {evidence_bundle_cid, ...preimage} = environment;
  verifyIdentity(preimage, evidence_bundle_cid);
  assert(Buffer.from(canonicalText(environment), 'utf8').equals(Buffer.from(bytes)),
    'The original Check Environment must contain exact canonical bytes');
  return environment;
}

export async function inspectNativeLocalSourceFixture() {
  const names = ['source-program.json', 'source-expected.json', 'source-environment.json',
    'source-installation.json', 'run-installation.json', 'read-installation.json'];
  const bytes = await Promise.all(names.map(name => readFile(join(fixtures, name))));
  const [program, expected, environment, sourceOriginal, runOriginal, readOriginal] =
    bytes.map(value => JSON.parse(value));
  verifyNativeLocalCheckEnvironmentOriginal(bytes[2]);
  const source = sourceOriginal.native.source, run = runOriginal.native.run;
  const read = readOriginal.native.result_read;
  const policy = environment.contract_registry.find(value => value.kind === 'data_policy');
  assert(policy, 'The actual Source Policy original is required');
  assert.equal(policy.body.classification, 'unknown', 'Do not declassify the Source');
  assert.equal(policy.body.source_ref, source.source_ref);
  assert.deepEqual(read.data_policy_cids, [policy.cid]);
  assert.equal(JSON.parse(run.retention_policy_wire).effective_data_policy_cid, policy.cid);
  const catalog = environment.connector_catalogs.find(value => value.connector_id === 'crm/main');
  assert(catalog?.contracts.some(value => value.cid === policy.cid && canonical(value) === canonical(policy)),
    'The checked Source catalog retains the same Policy original');
  assert.equal(environment.schema_snapshots[0].source_data_policy_cid, policy.cid);
  assert.deepEqual(expected.rows, [{id: 3}]);
  assert.deepEqual(expected.columns, ['id']);
  assert.deepEqual(expected.schema, {id: {type: 'number', nullable: false}});
  assert.equal(Object.keys(program.results).length, 1);
  assert.equal(expected.resultName, 'answer');
  assert.deepEqual(read.result_names, [expected.resultName]);
  assert.deepEqual(read.formats, ['jsonl']);
  assert.equal(read.sink, 'stdout');
  assert.equal(read.max_bytes, run.result_payload_bytes);
  assert.equal(read.max_uses, 1);
  assert.equal(source.ledger.retained_bytes, 536870912);
  assert.equal(source.ledger.execution_bytes, 536870912);
  return {expected, environment, sourceOriginal, runOriginal, readOriginal,
    inputs: names.map((name, index) => ({name, bytes: bytes[index].length, sha256: hash(bytes[index])}))};
}

const permission = (entry_id, resource, operation) => ({entry_id, outcome: 'allow',
  principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
  resource: {any_of: [resource]}, operation: {any_of: [operation]}, exclusions: []});

// Read-only diagnostics of the existing journal, after each Native process has
// exited. These records do not replace public lookup or grant/Store admission.
function inspectResultMetadata(path) {
  const database = new DatabaseSync(path, {readOnly: true});
  try {
    return {
      usage: database.prepare("SELECT body FROM actql_records WHERE namespace = 'result_read_grant_usage' ORDER BY record_key")
        .all().map(row => JSON.parse(Buffer.from(row.body).toString('utf8'))),
      contracts: database.prepare("SELECT body FROM actql_records WHERE namespace = 'publication_contract' ORDER BY record_key")
        .all().map(row => JSON.parse(Buffer.from(row.body).toString('utf8'))),
    };
  } finally { database.close(); }
}

function assertJournalSnapshotUnchanged(before, after, message) {
  assertNativeLocalJournalUnchanged(before.host, after.host, message);
  assertNativeLocalJournalUnchanged(before.store, after.store, message);
}

export async function runNativeLocalSourceResult({artifactDirectory, sourceSha,
  duckdbPackage, sqliteLibrary, cryptoLibrary, duckdbLibrary}) {
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1',
    'Keep the original Host/Store custody and process receipts for review');
  for (const path of [artifactDirectory, duckdbPackage, sqliteLibrary, cryptoLibrary, duckdbLibrary]) {
    assert.equal(typeof path, 'string');
    assert(isAbsolute(path), 'Select actual dependencies explicitly; no discovery or download');
  }
  // System dylibs may live in the OS shared cache rather than as stat-able
  // files. The Native library Owners validate their explicit identifiers.
  for (const path of [artifactDirectory, duckdbPackage, duckdbLibrary]) await stat(path);
  const source = checkoutState(repository);
  assert(source.clean && source.revision === sourceSha, 'Use the fixed clean acceptance source');
  const artifact = await admitNativeArtifact(artifactDirectory, sourceSha);
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  assert.equal(artifact.platform, platformKey({platform: process.platform, arch: process.arch, glibc}));
  assert.equal(artifact.toolchainPinSha256, hash(await readFile(join(repository, 'toolchain.json'))));
  const executable = join(artifactDirectory, 'actql-native-client');
  const selected = await inspectNativeLocalSourceFixture();
  const scratch = await createOwnedScratch({parent: '/private/tmp', prefix: 'actql-native-local-source-result-',
    label: 'Native CLI original Source/Result processes', digests: () => ['acceptance.json']});
  const root = scratch.path, managed = join(root, 'managed');
  const commands = [], checks = [];
  const record = {sourceSha, artifact, artifactManifestSha256: hash(await readFile(join(artifactDirectory, 'artifact.json'))),
    inputs: selected.inputs, commands, checks, acceptance: false,
    scope: 'Native CLI artifact; no npm install, Effect or full-holder release claim'};
  const snapshot = () => ({host: inspectNativeLocalJournal(join(root, 'host', 'client.sqlite3')),
    store: inspectNativeLocalJournal(join(managed, 'results', '.actql-publication.sqlite3'))});
  const invoke = args => {
    const command = [executable, '--mode', 'local', '--config-root', root,
      '--config-file', 'actql.config.json', ...args];
    const result = spawnSync(command[0], command.slice(1), {cwd: root,
      env: {...process.env, PATH: ''}, encoding: 'utf8', timeout: 15000, maxBuffer: 1048576});
    const observation = {command, pid: result.pid ?? null, status: result.status, signal: result.signal,
      error: result.error?.message ?? null, stdout: result.stdout, stderr: result.stderr, exitObservedAbsent: false};
    commands.push(observation);
    assert.ifError(result.error);
    assert.equal(result.signal, null, 'The Native process must actually exit');
    assert(result.pid > 0);
    assert.throws(() => process.kill(result.pid, 0), {code: 'ESRCH'}, 'Confirm original CLI process termination');
    observation.exitObservedAbsent = true;
    return result;
  };
  const success = result => { assert.equal(result.status, 0, result.stderr); return JSON.parse(result.stdout); };
  const refused = (result, reason) => {
    assert.equal(result.status, 1, result.stderr); assert.equal(result.stdout, ''); assert.match(result.stderr, reason);
  };
  const refs = ['--submission-ref-file', 'original-submission.json', '--ref-file', 'original-run.json'];
  const readArgs = (attempt, maxBytes = '65536') => ['read', ...refs, '--result-name', 'answer', '--purpose', 'inspection',
    '--format', 'jsonl', '--attempt-id', attempt, '--max-output-bytes', maxBytes];
  const lookupArgs = attempt => ['delivery-attempt', ...refs, '--result-name', 'answer',
    '--purpose', 'inspection', '--attempt-id', attempt];
  const lookup = () => success(invoke(['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  try {
    await mkdir(managed, {mode: 0o700});
    for (const name of ['source-program.json', 'source-environment.json', 'run-installation.json', 'read-installation.json']) {
      await copyFile(join(fixtures, name), join(root, name));
    }
    const installation = structuredClone(selected.sourceOriginal);
    installation.native.source.duckdb_library = duckdbLibrary;
    await writeFile(join(root, 'source-installation.json'), JSON.stringify(installation) + '\r\n');
    await writeFile(join(root, 'account.json'), JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'operator', entries: [permission('submit', 'run', 'submit'), permission('run-read', 'run', 'read'),
        permission('result-read', 'result/answer', 'read'), permission('source-read', installation.native.source.source_ref, 'read')]}));
    await writeFile(join(root, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1', account_config: 'account.json',
      native: {check_environment: {file: 'source-environment.json', evidence_bundle_cid: selected.environment.evidence_bundle_cid},
        local: {account_id: 'operator', principal: 'operator', connection: 'cli', state_parent: root, state_name: 'host',
          managed_root: managed, sqlite_library: sqliteLibrary, signature_library: cryptoLibrary,
          submission_ttl_ms: 60000, journal_record_limit: 8, journal_snapshot_bytes: 8388608,
          installation_files: ['source-installation.json', 'run-installation.json', 'read-installation.json'],
          source_file: 'source-installation.json', run_file: 'run-installation.json', read_file: 'read-installation.json'}}}));
    // Node creates only synthetic fixture data. All Program operations below
    // execute in the selected Native artifact with no command available in PATH.
    const {DuckDBInstance} = createRequire(import.meta.url)(duckdbPackage);
    const database = await DuckDBInstance.create(join(managed, 'records.duckdb'));
    try {
      const connection = await database.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE NOT NULL, amount DOUBLE)');
        for (const row of selected.expected.fixtureRows) {
          assert(Number.isFinite(row.id) && (row.amount === null || Number.isFinite(row.amount)));
          await connection.run(`INSERT INTO records VALUES (${row.id},${row.amount === null ? 'NULL' : row.amount})`);
        }
      } finally { connection.closeSync(); }
    } finally { database.closeSync(); }
    record.setup = {duckdbPackage, sqliteLibrary, cryptoLibrary, duckdbLibrary,
      databaseSha256: hash(await readFile(join(managed, 'records.duckdb')))};
    const adoption = success(invoke(['adopt', '--json']));
    const connected = success(invoke(['connect', '--json']));
    assert.equal(connected.adoptionCid, adoption.adoptionCid);
    const submission = success(invoke(['new-submission', '--request-id', 'original-source-result']));
    await writeFile(join(root, 'original-submission.json'), JSON.stringify(submission));
    const first = invoke(['start', '--program-file', 'source-program.json', '--submission-ref-file',
      'original-submission.json', '--operation-attempt-id', 'first-start']);
    assert.equal(first.status, 0, first.stderr);
    // Deliberately do not use the start reply to construct recovery references.
    // Discarded stdout models caller response loss after the producer exited.
    await rename(join(managed, 'records.duckdb'), join(managed, 'source-retained-for-diagnosis.duckdb'));
    await unlink(join(root, 'source-program.json'));
    const original = lookup();
    const published = JSON.parse(first.stdout);
    assert.equal(published.kind, 'local_run_published');
    assert.deepEqual(published.resultNames, ['answer']);
    assert.deepEqual(original.ref, published.ref);
    assert.deepEqual(original.submissionRef, submission);
    assert.equal(original.history, 'retained');
    await writeFile(join(root, 'original-run.json'), JSON.stringify(original.ref));
    checks.push('Original Submission recovers the published Run after exited producer and discarded reply');
    const beforeReads = snapshot();
    const neverOpened = success(invoke(lookupArgs('first-read')));
    assert.equal(neverOpened.history, 'unresolved');
    assertJournalSnapshotUnchanged(beforeReads, snapshot(), 'Metadata lookup must not issue grants or reserve/open payloads');
    const delivered = [];
    for (const attempt of ['first-read', 'explicit-new-read']) {
      const payload = invoke(readArgs(attempt));
      assert.equal(payload.status, 0, payload.stderr);
      assert.equal(payload.stdout.endsWith('\n'), true);
      const rows = payload.stdout.trimEnd().split('\n').map(line => JSON.parse(line));
      assert.deepEqual(rows, selected.expected.rows);
      for (const row of rows) assert.deepEqual(Object.keys(row), selected.expected.columns);
      const observed = success(invoke(lookupArgs(attempt)));
      assert.equal(observed.history, 'retained');
      assert.deepEqual(observed.ref, original.ref);
      assert.equal(observed.attempt.attempt_id, attempt);
      assert.equal(observed.attempt.run_definition_cid, original.runDefinitionCid);
      assert.equal(observed.record.state, 'succeeded');
      assert.equal(observed.record.confirmed_byte_count, Buffer.byteLength(payload.stdout));
      assert.equal(observed.record.delivered_sha256, hash(payload.stdout));
      assert.equal(observed.hostReleaseReceipt.result_delivery_receipt_cid, observed.record.result_delivery_receipt_cid);
      const stable = snapshot();
      assert.deepEqual(success(invoke(lookupArgs(attempt))), observed);
      refused(invoke(readArgs(attempt)), /LocalReadAttemptAlreadyStarted/u);
      assertJournalSnapshotUnchanged(stable, snapshot(), 'Same attempt neither reopens nor consumes another grant/reservation');
      assert.equal(lookup().controlRevision, original.controlRevision, 'Read does not mutate Run control');
      delivered.push(observed);
    }
    assert.notEqual(delivered[0].attempt.result_read_grant_cid, delivered[1].attempt.result_read_grant_cid);
    const completedReads = snapshot();
    const evidence = completedReads.host.records.filter(row => row.namespace === 'client_local_read_evidence');
    assert.equal(evidence.length, 2, 'Only the two explicitly requested attempts have originals');
    const metadata = inspectResultMetadata(join(managed, 'results', '.actql-publication.sqlite3'));
    const usage = metadata.usage;
    assert.equal(usage.length, 2);
    for (const [index, item] of usage.entries()) {
      assert.equal(item.use_count, 1); assert.equal(item.max_uses, 1);
      assert.equal(item.delivery_attempt_cids.length, 1);
      assert(delivered.some(value => value.attempt.delivery_attempt_cid === item.delivery_attempt_cids[0]), `usage ${index}`);
    }
    const contracts = metadata.contracts;
    const binding = contracts.find(value => value.version === 'actql-durable-result-binding/0.1');
    assert(binding);
    assert.deepEqual(binding.result_fields, selected.expected.columns);
    assert.equal(binding.row_count, selected.expected.rows.length);
    assert.equal(binding.result_schema_cid, `sha256:${hash(canonical(selected.expected.schema))}`);
    checks.push('Independent rows, column order and schema; explicit new read with one use per grant');
    checks.push('No original Program/Source available during lookup/read; original Run control unchanged');
    const short = invoke(readArgs('bounded-interruption', '1'));
    assert.equal(short.status, 1, short.stderr);
    assert.match(short.stderr, /LocalReadInterrupted/u);
    assert.equal(short.stdout, '{', 'Only the one-byte prefix may reach stdout');
    const interrupted = success(invoke(lookupArgs('bounded-interruption')));
    assert.equal(interrupted.history, 'retained');
    assert.equal(interrupted.record.state, 'failed');
    assert.equal(interrupted.record.confirmed_byte_count, 1);
    assert.equal(interrupted.hostReleaseReceipt, null, 'An interrupted read is not a completed delivery');
    const afterReads = snapshot();
    refused(invoke(readArgs('bounded-interruption', '1')), /LocalReadAttemptAlreadyStarted/u);
    assertJournalSnapshotUnchanged(afterReads, snapshot(), 'Interruption cannot reopen the original attempt');
    assert.equal(lookup().controlRevision, original.controlRevision);
    checks.push('Explicit one-byte sink cap retains a prefix without a completion receipt or internal replacement attempt');
    await writeFile(join(root, 'foreign-run.json'), JSON.stringify({...original.ref, namespaceId: 'another-run'}));
    const foreign = [...readArgs('foreign')]; foreign[foreign.indexOf('original-run.json')] = 'foreign-run.json';
    refused(invoke(foreign), /LocalOriginalRunReferenceMismatch/u);
    assertJournalSnapshotUnchanged(afterReads, snapshot(), 'Foreign reference must fail without new originals or grant');
    checks.push('Foreign Run reference refused without modifying retained custody');
    // Changing the originally adopted file is not a current Policy update.
    const changed = structuredClone(selected.readOriginal);
    changed.native.result_read.max_bytes = 32768;
    await writeFile(join(root, 'read-installation.json'), JSON.stringify(changed));
    refused(invoke(readArgs('replacement-read')), /LocalConfigurationChanged/u);
    assertJournalSnapshotUnchanged(afterReads, snapshot(), 'Replacing the selected original cannot refresh adoption or grant');
    checks.push('Changed adopted read original refused without refreshing custody');
    record.beforeReads = beforeReads; record.afterReads = afterReads; record.delivered = delivered;
    record.interrupted = interrupted;
    assert.deepEqual(checkoutState(repository), source);
    record.acceptance = true;
    await writeFile(join(root, 'acceptance.json'), JSON.stringify(record, null, 2) + '\n');
    console.log(JSON.stringify({sourceSha, binarySha256: artifact.binarySha256, checks,
      commands: commands.length, acceptance: true, receipt: join(root, 'acceptance.json')}));
    scratch.passed();
  } finally {
    await writeFile(join(root, 'acceptance.json'), JSON.stringify(record, null, 2) + '\n');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--preflight') {
    const fixture = await inspectNativeLocalSourceFixture();
    console.log(JSON.stringify({inputs: fixture.inputs, fixturePreflight: true,
      nativeCliExecuted: false, publicAcceptance: false}));
  } else {
    assert.equal(args.length, 6, 'usage: test-native-local-source-result.mjs <artifact-dir> <source-sha> <duckdb-node-api-package> <sqlite-library> <crypto-library> <duckdb-library> | --preflight');
    const [artifactDirectory, sourceSha, duckdbPackage, sqliteLibrary, cryptoLibrary, duckdbLibrary] = args;
    await runNativeLocalSourceResult({artifactDirectory, sourceSha, duckdbPackage, sqliteLibrary, cryptoLibrary, duckdbLibrary});
  }
}

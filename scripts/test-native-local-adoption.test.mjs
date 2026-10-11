// Actual Native CLI processes only. Adoption is not Source/Result acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, copyFile, mkdir, readFile, rename, stat, unlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';

const binary = process.env.ACTQL_TEST_NATIVE_CLIENT_BINARY ?? fileURLToPath(new URL(
  '../_build/native/release/build/cmd/native_client/native_client.exe', import.meta.url));
const sqlite = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY;
const crypto = process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY;
assert.ok(sqlite && crypto, 'Select the actual Native SQLite and crypto libraries explicitly');
const scratch = await createOwnedScratch({parent: '/private/tmp', prefix: 'actql-native-local-adoption-',
  label: 'Native CLI original Host adoption'});
console.log(`Native CLI binary sha256:${createHash('sha256').update(await readFile(binary)).digest('hex')}`);
after(() => scratch.passed());

async function fixture(name, entries = []) {
  const root = join(scratch.path, name);
  await mkdir(root, {mode: 0o700});
  await mkdir(join(root, 'managed'), {mode: 0o700});
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/environment.json', import.meta.url)),
    join(root, 'environment.json'));
  await writeFile(join(root, 'account.json'), JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'operator', entries,
  }) + '\r\n');
  const configuration = {
    version: 'actql-config/0.1', account_config: 'account.json',
    native: {
      check_environment: {file: 'environment.json',
        evidence_bundle_cid: 'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904'},
      local: {account_id: 'operator', principal: 'operator', connection: 'cli',
        state_parent: root, state_name: 'host', managed_root: join(root, 'managed'),
        sqlite_library: sqlite, signature_library: crypto, submission_ttl_ms: 60000,
        journal_record_limit: 8, journal_snapshot_bytes: 8388608},
    },
  };
  const save = async () => writeFile(join(root, 'actql.config.json'), JSON.stringify(configuration) + '\r\n');
  await save();
  return {root, configuration, save};
}

function invoke(fixture, args, options = []) {
  const result = spawnSync(binary, ['--mode', 'local', '--config-root', fixture.root,
    '--config-file', 'actql.config.json', ...options, ...args],
  {cwd: fixture.root, env: {...process.env, PATH: ''}, encoding: 'utf8', timeout: 15000});
  assert.ifError(result.error);
  assert.equal(result.signal, null, 'The actual CLI process must exit');
  assert.ok(result.pid > 0);
  return result;
}

function success(result) {
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

function refusal(result, reason) {
  assert.equal(result.status, 1, result.stderr);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, reason);
}

async function journal(fixture) {
  return readFile(join(fixture.root, 'host', 'client.sqlite3'));
}

test('Native CLI connect cannot initialize an absent Host', async () => {
  const f = await fixture('no-host');
  refusal(invoke(f, ['connect', '--json']), /LocalHostCustodyLost/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI adopts and reopens the same Host in separate exited processes without grants', async () => {
  const f = await fixture('reopen');
  const adopted = success(invoke(f, ['adopt', '--json']));
  assert.equal(adopted.kind, 'local_host_adopted');
  assert.equal(adopted.accountId, 'operator');
  assert.equal(Object.hasOwn(adopted, 'run'), false);
  const original = await journal(f);
  const connected = success(invoke(f, ['connect', '--json']));
  assert.equal(connected.kind, 'local_host_connected');
  assert.equal(connected.adoptionCid, adopted.adoptionCid);
  assert.equal(connected.accountConfigurationCid, adopted.accountConfigurationCid);
  refusal(invoke(f, ['new-submission', '--request-id', 'request-1']), /LocalSubmissionAuthorizationDenied/u);
  assert.deepEqual(await journal(f), original, 'No-match must not rotate epoch custody or initialize a Run');
});

test('Native CLI issues a reference only under an explicit account submit permission', async () => {
  const f = await fixture('explicit-submit', [{entry_id: 'run-submit', outcome: 'allow',
    principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
    resource: {any_of: ['run']}, operation: {any_of: ['submit']}, exclusions: []}]);
  success(invoke(f, ['adopt', '--json']));
  const reference = success(invoke(f, ['new-submission', '--request-id', 'original-request']));
  assert.deepEqual(Object.keys(reference).sort(), ['epoch', 'nonce']);
  assert.equal(reference.nonce, 'original-request');
  assert.equal(reference.epoch.version, 'actql-submission-epoch/0.1');
  assert.match(reference.epoch.authorityScopeCid, /^sha256:[0-9a-f]{64}$/u);
});

const submitPermission = {entry_id: 'run-submit', outcome: 'allow',
  principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
  resource: {any_of: ['run']}, operation: {any_of: ['submit']}, exclusions: []};

test('Native CLI original Submission lookup stays unresolved across separate exited processes', async () => {
  const f = await fixture('lookup-unaccepted', [submitPermission]);
  success(invoke(f, ['adopt', '--json']));
  const reference = success(invoke(f, ['new-submission', '--request-id', 'unaccepted-request']));
  await writeFile(join(f.root, 'original-submission.json'), JSON.stringify(reference));
  const first = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  const second = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(Object.keys(first).sort(), ['history', 'kind', 'requestId', 'submissionRef']);
  assert.equal(first.kind, 'local_submission_lookup');
  assert.equal(first.history, 'unresolved');
  assert.deepEqual(first.submissionRef, reference);
  assert.deepEqual(second, first);
  // Missing intent history is not an acceptance, Run or permission to replay.
  assert.equal(Object.hasOwn(first, 'runDefinitionCid'), false);
  assert.equal(Object.hasOwn(first, 'phase'), false);
});

test('Native CLI Submission lookup rejects a foreign or altered original epoch', async () => {
  const original = await fixture('lookup-original', [submitPermission]);
  const foreign = await fixture('lookup-foreign', [submitPermission]);
  success(invoke(original, ['adopt', '--json']));
  success(invoke(foreign, ['adopt', '--json']));
  const reference = success(invoke(original, ['new-submission', '--request-id', 'original']));
  await writeFile(join(foreign.root, 'original-submission.json'), JSON.stringify(reference));
  refusal(invoke(foreign, ['lookup-submission', '--submission-ref-file', 'original-submission.json']),
    /LocalSubmissionLookupUnavailable/u);
  const changed = structuredClone(reference);
  changed.epoch.authorityScopeCid = `sha256:${'0'.repeat(64)}`;
  await writeFile(join(original.root, 'changed-submission.json'), JSON.stringify(changed));
  refusal(invoke(original, ['lookup-submission', '--submission-ref-file', 'changed-submission.json']),
    /LocalSubmissionLookupUnavailable/u);
});

test('Native CLI Submission lookup requires current account permission and retained Host custody', async () => {
  const f = await fixture('lookup-denied');
  success(invoke(f, ['adopt', '--json']));
  const before = await journal(f);
  // Current authority is checked before opening caller-supplied references.
  refusal(invoke(f, ['lookup-submission', '--submission-ref-file', 'absent.json']),
    /LocalSubmissionAuthorizationDenied/u);
  assert.deepEqual(await journal(f), before);
  const absent = await fixture('lookup-no-host', [submitPermission]);
  refusal(invoke(absent, ['lookup-submission', '--submission-ref-file', 'absent.json']),
    /LocalHostCustodyLost/u);
  await assert.rejects(stat(join(absent.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI rejects changed selected settings without replacing original custody', async () => {
  const f = await fixture('changed');
  success(invoke(f, ['adopt', '--json']));
  const original = await journal(f);
  f.configuration.native.local.principal = 'other';
  await f.save();
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), original);
});

test('Native CLI rejects byte-identical configuration replacement', async () => {
  const f = await fixture('replaced');
  success(invoke(f, ['adopt', '--json']));
  const original = await journal(f);
  await rename(join(f.root, 'actql.config.json'), join(f.root, 'original.config.json'));
  await copyFile(join(f.root, 'original.config.json'), join(f.root, 'actql.config.json'));
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), original);
});

test('Native CLI refuses missing account custody without repair', async () => {
  const f = await fixture('missing-custody');
  success(invoke(f, ['adopt', '--json']));
  const original = await journal(f);
  const witness = join(f.root, 'host', 'configuration-custody.json');
  await unlink(witness);
  refusal(invoke(f, ['connect', '--json']), /LocalAdoptionUnknown/u);
  await assert.rejects(stat(witness), {code: 'ENOENT'});
  assert.deepEqual(await journal(f), original);
});

test('Native CLI rejects conflicting state and non-finite or excessive budgets before adoption', async () => {
  for (const [name, update] of [
    ['conflict', f => { f.configuration.state_dir = join(f.root, 'other'); }],
    ['too-large', f => { f.configuration.native.local.journal_snapshot_bytes = 536870913; }],
    ['fractional', f => { f.configuration.native.local.submission_ttl_ms = 1.5; }],
  ]) {
    const f = await fixture(name);
    update(f);
    await f.save();
    refusal(invoke(f, ['adopt', '--json']), /ConflictingLocalHostState|InvalidLocalHost/u);
    await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
  }
});

test('Native CLI adoption never switches to a Remote endpoint', async () => {
  const f = await fixture('no-remote');
  refusal(invoke(f, ['adopt', '--json'], ['--endpoint', 'https://127.0.0.1:1/']),
    /Local mode cannot use Remote connection options/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI refuses an untrusted root before loading selected physical libraries', async () => {
  const f = await fixture('untrusted-root');
  f.configuration.native.local.signature_library = '/not-an-installed-library';
  await f.save();
  await chmod(f.root, 0o755);
  refusal(invoke(f, ['adopt', '--json']), /LocalConfigurationRootUntrusted/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});


test('Native CLI retains explicitly selected installation originals across exited processes', async () => {
  const f = await fixture('installation-original');
  const original = '{"mapping":{"label":"e\\u0301","line":"a\\r\\nb","null":null}}\r\n';
  await writeFile(join(f.root, 'source-installation.json'), original);
  f.configuration.native.local.installation_files = ['source-installation.json'];
  await f.save();
  const adopted = success(invoke(f, ['adopt', '--json']));
  const before = await journal(f);
  const connected = success(invoke(f, ['connect', '--json']));
  assert.equal(connected.adoptionCid, adopted.adoptionCid);
  assert.deepEqual(await readFile(join(f.root, 'source-installation.json'), 'utf8'), original);
  assert.deepEqual(await journal(f), before);
  // A selected original is configuration custody, never a read/submit grant.
  refusal(invoke(f, ['new-submission', '--request-id', 'source-request']), /LocalSubmissionAuthorizationDenied/u);
  await writeFile(join(f.root, 'source-installation.json'), original.replace('e\\u0301', 'é'));
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), before);
});

test('Native CLI refuses replaced or missing installation originals without repair', async () => {
  for (const missing of [false, true]) {
    const f = await fixture(`installation-custody-${missing}`);
    const selected = join(f.root, 'source-installation.json');
    await writeFile(selected, '{"mapping":"selected"}\n');
    f.configuration.native.local.installation_files = ['source-installation.json'];
    await f.save();
    success(invoke(f, ['adopt', '--json']));
    const before = await journal(f);
    await rename(selected, join(f.root, 'original-source-installation.json'));
    if (!missing) await copyFile(join(f.root, 'original-source-installation.json'), selected);
    refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged|LocalHostCustodyLost/u);
    if (missing) await assert.rejects(stat(selected), {code: 'ENOENT'});
    assert.deepEqual(await journal(f), before);
  }
});

test('Native CLI rejects ambiguous or excessive installation selections before Host creation', async () => {
  for (const [index, files] of [
    ['source.json', 'source.json'], ['account.json'], ['actql.config.json'],
    ['environment.json'], ['../outside.json'], [''], [null],
    Array.from({length: 7}, (_, i) => `source-${i}.json`),
  ].entries()) {
    const f = await fixture(`installation-selection-${index}`);
    f.configuration.native.local.installation_files = files;
    await f.save();
    refusal(invoke(f, ['adopt', '--json']), /InvalidLocalInstallationSelection|LocalHostAdoptionRefused/u);
    await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
  }
});

async function sourceFixture(name, update = () => {}, entries = []) {
  const f = await fixture(name, entries);
  const source = JSON.parse(await readFile(fileURLToPath(new URL(
    './fixtures/native-local-cli/source-installation.json', import.meta.url)), 'utf8'));
  // Configuration admission must not load the Source library or open its DB.
  source.native.source.duckdb_library = '/not-installed-for-adoption';
  update(source.native.source);
  await writeFile(join(f.root, 'source-installation.json'), JSON.stringify(source));
  f.configuration.native.local.installation_files = ['source-installation.json'];
  f.configuration.native.local.source_file = 'source-installation.json';
  await f.save();
  return f;
}

async function submissionFixture(name) {
  const f = await sourceFixture(name, () => {}, [submitPermission]);
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/source-environment.json', import.meta.url)),
    join(f.root, 'environment.json'));
  f.configuration.native.check_environment.evidence_bundle_cid =
    'sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554';
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/run-installation.json', import.meta.url)),
    join(f.root, 'run-installation.json'));
  f.configuration.native.local.installation_files.push('run-installation.json');
  f.configuration.native.local.run_file = 'run-installation.json';
  await f.save();
  success(invoke(f, ['adopt', '--json']));
  const reference = success(invoke(f, ['new-submission', '--request-id', 'original']));
  await writeFile(join(f.root, 'original-submission.json'), JSON.stringify(reference));
  return {f, reference};
}

const originalStart = ['start', '--program-file', 'input.json',
  '--submission-ref-file', 'original-submission.json', '--operation-attempt-id', 'first'];

test('Native CLI saves original submission before preparation refusal and refuses changed input after process exit', async () => {
  const {f, reference} = await submissionFixture('start-refused-preparation');
  await writeFile(join(f.root, 'input.json'), '{}');
  refusal(invoke(f, originalStart), /LocalPreparationNotReady/u);
  const first = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(first.submissionRef, reference);
  assert.equal(first.history, 'retained');
  assert.equal(first.phase, 'preparing');
  assert.equal(Object.hasOwn(first, 'runDefinitionCid'), false);
  await assert.rejects(stat(join(f.root, 'managed', 'results')), {code: 'ENOENT'});
  const before = await journal(f);
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/source-program.json', import.meta.url)),
    join(f.root, 'input.json'));
  refusal(invoke(f, originalStart), /LocalSubmissionAcceptanceUnavailable/u);
  const later = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(later.intentCid, first.intentCid);
  assert.equal(later.revision, first.revision);
  assert.deepEqual(await journal(f), before);
});

test('Native CLI original AQL refusal is retained and lookup does not lower or execute it again', async () => {
  const {f, reference} = await submissionFixture('aql-refused-preparation');
  await writeFile(join(f.root, 'bad.sql'), 'SELECT missing AS n');
  refusal(invoke(f, ['aql', '--program-file', 'bad.sql', '--format', 'sql',
    '--submission-ref-file', 'original-submission.json', '--operation-attempt-id', 'first']),
  /LocalPreparationNotReady/u);
  await unlink(join(f.root, 'bad.sql'));
  const looked = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(looked.submissionRef, reference);
  assert.equal(looked.history, 'retained');
  assert.equal(looked.phase, 'preparing');
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI admitted Source Run still requires read authority before loading Source library', async () => {
  const {f} = await submissionFixture('start-denied-source');
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/source-program.json', import.meta.url)),
    join(f.root, 'input.json'));
  refusal(invoke(f, originalStart), /LocalSourceAuthorizationDenied/u);
  const admitted = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(admitted.history, 'retained');
  assert.equal(admitted.phase, 'ready', 'Ready is admission, not execution or publication');
  assert.match(admitted.runDefinitionCid, /^sha256:[0-9a-f]{64}$/u);
  assert.deepEqual(Object.keys(admitted.ref).sort(), ['authorityScopeCid', 'namespaceId', 'runDefinitionCid']);
  assert.equal(admitted.ref.namespaceId, 'local-example');
  assert.equal(admitted.ref.runDefinitionCid, admitted.runDefinitionCid);
  assert.match(admitted.ref.authorityScopeCid, /^sha256:[0-9a-f]{64}$/u);
  assert.match(admitted.controlRevision, /^[0-9]+$/u, 'Current journal control revision is an independent observation');
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
  await unlink(join(f.root, 'input.json'));
  const looked = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(looked.runDefinitionCid, admitted.runDefinitionCid);
  assert.deepEqual(looked.ref, admitted.ref);
  assert.equal(looked.controlRevision, admitted.controlRevision);
});

test('Native CLI refuses conflicting request assertion before durable acceptance', async () => {
  const {f} = await submissionFixture('start-foreign-request');
  await writeFile(join(f.root, 'input.json'), '{}');
  const before = await journal(f);
  refusal(invoke(f, [...originalStart, '--request-id', 'other']), /LocalSubmissionIdentityMismatch/u);
  const looked = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(looked.history, 'unresolved');
  assert.deepEqual(await journal(f), before);
});

test('Native CLI binds selected Source settings without opening Source or granting access', async () => {
  const f = await sourceFixture('typed-source-original');
  const source = await readFile(join(f.root, 'source-installation.json'));
  const adopted = success(invoke(f, ['adopt', '--json']));
  const before = await journal(f);
  const restored = success(invoke(f, ['connect', '--json']));
  assert.equal(restored.adoptionCid, adopted.adoptionCid);
  assert.deepEqual(await journal(f), before);
  assert.deepEqual(await readFile(join(f.root, 'source-installation.json')), source);
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
  refusal(invoke(f, ['new-submission', '--request-id', 'source-without-grant']),
    /LocalSubmissionAuthorizationDenied/u);
  assert.deepEqual(await journal(f), before);
});

test('Native CLI Source setting selection cannot bypass durable original custody', async () => {
  const f = await sourceFixture('typed-source-unselected');
  f.configuration.native.local.installation_files = [];
  await f.save();
  refusal(invoke(f, ['adopt', '--json']), /LocalSourceOriginalNotSelected/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI rejects malformed Source budgets and escaping locations before Host initialization', async () => {
  const updates = [
    source => { source.memory_bytes = 536870913; },
    source => { source.ledger.retained_bytes = 536870913; },
    source => { source.imports.max_rows = 1.5; },
    source => { source.database_file = '../foreign.duckdb'; },
    source => { source.database_file = '/foreign.duckdb'; },
    source => { source.dispatch.guards.unrecognized = 1; },
    source => { source.estimates[0].native_rates[0].work_slots = [0, 0]; },
    source => { source.estimates[0].output_rows_per_mille = 1001; },
    source => { source.contracts.query = null; },
    source => { source.source_contract_cid = 'sha256:invalid'; },
    source => { source.dispatch.capacity.contract_cid = 'sha256:invalid'; },
    source => { delete source.execution_bytes; },
  ];
  for (const [index, update] of updates.entries()) {
    const f = await sourceFixture(`typed-source-refusal-${index}`, update);
    refusal(invoke(f, ['adopt', '--json']), /InvalidLocalSource/u);
    await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
  }
});

async function runFixture(name, update = () => {}) {
  const f = await fixture(name);
  const run = JSON.parse(await readFile(fileURLToPath(new URL(
    './fixtures/native-local-cli/run-installation.json', import.meta.url)), 'utf8'));
  update(run.native.run);
  await writeFile(join(f.root, 'run-installation.json'), JSON.stringify(run));
  f.configuration.native.local.installation_files = ['run-installation.json'];
  f.configuration.native.local.run_file = 'run-installation.json';
  await f.save();
  return f;
}

test('Native CLI retains complete Result settings without opening Store or granting read', async () => {
  const f = await runFixture('typed-result-original');
  const original = await readFile(join(f.root, 'run-installation.json'));
  const adopted = success(invoke(f, ['adopt', '--json']));
  const before = await journal(f);
  assert.equal(success(invoke(f, ['connect', '--json'])).adoptionCid, adopted.adoptionCid);
  assert.deepEqual(await readFile(join(f.root, 'run-installation.json')), original);
  assert.deepEqual(await journal(f), before);
  await assert.rejects(stat(join(f.root, 'managed', 'results')), {code: 'ENOENT'});
  refusal(invoke(f, ['new-submission', '--request-id', 'result-without-submit']),
    /LocalSubmissionAuthorizationDenied/u);
  await writeFile(join(f.root, 'run-installation.json'), original.toString().replace(
    'local-example', 'other-namespace'));
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), before);
});

test('Native CLI Result settings require selected original custody', async () => {
  const f = await runFixture('typed-result-unselected');
  f.configuration.native.local.installation_files = [];
  await f.save();
  refusal(invoke(f, ['adopt', '--json']), /LocalRunOriginalNotSelected/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI refuses altered retention CID and invalid Result bounds before initialization', async () => {
  const updates = [
    run => { run.store_capacity_bytes = 536870913; },
    run => { run.store_record_bytes = 536870913; },
    run => { run.result_payload_bytes = run.store_capacity_bytes + 1; },
    run => { run.store_objects = 0; },
    run => { run.store_record_bytes = 0; },
    run => { run.store_objects = 1.5; },
    run => { run.store_name = '../foreign'; },
    run => { run.store_name = '/foreign'; },
    run => { run.store_authority_cid = 'sha256:invalid'; },
    run => { run.unknown = 'ignored'; },
    run => { run.retention_policy_wire = run.retention_policy_wire.replace(
      '2099-01-01T00:00:00.000Z', '2098-01-01T00:00:00.000Z'); },
    run => { const body = JSON.parse(run.retention_policy_wire);
      delete body.effective_retention_policy_cid;
      run.retention_policy_wire = JSON.stringify(body); },
  ];
  for (const [index, update] of updates.entries()) {
    const f = await runFixture(`typed-result-refusal-${index}`, update);
    refusal(invoke(f, ['adopt', '--json']), /InvalidLocalRun|InvalidLocalResultRetentionPolicy/u);
    await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
    await assert.rejects(stat(join(f.root, 'managed', 'results')), {code: 'ENOENT'});
  }
});

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

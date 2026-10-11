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

const cancelPermission = {entry_id: 'run-cancel', outcome: 'allow',
  principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
  resource: {any_of: ['run']}, operation: {any_of: ['cancel']}, exclusions: []};

const runReadPermission = {entry_id: 'run-read', outcome: 'allow',
  principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
  resource: {any_of: ['run']}, operation: {any_of: ['read']}, exclusions: []};

const resultReadPermission = {entry_id: 'result-read', outcome: 'allow',
  principal: {any_of: ['operator']}, connection: {any_of: ['cli']},
  resource: {any_of: ['result/answer']}, operation: {any_of: ['read']}, exclusions: []};

// Explicit operator disclosure settings. A syntactically admitted original is
// not a payload grant, current Account permission or a completed read attempt.
function readPolicy() {
  return {version: 'actql-config/0.1', native: {result_read: {
    enabled: true, principal: 'operator', connection: 'cli', result_names: ['answer'],
    formats: ['jsonl'], purpose: 'inspection', sink: 'stdout',
    data_policy_cids: [`sha256:${'a'.repeat(64)}`], max_bytes: 65536,
    max_uses: 1, expires_at: '2026-10-12T00:00:00.000Z',
  }}};
}

async function selectReadPolicy(f, policy = readPolicy()) {
  f.configuration.native.local.installation_files = ['read.settings.json'];
  f.configuration.native.local.read_file = 'read.settings.json';
  await writeFile(join(f.root, 'read.settings.json'), JSON.stringify(policy) + '\r\n');
  await f.save();
}

test('Native CLI retains explicitly selected read settings across exited processes without issuing a grant', async () => {
  const f = await fixture('read-policy-retained');
  const policy = readPolicy();
  policy.native.result_read.enabled = false;
  policy.native.result_read.purpose = 'e\u0301\r\ninspection';
  await selectReadPolicy(f, policy);
  const adopted = success(invoke(f, ['adopt', '--json']));
  const connected = success(invoke(f, ['connect', '--json']));
  assert.equal(connected.adoptionCid, adopted.adoptionCid);
  assert.equal(Object.hasOwn(connected, 'grant'), false);
  const original = await journal(f);
  policy.native.result_read.purpose = 'é\ninspection';
  await writeFile(join(f.root, 'read.settings.json'), JSON.stringify(policy) + '\r\n');
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), original, 'No settings refresh or custody repair');
});

test('Native CLI requires explicit selection of the read Policy original', async () => {
  const f = await fixture('read-policy-unselected');
  await selectReadPolicy(f);
  f.configuration.native.local.installation_files = [];
  await f.save();
  refusal(invoke(f, ['adopt', '--json']), /LocalReadPolicyOriginalNotSelected/u);
  await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
});

test('Native CLI refuses malformed or excessive read settings before Host creation', async () => {
  const cases = [
    ['byte-cap', policy => {policy.max_bytes = 536870913;}, /InvalidLocalReadPolicyLimits/u],
    ['uses-cap', policy => {policy.max_uses = 1025;}, /InvalidLocalReadPolicyLimits/u],
    ['zero-budget', policy => {policy.max_bytes = 0;}, /InvalidLocalReadPolicyLimits/u],
    ['duplicate-name', policy => {policy.result_names = ['answer', 'answer'];}, /InvalidLocalReadPolicyOriginal/u],
    ['unknown-field', policy => {policy.allow_all = true;}, /InvalidLocalReadPolicyOriginal/u],
    ['missing-expiry', policy => {delete policy.expires_at;}, /InvalidLocalReadPolicyOriginal/u],
    ['invalid-expiry', policy => {policy.expires_at = '2026-02-30T00:00:00.000Z';}, /InvalidLocalReadPolicyOriginal/u],
    ['bad-policy-cid', policy => {policy.data_policy_cids = ['missing'];}, /InvalidLocalReadPolicyReference/u],
    ['format', policy => {policy.formats = ['arrow'];}, /UnsupportedLocalReadFormat/u],
    ['sink', policy => {policy.sink = 'external-model';}, /UnsupportedLocalReadSink/u],
  ];
  for (const [name, mutate, expected] of cases) {
    const f = await fixture(`read-policy-refusal-${name}`);
    const policy = readPolicy(); mutate(policy.native.result_read);
    await selectReadPolicy(f, policy);
    refusal(invoke(f, ['adopt', '--json']), expected);
    await assert.rejects(stat(join(f.root, 'host')), {code: 'ENOENT'});
  }
});

test('Native CLI cannot substitute an independently valid read settings original after adoption', async () => {
  const f = await fixture('read-policy-substitution');
  await selectReadPolicy(f);
  success(invoke(f, ['adopt', '--json']));
  const original = await journal(f);
  const replacement = readPolicy(); replacement.native.result_read.max_bytes = 131072;
  await writeFile(join(f.root, 'read.settings.json'), JSON.stringify(replacement) + '\r\n');
  refusal(invoke(f, ['connect', '--json']), /LocalConfigurationChanged/u);
  assert.deepEqual(await journal(f), original);
});

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

async function submissionFixture(name, entries = [submitPermission]) {
  const f = await sourceFixture(name, () => {}, entries);
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

async function cancellationLookupFixture(name, entries = [submitPermission, cancelPermission]) {
  const {f, reference} = await submissionFixture(name, entries);
  await copyFile(fileURLToPath(new URL('./fixtures/native-local-cli/source-program.json', import.meta.url)),
    join(f.root, 'input.json'));
  refusal(invoke(f, originalStart), /LocalSourceAuthorizationDenied/u);
  const admitted = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(admitted.phase, 'ready');
  assert.equal(admitted.ref.namespaceId, 'local-example');
  await writeFile(join(f.root, 'original-run.json'), JSON.stringify(admitted.ref));
  await unlink(join(f.root, 'input.json'));
  const lookup = ['lookup-cancellation', '--submission-ref-file', 'original-submission.json',
    '--ref-file', 'original-run.json', '--cancel-id', 'cancel-original',
    '--expected-revision', admitted.controlRevision];
  return {f, reference, admitted, lookup};
}

test('Native CLI original cancellation lookup remains unresolved across exited processes without execution', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-lookup-original');
  const storeFile = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  const originalStore = await readFile(storeFile);
  const expected = {kind: 'local_cancellation_lookup', history: 'unresolved', ref: admitted.ref,
    cancelRef: {...admitted.ref, cancelId: 'cancel-original', expectedRevision: Number(admitted.controlRevision)}};
  assert.deepEqual(success(invoke(f, lookup)), expected);
  assert.deepEqual(success(invoke(f, lookup)), expected);
  assert.deepEqual(await readFile(storeFile), originalStore, 'Lookup must not open or rewrite the publication Store');
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(original.ref, admitted.ref);
  assert.equal(original.controlRevision, admitted.controlRevision, 'Missing cancellation history cannot issue a cancellation');
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI cancellation lookup requires independent current cancel authority', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-lookup-denied', [submitPermission]);
  refusal(invoke(f, lookup), /LocalCancellationAuthorizationDenied/u);
  refusal(invoke(f, cancellationCommand(lookup)), /LocalCancellationAuthorizationDenied/u);
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(original.ref, admitted.ref);
  assert.equal(original.controlRevision, admitted.controlRevision);
});

function cancellationCommand(lookup, attempt = 'cancel-invocation') {
  return ['cancel', ...lookup.slice(1), '--operation-attempt-id', attempt];
}

test('Native CLI records original cancellation and replays it across exited processes without new execution', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-original-operation');
  const expected = {kind: 'local_cancellation_operation', history: 'retained', ref: admitted.ref,
    cancelRef: {...admitted.ref, cancelId: 'cancel-original', expectedRevision: Number(admitted.controlRevision)},
    action: 'accepted', recordedControlRevision: (BigInt(admitted.controlRevision) + 1n).toString()};
  const first = success(invoke(f, cancellationCommand(lookup, 'first-invocation')));
  assert.deepEqual(first, {...expected, invocationRef: {operation: 'cancel', attemptId: 'first-invocation'}});
  const replay = success(invoke(f, cancellationCommand(lookup, 'later-invocation')));
  assert.deepEqual(replay, {...expected, invocationRef: {operation: 'cancel', attemptId: 'later-invocation'}});
  assert.deepEqual(success(invoke(f, lookup)), {...expected, kind: 'local_cancellation_lookup'});
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(original.ref, admitted.ref);
  assert.equal(original.controlRevision, expected.recordedControlRevision, 'Replay cannot issue another cancellation');
  for (const name of ['status', 'physicallyStopped', 'cleanupComplete', 'released']) {
    assert.equal(Object.hasOwn(first, name), false, 'Acceptance cannot manufacture terminal or cleanup evidence');
  }
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI discarded cancellation reply is recovered from original journal without reopening Store', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-discarded-reply');
  // The command really executes and exits; its stdout is deliberately discarded.
  // This is a lost consumer reply, not injection of a pre/post-commit failure.
  const lost = spawnSync(binary, ['--mode', 'local', '--config-root', f.root,
    '--config-file', 'actql.config.json', ...cancellationCommand(lookup)],
  {cwd: f.root, env: {...process.env, PATH: ''}, encoding: 'utf8', timeout: 15000,
    stdio: ['ignore', 'ignore', 'pipe']});
  assert.ifError(lost.error);
  assert.equal(lost.signal, null);
  assert.ok(lost.pid > 0);
  assert.equal(lost.status, 0, lost.stderr);
  const originalStore = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  await rename(originalStore, `${originalStore}.held-original`);
  const observed = success(invoke(f, lookup));
  assert.equal(observed.history, 'retained');
  assert.equal(observed.action, 'accepted');
  assert.deepEqual(observed.ref, admitted.ref);
  assert.deepEqual(observed.cancelRef, {...admitted.ref, cancelId: 'cancel-original',
    expectedRevision: Number(admitted.controlRevision)});
  assert.equal(observed.recordedControlRevision, (BigInt(admitted.controlRevision) + 1n).toString());
  assert.deepEqual(success(invoke(f, lookup)), observed);
  await assert.rejects(stat(originalStore), {code: 'ENOENT'});
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI stale cancellation does not commit and preserves exact original lookup guidance', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-stale-revision');
  const stale = [...lookup];
  stale[stale.indexOf('--expected-revision') + 1] = (BigInt(admitted.controlRevision) + 1n).toString();
  const denied = invoke(f, cancellationCommand(stale));
  refusal(denied, /LocalCancellationUnknown .*lookup=lookup-cancellation reason=LocalCancellationControlRevisionConflict/u);
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(original.controlRevision, admitted.controlRevision);
  assert.deepEqual(original.ref, admitted.ref);
  assert.equal(success(invoke(f, stale)).history, 'unresolved', 'A conflict cannot become an accepted original operation');
  assert.equal(success(invoke(f, lookup)).history, 'unresolved');
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI another cancellation identity records already-requested without changing original result', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-already-requested');
  const first = success(invoke(f, cancellationCommand(lookup)));
  assert.equal(first.action, 'accepted');
  const next = [...lookup];
  next[next.indexOf('--cancel-id') + 1] = 'distinct-operation';
  next[next.indexOf('--expected-revision') + 1] = first.recordedControlRevision;
  const recorded = success(invoke(f, cancellationCommand(next, 'distinct-invocation')));
  assert.equal(recorded.action, 'already_requested');
  assert.equal(recorded.recordedControlRevision, first.recordedControlRevision);
  assert.deepEqual(recorded.ref, admitted.ref);
  assert.equal(recorded.cancelRef.cancelId, 'distinct-operation');
  assert.deepEqual(success(invoke(f, lookup)), {kind: 'local_cancellation_lookup', history: 'retained',
    ref: first.ref, cancelRef: first.cancelRef, action: first.action, recordedControlRevision: first.recordedControlRevision});
  const changed = [...lookup];
  changed[changed.indexOf('--expected-revision') + 1] = first.recordedControlRevision;
  refusal(invoke(f, changed), /LocalCancellationIntentConflict/u);
});

test('Native CLI cancellation refuses missing original Store without initializing a replacement', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-missing-store');
  const originalStore = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  await rename(originalStore, `${originalStore}.held-original`);
  refusal(invoke(f, cancellationCommand(lookup)), /LocalOriginalStoreUnavailable/u);
  await assert.rejects(stat(originalStore), {code: 'ENOENT'});
  assert.equal(success(invoke(f, lookup)).history, 'unresolved');
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(original.controlRevision, admitted.controlRevision);
  assert.deepEqual(original.ref, admitted.ref);
});

function deliveryLookupCommand(attempt = 'original-read') {
  return ['delivery-attempt', '--submission-ref-file', 'original-submission.json',
    '--ref-file', 'original-run.json', '--result-name', 'answer',
    '--purpose', 'cli-read', '--attempt-id', attempt];
}

test('Native CLI original delivery lookup stays unresolved across exited processes without grant or payload replay', async () => {
  const {f, admitted} = await cancellationLookupFixture('delivery-lookup-original',
    [submitPermission, runReadPermission, resultReadPermission]);
  const storeFile = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  const before = await readFile(storeFile);
  const expected = {kind: 'local_delivery_attempt_lookup', history: 'unresolved',
    ref: admitted.ref, resultName: 'answer', purpose: 'cli-read', attemptId: 'original-read'};
  assert.deepEqual(success(invoke(f, deliveryLookupCommand())), expected);
  assert.deepEqual(success(invoke(f, deliveryLookupCommand())), expected);
  assert.deepEqual(await readFile(storeFile), before, 'Metadata lookup cannot issue/consume a grant or create an attempt');
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.deepEqual(original.ref, admitted.ref);
  assert.equal(original.controlRevision, admitted.controlRevision);
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI delivery lookup requires separate current Run and named-Result read authority', async () => {
  for (const [name, entries] of [['run', [submitPermission, resultReadPermission]],
    ['result', [submitPermission, runReadPermission]]]) {
    const {f, admitted} = await cancellationLookupFixture(`delivery-lookup-denied-${name}`, entries);
    const before = await readFile(join(f.root, 'managed', 'results', '.actql-publication.sqlite3'));
    refusal(invoke(f, deliveryLookupCommand()), /LocalDeliveryLookupAuthorizationDenied/u);
    assert.deepEqual(await readFile(join(f.root, 'managed', 'results', '.actql-publication.sqlite3')), before);
    const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
    assert.equal(original.controlRevision, admitted.controlRevision);
  }
});

test('Native CLI delivery lookup rejects foreign Run and missing original Store without recreating state', async () => {
  const {f, admitted} = await cancellationLookupFixture('delivery-lookup-custody',
    [submitPermission, runReadPermission, resultReadPermission]);
  for (const [field, value] of [['namespaceId', 'foreign'],
    ['authorityScopeCid', `sha256:${'0'.repeat(64)}`], ['runDefinitionCid', `sha256:${'0'.repeat(64)}`]]) {
    await writeFile(join(f.root, 'original-run.json'), JSON.stringify({...admitted.ref, [field]: value}));
    refusal(invoke(f, deliveryLookupCommand()), /LocalOriginalRunReferenceMismatch/u);
  }
  await writeFile(join(f.root, 'original-run.json'), JSON.stringify(admitted.ref));
  const db = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  await rename(db, `${db}.held-original`);
  refusal(invoke(f, deliveryLookupCommand()), /LocalOriginalStoreUnavailable/u);
  await assert.rejects(stat(db), {code: 'ENOENT'});
});

test('Native CLI delivery lookup rejects malformed attempt and unauthorized Result before opening Store', async () => {
  const {f} = await cancellationLookupFixture('delivery-lookup-scope',
    [submitPermission, runReadPermission, resultReadPermission]);
  const before = await readFile(join(f.root, 'managed', 'results', '.actql-publication.sqlite3'));
  refusal(invoke(f, deliveryLookupCommand('x'.repeat(257))), /InvalidLocalDeliveryLookup/u);
  const foreign = deliveryLookupCommand();
  foreign[foreign.indexOf('--result-name') + 1] = 'foreign';
  refusal(invoke(f, foreign), /LocalDeliveryLookupAuthorizationDenied/u);
  assert.deepEqual(await readFile(join(f.root, 'managed', 'results', '.actql-publication.sqlite3')), before);
});

test('Native CLI delivery lookup rejects a same-authority replacement Store instead of claiming absent history', async () => {
  const entries = [submitPermission, runReadPermission, resultReadPermission];
  const {f} = await cancellationLookupFixture('delivery-lookup-original-store', entries);
  const {f: foreign} = await cancellationLookupFixture('delivery-lookup-foreign-store', entries);
  const original = join(f.root, 'managed', 'results', '.actql-publication.sqlite3');
  const replacement = join(foreign.root, 'managed', 'results', '.actql-publication.sqlite3');
  await rename(original, `${original}.held-original`);
  await copyFile(replacement, original);
  refusal(invoke(f, deliveryLookupCommand()), /LocalDeliveryLookupUnavailable/u);
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI cancellation lookup rejects substituted namespace authority and Run before original operation lookup', async () => {
  const {f, admitted, lookup} = await cancellationLookupFixture('cancel-lookup-target');
  for (const [field, value] of [['namespaceId', 'foreign-namespace'],
    ['authorityScopeCid', `sha256:${'0'.repeat(64)}`], ['runDefinitionCid', `sha256:${'0'.repeat(64)}`]]) {
    await writeFile(join(f.root, 'original-run.json'), JSON.stringify({...admitted.ref, [field]: value}));
    refusal(invoke(f, lookup), /LocalOriginalRunReferenceMismatch/u);
    refusal(invoke(f, cancellationCommand(lookup)), /LocalOriginalRunReferenceMismatch/u);
  }
  await writeFile(join(f.root, 'original-run.json'), JSON.stringify(admitted.ref));
  assert.equal(success(invoke(f, lookup)).history, 'unresolved');
  await assert.rejects(stat(join(f.root, 'managed', 'records.duckdb')), {code: 'ENOENT'});
});

test('Native CLI cancellation lookup refuses absent Run admission and altered Submission without recreating either', async () => {
  const {f, reference} = await submissionFixture('cancel-lookup-unaccepted', [submitPermission, cancelPermission]);
  await writeFile(join(f.root, 'original-run.json'), JSON.stringify({namespaceId: 'local-example',
    authorityScopeCid: reference.epoch.authorityScopeCid, runDefinitionCid: `sha256:${'0'.repeat(64)}`}));
  const lookup = ['lookup-cancellation', '--submission-ref-file', 'original-submission.json',
    '--ref-file', 'original-run.json', '--cancel-id', 'cancel-original', '--expected-revision', '0'];
  refusal(invoke(f, lookup), /LocalOriginalRunUnavailable/u);
  refusal(invoke(f, cancellationCommand(lookup)), /LocalOriginalRunUnavailable/u);
  const original = success(invoke(f, ['lookup-submission', '--submission-ref-file', 'original-submission.json']));
  assert.equal(original.history, 'unresolved');
  assert.equal(Object.hasOwn(original, 'ref'), false);
  const altered = structuredClone(reference);
  altered.epoch.authorityScopeCid = `sha256:${'0'.repeat(64)}`;
  await writeFile(join(f.root, 'original-submission.json'), JSON.stringify(altered));
  refusal(invoke(f, lookup), /LocalOriginalRunUnavailable/u);
  await assert.rejects(stat(join(f.root, 'managed', 'results')), {code: 'ENOENT'});
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

import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createGcsMetadataAcceptanceCredential} from './gcs-files-content-credential.mjs';

const execute = promisify(execFile);
const secret = 'synthetic-secret-never-a-live-credential';
const scope = {resourceOrigin: 'https://storage.googleapis.com',
  connectorRegistration: 'gcs', operation: 'gcs:file:list'};
const manifest = () => ({version: 'actql-gcs-metadata-acceptance/0.1',
  project: 'fixture-project', bucket: 'fixture-bucket', prefix: 'test/',
  credential: {kind: 'gcloud-impersonation', serviceAccount:
    'fixture-reader@fixture-project.iam.gserviceaccount.com', account: 'fixture@example.invalid',
  executable: '/fixture/gcloud'}, permissions: ['list', 'read_metadata'],
  limits: {maxRequests: 10, maxResponseBytes: 1048576, maxDurationMs: 60000},
  costLimitUsd: 1, expectedObjects: ['test/a.csv']});

async function checkFailure(run, expected) {
  let attempts = 0;
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: (...args) => { attempts++; return run(...args); }});
  for (let index = 0; index < 2; index++) {
    await assert.rejects(owner.resolveSecret(scope), error => {
      assert.equal(error.code, 'GcsAcceptanceCredential');
      assert.equal(error.reason, 'mint_failed');
      assert.equal(error.message, 'GcsAcceptanceCredential:mint_failed');
      assert.equal(error.cause, undefined);
      assert.equal(JSON.stringify(error).includes(secret), false);
      return true;
    });
    assert.deepEqual(owner.observation().mintFailureDetail, expected);
    assert.equal(Object.isFrozen(owner.observation().mintFailureDetail), true);
    assert.equal(JSON.stringify(owner.observation()).includes(secret), false);
  }
  assert.equal(attempts, 1);
  assert.deepEqual(owner.observation(), {credentialResolutions: 2,
    reservedResponseBytes: 16384, tokenMints: 1, closed: false,
    mintFailure: 'mint_failed', mintFailureDetail: expected});
  owner.close();
  assert.equal(owner.observation().closed, true);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'closed'});
  assert.equal(attempts, 1);
}

for (const [name, fields, expected] of [
  ['exit', {code: 7}, {kind: 'nonzero_exit', exitCode: 7}],
  ['maximum exit', {code: 255}, {kind: 'nonzero_exit', exitCode: 255}],
  ['output limit before termination', {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER', killed: true,
    signal: 'SIGTERM'}, {kind: 'output_limit'}],
  ['missing executable', {code: 'ENOENT'}, {kind: 'spawn_failed'}],
  ['permission', {code: 'EACCES'}, {kind: 'spawn_failed'}],
  ['abort', {code: 'ABORT_ERR', killed: true}, {kind: 'aborted'}],
  ['termination without inferring timeout', {killed: true, signal: 'SIGTERM'}, {kind: 'terminated'}],
  ['unrecognized text', {code: secret, signal: secret}, {kind: 'unclassified'}],
  ['no successful exit from a rejection', {code: 0}, {kind: 'unclassified'}],
]) test(`credential process failure retains only closed ${name} classification`, async () => {
  await checkFailure(async () => {
    throw Object.assign(new Error(secret), {stdout: secret, stderr: secret, cmd: secret,
      cause: {token: secret}, ...fields});
  }, expected);
});

test('credential failure classification does not invoke accessors or inspect inherited/raw fields', async () => {
  let accessed = 0;
  const raw = Object.create({code: 7, killed: true});
  for (const name of ['code', 'signal', 'killed', 'message', 'stack', 'stdout', 'stderr', 'cause', 'cmd']) {
    Object.defineProperty(raw, name, {get() { accessed++; throw new Error(secret); }});
  }
  await checkFailure(async () => { throw raw; }, {kind: 'unclassified'});
  assert.equal(accessed, 0);
  await checkFailure(async () => { throw Object.create({code: 7}); }, {kind: 'unclassified'});
  await checkFailure(async () => { throw new Proxy({}, {
    getOwnPropertyDescriptor() { throw new Error(secret); },
  }); }, {kind: 'unclassified'});
});

test('actual local subprocess nonzero exit is classified without retaining its output', async () => {
  // A local fixture process, not gcloud, network, authentication or a Provider.
  await checkFailure((_executable, _args, options) => execute(process.execPath,
    ['-e', `process.stdout.write('${secret}');process.stderr.write('${secret}');process.exit(7)`],
    options), {kind: 'nonzero_exit', exitCode: 7});
});

test('actual local subprocess output cap is classified without widening the original limit', async () => {
  await checkFailure((_executable, _args, options) => {
    assert.equal(options.maxBuffer, 16384);
    return execute(process.execPath, ['-e', 'process.stdout.write("x".repeat(16385))'], options);
  }, {kind: 'output_limit'});
});

test('actual local missing executable is classified without disclosing its path', async () => {
  await checkFailure((_executable, _args, options) => execute(
    '/fixture/actql-nonexistent-credential-process', [], options), {kind: 'spawn_failed'});
});

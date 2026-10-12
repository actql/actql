import assert from 'node:assert/strict';
import test from 'node:test';
import {createGcsAcceptanceCredential} from './gcs-files-content-credential.mjs';

const token = 'fixture-token-not-a-live-secret';
const scope = {resourceOrigin: 'https://storage.googleapis.com',
  connectorRegistration: 'gcs', operation: 'gcs:file:list'};
const manifest = () => ({version: 'actql-gcs-files-content-acceptance/0.1',
  project: 'fixture-project', bucket: 'fixture-bucket', prefix: 'test/',
  credential: {kind: 'gcloud-impersonation', serviceAccount:
    'fixture-reader@fixture-project.iam.gserviceaccount.com', account: 'fixture@example.invalid',
  executable: '/fixture/gcloud'}, permissions: ['list', 'read_metadata', 'read_content'],
  limits: {maxRequests: 200, maxResponseBytes: 10485760, maxDurationMs: 900000, maxObjectBytes: 1048576},
  costLimitUsd: 1, expectedObjects: [{name: 'test/a.csv', mediaType: 'text/csv',
    contentCid: `sha256:${'1'.repeat(64)}`, sizeBytes: 2}]});

test('short-token resolver binds exact account and SA, caches in memory and emits no token evidence', async () => {
  let mints = 0;
  const owner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: async (executable, args, options) => {
      mints++;
      assert.equal(executable, '/fixture/gcloud');
      assert.deepEqual(args, ['auth', 'print-access-token',
        '--impersonate-service-account=fixture-reader@fixture-project.iam.gserviceaccount.com',
        '--account=fixture@example.invalid', '--project=fixture-project', '--quiet']);
      assert.equal(options.maxBuffer, 16384);
      assert.ok(options.timeout <= 30000);
      assert.equal(options.env.CLOUDSDK_CORE_LOG_HTTP, 'false');
      for (const name of ['CLOUDSDK_AUTH_ACCESS_TOKEN', 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE',
        'CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT', 'GOOGLE_APPLICATION_CREDENTIALS']) {
        assert.equal(options.env[name], undefined);
      }
      return {stdout: token + '\n', stderr: 'ignored'};
    }});
  assert.deepEqual(await Promise.all([owner.resolveSecret(scope),
    owner.resolveSecret({...scope, operation: 'gcs:file:read'})]), [token, token]);
  assert.equal(mints, 1);
  assert.deepEqual(owner.observation(), {credentialResolutions: 2,
    reservedResponseBytes: 16384, tokenMints: 1, closed: false});
  assert.equal(JSON.stringify(owner.observation()).includes(token), false);
  owner.close();
  await assert.rejects(owner.resolveSecret(scope), {reason: 'closed'});
});

for (const mutate of [x => ({...x, operation: 'gcs:file:write'}),
  x => ({...x, resourceOrigin: 'https://foreign.invalid'}),
  x => ({...x, connectorRegistration: 'foreign'})]) {
  test('foreign physical scope is refused before mint', async () => {
    const owner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
      run: () => assert.fail('must not mint')});
    await assert.rejects(owner.resolveSecret(mutate(scope)), {reason: 'scope'});
    assert.equal(owner.observation().credentialResolutions, 0);
  });
}

test('total request and response reservations do not reset between Runs', async () => {
  const input = manifest();
  input.limits.maxRequests = 8;
  const owner = createGcsAcceptanceCredential(input, {maxResponseBytesPerCall: 8192,
    run: async () => ({stdout: token})});
  for (let index = 0; index < 8; index++) await owner.resolveSecret(scope);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'budget'});
  assert.equal(owner.observation().credentialResolutions, 8);
  const bytesOwner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 10485760,
    run: async () => ({stdout: token})});
  await bytesOwner.resolveSecret(scope);
  await assert.rejects(bytesOwner.resolveSecret(scope), {reason: 'budget'});
});

test('deadline, cancellation and token invalidation stop new sends', async () => {
  let clock = 0;
  const owner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    now: () => clock, run: async () => ({stdout: token})});
  clock = 900000;
  await assert.rejects(owner.resolveSecret(scope), {reason: 'deadline'});
  assert.equal(owner.observation().tokenMints, 0);
  const active = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: async () => ({stdout: token})});
  await assert.rejects(active.resolveSecret(scope, AbortSignal.abort()), {name: 'AbortError'});
  assert.equal(active.observation().tokenMints, 0);
  await active.resolveSecret(scope);
  active.resolveSecret.invalidate(token);
  await assert.rejects(active.resolveSecret(scope), {reason: 'closed'});
  assert.equal(active.observation().tokenMints, 1);
});

test('mint failure never exposes subprocess stdout, stderr or cause and is not retried', async () => {
  let attempts = 0;
  const owner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: async () => { attempts++; throw Object.assign(new Error(token), {stdout: token, stderr: token}); }});
  for (let index = 0; index < 2; index++) await assert.rejects(owner.resolveSecret(scope), error => {
    assert.equal(error.reason, 'mint_failed');
    assert.equal(error.cause, undefined);
    assert.equal(error.message.includes(token), false);
    return true;
  });
  assert.equal(attempts, 1);
  assert.equal(owner.observation().mintFailure, 'mint_failed');
});

test('deadline crossing during mint cannot authorize a later send', async () => {
  let clock = 0;
  const owner = createGcsAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    now: () => clock, run: async () => { clock = 900000; return {stdout: token}; }});
  await assert.rejects(owner.resolveSecret(scope), {reason: 'deadline'});
  assert.equal(owner.observation().credentialResolutions, 1);
});

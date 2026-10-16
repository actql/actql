import assert from 'node:assert/strict';
import test from 'node:test';
import {checkGcsMetadataAcceptanceEnvironment, createGcsMetadataAcceptanceCredential}
  from './gcs-files-content-credential.mjs';
import {checkGcsAcceptanceEnvironment} from './gcs-files-content-environment.mjs';

const token = 'synthetic-token-never-a-live-credential';
const scope = {resourceOrigin: 'https://storage.googleapis.com',
  connectorRegistration: 'gcs', operation: 'gcs:file:list'};
const manifest = () => ({version: 'actql-gcs-metadata-acceptance/0.1',
  project: 'fixture-project', bucket: 'fixture-bucket', prefix: 'test/e\u0301/',
  credential: {kind: 'gcloud-impersonation', serviceAccount:
    'fixture-reader@fixture-project.iam.gserviceaccount.com', account: 'fixture@example.invalid',
  executable: '/fixture/gcloud'}, permissions: ['list', 'read_metadata'],
  limits: {maxRequests: 10, maxResponseBytes: 1048576, maxDurationMs: 60000},
  costLimitUsd: 1, expectedObjects: ['test/e\u0301/a.csv']});

test('metadata scope is distinct, closed and deeply snapshotted without normalizing object data', () => {
  const input = manifest();
  const checked = checkGcsMetadataAcceptanceEnvironment(input);
  input.credential.account = 'changed@example.invalid';
  input.permissions.push('read_content');
  input.limits.maxRequests = 200;
  input.expectedObjects[0] = 'elsewhere/a.csv';
  assert.equal(checked.credential.account, 'fixture@example.invalid');
  assert.deepEqual(checked.permissions, ['list', 'read_metadata']);
  assert.equal(checked.limits.maxRequests, 10);
  assert.deepEqual(checked.expectedObjects, ['test/e\u0301/a.csv']);
  assert.notEqual(checked.prefix, 'test/é/');
  for (const value of [checked, checked.credential, checked.permissions,
    checked.limits, checked.expectedObjects]) assert.ok(Object.isFrozen(value));
  assert.throws(() => checkGcsAcceptanceEnvironment(manifest()), {reason: 'shape'});
});

for (const [reason, mutate] of [
  ['metadata_shape', x => { x.version = 'actql-gcs-files-content-acceptance/0.1'; }],
  ['metadata_shape', x => { x.token = token; }],
  ['metadata_scope', x => { x.prefix = ''; }],
  ['metadata_permissions', x => { x.permissions.push('read_content'); }],
  ['metadata_permissions', x => { x.permissions = ['list', 'list']; }],
  ['metadata_limits', x => { x.limits.maxRequests = 11; }],
  ['metadata_limits', x => { x.limits.maxResponseBytes = 1048577; }],
  ['metadata_limits', x => { x.limits.maxDurationMs = 60001; }],
  ['metadata_limits', x => { x.limits.maxRequests = 0; }],
  ['metadata_limits', x => { x.limits.maxObjectBytes = 8192; }],
  ['metadata_credential', x => { x.credential.executable = 'gcloud'; }],
  ['metadata_credential', x => { x.credential.serviceAccount = 'reader@other-project.iam.gserviceaccount.com'; }],
  ['metadata_credential', x => { x.credential.token = token; }],
  ['metadata_objects', x => { x.expectedObjects = ['outside/a.csv']; }],
  ['metadata_objects', x => { x.expectedObjects.push(x.expectedObjects[0]); }],
  ['metadata_cost', x => { x.costLimitUsd = 1.01; }],
]) test(`metadata rejects ${reason}: ${mutate.toString()}`, () => {
  const input = manifest();
  mutate(input);
  assert.throws(() => createGcsMetadataAcceptanceCredential(input, {
    maxResponseBytesPerCall: 8192, run: () => assert.fail('must not mint'),
  }), {reason});
});

test('one cached auth subprocess is distinct from ten pre-send GCS reservations across Runs', async () => {
  let mints = 0;
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    now: () => 1000, run: async (executable, args, options) => {
      mints++;
      assert.equal(executable, '/fixture/gcloud');
      assert.deepEqual(args, ['auth', 'print-access-token',
        '--impersonate-service-account=fixture-reader@fixture-project.iam.gserviceaccount.com',
        '--account=fixture@example.invalid', '--project=fixture-project', '--quiet']);
      assert.equal(options.timeout, 30000);
      assert.equal(options.maxBuffer, 16384);
      assert.equal(options.env.CLOUDSDK_CORE_LOG_HTTP, 'false');
      assert.equal(options.env.CLOUDSDK_CORE_VERBOSITY, 'error');
      for (const key of ['CLOUDSDK_AUTH_ACCESS_TOKEN', 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE',
        'CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT', 'GOOGLE_APPLICATION_CREDENTIALS']) {
        assert.equal(options.env[key], undefined);
      }
      return {stdout: token, stderr: 'not retained'};
    }});
  assert.deepEqual(await Promise.all(Array.from({length: 10}, () => owner.resolveSecret(scope))),
    Array(10).fill(token));
  await assert.rejects(owner.resolveSecret(scope), {reason: 'budget'});
  assert.equal(mints, 1);
  assert.deepEqual(owner.observation(), {credentialResolutions: 10,
    reservedResponseBytes: 81920, tokenMints: 1, closed: false});
  assert.equal(JSON.stringify(owner.observation()).includes(token), false);
  owner.close();
});

test('GCS byte reservations consume a single total and do not include trusted auth buffering', async () => {
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 524288,
    run: async () => ({stdout: token})});
  await owner.resolveSecret(scope);
  await owner.resolveSecret(scope);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'budget'});
  assert.deepEqual(owner.observation(), {credentialResolutions: 2,
    reservedResponseBytes: 1048576, tokenMints: 1, closed: false});
});

test('content, write, foreign origin and foreign registration refuse before auth', async () => {
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: () => assert.fail('must not mint')});
  for (const candidate of [{...scope, operation: 'gcs:file:read'},
    {...scope, operation: 'gcs:file:write'}, {...scope, resourceOrigin: 'https://foreign.invalid'},
    {...scope, connectorRegistration: 'foreign'}]) {
    await assert.rejects(owner.resolveSecret(candidate), {reason: 'scope'});
  }
  assert.equal(owner.observation().credentialResolutions, 0);
  assert.equal(owner.observation().tokenMints, 0);
});

test('auth duration is inside the total deadline, including expiry while mint is pending', async () => {
  let clock = 1000;
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    now: () => clock, run: async (_executable, _args, options) => {
      assert.equal(options.timeout, 15000);
      clock = 61000;
      return {stdout: token};
    }});
  clock = 46000;
  assert.equal(owner.remainingDurationMs(), 15000);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'deadline'});
  assert.equal(owner.observation().tokenMints, 1);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'deadline'});
});

test('cancellation, close and invalidation cannot authorize subsequent use or remint', async () => {
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: async () => ({stdout: token})});
  await assert.rejects(owner.resolveSecret(scope, AbortSignal.abort()), {name: 'AbortError'});
  assert.equal(owner.observation().tokenMints, 0);
  await owner.resolveSecret(scope);
  owner.resolveSecret.invalidate(token);
  await assert.rejects(owner.resolveSecret(scope), {reason: 'closed'});
  assert.equal(owner.observation().tokenMints, 1);
  const other = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: () => assert.fail('closed before subprocess')});
  const pending = other.resolveSecret(scope);
  other.close();
  await assert.rejects(pending, {reason: 'closed'});
  assert.equal(other.observation().tokenMints, 0);
});

test('failed or malformed auth is sanitized and never automatically retried', async () => {
  for (const invalid of [false, true]) {
    let attempts = 0;
    const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
      run: async () => {
        attempts++;
        if (invalid) return {stdout: 'invalid token'};
        throw Object.assign(new Error(token), {stdout: token, stderr: token});
      }});
    for (let index = 0; index < 2; index++) await assert.rejects(owner.resolveSecret(scope), error => {
      assert.equal(error.reason, invalid ? 'invalid_token' : 'mint_failed');
      assert.equal(error.cause, undefined);
      assert.equal(error.message.includes(token), false);
      return true;
    });
    assert.equal(attempts, 1);
  }
});

test('synchronous subprocess-adapter reentry cannot initiate another auth subprocess', async () => {
  let mints = 0, reentered;
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    run: async () => {
      mints++;
      reentered = owner.resolveSecret(scope);
      return {stdout: token};
    }});
  assert.equal(await owner.resolveSecret(scope), token);
  assert.equal(await reentered, token);
  assert.equal(mints, 1);
  assert.equal(owner.observation().credentialResolutions, 2);
});

test('invalid or backwards clocks refuse instead of disabling the total deadline', async () => {
  assert.throws(() => createGcsMetadataAcceptanceCredential(manifest(), {
    maxResponseBytesPerCall: 8192, now: () => NaN,
  }), {reason: 'configuration'});
  let clock = 1000;
  const owner = createGcsMetadataAcceptanceCredential(manifest(), {maxResponseBytesPerCall: 8192,
    now: () => clock, run: () => assert.fail('must not mint')});
  clock = 999;
  await assert.rejects(owner.resolveSecret(scope), {reason: 'clock'});
});

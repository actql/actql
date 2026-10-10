import assert from 'node:assert/strict';
import test from 'node:test';
import {checkGcsAcceptanceEnvironment, gcsAcceptancePrograms} from './gcs-files-content-environment.mjs';

export const gcsAcceptanceManifestFixture = () => ({
  version: 'actql-gcs-files-content-acceptance/0.1', project: 'fixture-project',
  bucket: 'actql-fixture', prefix: 'test/e\u0301/',
  credential: {kind: 'gcloud-impersonation', account: 'fixture@example.invalid',
    serviceAccount: 'actql-content-test@fixture-project.iam.gserviceaccount.com',
    executable: '/fixture/gcloud'}, permissions: ['list', 'read_metadata', 'read_content'],
  limits: {maxRequests: 200, maxResponseBytes: 10485760, maxDurationMs: 900000, maxObjectBytes: 1048576},
  costLimitUsd: 1,
  expectedObjects: [{name: 'test/e\u0301/a.csv', mediaType: 'text/csv',
    contentCid: `sha256:${'1'.repeat(64)}`, sizeBytes: 24}],
});
test('explicit read-only scope and credential reference are preserved without provider I/O', () => {
  const manifest = gcsAcceptanceManifestFixture();
  const checked = checkGcsAcceptanceEnvironment(manifest);
  assert.equal(checked.prefix, 'test/e\u0301/');
  assert.notEqual(checked.prefix, 'test/é/');
  assert.deepEqual(checked.credential, manifest.credential);
  assert.ok(Object.isFrozen(checked.expectedObjects[0]));
  const programs = gcsAcceptancePrograms(checked, 'storage');
  assert.deepEqual(programs.capture.stages[0].inputs.files.request.paths, ['test/e\u0301/a.csv']);
  assert.deepEqual(programs.empty.stages[0].inputs.files.request.paths, []);
  assert.deepEqual(programs.capture.stages[0].steps[0],
    {from: 'files', filter: 'name IS NOT NULL', as: 'listed'});
  assert.deepEqual(programs.capture.stages[0].steps[1],
    {from: 'listed', select: ['resource', 'version', 'name', 'path', 'media_type',
      'size_bytes', 'modified_at'], as: 'listing_capture'});
  assert.deepEqual(programs.capture.stages[0].steps[2].join.on,
    [{left: 'resource', right: 'resource'}, {left: 'version', right: 'version'}]);
  assert.equal(programs.capture.stages[0].inputs.contents.request, undefined);
  assert.equal(programs.capture.stages[0].inputs.files.view, 'records');
  assert.equal(programs.capture.stages[0].inputs.contents.view, 'records');
  assert.equal(programs.capture.stages[0].steps[2].join.left, 'listing_capture');
  assert.deepEqual(programs.capture.stages[0].steps[3],
    {from: 'captured', assert_rows: {unique_by: ['name']}, as: 'unique_names'});
  assert.deepEqual(programs.capture.stages[0].steps[4],
    {from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered'});
  assert.deepEqual(programs.capture.stages[0].results.files.fields, ['name', 'content']);
});
for (const [reason, mutate] of [
  ['scope', x => { x.prefix = ''; }],
  ['object', x => { x.expectedObjects[0].name = 'another-scope/a.csv'; }],
  ['object', x => { x.expectedObjects.push({...x.expectedObjects[0]}); }],
  ['permissions', x => { x.permissions.push('write'); }],
  ['credential', x => { x.credential.serviceAccount = 'reader@another-project.iam.gserviceaccount.com'; }],
  ['credential', x => { x.credential.executable = 'gcloud'; }],
  ['credential', x => { x.credential.token = 'a-secret-must-not-be-in-the-manifest'; }],
  ['limits', x => { x.limits.maxRequests = 201; }],
  ['limits', x => { x.limits.maxResponseBytes = 10485761; }],
  ['insufficient_total_budget', x => { x.limits.maxRequests = 7; }],
]) test(`GCS acceptance rejects ${reason} before credential acquisition: ${mutate.toString()}`, () => {
  const manifest = gcsAcceptanceManifestFixture();
  mutate(manifest);
  assert.throws(() => checkGcsAcceptanceEnvironment(manifest), error =>
    error.code === 'InvalidGcsAcceptanceEnvironment' && error.reason === reason);
});

// Nonsecret, explicit authority for the real-service acceptance harness. This
// is test configuration, not a Source grant, policy attestation or new owner.
import {isAbsolute} from 'node:path';

const fields = ['version', 'project', 'bucket', 'prefix', 'credential',
  'permissions', 'limits', 'costLimitUsd', 'expectedObjects'];
const limitFields = ['maxRequests', 'maxResponseBytes', 'maxDurationMs', 'maxObjectBytes'];
const permissions = ['list', 'read_metadata', 'read_content'];
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === keys.slice().sort().join('\0');
const exact = (value, maximum) => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value) && Buffer.byteLength(value) <= maximum;
const integer = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const fail = reason => { throw Object.assign(new TypeError(`InvalidGcsAcceptanceEnvironment:${reason}`),
  {code: 'InvalidGcsAcceptanceEnvironment', reason}); };

export function checkGcsAcceptanceEnvironment(value) {
  if (!closed(value, fields) || value.version !== 'actql-gcs-files-content-acceptance/0.1') fail('shape');
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u.test(value.project ?? '') ||
      !/^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/u.test(value.bucket ?? '') ||
      !exact(value.prefix, 1024) || !value.prefix.endsWith('/')) fail('scope');
  if (!closed(value.credential, ['kind', 'serviceAccount', 'account', 'executable']) ||
      value.credential.kind !== 'gcloud-impersonation' ||
      !exact(value.credential.account, 256) || !/^[^\s@]+@[^\s@]+$/u.test(value.credential.account) ||
      !exact(value.credential.serviceAccount, 256) ||
      !value.credential.serviceAccount.endsWith(`@${value.project}.iam.gserviceaccount.com`) ||
      value.credential.serviceAccount.split('@').length !== 2 ||
      !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u.test(value.credential.serviceAccount.split('@')[0]) ||
      !exact(value.credential.executable, 4096) || !isAbsolute(value.credential.executable)) fail('credential');
  if (!Array.isArray(value.permissions) || value.permissions.length !== permissions.length ||
      new Set(value.permissions).size !== permissions.length ||
      !permissions.every(permission => value.permissions.includes(permission))) fail('permissions');
  if (!closed(value.limits, limitFields) || !limitFields.every(key => integer(value.limits[key])) ||
      value.limits.maxDurationMs > 900000 || value.limits.maxRequests > 200 ||
      value.limits.maxResponseBytes > 10485760 || value.limits.maxObjectBytes > 1048576) fail('limits');
  if (!Number.isFinite(value.costLimitUsd) || value.costLimitUsd <= 0 || value.costLimitUsd > 1) fail('cost');
  if (!Array.isArray(value.expectedObjects) || value.expectedObjects.length === 0 ||
      value.expectedObjects.length > 16) fail('objects');
  const names = new Set();
  for (const object of value.expectedObjects) {
    if (!closed(object, ['name', 'mediaType', 'contentCid', 'sizeBytes']) ||
        !exact(object.name, 1024) || !object.name.startsWith(value.prefix) || names.has(object.name) ||
        !exact(object.mediaType, 1024) || !/^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/u.test(object.mediaType) ||
        !cid(object.contentCid) || !Number.isSafeInteger(object.sizeBytes) || object.sizeBytes < 0 ||
        object.sizeBytes > value.limits.maxObjectBytes) fail('object');
    names.add(object.name);
  }
  if (new Set(value.expectedObjects.map(object => object.mediaType)).size !== 1) fail('mixed_media_types');
  // Each transport owns a separate listing and exactly two reads per key.
  // Derive finite per-Run ceilings instead of resetting one total for each Run.
  if (value.limits.maxRequests < 2 * (2 + 2 * value.expectedObjects.length) ||
      value.limits.maxResponseBytes < 2 * value.expectedObjects.reduce((sum, object) => sum + object.sizeBytes, 0) + 32768) {
    fail('insufficient_total_budget');
  }
  return Object.freeze({...value, credential: Object.freeze({...value.credential}),
    permissions: Object.freeze(permissions.slice()), limits: Object.freeze({...value.limits}),
    expectedObjects: Object.freeze(value.expectedObjects.map(object => Object.freeze({...object})))});
}

export function gcsAcceptancePrograms(manifest, connectorId = 'gcs-acceptance') {
  const checked = checkGcsAcceptanceEnvironment(manifest);
  if (!exact(connectorId, 128)) fail('connector');
  const make = paths => ({version: 'actql/0.1', id: 'gcs-version-fixed-read',
    stages: [{id: 's', inputs: {
      // The common row declaration publishes records explicitly. Omitting the
      // view cannot prove that this selector is an audience-visible Source.
      files: {connector: connectorId, resource: 'files', view: 'records', request: {paths, glob: null}},
      contents: {connector: connectorId, resource: 'contents', view: 'records'},
    }, steps: [{join: {left: 'files', with: 'contents', kind: 'inner',
      on: [{left: 'resource', right: 'resource'}, {left: 'version', right: 'version'}],
      select: {name: 'left.name', content: 'right.content'}}, as: 'captured'},
    // The Source name is unique within this bucket. Have the existing row
    // assertion verify that fact; sorting must not fabricate a tie-breaker
    // over opaque ContentRefs or infer uniqueness from the expected fixture.
    {from: 'captured', assert_rows: {unique_by: ['name']}, as: 'unique_names'},
    {from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered'}],
    results: {files: {from: 'ordered', fields: ['name', 'content']}}}],
    results: {files: {from: {stage: 's', result: 'files'}}}});
  return {capture: make(checked.expectedObjects.map(object => object.name)), empty: make([])};
}

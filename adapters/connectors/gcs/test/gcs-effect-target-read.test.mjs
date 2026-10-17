// Real credential Site/signature/SQLite journal; explicit Checkpoint ports.
// No token resolution, HTTP, Core authorization or funded admission is claimed.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {recordCheckpointApproval} from '../../../host-common/checkpoint-approval.mjs';
import {openGcsCredentialSite} from '../site/gcs-credential-site.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const operation = 'gcs:file:read', connection = 'gcs:project/bucket';
const physical = Object.freeze({version: 'actql-installed-gcs-target/0.1',
  project: 'project', bucket: 'bucket', prefix: 'in/e\u0301/',
  scope_cid: cid('1'), catalog_cid: cid('2'), resource: 'objects',
  fields: Object.freeze(['name', 'generation', 'metageneration'])});
const failure = {code: 'RowSourceEffectTargetReadApprovalNotAdmitted'};

async function fixture(t, {legacy = false} = {}) {
  const scratch = await createOwnedScratch({
    parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-target-read-', label: 'GCS same Site original target read'});
  const key = join(scratch.path, 'credential.key');
  const keys = generateKeyPairSync('ed25519');
  await writeFile(key, keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const state = {enters: 0, current: true, checks: 0, secrets: 0, spent: false};
  // Independent installation scope expectation, not a returned request/CID.
  const admitsApprovalTarget = (binding, resource) => {
    state.checks++;
    return !legacy && resource === 'objects' && binding !== null &&
      typeof binding === 'object' && !Array.isArray(binding) &&
      Object.keys(binding).sort().join(',') === Object.keys(physical).sort().join(',') &&
      ['version', 'project', 'bucket', 'prefix', 'scope_cid', 'catalog_cid', 'resource']
        .every(name => binding[name] === physical[name]) &&
      Array.isArray(binding.fields) && new Set(binding.fields).size === binding.fields.length &&
      binding.fields.every(name => physical.fields.includes(name));
  };
  const site = await openGcsCredentialSite({profile: {
    credentialPrivateKeyPath: key, credentialAuthorityId: 'test-authority',
    credentialKeyId: 'test-key', journalRoot: join(scratch.path, 'journal'),
    resourceOrigin: 'https://storage.googleapis.com', namespaceId: 'namespace',
    environment: 'test', siteKey: 'site', siteGeneration: 1},
    principalId: 'principal', authorization: {issued: () => false,
      configurationCid: cid('a'), context: {contextCid: cid('b')}},
    connection, connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
    runtimeBundleCid: cid('c'), commonMoon: moon, admitsApprovalTarget,
    resolveSecret: async () => { state.secrets++; assert.fail('No token resolution'); }});
  t.after(() => { site.close(); assert.equal(state.secrets, 0); scratch.passed(); });
  const tuple = Object.freeze({connection, resource: 'objects', operation: 'read'});
  const decision = (binding = physical, changed = {}, selected = tuple) =>
    recordCheckpointApproval(Object.freeze({action: 'dispatch', basis: 'resumed_approval',
      boundary: 'acquisition', tuple: selected}), {kind: 'effect_target',
      principalId: 'principal', configurationCid: cid('a'), contextCid: cid('b'),
      runDefinitionCid: cid('d'), readTuple: selected, physicalBindings: [binding],
      assertCurrent() {
        if (!state.current) throw Object.assign(new Error('OriginalChanged'), {code: 'OriginalChanged'});
      },
      enter() {
        if (state.spent) throw Object.assign(new Error('OriginalEntrySpent'), {code: 'OriginalEntrySpent'});
        state.spent = true; state.enters++;
      }, ...changed});
  const grant = (original, changes = {}) => site.issueReadGrant({operation,
    decision: original, resource: 'objects', runInvocationCid: cid('e'),
    dispatchRequestCid: cid('f'), maxUses: 1, ...changes});
  return {site, state, decision, grant};
}

test('GCS same Site admits the original objects read and preserves the one-shot entry', async t => {
  const f = await fixture(t), original = f.decision();
  assert.equal(f.site.admitCheckpointEffectTargetRead(original, physical, operation), original);
  assert.equal(f.state.enters, 0);
  const result = f.grant(original);
  assert.equal(result.scope.operation, operation);
  assert.equal(result.scope.resourceOrigin, 'https://storage.googleapis.com');
  assert.equal(f.state.enters, 1);
  assert.throws(() => f.grant(original), {code: 'OriginalEntrySpent'});
  assert.equal(f.state.enters, 1);
});

for (const [name, changes] of [
  ['project', {project: 'other'}], ['bucket', {bucket: 'other'}],
  ['NFC prefix', {prefix: 'in/é/'}], ['scope', {scope_cid: cid('3')}],
  ['catalog', {catalog_cid: cid('3')}], ['resource', {resource: 'files'}],
  ['extra selector', {name: 'in/e\u0301/a'}], ['foreign field', {fields: ['foreign']}],
  ['duplicate field', {fields: ['name', 'name']}],
]) {
  test(`GCS target read rejects a matching approval for foreign ${name}`, async t => {
    const f = await fixture(t), binding = {...physical, ...changes};
    assert.throws(() => f.site.admitCheckpointEffectTargetRead(
      f.decision(binding), binding, operation), failure);
    assert.equal(f.state.enters, 0);
  });
}

test('write, listing and keyed-content operations cannot use the objects target read port', async t => {
  const f = await fixture(t);
  for (const selectedOperation of ['gcs:object:upload', 'gcs:file:list', 'gcs:object:delete']) {
    assert.throws(() => f.site.admitCheckpointEffectTargetRead(
      f.decision(), physical, selectedOperation), failure);
  }
  for (const resource of ['files', 'contents']) {
    const tuple = {connection, resource, operation: 'read'};
    const binding = {...physical, resource};
    assert.throws(() => f.site.admitCheckpointEffectTargetRead(
      f.decision(binding, {}, tuple), binding, operation), failure);
  }
  assert.equal(f.state.checks, 0, 'wrong operation/Resource refuses before scope comparison');
  assert.equal(f.state.enters, 0);
});

test('GCS keeps original Checkpoint authority separate from equal packets and write grants', async t => {
  const f = await fixture(t), original = f.decision();
  assert.throws(() => f.site.admitCheckpointEffectTargetRead({...original}, physical, operation), failure);
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  assert.throws(() => f.grant(original, {operation: 'gcs:object:upload'}),
    {code: 'RowSourceGrantNotAuthorized'});
  assert.throws(() => f.site.issueEffectGrant({operation: 'gcs:object:upload', decision: original,
    resource: 'objects', runInvocationCid: cid('e'), dispatchRequestCid: cid('f'), subjectCid: cid('1')}),
  {code: 'RowSourceGrantNotAuthorized'});
  assert.equal(f.state.enters, 0);
});

test('GCS target grant rechecks the original current fence and same Site lifetime', async t => {
  const f = await fixture(t), original = f.decision();
  f.site.admitCheckpointEffectTargetRead(original, physical, operation);
  f.state.current = false;
  assert.throws(() => f.grant(original), {code: 'OriginalChanged'});
  assert.equal(f.state.enters, 0);
  f.site.close();
  assert.throws(() => f.grant(original), {code: 'RowSourceSiteClosed'});
});

test('a source-only GCS installation still cannot admit an objects target read', async t => {
  const f = await fixture(t, {legacy: true});
  assert.throws(() => f.site.admitCheckpointEffectTargetRead(f.decision(), physical, operation), failure);
  assert.equal(f.state.enters, 0);
});

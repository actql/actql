import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {generateKeyPairSync} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openRowSourceCredentialCustody} from './installed-row-source.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';

const runtimeUrl = process.env.ACTQL_SOURCE_CREDENTIAL_RUNTIME_URL ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href;
const moon = await import(runtimeUrl);
const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => 'sha256:' + digit.repeat(64);

async function originalSourceSigner(t) {
  const root = await mkdtemp(join(process.env.ACTQL_SOURCE_CREDENTIAL_SCRATCH ?? tmpdir(), 'source-original-grant-'));
  const keys = generateKeyPairSync('ed25519');
  const profile = Object.freeze({credentialAuthorityId: 'source-authority', credentialKeyId: 'source-key',
    journalRoot: root, namespaceId: 'source-constructor-test', environment: 'test', siteKey: 'source-site',
    siteGeneration: 1, resourceOrigin: 'https://resource.example'});
  const custody = openRowSourceCredentialCustody({profile, principalId: 'source-principal',
    runtimeBundleCid: cid('a'), connectorRegistration: 'rest-acme', connectorRevision: 'acme/0.1',
    commonMoon: moon, privateKey: keys.privateKey, now: () => 1_999_999_999_000, grantLifetimeMs: 1000,
    runAcquisitionLimits: {maxBindings: 1, maxSecretBytes: 64},
    resolveSecret() {assert.fail('Signing cannot resolve a provider secret');},
    openCredentialJournal(path, options) {
      assert.equal(path, root);
      assert.deepEqual(options.credentialAuthorities.get(profile.credentialAuthorityId).get(profile.credentialKeyId),
        keys.publicKey);
      return openSqliteCredentialJournal(path, options);
    }});
  t.after(() => {
    custody.closeOnce();
    assert.equal(custody.cleanupPending(), false);
    t.diagnostic('Fresh original Credential journal KEEP: ' + root);
  });
  const purpose = Object.freeze({kind: 'read', resource: 'customers', decision: Object.freeze({})});
  const input = Object.freeze({operation: 'read', runInvocationCid: cid('b'),
    dispatchRequestCid: cid('c'), maxUses: 2, issuerPurpose: purpose});
  return {sign: custody.sign, input, journal: custody.credential.journal, custody, purpose};
}

test('Source signer uses the original existing native grant constructor and signed scope', async t => {
  const f = await originalSourceSigner(t);
  assert.equal(control.issue, undefined, 'The selected original control has no second issue API');
  const authorization = f.sign(f.input);
  assert(Object.isFrozen(authorization));assert(Object.isFrozen(authorization.scope));
  assert.strictEqual(f.custody.authorizationPurpose(authorization), f.purpose);
  assert.throws(() => f.custody.authorizationPurpose({...authorization}), {code: 'RowSourceAuthorizationPurposeUnavailable'});
  const grantCid = control.identity(authorization.grant);
  const body = JSON.parse(control.json(authorization.grant));
  assert.deepEqual(body, {version: 'actql-remote-credential-grant/0.1',
    issuer_authority: 'source-authority', principal: 'source-principal',
    namespace_id: 'source-constructor-test', environment: 'test', site_key: 'source-site', site_generation: 1,
    runtime_bundle_cid: cid('a'), connector_registration: 'rest-acme', connector_revision: 'acme/0.1',
    resource_origin: 'https://resource.example', operation: 'read', run_invocation_cid: cid('b'),
    task_attempt: 1, dispatch_request_cid: cid('c'), expires_unix_ms: '2000000000000', max_uses: 2});
  const first = f.journal.claim(grantCid, 'original-use', 1_999_999_999_999n, authorization.scope, control);
  assert.equal(first.replayed, false);assert.equal(first.record.useOrdinal, 1);
  f.journal.finish(first.record.useCid, 'unknown');
});

test('Source signer re-admission keeps the original signed-scope durable use budget', async t => {
  const f = await originalSourceSigner(t), first = f.sign(f.input);
  const id = control.identity(first.grant);
  const used = f.journal.claim(id, 'first-use', 1_999_999_999_999n, first.scope, control);
  f.journal.finish(used.record.useCid, 'unknown');
  const repeated = f.sign(f.input);
  assert.equal(control.identity(repeated.grant), id);
  const second = f.journal.claim(id, 'second-use', 1_999_999_999_999n, repeated.scope, control);
  assert.equal(second.record.useOrdinal, 2);
  f.journal.finish(second.record.useCid, 'unknown');
  assert.throws(() => f.journal.claim(id, 'third-use', 1_999_999_999_999n, repeated.scope, control));
  assert.throws(() => control.prepareUse(first.grant, {useId: 'foreign-operation',
    trustedNowMilliseconds: 1_999_999_999_999n, usedCount: 0, revoked: false,
    scope: {...first.scope, operation: 'other'}}));
});

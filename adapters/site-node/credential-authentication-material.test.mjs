import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding,
  prepareHttpsCredentialAuthenticationMaterial, callHttpsCredentialResource} from './https-credential-resource.mjs';
import {googleServiceAccountAssertionRequest} from './google-service-account-assertion.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({maxScopes: 4, maxScopeBytes: 1024, maxIdentityBytes: 512,
  maxClaimBytes: 2048, maxAssertionBytes: 4096, maxRequestBytes: 8192, maxKeyBits: 2048});

async function fixture(t, options = {}) {
  const parent = fileURLToPath(new URL('../../_build/authentication-material/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'owned-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(root, {credentialAuthorities:
    new Map([['authority', new Map([['issuer', authority.publicKey]])]])});
  const nowValue = 1_700_000_000_000;
  let observedNow = nowValue, resolutions = 0, secretResolutions = 0, checks = 0;
  const scope = Object.freeze({issuerAuthority: 'authority', principal: 'principal',
    namespaceId: 'namespace', environment: 'production', siteKey: 'site', siteGeneration: 2,
    runtimeBundleCid: cid('a'), connectorRegistration: 'google-fixture', connectorRevision: '0.1',
    resourceOrigin: 'https://resource.example', operation: 'read', runInvocationCid: cid('b'),
    taskAttempt: 3, dispatchRequestCid: cid('c'), expiresUnixMilliseconds: BigInt(nowValue + 600_000), maxUses: 2});
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {privateKey: authority.privateKey, keyId: 'issuer'}), control);
  const claim = journal.claim(control.identity(grant), 'original-parent', BigInt(nowValue), scope, control);
  const native = generateKeyPairSync('rsa', {modulusLength: 2048}).privateKey;
  let selected = {privateKey: native, keyGeneration: 'original-secret-generation',
    clientEmail: 'fixture@example.test', scopes: ['scope:a', 'scope:b'], delegate: undefined,
    expiresUnixMilliseconds: BigInt(nowValue + 300_000)};
  const original = selected;
  const resolveSecret = async () => {secretResolutions++; return 'not-an-auth-token';};
  const registration = {clientEmail: original.clientEmail, scopes: original.scopes,
    keyGeneration: original.keyGeneration, lifetimeSeconds: 120, signingLimits: limits,
    resolveMaterial: async (context, signal) => {
      resolutions++;
      assert.equal(context.dispatchRequestCid, scope.dispatchRequestCid);
      assert.equal(context.grantCid, control.identity(grant));
      await options.resolve?.(original, signal);
      return original;
    },
    assertCurrentMaterial(value) {
      checks++;
      assert.equal(value, original);
      if (selected !== original) throw Object.assign(new Error('OriginalMaterialRevoked'),
        {code: 'OriginalMaterialRevoked'});
    }};
  const binding = openHttpsCredentialBinding({scope, control, journal, resolveSecret,
    maxSecretBytes: 64, authentication: options.unregistered ? undefined : registration});
  t.after(async () => {
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    journal.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Original material/Journal scratch retained: ${root}`);
    } else await rm(root, {recursive: true, force: true});
  });
  const call = overrides => prepareHttpsCredentialAuthenticationMaterial({binding,
    scope, control, journal, resolveSecret, parentClaim: claim, now: () => observedNow,
    currentBeforeSign: async () => {}, ...overrides});
  return {binding, scope, control, journal, grant, claim, original, registration, resolveSecret, call,
    resolutions: () => resolutions, secretResolutions: () => secretResolutions,
    checks: () => checks, revokeMaterial: () => {selected = {};},
    advance: value => {observedNow = value;}, nowValue};
}

test('the same binding retains native original material without exposing a key form or token', async t => {
  const f = await fixture(t);
  let currents = 0;
  const material = await f.call({currentBeforeSign: async () => {currents++;}});
  assert.deepEqual(Reflect.ownKeys(material), []);
  assert.equal(Object.isFrozen(material), true);
  assert.throws(() => googleServiceAccountAssertionRequest(material), {code: 'ForeignGoogleAssertionPreparation'});
  assert.equal(f.resolutions(), 1);
  assert.equal(f.secretResolutions(), 0);
  assert.equal(currents, 2);
  assert.equal(f.checks(), 2);
  assert.deepEqual(f.journal.recover().map(record => record.outcome), ['claimed']);
  await assert.rejects(f.call(), {code: 'RemoteCredentialAuthenticationAlreadyPrepared'});
  assert.equal(f.resolutions(), 1);
});

test('missing registration refuses before current reads resolver or another use', async t => {
  const f = await fixture(t, {unregistered: true});
  let currents = 0;
  await assert.rejects(f.call({currentBeforeSign: async () => {currents++;}}),
    {code: 'RemoteCredentialAuthenticationUnavailable'});
  assert.equal(currents, 0);
  assert.equal(f.resolutions(), 0);
  assert.equal(f.journal.recover().length, 1);
});

for (const field of ['keyGeneration', 'clientEmail', 'scopes', 'expiresUnixMilliseconds']) {
  test(`material ${field} substitution across the current await refuses without another lookup`, async t => {
    const f = await fixture(t);
    let currents = 0;
    await assert.rejects(f.call({currentBeforeSign: async () => {
      if (++currents === 2) {
        if (field === 'keyGeneration') f.original[field] = 'replacement-generation';
        if (field === 'clientEmail') f.original[field] = 'other@example.test';
        if (field === 'scopes') f.original[field] = ['scope:other'];
        if (field === 'expiresUnixMilliseconds') f.original[field] += 1n;
        await Promise.resolve();
      }
    }}), {code: 'RemoteCredentialAuthenticationMaterialChanged'});
    assert.equal(f.resolutions(), 1);
    await assert.rejects(f.call(), {code: 'RemoteCredentialAuthenticationAlreadyPrepared'});
  });
}

test('the original resolver current check refuses a rotated generation after the authority await', async t => {
  const f = await fixture(t);
  let currents = 0;
  await assert.rejects(f.call({currentBeforeSign: async () => {
    if (++currents === 2) { f.revokeMaterial(); await Promise.resolve(); }
  }}), {code: 'OriginalMaterialRevoked'});
  assert.equal(f.resolutions(), 1);
});

test('parent revocation after material resolution keeps its original claimed use and refuses signing', async t => {
  const f = await fixture(t);
  let currents = 0;
  await assert.rejects(f.call({currentBeforeSign: async () => {
    if (++currents === 2) f.journal.revoke(control.identity(f.grant));
  }}));
  assert.equal(f.resolutions(), 1);
  assert.equal(f.journal.recover()[0].outcome, 'claimed');
});

test('binding retirement during resolution stays pending until that original operation retires', async t => {
  let release, entered;
  const waiting = new Promise(resolve => {entered = resolve;});
  const pending = new Promise(resolve => {release = resolve;});
  const f = await fixture(t, {resolve: async () => {entered(); await pending;}});
  let currents = 0;
  const attempt = f.call({currentBeforeSign: async () => {currents++;}});
  const result = assert.rejects(attempt, {code: 'RemoteCredentialBindingRetiring'});
  await waiting;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  release();
  await result;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(currents, 1);
});

test('material expiry and the actual native key kind are not filled from a key ID or Site generation', async t => {
  const expired = await fixture(t);
  expired.original.expiresUnixMilliseconds = BigInt(expired.nowValue - 1);
  await assert.rejects(expired.call(), {code: 'RemoteCredentialAuthenticationMaterialExpired'});
  const wrong = await fixture(t);
  wrong.original.privateKey = generateKeyPairSync('ed25519').privateKey;
  await assert.rejects(wrong.call(), {code: 'InvalidGoogleAssertionKey'});
});

test('an auth-registered binding cannot use the old Bearer port before its separate exchange exists', async t => {
  const f = await fixture(t);
  await assert.rejects(callHttpsCredentialResource({binding: f.binding, scope: f.scope,
    control, journal: f.journal, resolveSecret: f.resolveSecret}),
  {code: 'RemoteCredentialAuthenticationUnavailable'});
  assert.equal(f.secretResolutions(), 0);
  assert.equal(f.journal.recover().length, 1);
});

test('the original resolver failure retains its own cleanup duty beside binding retirement', async t => {
  const cleanup = Object.freeze({status: () => ({pending: true}), retry: async () => {}});
  const failure = Object.freeze(Object.assign(new Error('OriginalMaterialReaderPending'), {
    cleanupHandle: cleanup, cleanupPending: true,
  }));
  const f = await fixture(t, {resolve: async () => {throw failure;}});
  await assert.rejects(f.call(), error => error === failure);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  // The binding ACK is not the failed resolver's original Reader ACK.
  assert.equal(failure.cleanupHandle, cleanup);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(failure.cleanupPending, true);
  assert.equal(f.resolutions(), 1);
});

test('every generated invocation field remains required before material lookup', async t => {
  const f = await fixture(t);
  const {credentialInvocationBindingKeys} = await import('../host-common/credential-scope-fields.generated.mjs');
  for (const field of credentialInvocationBindingKeys) {
    const missing = {...f.scope}; delete missing[field];
    await assert.rejects(f.call({scope: missing}), {code: 'ForeignRemoteCredentialBinding'});
  }
  assert.equal(f.resolutions(), 0);
  assert.equal(f.journal.recover().length, 1);
});

test('a key replacement during the final current await cannot replace the original native object', async t => {
  const f = await fixture(t), replacement = generateKeyPairSync('rsa', {modulusLength: 2048}).privateKey;
  let currents = 0;
  await assert.rejects(f.call({currentBeforeSign: async () => {
    if (++currents === 2) f.original.privateKey = replacement;
  }}), {code: 'RemoteCredentialAuthenticationMaterialChanged'});
  assert.equal(f.resolutions(), 1);
});

test('registration missing generation or finite signing limits performs no material lookup', async t => {
  const f = await fixture(t);
  for (const authentication of [{...f.registration, keyGeneration: undefined},
    {...f.registration, signingLimits: undefined},
    {...f.registration, signingLimits: {...limits, maxRequestBytes: 0}},
    {...f.registration, signingLimits: {...limits, maxRequestBytes: 2147483648}}]) {
    assert.throws(() => openHttpsCredentialBinding({scope: f.scope, control,
      journal: f.journal, resolveSecret: f.resolveSecret, maxSecretBytes: 64, authentication}),
    {code: 'InvalidRemoteCredentialAuthenticationRegistration'});
  }
  assert.equal(f.resolutions(), 0);
  assert.equal(f.journal.recover().length, 1);
});

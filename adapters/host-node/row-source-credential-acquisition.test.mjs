import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../site-node/https-credential-resource.mjs';
import {openHttpsExchangeFixture} from '../site-node/https-exchange-fixture.mjs';
import {openRowSourceCredentialCustody} from './installed-row-source.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteCredentialControl;
const request = () => ({operation: 'fixture:read', runInvocationCid: cid('b'),
  dispatchRequestCid: cid('c'), taskAttempt: 3, maxUses: 2});
const current = () => ({assertCurrent() {}, async observeCurrent() {}});
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
}

async function fixture(t, options = {}) {
  const exchange = await openHttpsExchangeFixture(t, {routes: [{method: 'GET',
    pathname: '/records', handle: () => ({body: {records: [1]}})}]});
  const root = await mkdtemp(join(tmpdir(), 'actql-credential-acquisition-'));
  const key = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'authority.key'), key.privateKey.export({type: 'pkcs8', format: 'pem'}),
    {mode: 0o600});
  const profile = Object.freeze({credentialAuthorityId: 'authority', credentialKeyId: 'issuer',
    journalRoot: join(root, 'journal'), resourceOrigin: exchange.origin,
    namespaceId: 'namespace', environment: 'test', siteKey: 'site', siteGeneration: 2});
  let resolutions = 0, accepts = 0, claims = 0, finishes = 0, closes = 0;
  let secret = 'original-test-secret', failClose = options.failClose;
  const args = {profile, principalId: 'principal', connectorRegistration: 'fixture',
    connectorRevision: 'fixture/0.1', runtimeBundleCid: cid('a'), commonMoon: moon,
    privateKey: key.privateKey, ca: exchange.ca, now: () => 1_700_000_000_000,
    grantLifetimeMs: 456, runAcquisitionLimits: {maxBindings: 2, maxSecretBytes: 64},
    resolveSecret: async () => {
      resolutions++; await options.resolve?.(); return secret;
    },
    openCredentialJournal(path, input) {
      const original = openSqliteCredentialJournal(path, input);
      return Object.freeze({...original,
        acceptGrant(...fields) { accepts++; return original.acceptGrant(...fields); },
        claim(...fields) { claims++; return original.claim(...fields); },
        finish(...fields) { finishes++; if (options.finishFailure) throw options.finishFailure;
          return original.finish(...fields); },
        close() { closes++; if (failClose) { const failure = failClose; failClose = undefined; throw failure; }
          return original.close(); },
      });
    }, ...options.custody};
  const custody = openRowSourceCredentialCustody(args);
  t.after(async () => {
    custody.closeOnce();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') console.error(`Original acquisition custody retained: ${root}`);
    else await rm(root, {recursive: true, force: true});
  });
  const invoke = (acquisition, useId, overrides = {}) => callHttpsCredentialResource({
    ...acquisition.credential, ...acquisition.authorization, useId,
    operations: new Map([['fixture:read', {method: 'GET', path: '/records'}]]),
    maxRequestBytes: 1024, maxResponseBytes: 1024, ...overrides});
  return {custody, invoke, exchange, args,
    secret: value => { secret = value; },
    counts: () => ({resolutions, accepts, claims, finishes, closes})};
}

test('run acquisition custody uses the existing issuer, exact scope, and actual confirmed response use', async t => {
  const f = await fixture(t);
  const original = request();
  const old = f.custody.sign(original);
  const acquired = f.custody.openRunAcquisition(original, current());
  assert.equal(control.json(acquired.authorization.grant), control.json(old.grant));
  assert.deepEqual(acquired.authorization.scope, old.scope);
  assert.equal(acquired.authorization.scope.taskAttempt, 3);
  assert.equal(acquired.authorization.scope.expiresUnixMilliseconds, 1_700_000_000_456n);
  assert.equal(acquired.credential.control, f.custody.credential.control);
  assert.equal(acquired.credential.journal, f.custody.credential.journal);
  assert.equal(acquired.credential.resolveSecret, f.custody.credential.resolveSecret);
  const response = await f.invoke(acquired, 'original-response', {retainRunResponseOriginal: true});
  withHttpsCredentialRunResponseOriginal(response, control, acquired.credential.journal, facts => {
    assert.notEqual(facts.grant, acquired.authorization.grant);
    assert.equal(control.useIdentity(facts.use), response.useCid);
    assert.equal(facts.scope, acquired.authorization.scope);
  });
  assert.deepEqual(JSON.parse(response.body), {records: [1]});
  assert.equal(f.exchange.seen().length, 1);
  assert.equal(acquired.close(), 'closed');
  f.custody.closeOnce(); f.custody.closeOnce(); f.custody.close();
  assert.equal(f.counts().closes, 1);
});

test('run acquisition custody captures request and current methods before callbacks can substitute them', async t => {
  const f = await fixture(t);
  const original = request();
  let assertions = 0, observations = 0, replacements = 0;
  const methods = {
    assertCurrent(...args) {
      assert.equal(this, undefined); assert.deepEqual(args, []); assertions++;
      original.operation = 'foreign:operation';
      methods.assertCurrent = () => { replacements++; };
    },
    async observeCurrent(...args) {
      assert.equal(this, undefined); assert.deepEqual(args, []); observations++;
      methods.observeCurrent = () => { replacements++; };
    },
  };
  const acquired = f.custody.openRunAcquisition(original, methods);
  assert.equal(acquired.authorization.scope.operation, 'fixture:read');
  await f.invoke(acquired, 'captured-methods');
  assert.ok(assertions > 3); assert.equal(observations, 3); assert.equal(replacements, 0);
  assert.equal(acquired.close(), 'closed');
});

test('run acquisition custody refuses stale current before issuing a grant', async t => {
  const f = await fixture(t), cause = new Error('OriginalCurrentRevoked');
  assert.throws(() => f.custody.openRunAcquisition(request(), {
    assertCurrent() { throw cause; }, async observeCurrent() { assert.fail('No observation'); },
  }), error => error === cause);
  assert.deepEqual(f.counts(), {resolutions: 0, accepts: 0, claims: 0, finishes: 0, closes: 0});
  assert.equal(f.exchange.seen().length, 0);
});

test('run acquisition custody retains the Journal while its original resolver is pending', async t => {
  const entered = deferred(), released = deferred();
  const f = await fixture(t, {resolve: async () => { entered.resolve(); await released.promise; }});
  const acquired = f.custody.openRunAcquisition(request(), current());
  const result = f.invoke(acquired, 'resolver-pending');
  try {
    await entered.promise;
    assert.throws(() => f.custody.closeOnce(), {code: 'RowSourceCredentialAcquisitionCleanupPending'});
    assert.equal(f.custody.cleanupPending(), true); assert.equal(f.counts().closes, 0);
    assert.equal(acquired.close(), 'pending');
  } finally { released.resolve(); }
  await assert.rejects(result, {code: 'RemoteCredentialBindingRetiring'});
  assert.deepEqual(acquired.credential.journal.recover().map(row => row.outcome), ['failed']);
  f.custody.closeOnce(); f.custody.closeOnce();
  assert.equal(f.counts().closes, 1); assert.equal(f.custody.cleanupPending(), false);
  assert.equal(f.exchange.seen().length, 0);
});

test('run acquisition custody waits through the final response observation before closing the Journal', async t => {
  const f = await fixture(t), entered = deferred(), released = deferred();
  let observations = 0;
  const acquired = f.custody.openRunAcquisition(request(), {assertCurrent() {},
    async observeCurrent() { if (++observations === 3) { entered.resolve(); await released.promise; } },
  });
  const result = f.invoke(acquired, 'response-pending');
  try {
    await entered.promise;
    assert.equal(f.exchange.seen().length, 1);
    assert.throws(() => f.custody.closeOnce(), {code: 'RowSourceCredentialAcquisitionCleanupPending'});
    assert.equal(f.counts().closes, 0);
    assert.throws(() => f.custody.openRunAcquisition(request(), current()), {code: 'RowSourceSiteClosed'});
  } finally { released.resolve(); }
  await assert.rejects(result, {code: 'RowSourceSiteClosed'});
  assert.deepEqual(acquired.credential.journal.recover().map(row => row.outcome), ['unknown']);
  assert.equal(acquired.close(), 'closed');
  f.custody.closeOnce(); assert.equal(f.counts().closes, 1);
});

test('run acquisition custody cannot send replacement material or re-probe after rotation', async t => {
  const f = await fixture(t);
  const acquired = f.custody.openRunAcquisition(request(), current());
  await f.invoke(acquired, 'original-material');
  f.secret('another-account-secret');
  await assert.rejects(f.invoke(acquired, 'changed-material'), {code: 'RemoteCredentialBindingChanged'});
  await assert.rejects(f.invoke(acquired, 'no-reprobe'), {code: 'RemoteCredentialBindingChanged'});
  assert.equal(f.counts().resolutions, 2); assert.equal(f.counts().claims, 2);
  assert.equal(f.exchange.seen().length, 1);
  assert.deepEqual(acquired.credential.journal.recover().map(row => row.outcome), ['succeeded', 'failed']);
});

test('run acquisition custody retains an unconfirmed original Journal claim without resend', async t => {
  const cause = new Error('OriginalCommitOutcomeUnconfirmed');
  const f = await fixture(t, {finishFailure: cause});
  const acquired = f.custody.openRunAcquisition(request(), current());
  await assert.rejects(f.invoke(acquired, 'unconfirmed'), error => error === cause);
  await assert.rejects(f.invoke(acquired, 'no-resend'), error => error === cause);
  assert.deepEqual(acquired.credential.journal.recover().map(row => row.outcome), ['claimed']);
  assert.equal(f.counts().finishes, 1); assert.equal(f.counts().claims, 1);
  assert.equal(f.exchange.seen().length, 1);
  assert.equal(acquired.close(), 'closed');
});

test('run acquisition custody uses explicit retained capacity and does not replenish it from a close ACK', async t => {
  const f = await fixture(t, {custody: {runAcquisitionLimits: {maxBindings: 1, maxSecretBytes: 64}}});
  const acquired = f.custody.openRunAcquisition(request(), current());
  assert.equal(acquired.close(), 'closed');
  assert.throws(() => f.custody.openRunAcquisition(request(), current()), {code: 'RowSourceCredentialAcquisitionLimit'});
  assert.equal(f.counts().accepts, 1); assert.equal(f.counts().claims, 0);
  assert.equal(f.counts().resolutions, 0); assert.equal(f.exchange.seen().length, 0);
});

test('run acquisition custody preserves the original Journal close failure after child ACK', async t => {
  const cause = new Error('OriginalJournalCloseFailed');
  const f = await fixture(t, {failClose: cause});
  const acquired = f.custody.openRunAcquisition(request(), current());
  assert.equal(acquired.close(), 'closed');
  assert.throws(() => f.custody.closeOnce(), error => error === cause);
  assert.equal(f.custody.cleanupPending(), true); assert.equal(f.counts().closes, 1);
  f.custody.closeOnce(); f.custody.close();
  assert.equal(f.counts().closes, 2); assert.equal(f.custody.cleanupPending(), false);
});

test('run acquisition custody has no implicit capacity or current certificate', async t => {
  const f = await fixture(t, {custody: {runAcquisitionLimits: undefined}});
  assert.throws(() => f.custody.openRunAcquisition(request(), current()), {code: 'RowSourceCredentialAcquisitionUnavailable'});
  let opens = 0;
  for (const limits of [{maxBindings: 0, maxSecretBytes: 1}, {maxBindings: 1},
    {maxBindings: 1, maxSecretBytes: 0}, {get maxBindings() { assert.fail('Getter'); }, maxSecretBytes: 1}]) {
    assert.throws(() => openRowSourceCredentialCustody({...f.args, runAcquisitionLimits: limits,
      openCredentialJournal() { opens++; assert.fail('No Journal before capacity validation'); }}),
    {code: 'InvalidRowSourceCredentialAcquisitionLimits'});
  }
  assert.equal(opens, 0); assert.equal(f.counts().accepts, 0);
});

test('run acquisition custody refuses copied request accessors, null attempt and async current certificates', async t => {
  const f = await fixture(t);
  assert.throws(() => f.custody.openRunAcquisition({...request(), get operation() { assert.fail('Getter'); }}, current()),
    {code: 'InvalidRowSourceCredentialAcquisitionRequest'});
  assert.throws(() => f.custody.openRunAcquisition({...request(), taskAttempt: null}, current()),
    {code: 'InvalidRowSourceGrantRequest'});
  assert.throws(() => f.custody.openRunAcquisition(request(), {assertCurrent: async () => {}, observeCurrent: async () => {}}),
    {code: 'InvalidRemoteCredentialCurrentFence'});
  assert.equal(f.counts().accepts, 0); assert.equal(f.counts().claims, 0);
  assert.equal(f.counts().resolutions, 0); assert.equal(f.exchange.seen().length, 0);
});

import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const parentScope = Object.freeze({issuerAuthority: 'credential-authority-a',
  principal: 'principal-a', namespaceId: 'namespace-a', environment: 'production',
  siteKey: 'site-a', siteGeneration: 4, runtimeBundleCid: cid('a'),
  connectorRegistration: 'http-source', connectorRevision: 'http-source/1',
  resourceOrigin: 'https://resource.example', operation: 'records:read',
  runInvocationCid: cid('b'), taskAttempt: 2, dispatchRequestCid: cid('c'),
  expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 2});
const authScope = Object.freeze({...parentScope,
  resourceOrigin: 'https://oauth2.googleapis.com',
  operation: 'service-account:authenticate',
  expiresUnixMilliseconds: 1_999_999_999_999n, maxUses: 1});
const shape = ['POST', '/token', 'application/x-www-form-urlencoded'];

async function fixture(t) {
  const directory = fileURLToPath(new URL('../../_build/authentication-journal/', import.meta.url));
  await mkdir(directory, {recursive: true});
  const root = await mkdtemp(join(directory, 'owned-'));
  const authority = generateKeyPairSync('ed25519');
  const authorities = new Map([[parentScope.issuerAuthority,
    new Map([['original-issuer', authority.publicKey]])]]);
  const journals = [];
  const open = () => {
    const journal = openSqliteCredentialJournal(root, {credentialAuthorities: authorities});
    journals.push(journal);
    return journal;
  };
  const journal = open();
  t.after(async () => {
    for (const original of journals.reverse()) original.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Original authentication Journal scratch retained: ${root}`);
    } else await rm(root, {recursive: true, force: true});
  });
  const sign = grant => signRemoteCredentialGrant(grant, control,
    {keyId: 'original-issuer', privateKey: authority.privateKey});
  const parentGrant = control.prepare(parentScope);
  const authGrant = control.prepare(authScope);
  journal.acceptGrant(sign(parentGrant), control);
  const authEnvelope = sign(authGrant);
  journal.acceptGrant(authEnvelope, control);
  const parent = journal.claim(control.identity(parentGrant), 'original-parent', 1n, parentScope, control);
  const claim = () => journal.claim(control.identity(authGrant), 'original-auth', 1n, authScope, control);
  // Pure opaque membership fixture: this unit issues no physical secret/key
  // generation, token request or API authority from the material value.
  const material = Object.freeze({});
  const body = Buffer.from('original-private-form');
  const prepare = (grant, use = parent.use) => control.prepareAuthenticationRequest(
    use, grant, material, ...shape, body, body.length, 100n);
  const bind = (request, claim, use = parent.use, bytes = body, selected = material) =>
    control.bindAuthenticationUse(request, use, claim.use, selected, ...shape, bytes, 1n);
  const check = (operation, request, claim) => control.checkAuthenticationOperation(
    operation, request, parent.use, claim.use, material, ...shape, body, 1n);
  return {root, journal, open, authGrant, parentGrant, parent, authEnvelope,
    claim, prepare, bind, check, material, body};
}

test('the actual signature-admitted claim grant binds only its own original authentication use', async t => {
  const f = await fixture(t), claim = f.claim();
  assert.equal(claim.replayed, false);
  assert.ok(Object.hasOwn(claim, 'grant'));
  assert.equal(control.identity(claim.grant), control.identity(f.authGrant));
  assert.equal(control.json(claim.grant), f.authEnvelope.body);
  assert.equal(Object.isFrozen(claim), true);
  const request = f.prepare(claim.grant), operation = f.bind(request, claim);
  assert.doesNotThrow(() => f.check(operation, request, claim));
  assert.doesNotThrow(() => f.journal.authorize(claim.use, 1n, authScope, control));
  // Equal canonical issuer data is not the actual grant held by this claim.
  assert.throws(() => f.bind(f.prepare(f.authGrant), claim));
  const admittedAgain = control.admitJson(control.json(claim.grant), control.identity(claim.grant));
  assert.throws(() => f.bind(f.prepare(admittedAgain), claim));
  assert.equal(f.journal.recover().length, 2);
});

test('another claim observation cannot replace the original pair or bypass replay refusal', async t => {
  const f = await fixture(t), original = f.claim();
  const request = f.prepare(original.grant), operation = f.bind(request, original);
  const replay = f.claim();
  assert.equal(replay.replayed, true);
  assert.equal(replay.record.useCid, original.record.useCid);
  assert.equal(control.json(replay.grant), control.json(original.grant));
  assert.throws(() => f.bind(request, replay));
  assert.throws(() => f.check(operation, request, replay));
  const parentCopy = f.journal.claim(control.identity(f.parentGrant),
    'original-parent', 1n, parentScope, control);
  assert.equal(parentCopy.replayed, true);
  assert.throws(() => f.bind(request, original, parentCopy.use));
  assert.throws(() => f.bind(request, original, f.parent.use, f.body, Object.freeze({})));
  const changedBody = Buffer.from(f.body); changedBody[0] ^= 1;
  assert.throws(() => f.bind(request, original, f.parent.use, changedBody));
  f.journal.finish(original.record.useCid, 'unknown');
  f.journal.close();
  const reopened = f.open();
  const restored = reopened.claim(control.identity(f.authGrant), 'original-auth', 1n, authScope, control);
  assert.equal(restored.replayed, true);
  assert.equal(restored.record.outcome, 'unknown');
  assert.throws(() => f.bind(request, restored));
  assert.equal(reopened.recover().length, 2);
});

test('the matching pair does not replace current revocation expiry or final scope authorization', async t => {
  const f = await fixture(t), claim = f.claim();
  const request = f.prepare(claim.grant), operation = f.bind(request, claim);
  for (const scope of [{...authScope, siteGeneration: 5},
    {...authScope, operation: parentScope.operation},
    {...authScope, resourceOrigin: parentScope.resourceOrigin}]) {
    assert.throws(() => f.journal.authorize(claim.use, 1n, scope, control));
  }
  assert.throws(() => f.journal.authorize(claim.use,
    authScope.expiresUnixMilliseconds, authScope, control));
  f.journal.revoke(control.identity(f.authGrant));
  assert.throws(() => f.journal.authorize(claim.use, 1n, authScope, control));
  // Pure original correspondence stays true; it is not a send permission.
  assert.doesNotThrow(() => f.check(operation, request, claim));
  assert.equal(f.journal.recover().find(r => r.useCid === claim.record.useCid).outcome, 'claimed');
});

test('a lost claim COMMIT reply returns no original pair and never fabricates an unclaimed result', async t => {
  const f = await fixture(t), originalExec = DatabaseSync.prototype.exec;
  const failure = new Error('OriginalClaimCommitReplyLost');
  let commits = 0, returned;
  DatabaseSync.prototype.exec = function(sql) {
    const value = originalExec.call(this, sql);
    if (sql === 'COMMIT' && ++commits === 1) throw failure;
    return value;
  };
  try {
    assert.throws(() => {returned = f.claim();}, error => {
      assert.equal(error.code, 'RemoteCredentialJournalCommitOutcomeUnknown');
      assert.equal(error.cause, failure);
      assert.equal(error.outcome, 'unknown');
      return true;
    });
  } finally { DatabaseSync.prototype.exec = originalExec; }
  assert.equal(returned, undefined);
  assert.equal(commits, 1);
  const records = f.journal.recover();
  assert.equal(records.length, 2);
  assert.equal(records.filter(r => r.useId === 'original-auth').length, 1);
  assert.equal(records.find(r => r.useId === 'original-auth').outcome, 'claimed');
});

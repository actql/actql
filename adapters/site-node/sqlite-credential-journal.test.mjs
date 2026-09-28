import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from
  './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  './remote-credential-signature.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = Object.freeze({
  issuerAuthority: 'credential-authority-a',
  principal: 'principal-a',
  namespaceId: 'namespace-a',
  environment: 'production',
  siteKey: 'site-a',
  siteGeneration: 4,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'http-source',
  connectorRevision: 'http-source/1',
  resourceOrigin: 'https://resource.example',
  operation: 'records:read',
  runInvocationCid: cid('b'),
  taskAttempt: 2,
  dispatchRequestCid: cid('c'),
  expiresUnixMilliseconds: 2_000_000_000_000n,
  maxUses: 2,
});

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-credential-journal-'));
  const journals = [];
  t.after(async () => {
    for (const journal of journals.reverse()) journal.close();
    await rm(root, {recursive: true, force: true});
  });
  const keys = generateKeyPairSync('ed25519');
  const credentialAuthorities = new Map([
    ['credential-authority-a', new Map([['key-a', keys.publicKey]])],
  ]);
  const open = () => {
    const journal = openSqliteCredentialJournal(root, {
      credentialAuthorities,
      ...options,
    });
    journals.push(journal);
    return journal;
  };
  const sign = grant => signRemoteCredentialGrant(grant, control, {
    keyId: 'key-a',
    privateKey: keys.privateKey,
  });
  return Object.freeze({open, sign});
}

test('credential claim is durable before I/O and never refunds uncertainty',
  async t => {
    const {open, sign} = await fixture(t);
    const grant = control.prepare(scope);
    const grantCid = control.identity(grant);
    const first = open();
    first.acceptGrant(sign(grant), control);
    const claimed = first.claim(
      grantCid,
      'use-a',
      1_999_999_999_999n,
      scope,
      control,
    );
    assert.equal(claimed.replayed, false);
    first.close();

    const reopened = open();
    assert.deepEqual(reopened.recover(), [{
      useCid: claimed.record.useCid,
      grantCid,
      useId: 'use-a',
      useOrdinal: 1,
      outcome: 'claimed',
    }]);
    const replay = reopened.claim(
      grantCid,
      'use-a',
      1_999_999_999_999n,
      scope,
      control,
    );
    assert.equal(replay.replayed, true);
    reopened.finish(claimed.record.useCid, 'unknown');
    assert.equal(
      reopened.finish(claimed.record.useCid, 'failed').outcome,
      'failed',
    );
    assert.throws(
      () => reopened.finish(claimed.record.useCid, 'succeeded'),
      {code: 'RemoteCredentialOutcomeConflict'},
    );
  });

test('credential capacity and revocation are atomic across journal handles',
  async t => {
    const {open, sign} = await fixture(t);
    const grant = control.prepare(scope);
    const grantCid = control.identity(grant);
    const first = open();
    const second = open();
    first.acceptGrant(sign(grant), control);
    first.claim(grantCid, 'use-a', 1n, scope, control);
    second.claim(grantCid, 'use-b', 1n, scope, control);
    assert.throws(
      () => first.claim(grantCid, 'use-c', 1n, scope, control),
    );
    second.revoke(grantCid);
    assert.throws(
      () => first.claim(grantCid, 'use-c', 1n, scope, control),
    );
    assert.equal(first.recover().length, 2);
  });

test('credential journal stores no provider secret', async t => {
  const {open, sign} = await fixture(t);
  const journal = open();
  const grant = control.prepare(scope);
  journal.acceptGrant(sign(grant), control);
  journal.claim(control.identity(grant), 'use-a', 1n, scope, control);
  const bytes = await import('node:fs/promises').then(({readFile}) =>
    readFile(journal.path));
  assert.equal(bytes.includes(Buffer.from('provider-secret')), false);
});

test('admission checks authenticate current grants without consuming a use',
  async t => {
    const {open, sign} = await fixture(t);
    const journal = open();
    const grant = control.prepare(scope);
    const id = control.identity(grant);
    assert.throws(() => journal.checkGrant(id, 1n, scope, control),
      {code: 'RemoteCredentialGrantMissing'});
    journal.acceptGrant(sign(grant), control);
    for (let i = 0; i < 3; i++) {
      assert.equal(control.identity(journal.checkGrant(id, 1n, scope,
        control)), id);
    }
    assert.deepEqual(journal.recover(), []);
    assert.throws(() => journal.checkGrant(id,
      scope.expiresUnixMilliseconds, scope, control));
    assert.throws(() => journal.checkGrant(id, 1n,
      {...scope, siteGeneration: scope.siteGeneration + 1}, control));
    journal.claim(id, 'first', 1n, scope, control);
    journal.claim(id, 'second', 1n, scope, control);
    assert.throws(() => journal.checkGrant(id, 1n, scope, control));
    assert.equal(journal.recover().length, 2);
    const other = control.prepare({...scope, dispatchRequestCid: cid('d')});
    const otherId = control.identity(other);
    journal.acceptGrant(sign(other), control);
    journal.revoke(otherId);
    assert.throws(() => journal.checkGrant(otherId, 1n,
      {...scope, dispatchRequestCid: cid('d')}, control));
    assert.equal(journal.recover().length, 2);
  });

test('credential journal rejects an untrusted or altered issuer envelope',
  async t => {
    const {open, sign} = await fixture(t);
    const journal = open();
    const grant = control.prepare(scope);
    const envelope = sign(grant);
    const changed = Buffer.from(envelope.signature, 'base64url');
    changed[0] ^= 1;
    assert.throws(
      () => journal.acceptGrant({
        ...envelope,
        signature: changed.toString('base64url'),
      }, control),
      {code: 'RemoteCredentialSignatureRejected'},
    );
    assert.equal(journal.recover().length, 0);
  });

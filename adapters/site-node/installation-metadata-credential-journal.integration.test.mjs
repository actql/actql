// Actual Common and SQLite with explicit local fixture Subject/signing keys.
// This does not supply an operational Host request/current/material/funding.
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {generateKeyPairSync} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {createInstallationPreparationMetadata} from '../host-common/installation-preparation-metadata.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';

assert(process.env.ACTQL_METADATA_COMMON_RUNTIME, 'An actual matching Common runtime is mandatory');
const moon = await import(pathToFileURL(process.env.ACTQL_METADATA_COMMON_RUNTIME));
const legacy = runtimeCore(moon).remoteCredentialControl;
const cid = digit => 'sha256:' + digit.repeat(64);
const subjectData = () => ({accountConfigurationCid: cid('a'), accountId: 'account',
  connection: 'notion', connectorRegistration: 'notion', connectorRevision: 'original',
  declarationSourceCid: cid('b'), installationRequestId: 'publication-original',
  principal: 'actor', runtimeBundleCid: cid('c'), siteGeneration: 4, siteKey: 'site'});
const requestData = () => ({metadataOccurrenceId: 'database-original', operation: 'notion:databases:retrieve',
  requestBodyCid: 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  requestMethod: 'GET', requestPath: '/v1/databases/original', resourceOrigin: 'https://api.notion.com'});
const legacyScope = () => ({issuerAuthority: 'issuer', principal: 'actor', namespaceId: 'namespace',
  environment: 'fixture', siteKey: 'site', siteGeneration: 4, runtimeBundleCid: cid('c'),
  connectorRegistration: 'notion', connectorRevision: 'original', resourceOrigin: 'https://api.notion.com',
  operation: 'records:read', runInvocationCid: cid('d'), taskAttempt: 1, dispatchRequestCid: cid('e'),
  expiresUnixMilliseconds: 1000n, maxUses: 2});

function fixture(t, options = {}) {
  const base = join(process.cwd(), '_build', 'metadata-journal-fixtures');
  mkdirSync(base, {recursive: true, mode: 0o700});
  const root = mkdtempSync(join(base, 'original-'));
  const keys = generateKeyPairSync('ed25519');
  // Original disposable fixture evidence remains private and retained in place.
  writeFileSync(join(root, 'fixture-private.pem'), keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  writeFileSync(join(root, 'fixture-public.pem'), keys.publicKey.export({type: 'spki', format: 'pem'}), {mode: 0o600});
  const view = createInstallationPreparationMetadata(moon);
  const subject = view.prepareSubject(subjectData()), scope = view.prepareScope(subject, requestData());
  const control = view.forSubject(subject), journals = [];
  const authorities = new Map([['issuer', new Map([['fixture-key', keys.publicKey]])]]);
  const open = () => {
    const journal = openSqliteCredentialJournal(root, {credentialAuthorities: authorities,
      maxGrants: 10, maxUses: 20, maxGrantBytes: 32768, maxUseBytes: 4096, ...options});
    journals.push(journal); return journal;
  };
  const grantFor = (scope, maxUses = 2) => control.prepare({issuerAuthority: 'issuer', scope,
    expiresUnixMilliseconds: 1000n, maxUses});
  const sign = (grant, owner = control) => signRemoteCredentialGrant(grant, owner,
    {keyId: 'fixture-key', privateKey: keys.privateKey});
  t.after(() => {
    for (const journal of journals.reverse()) journal.close();
    console.error(`Original metadata Journal fixture retained: ${root}`);
  });
  return {root, view, subject, scope, control, open, grantFor, sign};
}

const hostFailure = error => error?.code === 'MoonBitHostFailure';

test('metadata original signed grant enters the existing Journal with the same original claim', t => {
  const f = fixture(t), journal = f.open(), grant = f.grantFor(f.scope);
  const admitted = journal.acceptGrant(f.sign(grant), f.control);
  assert.equal(f.control.json(admitted), f.control.json(grant));
  const claimed = journal.claim(f.control.identity(grant), 'database-use', 1n, f.scope, f.control);
  assert.equal(claimed.replayed, false);
  assert.equal(claimed.record.outcome, 'claimed');
  assert.equal(f.control.identity(claimed.grant), claimed.record.grantCid);
  assert.equal(f.control.useProjection(claimed.use)[1], f.control.identity(claimed.grant));
  assert.equal(journal.authorize(claimed.use, 2n, f.scope, f.control).useCid, claimed.record.useCid);
});

test('database and selected schema keep separate signed original operation occurrences', t => {
  const f = fixture(t), journal = f.open();
  const schema = f.view.prepareScope(f.subject, {...requestData(), metadataOccurrenceId: 'schema-original',
    operation: 'notion:data-sources:retrieve', requestPath: '/v1/data_sources/selected-original'});
  const first = f.grantFor(f.scope), second = f.grantFor(schema);
  assert.notEqual(f.control.identity(first), f.control.identity(second));
  journal.acceptGrant(f.sign(first), f.control); journal.acceptGrant(f.sign(second), f.control);
  assert.throws(() => journal.claim(f.control.identity(first), 'wrong-schema', 1n, schema, f.control), hostFailure);
  assert.throws(() => journal.claim(f.control.identity(second), 'wrong-database', 1n, f.scope, f.control), hostFailure);
  assert.deepEqual(journal.recover(), []);
  const databaseUse = journal.claim(f.control.identity(first), 'database', 1n, f.scope, f.control);
  const schemaUse = journal.claim(f.control.identity(second), 'schema', 1n, schema, f.control);
  assert.equal(journal.recover().length, 2);
  assert.notEqual(databaseUse.record.useCid, schemaUse.record.useCid);
});

test('metadata durable Unknown and same-use replay preserve ordinal and capacity after reopen', t => {
  const f = fixture(t), grant = f.grantFor(f.scope, 1), first = f.open();
  first.acceptGrant(f.sign(grant), f.control);
  const claimed = first.claim(f.control.identity(grant), 'original-use', 1n, f.scope, f.control);
  first.finish(claimed.record.useCid, 'unknown'); first.close();
  const reopened = f.open(), replay = reopened.claim(f.control.identity(grant), 'original-use', 2n, f.scope, f.control);
  assert.equal(replay.replayed, true);
  assert.deepEqual(replay.record, {...claimed.record, outcome: 'unknown'});
  assert.equal(reopened.recover().length, 1);
  assert.throws(() => reopened.claim(f.control.identity(grant), 'replacement-use', 2n, f.scope, f.control), hostFailure);
  assert.equal(reopened.inspect(claimed.record.useCid).outcome, 'unknown');
});

test('metadata copied scope foreign Subject and changed request cannot claim or authorize', t => {
  const f = fixture(t), grant = f.grantFor(f.scope), journal = f.open();
  journal.acceptGrant(f.sign(grant), f.control);
  const copy = f.view.admitSubject(f.view.subjectWire(f.subject), f.view.subjectCid(f.subject));
  const foreign = f.view.prepareScope(copy, requestData());
  for (const scope of [{...f.scope}, requestData(), foreign]) {
    assert.throws(() => journal.claim(f.control.identity(grant), 'copy', 1n, scope, f.control),
      {code: 'ForeignInstallationPreparationMetadata'});
  }
  for (const change of [{operation: 'notion:properties:read'}, {metadataOccurrenceId: 'other'},
    {requestPath: '/v1/databases/other'}, {resourceOrigin: 'https://other.example'}]) {
    const changed = f.view.prepareScope(f.subject, {...requestData(), ...change});
    assert.throws(() => journal.claim(f.control.identity(grant), 'changed', 1n, changed, f.control), hostFailure);
  }
  assert.deepEqual(journal.recover(), []);
  const use = journal.claim(f.control.identity(grant), 'original', 1n, f.scope, f.control);
  assert.throws(() => journal.authorize(use.use, 2n, foreign, f.control), {code: 'ForeignInstallationPreparationMetadata'});
  assert.equal(journal.inspect(use.record.useCid).outcome, 'claimed');
});

test('Run and metadata signature bodies and control purposes remain disjoint', t => {
  const f = fixture(t), journal = f.open(), grant = f.grantFor(f.scope);
  const old = legacy.prepare(legacyScope());
  assert.equal(legacy.projection(old).length, 17);
  assert.throws(() => journal.acceptGrant(f.sign(grant), legacy), hostFailure);
  assert.throws(() => journal.acceptGrant(f.sign(old, legacy), f.control), hostFailure);
  journal.acceptGrant(f.sign(old, legacy), legacy);
  const use = journal.claim(legacy.identity(old), 'legacy-original', 1n, legacyScope(), legacy);
  assert.equal(legacy.useProjection(use.use).length, 4);
  assert.equal(journal.authorize(use.use, 2n, legacyScope(), legacy).outcome, 'claimed');
  assert.equal(journal.recover().length, 1);
});

test('metadata named projection rejects old arrays missing and substituted original members', t => {
  const f = fixture(t), journal = f.open(), grant = f.grantFor(f.scope);
  for (const projection of [() => Array(17).fill('x'), original => {const value = {...original}; delete value.scope; return Object.freeze(value);},
    original => Object.freeze({...original, subject: {...original.subject}})]) {
    const control = Object.freeze({...f.control, projection(value) {return projection(f.control.projection(value));}});
    assert.throws(() => journal.acceptGrant(f.sign(grant), control), {code: 'InvalidRemoteCredentialGrant'});
  }
  const foreignScope = Object.freeze({...f.scope});
  const control = Object.freeze({...f.control, projection(value) {return Object.freeze({...f.control.projection(value), scope: foreignScope});}});
  assert.throws(() => journal.acceptGrant(f.sign(grant), control), {code: 'ForeignInstallationPreparationMetadata'});
  assert.deepEqual(journal.recover(), []);
  journal.acceptGrant(f.sign(grant), f.control);
});

test('metadata expiry revocation and view retirement do not issue replacement uses', t => {
  const f = fixture(t), journal = f.open(), grant = f.grantFor(f.scope);
  journal.acceptGrant(f.sign(grant), f.control);
  assert.throws(() => journal.checkGrant(f.control.identity(grant), 1000n, f.scope, f.control), hostFailure);
  journal.revoke(f.control.identity(grant));
  assert.throws(() => journal.claim(f.control.identity(grant), 'revoked', 1n, f.scope, f.control), hostFailure);
  assert.deepEqual(journal.recover(), []);
  const envelope = f.sign(grant);
  f.view.retireMetadataView();
  assert.throws(() => journal.acceptGrant(envelope, f.control), {code: 'InstallationPreparationMetadataRetired'});
});

test('metadata original COMMIT uncertainty is retained without repeating signed acceptance', t => {
  const f = fixture(t), journal = f.open(), grant = f.grantFor(f.scope);
  const original = DatabaseSync.prototype.exec, cause = new Error('OriginalMetadataCommitReplyLost');
  let commits = 0;
  DatabaseSync.prototype.exec = function(sql) {
    const result = Reflect.apply(original, this, [sql]);
    if (sql === 'COMMIT' && ++commits === 1) throw cause;
    return result;
  };
  try {
    assert.throws(() => journal.acceptGrant(f.sign(grant), f.control), error => {
      assert.equal(error.code, 'RemoteCredentialJournalCommitOutcomeUnknown');
      assert.equal(error.cause, cause); assert.equal(error.outcome, 'unknown'); return true;
    });
  } finally {DatabaseSync.prototype.exec = original;}
  assert.equal(commits, 1);
  assert.equal(f.control.identity(journal.checkGrant(f.control.identity(grant), 1n, f.scope, f.control)), f.control.identity(grant));
  assert.deepEqual(journal.recover(), []);
});

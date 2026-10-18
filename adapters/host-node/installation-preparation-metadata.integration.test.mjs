// Actual selected Common runtime with explicit fixture DATA, not operational
// Host/Account/issuer/funding, a journal claim or physical metadata acquisition.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {generateKeyPairSync} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createInstallationPreparationMetadata} from '../host-common/installation-preparation-metadata.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteCredentialGrant, admitSignedRemoteCredentialGrant} from '../site-node/remote-credential-signature.mjs';

assert(process.env.ACTQL_METADATA_COMMON_RUNTIME, 'Actual matching runtime must be selected explicitly');
const moon = await import(pathToFileURL(process.env.ACTQL_METADATA_COMMON_RUNTIME));
const vectors = JSON.parse(readFileSync(new URL('../../spec/contracts/fixtures/installation-metadata-credential-vectors.json', import.meta.url)));
const cid = digit => 'sha256:' + digit.repeat(64);
const originalSubject = () => ({accountConfigurationCid: cid('a'), accountId: 'account',
  connection: 'notion', connectorRegistration: 'notion', connectorRevision: 'original',
  declarationSourceCid: cid('b'), installationRequestId: 'publication-1',
  principal: 'actor', runtimeBundleCid: cid('c'), siteGeneration: 1, siteKey: 'site'});
const originalRequest = () => ({metadataOccurrenceId: 'database-1', operation: 'notion:databases:retrieve',
  requestBodyCid: 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  requestMethod: 'GET', requestPath: '/v1/databases/original', resourceOrigin: 'https://api.notion.com'});
const original = (view = createInstallationPreparationMetadata(moon)) => {
  const subject = view.prepareSubject(originalSubject()), scope = view.prepareScope(subject, originalRequest());
  const control = view.forSubject(subject);
  const grant = control.prepare({issuerAuthority: 'issuer', scope, expiresUnixMilliseconds: 100n, maxUses: 1});
  return {view, subject, scope, control, grant};
};
const useRequest = scope => ({useId: 'use-1', trustedNowMilliseconds: 1n, usedCount: 0, revoked: false, scope});

test('metadata actual Common subject scope and grant preserve independent originals', () => {
  const {view, subject, scope, control, grant} = original(runtimeCore(moon).installationPreparationMetadata());
  assert.equal(view.subjectWire(subject), vectors.subject_wire);
  assert.equal(view.subjectCid(subject), vectors.subject_cid);
  assert.deepEqual(view.subjectFields(subject), originalSubject());
  assert.deepEqual(view.scopeFields(scope), originalRequest());
  assert.equal(control.json(grant), vectors.grant_wire);
  assert.equal(control.identity(grant), vectors.grant_cid);
  const projection = control.projection(grant);
  assert.equal(projection.subject, subject);
  assert.equal(projection.issuerAuthority, 'issuer');
  assert.equal(projection.expiresUnixMilliseconds, 100n);
  assert.equal(projection.maxUses, 1);
  assert.deepEqual(control.scopeFields(projection.scope), originalRequest());
  assert.equal(view.forSubject(subject), control);
  assert.equal(control.kind, 'installation-metadata');
  assert(Object.isFrozen(projection));
});

test('metadata actual Common use keeps exact original scope and finite ordinal', () => {
  const {control, scope, grant} = original();
  const use = control.prepareUse(grant, useRequest(scope));
  assert.equal(control.useIdentity(use), vectors.use_cid);
  assert.equal(control.useJson(use), vectors.use_wire);
  assert.deepEqual(control.useProjection(use), [vectors.use_cid, vectors.grant_cid, 'use-1', '1']);
  assert.equal(control.authorizeUse(use, {trustedNowMilliseconds: 99n, revoked: false, scope}), undefined);
  const restored = control.admitUse(grant, vectors.use_wire, vectors.use_cid);
  assert.equal(control.useJson(restored), vectors.use_wire);
});

test('metadata exact closed decode refuses foreign bytes identities and legacy Run bodies', () => {
  const {view, subject, control} = original();
  for (const body of [' ' + vectors.subject_wire, vectors.subject_wire.replace('declaration_source_cid', 'declaration_cid')]) {
    assert.throws(() => view.admitSubject(body, vectors.subject_cid), {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => view.admitSubject(vectors.subject_wire, cid('0')), {code: 'MoonBitHostFailure'});
  for (const body of [vectors.grant_wire + ' ', vectors.grant_wire.replace('installation_metadata', 'run')]) {
    assert.throws(() => control.admitJson(body, vectors.grant_cid), {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => runtimeCore(moon).remoteCredentialControl.admitJson(vectors.grant_wire, vectors.grant_cid), {code: 'MoonBitHostFailure'});
  const copy = view.admitSubject(vectors.subject_wire, vectors.subject_cid);
  assert.notEqual(copy, subject);
  assert.equal(view.subjectCid(copy), view.subjectCid(subject));
});

test('metadata generated original field set rejects comma-key inherited hidden symbol and getter substitutes', () => {
  const view = createInstallationPreparationMetadata(moon), fields = originalSubject();
  const comma = Object.assign(Object.create(fields), {['accountConfigurationCid,accountId']: cid('a')});
  const missing = {...fields}; delete missing.accountId;
  const hidden = {...fields}; Object.defineProperty(hidden, 'accountId', {value: 'account', enumerable: false});
  const accessor = {...fields}; Object.defineProperty(accessor, 'accountId', {get() {assert.fail('must not invoke getter');}, enumerable: true});
  for (const wrong of [comma, missing, hidden, accessor, {...fields, [Symbol('foreign')]: 'x'}]) {
    assert.throws(() => view.prepareSubject(wrong), {code: 'InvalidInstallationPreparationMetadata'});
  }
  for (const siteGeneration of [-1, 2147483648, 1.5, '1']) {
    assert.throws(() => view.prepareSubject({...fields, siteGeneration}), {code: 'InvalidInstallationPreparationMetadata'});
  }
});

test('metadata copied or foreign view tokens never substitute opaque originals', () => {
  const {view, subject, scope, control, grant} = original(), other = original();
  for (const copy of [{...subject}, Object.create(subject), null, vectors.subject_cid]) {
    assert.throws(() => view.subjectCid(copy), {code: 'ForeignInstallationPreparationMetadata'});
  }
  assert.throws(() => other.view.subjectCid(subject), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => other.control.identity(grant), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => control.prepareUse(grant, useRequest(other.scope)), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => view.prepareScope(other.subject, originalRequest()), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => view.scopeFields({...scope}), {code: 'ForeignInstallationPreparationMetadata'});
});

test('metadata equal admitted subject DATA cannot replace the original control scope', () => {
  const {view, subject, scope, control, grant} = original();
  const copied = view.admitSubject(view.subjectWire(subject), view.subjectCid(subject));
  const foreignScope = view.prepareScope(copied, originalRequest()), other = view.forSubject(copied);
  const otherGrant = other.admitJson(vectors.grant_wire, vectors.grant_cid);
  assert.equal(other.identity(otherGrant), control.identity(grant));
  assert.throws(() => control.prepareUse(grant, useRequest(foreignScope)), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => control.identity(otherGrant), {code: 'ForeignInstallationPreparationMetadata'});
  assert.throws(() => other.prepareUse(grant, useRequest(scope)), {code: 'ForeignInstallationPreparationMetadata'});
});

test('metadata current per-use operation occurrence path and origin stay with Common', () => {
  const {view, subject, control, grant} = original();
  for (const change of [{metadataOccurrenceId: 'schema-1'}, {operation: 'notion:data-sources:retrieve'},
    {operation: 'notion:data-sources:query'}, {requestPath: '/v1/databases/foreign'}, {resourceOrigin: 'https://foreign.example'}]) {
    const scope = view.prepareScope(subject, {...originalRequest(), ...change});
    assert.throws(() => control.prepareUse(grant, useRequest(scope)), {code: 'MoonBitHostFailure'});
  }
  for (const change of [{requestMethod: 'POST'}, {requestBodyCid: cid('a')}, {requestPath: '//foreign'}]) {
    assert.throws(() => view.prepareScope(subject, {...originalRequest(), ...change}), {code: 'MoonBitHostFailure'});
  }
});

test('metadata clock revocation quota and malformed use do not create new authority', () => {
  const {control, scope, grant} = original(), request = useRequest(scope);
  for (const change of [{trustedNowMilliseconds: 100n}, {revoked: true}, {usedCount: 1}]) {
    assert.throws(() => control.prepareUse(grant, {...request, ...change}), {code: 'MoonBitHostFailure'});
  }
  for (const change of [{trustedNowMilliseconds: -1n}, {trustedNowMilliseconds: 1},
    {trustedNowMilliseconds: 9223372036854775808n}, {revoked: 0}, {usedCount: -1}]) {
    assert.throws(() => control.prepareUse(grant, {...request, ...change}), {code: 'InvalidInstallationPreparationMetadata'});
  }
  const use = control.prepareUse(grant, request);
  assert.throws(() => control.authorizeUse(use, {trustedNowMilliseconds: 100n, revoked: false, scope}), {code: 'MoonBitHostFailure'});
  for (const body of [vectors.use_wire + ' ', vectors.use_wire.replace('"use_ordinal":1', '"use_ordinal":2')]) {
    assert.throws(() => control.admitUse(grant, body, vectors.use_cid), {code: 'MoonBitHostFailure'});
  }
});

test('metadata existing signature helper preserves exact typed Common preimage and original subject', () => {
  const {control, grant} = original(), {privateKey, publicKey} = generateKeyPairSync('ed25519');
  const preimage = Buffer.concat([Buffer.from('actql-remote-credential-grant-signature/0.1\0'),
    Buffer.from(vectors.grant_cid), Buffer.from('\0'), Buffer.from(vectors.grant_wire)]);
  assert.deepEqual(Buffer.from(control.signaturePreimage(grant)), preimage);
  const envelope = signRemoteCredentialGrant(grant, control, {keyId: 'fixture-key', privateKey});
  assert.equal(envelope.body, vectors.grant_wire);
  const accepted = admitSignedRemoteCredentialGrant(envelope,
    new Map([['issuer', new Map([['fixture-key', publicKey]])]]), control);
  assert.equal(control.identity(accepted), vectors.grant_cid);
  assert.throws(() => admitSignedRemoteCredentialGrant({...envelope, signature: 'A'.repeat(86)},
    new Map([['issuer', new Map([['fixture-key', publicKey]])]]), control), {code: 'RemoteCredentialSignatureRejected'});
});

test('metadata captured runtime callbacks keep their actual receiver after replacement', () => {
  const selected = Object.create(moon), originalPrepare = moon.clientInstallationPreparationSubjectPrepare;
  let reads = 0, calls = 0;
  Object.defineProperty(selected, 'clientInstallationPreparationSubjectPrepare', {configurable: true,
    get() {reads++; return function(...args) {assert.equal(this, selected); calls++; return Reflect.apply(originalPrepare, moon, args);};}});
  const view = createInstallationPreparationMetadata(selected);
  Object.defineProperty(selected, 'clientInstallationPreparationSubjectPrepare', {value() {assert.fail('replaced runtime');}});
  assert.equal(view.subjectCid(view.prepareSubject(originalSubject())), vectors.subject_cid);
  assert.equal(reads, 1); assert.equal(calls, 1);
});

test('metadata retired view refuses escaped controls without retiring another original', () => {
  const {view, subject, scope, control, grant} = original(), other = original();
  const use = control.prepareUse(grant, useRequest(scope));
  assert.equal(view.retireMetadataView(), true); assert.equal(view.retireMetadataView(), false);
  for (const operation of [() => view.subjectCid(subject), () => control.identity(grant),
    () => control.useIdentity(use), () => control.prepareUse(grant, useRequest(scope)),
    () => control.admitJson(vectors.grant_wire, vectors.grant_cid), () => view.forSubject(subject)]) {
    assert.throws(operation, {code: 'InstallationPreparationMetadataRetired'});
  }
  assert.equal(other.control.identity(other.grant), vectors.grant_cid);
});

test('metadata missing runtime and abnormal raised results refuse without a fallback', () => {
  for (const selected of [undefined, null, {}]) {
    assert.throws(() => createInstallationPreparationMetadata(selected), {code: 'InstallationPreparationRuntimeUnavailable'});
  }
  const selected = Object.create(moon);
  Object.defineProperty(selected, 'clientInstallationPreparationSubjectPrepare', {value() {return undefined;}});
  assert.throws(() => createInstallationPreparationMetadata(selected).prepareSubject(originalSubject()), {code: 'InvalidHostRuntimeResult'});
});

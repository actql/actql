import assert from 'node:assert/strict';
import {generateKeyPairSync, createPrivateKey} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import test from 'node:test';

// Exercise the complete existing Site constructor with explicit metadata,
// Journal and Source-reader ports; no Common/Account/physical I/O is selected.
const source = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
const start = source.indexOf('export async function openRowSourceCredentialSite(');
const end = source.indexOf('\n// The installed source adapter of one row declaration', start);
assert.ok(start >= 0 && end > start);
const body = source.slice(start, end).replace(/^export /u, '');
const key = generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'});
const fail = code => {throw Object.assign(new Error(code), {code});};
const options = configurationReader => ({
  profile: {credentialPrivateKeyPath: '/original/issuer.pem', credentialAuthorityId: 'authority',
    credentialKeyId: 'key', journalRoot: '/original/journal', resourceOrigin: 'https://original.test',
    namespaceId: 'namespace', environment: 'fixture', siteKey: 'site', siteGeneration: 1},
  principalId: 'principal', authorization: {}, connection: 'fixture:records',
  connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1', runtimeBundleCid: 'runtime',
  commonMoon: {}, resolveSecret() {assert.fail('No secret resolution');},
  installationMetadata: {}, configurationReader,
});

function constructor({beforeMetadata = async () => {}, readNative = async () => key} = {}) {
  let nativeReads = 0, attached = 0;
  const site = Object.freeze({original: true});
  const metadata = {privateKeyPath: '/original/issuer.pem', maxIssuerKeyBytes: 4096,
    assertInitializingCurrent() {}, attach(custody) {
      assert.equal(custody.privateKey.asymmetricKeyType, 'ed25519');
      attached++;
      return {site};
    }};
  const open = new Function('nodeTypes', 'isAbsolute', 'text', 'fail',
    'ownCredentialSecretPresentation', 'ownCredentialAcquisitionLimits',
    'prepareInstallationMetadataSite', 'readBoundedConfigurationText', 'createPrivateKey',
    'retainInstalledHostInitializationFailure', 'openRowSourceCredentialCustody',
    'openSqliteCredentialJournal', 'openHttpsCredentialBinding',
    `${body}\nreturn openRowSourceCredentialSite;`)(
    nodeTypes, isAbsolute, value => typeof value === 'string' && value.length > 0, fail,
    () => undefined, () => undefined, async () => {await beforeMetadata(); return metadata;},
    async (...args) => {nativeReads++; return readNative(...args);}, createPrivateKey,
    async cause => cause, value => value, () => assert.fail('No Journal open'),
    () => assert.fail('No binding open'));
  return {open, site, counts: () => ({nativeReads, attached})};
}

test('metadata issuer uses the same configuration read and receiver captured before the metadata await', async () => {
  let reads = 0;
  const reader = {async readText(path, bounds) {
    assert.equal(this, reader);
    assert.equal(path, '/original/issuer.pem');
    assert.deepEqual(bounds, {maxBytes: 4096});
    reads++;
    return key;
  }};
  const original = reader.readText;
  const f = constructor({beforeMetadata() {
    reader.readText = () => assert.fail('A replacement method must not receive the original read');
  }});
  assert.equal(await f.open(options(reader)), f.site);
  assert.equal(reads, 1);
  assert.deepEqual(f.counts(), {nativeReads: 0, attached: 1});
  assert.notEqual(reader.readText, original);
});

test('metadata configuration refusal preserves the original pending cleanup and opens no custody', async () => {
  const cleanupHandle = Object.freeze({status: () => ({pending: true})});
  const original = Object.assign(new Error('OriginalConfigurationPending'), {cleanupHandle});
  const f = constructor();
  const reader = {readText() {assert.equal(this, reader); throw original;}};
  await assert.rejects(f.open(options(reader)), cause => cause === original && cause.cleanupHandle === cleanupHandle);
  assert.deepEqual(f.counts(), {nativeReads: 0, attached: 0});
});

test('metadata refuses a supplied invalid reader before its await and retains the absent-reader path', async () => {
  for (const reader of [{}, Object.create({readText() {}}), {get readText() {
    assert.fail('Reader accessor must not run');
  }}, {readText: 1}, new Proxy({}, {getOwnPropertyDescriptor() {
    assert.fail('Proxy inspection must not run');
  }})]) {
    let metadataCalls = 0;
    const f = constructor({beforeMetadata() {metadataCalls++;}});
    await assert.rejects(f.open(options(reader)), {code: 'InvalidRowSourceCredentialSite'});
    assert.equal(metadataCalls, 0);
    assert.deepEqual(f.counts(), {nativeReads: 0, attached: 0});
  }
  const f = constructor({readNative(path, bounds) {
    assert.equal(path, '/original/issuer.pem');
    assert.deepEqual(bounds, {maxBytes: 4096});
    return key;
  }});
  assert.equal(await f.open(options(undefined)), f.site);
  assert.deepEqual(f.counts(), {nativeReads: 1, attached: 1});
});

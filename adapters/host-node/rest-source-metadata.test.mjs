import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRestSourceMetadata, REST_SOURCE_SITE_VERSION} from './rest-source-metadata.mjs';

function fixture() {
  const sources = [{resource: 'records', resource_kind: 'record',
    fields: [{name: 'id', type: 'string', nullable: false}],
    read: {method: 'GET', path: '/records'}, pagination: {kind: 'none', items: []},
    limits: {maxPageRows: 2, maxPageBytes: 1024, maxPages: 1, maxRows: 2,
      maxNodes: 64, maxDepth: 8, maxCursorBytes: 32}}];
  const definition = {registration: 'acme', revision: 'acme/0.1',
    profileVersion: 'actql-installed-acme-rest-source/0.1', origin: 'https://api.acme.invalid',
    auth: {kind: 'bearer'}, sources,
    authoredViewsWire: JSON.stringify({views: sources.map(({resource, resource_kind, fields}) =>
      ({resource, resource_kind, fields}))})};
  const profile = {version: definition.profileVersion, connectorId: 'acme-one',
    siteProfilePath: '/UNOPENED/rest-site.json', accountConfigurationWire: '{}'};
  const site = {version: REST_SOURCE_SITE_VERSION, apiOrigin: definition.origin,
    credentialAuthorityId: 'authority', credentialKeyId: 'key',
    credentialPrivateKeyPath: '/UNOPENED/credential.pem', environment: 'test',
    journalRoot: '/UNOPENED/journal', namespaceId: 'fixture', siteGeneration: 0, siteKey: 'site',
    caPath: '/UNOPENED/original-ca.pem'};
  return {definition, profile, site};
}

// Explicit original reader ports only: no physical read, Source funding,
// Credential Site or normal Host acceptance is established by these cases.
test('REST metadata retains the same Host reader methods and exact original CA without an author bound', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition), calls = [];
  const ca = Buffer.from('-----BEGIN CERTIFICATE-----\r\nauthored-opaque-CA\r\n-----END CERTIFICATE-----\r\n');
  const reader = {
    async readJson(path) {
      assert.strictEqual(this, reader);calls.push(['json', path]);
      reader.readOriginalBytes = () => assert.fail('Captured before original JSON await');
      return f.site;
    },
    readText() {assert.fail('Configured CA uses the actual-FD reader, not a caller bound');},
    readOriginalBytes(path) {
      assert.strictEqual(this, reader);assert.equal(arguments.length, 1);
      calls.push(['bytes', path]);return ca;
    },
  };
  const input = await metadata.readInputs(f.profile, {configurationReader: reader});
  assert.equal(input.ca, ca);assert.deepEqual(input.site, f.site);
  assert.deepEqual(calls, [['json', f.profile.siteProfilePath], ['bytes', f.site.caPath]]);
  const original = metadata.authoredDeclarationWire();f.definition.sources[0].fields[0].name = 'changed';
  assert.equal(metadata.authoredDeclarationWire(), original);
  assert.equal(Object.hasOwn(metadata, 'restore'), false);assert.equal(Object.hasOwn(metadata, 'publish'), false);
});

test('REST identity binds changed CA bytes and path through the original Host reader', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  let ca = Buffer.from('authored-first-CA'), site = f.site;
  const reader = {readJson: async () => site,
    readText() {assert.fail('No bounded CA read');}, readOriginalBytes: async () => ca};
  const parts = () => metadata.identityParts(f.profile, f.profile, undefined, undefined,
    {configurationReader: reader});
  const expected = () => 'sha256:' + createHash('sha256').update(JSON.stringify([
    JSON.stringify(f.definition), f.profile.version, f.profile.connectorId,
    f.profile.siteProfilePath, f.profile.accountConfigurationWire,
    site.version, site.apiOrigin, site.credentialAuthorityId, site.credentialKeyId,
    site.credentialPrivateKeyPath, site.environment, site.journalRoot, site.namespaceId,
    site.siteGeneration, site.siteKey, 'tls-ca', site.caPath,
    'sha256:' + createHash('sha256').update(ca).digest('hex'),
  ])).digest('hex');
  const first = await parts();assert.deepEqual(first[3], {originalStringsCid: expected()});
  ca = Buffer.from('authored-second-CA');const changedBytes = await parts();
  assert.equal(changedBytes[3].originalStringsCid, expected());
  assert.notEqual(changedBytes[3].originalStringsCid, first[3].originalStringsCid);
  site = {...site, caPath: '/UNOPENED/other-ca.pem'};
  const changedPath = await parts();assert.equal(changedPath[3].originalStringsCid, expected());
  assert.notEqual(changedPath[3].originalStringsCid, changedBytes[3].originalStringsCid);
});

test('REST normal metadata has no standalone reader or declaration fallback', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  await assert.rejects(metadata.readInputs(f.profile), {code: 'RestSourceConfigurationReaderUnavailable'});
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson: async () => f.site, readText() {assert.fail('No bounded CA read');},
    readOriginalBytes: async () => 'not-original-bytes',
  }}), {code: 'InvalidInstalledRestSourceSite'});
  assert.throws(() => createRestSourceMetadata({...f.definition, authoredViewsWire: undefined}),
    {code: 'InvalidRestSourceInstallationDefinition'});
});

test('REST configured CA cannot disappear into default trust when its original reader returns no bytes', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson: async () => f.site, readText() {assert.fail('No bounded CA read');},
    readOriginalBytes: async () => undefined,
  }}), {code: 'InvalidInstalledRestSourceSite'});
});

test('REST configured CA refuses a missing actual-FD byte reader without a text fallback', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  let jsonReads = 0, boundedReads = 0;
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson() {jsonReads++;return f.site;},
    readText() {boundedReads++;return 'must not supply an implicit bound';},
  }}), {code: 'RestSourceTlsAuthorityPolicyUnavailable'});
  assert.equal(jsonReads, 1);assert.equal(boundedReads, 0);
});

test('REST CA uses only the captured actual-FD byte method and original receiver', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition), calls = [];
  const ca = Buffer.from([0xef, 0xbb, 0xbf, 13, 10, 0, 0xff]);
  const reader = {
    async readJson(path) {
      assert.strictEqual(this, reader);calls.push(['json', path]);
      reader.readOriginalBytes = () => assert.fail('Original method must be captured before JSON awaits');
      return f.site;
    },
    readText() {assert.fail('Bounded readText must not be used without a declared bound');},
    readOriginalText() {assert.fail('No CA text projection');},
    readOriginalBytes(path) {
      assert.strictEqual(this, reader);assert.equal(arguments.length, 1);
      calls.push(['original', path]);return ca;
    },
  };
  const input = await metadata.readInputs(f.profile, {configurationReader: reader});
  assert.equal(input.ca, ca);
  assert.deepEqual(calls, [['json', f.profile.siteProfilePath], ['original', f.site.caPath]]);
});

import assert from 'node:assert/strict';
import test from 'node:test';
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
  const ca = '-----BEGIN CERTIFICATE-----\r\nauthored-opaque-CA\r\n-----END CERTIFICATE-----\r\n';
  const reader = {
    async readJson(path) {
      assert.strictEqual(this, reader);calls.push(['json', path]);
      reader.readText = () => assert.fail('Captured before original JSON await');
      return f.site;
    },
    readText(path) {
      assert.strictEqual(this, reader);assert.equal(arguments.length, 1);
      calls.push(['text', path]);return ca;
    },
  };
  const input = await metadata.readInputs(f.profile, {configurationReader: reader});
  assert.equal(input.ca, ca);assert.deepEqual(input.site, f.site);
  assert.deepEqual(calls, [['json', f.profile.siteProfilePath], ['text', f.site.caPath]]);
  const original = metadata.authoredDeclarationWire();f.definition.sources[0].fields[0].name = 'changed';
  assert.equal(metadata.authoredDeclarationWire(), original);
  assert.equal(Object.hasOwn(metadata, 'restore'), false);assert.equal(Object.hasOwn(metadata, 'publish'), false);
});

test('REST identity binds changed CA bytes and path through the original Host reader', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  let ca = 'authored-first-CA', site = f.site;
  const reader = {readJson: async () => site, readText: async () => ca};
  const parts = () => metadata.identityParts(f.profile, f.profile, undefined, undefined,
    {configurationReader: reader});
  const first = await parts();assert.equal(first[3].ca, ca);
  ca = 'authored-second-CA';const changedBytes = await parts();
  assert.notEqual(changedBytes[3].originalStringsCid, first[3].originalStringsCid);
  site = {...site, caPath: '/UNOPENED/other-ca.pem'};
  assert.notEqual((await parts())[3].originalStringsCid, changedBytes[3].originalStringsCid);
});

test('REST normal metadata has no standalone reader or declaration fallback', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  await assert.rejects(metadata.readInputs(f.profile), {code: 'RestSourceConfigurationReaderUnavailable'});
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson: async () => f.site, readText: async () => Buffer.from('not-text'),
  }}), {code: 'InvalidInstalledRestSourceAuthority'});
  assert.throws(() => createRestSourceMetadata({...f.definition, authoredViewsWire: undefined}),
    {code: 'InvalidRestSourceInstallationDefinition'});
});

test('REST configured CA cannot disappear into default trust when its original reader returns no text', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson: async () => f.site, readText: async () => undefined,
  }}), {code: 'InvalidInstalledRestSourceAuthority'});
});

test('REST configuration refuses a missing actual-FD text reader before any JSON read', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition);
  let jsonReads = 0, boundedReads = 0;
  await assert.rejects(metadata.readInputs(f.profile, {configurationReader: {
    readJson() {jsonReads++;return f.site;},
    readText() {boundedReads++;return 'must not supply an implicit bound';},
  }}), {code: 'RestSourceConfigurationReaderUnavailable'});
  assert.equal(jsonReads, 0);assert.equal(boundedReads, 0);
});

test('REST CA uses only the captured actual-FD text method and original receiver', async () => {
  const f = fixture(), metadata = createRestSourceMetadata(f.definition), calls = [];
  const ca = 'opaque-original-CA\r\n';
  const reader = {
    async readJson(path) {
      assert.strictEqual(this, reader);calls.push(['json', path]);
      reader.readOriginalText = () => assert.fail('Original method must be captured before JSON awaits');
      return f.site;
    },
    readText() {assert.fail('Bounded readText must not be used without a declared bound');},
    readOriginalText(path) {
      assert.strictEqual(this, reader);assert.equal(arguments.length, 1);
      calls.push(['original', path]);return ca;
    },
  };
  const input = await metadata.readInputs(f.profile, {configurationReader: reader});
  assert.equal(input.ca, ca);
  assert.deepEqual(calls, [['json', f.profile.siteProfilePath], ['original', f.site.caPath]]);
});

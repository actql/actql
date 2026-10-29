import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createRestSourceMetadata, REST_SOURCE_SITE_VERSION} from './rest-source-metadata.mjs';

const definition = () => ({registration: 'acme', revision: 'acme/0.1',
  profileVersion: 'actql-installed-acme-rest-source/0.1', origin: 'https://api.acme.invalid',
  auth: {kind: 'bearer'}, sources: [{resource: 'customers', resource_kind: 'record',
    fields: [{name: 'id', type: 'string', nullable: false},
      {name: 'e\u0301', type: 'decimal', precision: 38, scale: 10, nullable: true}],
    read: {method: 'GET', path: '/customers'}, pagination: {kind: 'none', items: []},
    limits: {maxPageRows: 2, maxPageBytes: 1024, maxPages: 1, maxRows: 2,
      maxNodes: 64, maxDepth: 8, maxCursorBytes: 32}}]});
const profile = path => ({version: 'actql-installed-acme-rest-source/0.1', connectorId: 'acme-one',
  siteProfilePath: path, accountConfigurationWire: '{"authored":"e\u0301"}'});
const site = () => ({version: REST_SOURCE_SITE_VERSION, apiOrigin: 'https://api.acme.invalid',
  credentialAuthorityId: 'authority', credentialKeyId: 'key',
  credentialPrivateKeyPath: '/UNOPENED/credential-key.pem', environment: 'e\u0301',
  journalRoot: '/UNOPENED/journal', namespaceId: 'namespace', siteGeneration: 0, siteKey: 'site'});

// The declaration methods below are explicit scalar ports, not a compiled
// Common/type-admission claim. They prove original arguments and receiver,
// complete issued DATA forwarding, and unchanged typed refusal propagation.
function runtime(expectedWire) {
  const declaration = Object.freeze({}), calls = [];
  const declared = {catalog_cid: 'original-catalog-cid', catalog: 'original-catalog-body',
    contracts: ['contract-one', 'contract-two'], view_bodies: ['original-source-view'],
    manifest_entry: 'original-manifest-entry'};
  const moon = {
    clientProgramRowSourceRestoreDeclaration(...args) {
      assert.strictEqual(this, moon); assert.equal(args[3], expectedWire);
      assert.equal(args[4], undefined); calls.push(args); return {$tag: 1, _0: declaration};
    },
    clientProgramRowSourceDeclarationJson(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, declaration); return JSON.stringify(declared);
    },
  };
  return {moon, declaration, declared, calls};
}

test('REST metadata passes unchanged typed field DATA to the original Common declaration methods', () => {
  const input = definition(), metadata = createRestSourceMetadata(input);
  const expectedWire = JSON.stringify({views: [{resource: 'customers', resource_kind: 'record',
    fields: input.sources[0].fields}]});
  input.sources[0].fields[0].name = 'changed-after-capture';
  const f = runtime(expectedWire), selected = metadata.restore(profile('/UNOPENED/site.json'), f.moon);
  assert.strictEqual(selected.declaration, f.declaration);
  assert.deepEqual(selected.declared, f.declared);
  assert.deepEqual(f.calls[0].slice(0, 3), ['acme-one', 'acme', 'acme/0.1']);
  assert.equal(Object.isFrozen(metadata.definition.sources[0].fields[0]), true);
  const originalIssue = Object.freeze({kind: 'UnsupportedType', type: 'decimal'});
  f.moon.clientProgramRowSourceRestoreDeclaration = () => ({$tag: 0, _0: originalIssue});
  assert.throws(() => metadata.restore(profile('/UNOPENED/site.json'), f.moon), cause =>
    cause.code === 'MoonBitHostFailure' && cause.cause === originalIssue);
  assert.throws(() => metadata.restore(profile('/UNOPENED/site.json'), {}),
    {code: 'RestSourceDeclarationRuntimeUnavailable'});
});

test('REST identity pins fresh real Site and exact strings without opening a credential or provider', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-rest-metadata-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'site.json'), installed = profile(path), metadata = createRestSourceMetadata(definition());
  await writeFile(path, JSON.stringify(site()));
  const first = await metadata.identityParts(installed, installed);
  assert.deepEqual(first[0].accountConfigurationWire, {authored: 'e\u0301'});
  assert.equal(first[1].credentialPrivateKeyPath, '/UNOPENED/credential-key.pem');
  assert.equal(first[1].siteGeneration, 0);
  await writeFile(path, JSON.stringify({...site(), siteGeneration: 1}));
  const changed = await metadata.identityParts(installed, installed);
  assert.notEqual(changed[3].originalStringsCid, first[3].originalStringsCid);
  await writeFile(path, JSON.stringify({...site(), environment: '\u00e9'}));
  const normalizedAlias = await metadata.identityParts(installed, installed);
  assert.notEqual(normalizedAlias[3].originalStringsCid, first[3].originalStringsCid);
  const second = {...installed, connectorId: 'acme-two'};
  assert.notEqual((await metadata.identityParts(second, second))[3].originalStringsCid,
    normalizedAlias[3].originalStringsCid);
});

test('REST metadata refuses changed origin and unavailable CA policy without borrowing another bound', async () => {
  const metadata = createRestSourceMetadata(definition()), installed = profile('/UNOPENED/site.json');
  let observed = 0;
  const accessor = {...installed};
  Object.defineProperty(accessor, 'connectorId', {get() {observed++;return 'acme-one';}});
  assert.throws(() => metadata.checkProfile(accessor), {code: 'InvalidInstalledRestSourceProfile'});
  assert.equal(observed, 0);
  for (const key of ['limits', 'capacity', 'credential', 'cleanup']) {
    assert.throws(() => metadata.checkProfile({...installed, [key]: {}}), {code: 'InvalidInstalledRestSourceProfile'});
  }
  const run = value => metadata.readInputs(installed, {configurationReader: {
    readJson() {return value;}, readText() {assert.fail('No unqualified CA read');},
  }});
  await assert.rejects(run({...site(), apiOrigin: 'https://other.invalid'}), {code: 'InvalidInstalledRestSourceSite'});
  await assert.rejects(run({...site(), caPath: '/UNOPENED/ca.pem'}), {code: 'RestSourceTlsAuthorityPolicyUnavailable'});
});

test('REST static publication reports every original issued body without claiming a storage write', async () => {
  const input = definition(), metadata = createRestSourceMetadata(input);
  const expectedWire = JSON.stringify({views: [{resource: 'customers', resource_kind: 'record',
    fields: input.sources[0].fields}]});
  const f = runtime(expectedWire), reader = {reads: 0,
    readJson(path) {assert.strictEqual(this, reader);assert.equal(path, '/UNOPENED/site.json');this.reads++;return site();},
    readText() {assert.fail('No provider or CA operation');}};
  const output = await metadata.publish(profile('/UNOPENED/site.json'), {moon: f.moon, configurationReader: reader});
  assert.equal(reader.reads, 1);assert.equal(f.calls.length, 1);
  assert.equal(output.catalogCid, f.declared.catalog_cid);assert.equal(output.catalog, f.declared.catalog);
  assert.deepEqual(output.contracts, f.declared.contracts);assert.deepEqual(output.sourceViews, f.declared.view_bodies);
  assert.equal(output.manifestEntry, f.declared.manifest_entry);assert.equal(output.connectorId, 'acme-one');
  assert.equal(Object.isFrozen(output.contracts), true);
});

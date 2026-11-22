// Actual standard generated loader, Common initialization Ledger, native
// Mapping producer and physical Site. Initialization sends no provider call.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as originalMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createInstalledLoaderParent, installedFailureCode} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {loadInstalledEffect, installedEffectIdentity} from '../../../host-node/installed-effect.mjs';
import {installedSourceConfigurationReader, retireInstalledSourceInitialization} from '../../../host-node/installed-host-services.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {form} from './kintone-update-form.fixture.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const base = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');

async function fixture(t, {field = 'Subject', key, unique = true} = {}) {
  const dependentCleanup = [];
  let parent, secretReads = 0;
  // The Account gate admits its configuration in this same module namespace.
  const moon = originalMoon;
  const directory = new URL('../../../../_build/kintone-effect-initialization/', import.meta.url);
  await mkdir(directory, {recursive: true});
  const root = await mkdtemp(join(directory.pathname, 'fresh-'));
  t.after(async () => {
    const failures = [];
    try {await parent?.close();} catch (cause) {failures.push(cause);}
    for (const close of dependentCleanup.toReversed()) try {await close();} catch (cause) {failures.push(cause);}
    t.diagnostic(`Retained original kintone initialization: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'KintoneInitializationCleanupPending');
  });
  const tls = await openHttpsExchangeFixture({after: close => dependentCleanup.push(close)});
  const keyPath = join(root, 'credential.key');
  await writeFile(keyPath, generateKeyPairSync('ed25519').privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const sitePath = join(root, 'site.json'), metadataPath = join(root, 'metadata.json'), sourcePath = join(root, 'source.json');
  const keyed = key !== undefined;
  const originalForm = keyed ? {...form, properties: {
    Subject: {...form.properties.Subject, required: true},
    Tags: {...form.properties.Tags, required: false},
    Computed: {...form.properties.Computed, required: false},
    CustomerKey: {code: 'CustomerKey', type: 'SINGLE_LINE_TEXT', expression: '', unique, required: true},
  }} : form;
  await writeFile(sitePath, JSON.stringify({version: 'actql-installed-kintone-site/0.1', apiOrigin: tls.origin,
    credentialAuthorityId: 'kintone-initialization', credentialKeyId: 'key', credentialPrivateKeyPath: keyPath,
    environment: 'test', journalRoot: join(root, 'credential-journal'), namespaceId: 'kintone-initialization',
    siteGeneration: 1, siteKey: 'kintone-initialization', tokenEnvironment: 'ACTQL_KINTONE_COMPONENT_TOKEN', caPath: tls.caPath}));
  await writeFile(metadataPath, JSON.stringify({version: 'actql-kintone-record-metadata/0.1', connectorId: 'kintone',
    appId: '12', apiOrigin: tls.origin, formBody: Buffer.from(JSON.stringify(originalForm)).toString('base64')}));
  const accountConfigurationWire = canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'kintone-component',
    entries: [{entry_id: 'records', outcome: 'allow', principal: {all: true}, connection: {any_of: ['kintone:kintone']},
      resource: {any_of: ['form', 'inquiries']}, operation: {any_of: keyed ? ['read', 'upsert'] : ['read', 'update']}, exclusions: []}]},
  {dataKeys: true});
  const limits = {maxResponseBytes: 16384, maxNodes: 8000, maxDepth: 32, maxFields: 16, maxNameUnits: 512,
    maxColumns: 8, maxCells: 32, maxTableRows: 16, maxValueNodes: 8000, maxValueDepth: 32,
    maxValueTextBytes: 16384, maxContractPairs: 100, maxRequestBytes: 2048, maxRequests: 6,
    maxPages: 2, perPage: 2, maxSecretBytes: 128, maxRows: 4, maxDeclarationBytes: 65536, maxDeclarationNodes: 8000};
  await writeFile(sourcePath, JSON.stringify({version: 'actql-installed-kintone-source/0.1', connectorId: 'kintone',
    appId: '12', resource: 'inquiries', formResource: 'form', fieldCodes: ['Subject', 'Tags', 'Computed', ...(keyed ? ['CustomerKey'] : [])],
    metadataPath, siteProfilePath: sitePath, accountConfigurationWire, limits}));
  const path = join(root, 'effect.json');
  await writeFile(path, JSON.stringify({version: 'actql-installed-kintone-effect/0.1', connectorId: 'kintone',
    sourceProfilePath: sourcePath, writes: [{resource: 'inquiries', ...(keyed ? {kind: 'upsert', key} : {}), fields: [field]}]}));
  parent = createInstalledLoaderParent({root, moon}); parent.open();
  const load = async () => {
    try {
      return await parent.load(loadInstalledEffect, path, {root, principalId: 'operator', moon, runtimeUrl,
        baseEnvironmentWire: base, resolveSecret: async () => {secretReads++; return 'unused-component-secret';}});
    } catch (failure) {
      // Retain only bounded own Error diagnostics. The original failure and
      // its cleanup owner still propagate unchanged; no retry is selected.
      const pending = [failure], seen = new Set(), errors = [];
      while (pending.length && seen.size < 12) {
        const value = pending.shift();
        if (!(value instanceof Error) || seen.has(value)) continue;
        seen.add(value); errors.push({name: value.name, code: value.code, message: value.message, stack: value.stack});
        pending.push(value.cause, value.primaryFailure);
      }
      await writeFile(join(root, 'original-initialization-failure.json'), JSON.stringify(errors, null, 2) + '\n', {mode: 0o600});
      throw failure;
    }
  };
  return {parent, path, load, tls,
    secretReads: () => secretReads, close: () => parent.close()};
}

test('standard kintone UPDATE initialization keeps the original Site owned until close', async t => {
  const f = await fixture(t);
  const identity = await installedEffectIdentity(f.path, {
    configurationReader: installedSourceConfigurationReader(f.parent.services)});
  assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
  const effect = await f.load(), env = JSON.parse(effect.environmentWire);
  assert.equal(effect.connectorBindings[0].connectorId, 'kintone');
  assert.equal(effect.mappings.length, 1);
  const mapping = env.mapping_contracts.find(value => value.mapping_contract_cid === effect.mappings[0].mappingCid);
  assert.equal(mapping.primary_identity, '$id');
  assert.equal(mapping.target_ref, effect.mappings[0].target);
  assert.equal(mapping.minimum_approval, 'required');
  assert.deepEqual(mapping.writable_fields, ['Subject']);
  assert.deepEqual(Object.keys(mapping.target_schema.fields).sort(), ['$id', 'Computed', 'Subject', 'Tags']);
  assert.equal(f.secretReads(), 0); assert.deepEqual(f.tls.seen(), []);
  assert.equal(retireInstalledSourceInitialization(f.parent.services), false, 'live original Site is still owned');
  await f.close();
  assert.equal(retireInstalledSourceInitialization(f.parent.services), true);
});

test('standard kintone UPDATE initialization refuses a computed write before Site or secret use', async t => {
  const f = await fixture(t, {field: 'Computed'});
  await assert.rejects(f.load(), installedFailureCode('MoonBitHostFailure'));
  assert.equal(f.secretReads(), 0); assert.deepEqual(f.tls.seen(), []);
  await f.close();
  assert.equal(retireInstalledSourceInitialization(f.parent.services), true);
});

test('standard kintone UPSERT initialization binds the selected unique key and both guarded permissions', async t => {
  const f = await fixture(t, {key: 'CustomerKey'});
  const identity = await installedEffectIdentity(f.path, {
    configurationReader: installedSourceConfigurationReader(f.parent.services)});
  assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
  const effect = await f.load(), env = JSON.parse(effect.environmentWire);
  assert.equal(effect.mappings.length, 1);
  assert.equal(effect.mappings[0].kind, 'upsert');
  const mapping = env.mapping_contracts.find(value => value.mapping_contract_cid === effect.mappings[0].mappingCid);
  assert.equal(mapping.target_ref, effect.mappings[0].target);
  assert.equal(mapping.primary_identity, 'CustomerKey');
  assert.equal(mapping.minimum_approval, 'required');
  assert.deepEqual(mapping.required_fields, ['Subject']);
  assert.deepEqual(mapping.writable_fields, ['Subject']);
  assert.deepEqual(mapping.permission_rules, [{effect_kind: 'upsert', selector_class: 'key', write_fields: ['Subject'],
    permissions: ['kintone:records:create', 'kintone:records:update']}]);
  assert.equal(f.secretReads(), 0);
  assert.deepEqual(f.tls.seen(), []);
  assert.equal(retireInstalledSourceInitialization(f.parent.services), false);
  await f.close();
  assert.equal(retireInstalledSourceInitialization(f.parent.services), true);
});

test('standard kintone UPSERT initialization refuses a nonunique Form key before Site or secret use', async t => {
  const f = await fixture(t, {key: 'CustomerKey', unique: false});
  await assert.rejects(f.load(), installedFailureCode('MoonBitHostFailure'));
  assert.equal(f.secretReads(), 0);
  assert.deepEqual(f.tls.seen(), []);
  await f.close();
  assert.equal(retireInstalledSourceInitialization(f.parent.services), true);
});

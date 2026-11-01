// Exact loader and method-capture declarations with explicit construction
// ports. These tests do not issue a Common parent or qualify ordinary reads.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';

const loaderSource = await readFile(new URL('../host/installed-notion-source.mjs', import.meta.url), 'utf8');
const serviceSource = await readFile(new URL('../../../host-node/installed-host-services.mjs', import.meta.url), 'utf8');
const declarations = code => parse(code, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node);
const capture = declarations(serviceSource).find(node => node.id?.name === 'captureInstalledSourceServices');
assert(capture);
const captureInstalledSourceServices = Function('nodeTypes', serviceSource.slice(capture.start, capture.end) +
  '\nreturn captureInstalledSourceServices;')(nodeTypes);
const body = declarations(loaderSource).filter(node =>
  ['VariableDeclaration', 'FunctionDeclaration'].includes(node.type))
  .map(node => loaderSource.slice(node.start, node.end)).join('\n');
const ok = value => ({$tag: 1, _0: value});
const readLimits = Object.freeze({maxResponseBytes: 8192, maxTotalResponseBytes: 24576,
  maxNodes: 512, maxDepth: 16, maxRows: 2, maxTotalRows: 3, maxPages: 4, pageSize: 2,
  maxCursorBytes: 128, maxIdentityBytes: 128, maxTargetBytes: 1024,
  maxValueNodes: 100, maxValueTextBytes: 4096, maxRowsWireBytes: 8192,
  maxRowsWireNodes: 200, maxRowsWireDepth: 8});

function fixture({mutateMethods = false, implementationFailure, sourceFailure} = {}) {
  const events = [], cleanup = [], installation = {}, declaration = {}, capacity = {}, acquisition = {};
  const environment = Object.freeze({wire: 'original-environment'});
  const declared = Object.freeze({catalog_cid: 'original-catalog', views: [
    {resource: 'users', fields: ['email', 'id', 'name', 'type']},
  ]});
  const profile = {version: 'actql-installed-notion-source/0.1', connectorId: 'workspace',
    siteProfilePath: '/UNOPENED/notion-site.json', accountConfigurationWire: '{}',
    limits: {...readLimits, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000,
      maxSecretBytes: 128, maxCaBytes: 16384}};
  const siteProfile = {version: 'actql-installed-notion-site/0.1', apiOrigin: 'https://notion.invalid',
    credentialAuthorityId: 'original-authority', credentialKeyId: 'original-key',
    credentialPrivateKeyPath: '/UNOPENED/private-key', environment: 'fixture',
    journalRoot: '/UNOPENED/credential-journal', namespaceId: 'original',
    siteGeneration: 1, siteKey: 'notion'};
  const sourceInitialization = {prepareDeclaration(views) {
    assert.equal(this, sourceInitialization);
    assert.deepEqual(views, [{resource: 'users', resource_kind: 'notion_users', schema_wire: 'original-schema',
      schema_cid: `sha256:${createHash('sha256').update('original-schema').digest('hex')}`,
      facts_wire: 'original-facts'}]);
    events.push('declaration'); return {declaration, declared, environment};
  }};
  const provider = {
    notionUserListSchemaWire() {assert.equal(this, provider); events.push('schema'); return ok('original-schema');},
    notionUserListRelationFactsWire() {assert.equal(this, provider); return 'original-facts';},
    notionUserListColumnNames() {assert.equal(this, provider); return ['email', 'id', 'name', 'type'];},
    notionProjectUserList() {assert.fail('No response or provider read in the constructor case');},
    notionUserListIds() {assert.fail('No response');},
    notionUserListMetadataJson() {assert.fail('No response');},
    notionUserListRowsWire() {assert.fail('No response');},
  };
  const policy = Object.freeze(Object.fromEntries([...installedJsonSourceReaderLimitNames,
    'maxSecretBytes', 'maxDeclarationBytes', 'maxDeclarationNodes'].map(name => [name,
    Math.max(profile.limits[name] ?? 1000, 1000)])));
  const implementation = Object.freeze({capacity, runAcquisitionLimits: acquisition});
  const authorization = {context: {contextCid: 'original-context'}}, site = {}, result = {};
  let implementationInput, readerInput, sourceInput;
  const services = {
    sourceReaderImplementationProfile(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); events.push('profile'); return policy;
    },
    sourceReaderImplementation(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); implementationInput = input;
      events.push('implementation'); if (implementationFailure) throw implementationFailure; return implementation;
    },
    async openRowSite(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization);
      assert.equal(input.runAcquisitionLimits, acquisition); events.push('site'); return {site, authorization};
    },
    createSourceReader(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.site, site);
      assert.equal(input.implementation, implementation); readerInput = input; events.push('reader');
      return reader;
    },
  };
  const reader = Object.freeze({capacity});
  const configurationReader = {readJson(path) {
    assert.equal(this, configurationReader); assert.equal(path, profile.siteProfilePath);
    if (mutateMethods) {
      for (const name of Object.keys(services)) services[name] = () => assert.fail('Replaced service consumed');
      for (const name of Object.keys(provider)) provider[name] = () => assert.fail('Replaced provider consumed');
      sourceInitialization.prepareDeclaration = () => assert.fail('Replaced constructor consumed');
    }
    events.push('configuration'); return siteProfile;
  }, readText() {assert.fail('No CA path selected');}};
  const ports = {createHash, isAbsolute, nodeTypes, canonicalJson, checked,
    captureConfigurationReaders, captureInstalledSourceServices, installedJsonSourceReaderLimitNames,
    prepareNotionUserListPages() {assert.fail('No reader execution in a construction-only case');},
    NOTION_USER_LIST_OPERATION: 'notion:users:list',
    createInstalledRowSource(input) {
      sourceInput = input; assert.equal(input.declaration, declaration); assert.equal(input.declared, declared);
      assert.equal(input.environment, environment); assert.equal(input.environmentWire, environment.wire);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.providerReader, reader);
      assert.equal(input.site, site); assert.equal(input.authorization, authorization); events.push('source');
      if (sourceFailure) throw sourceFailure;
      return result;
    },
    retainInstalledHostInitializationFailure(cause, original) {
      assert.equal(cause, sourceFailure); assert.equal(original.sourceProfile, site);
      assert.equal(original.sourceReader, reader); cleanup.push(original); return cause;
    },
  };
  const load = Function(...Object.keys(ports), body + '\nreturn loadInstalledNotionSource;')(...Object.values(ports));
  return {events, cleanup, profile, sourceInitialization, services, provider, result,
    get selected() {return {implementationInput, readerInput, sourceInput};},
    load: (overrides = {}) => load(profile, {moon: {}, providerMoon: provider, runtimeBundleCid: 'original-runtime',
      configurationReader, installation, sourceInitialization, installationServices: services,
      resolveSecret() {assert.fail('No credential resolution in constructor scope');}, ...overrides})};
}

test('Notion users constructs through the same current Host Source services without external reader capacity', async () => {
  const f = fixture({mutateMethods: true});
  assert.equal(await f.load(), f.result);
  assert.deepEqual(f.events, ['configuration', 'profile', 'implementation', 'schema', 'declaration', 'site', 'reader', 'source']);
  const {implementationInput, sourceInput, readerInput} = f.selected;
  assert.equal(implementationInput.limits.maxPages, sourceInput.limits.maxPages);
  assert.equal(implementationInput.limits.maxResponseBytes, sourceInput.limits.maxPageBytes);
  assert.equal(implementationInput.limits.maxRows, sourceInput.limits.maxPageRows);
  assert.equal(implementationInput.limits.maxTotalRows, sourceInput.limits.maxCaptureRows);
  assert.equal(readerInput.operation, 'notion:users:list');
  assert.equal(typeof readerInput.preparePageReader, 'function');
});

test('Notion standard loader refuses unowned constructor and service accessors before configuration', async () => {
  const missing = fixture();
  await assert.rejects(missing.load({sourceInitialization: undefined}), {code: 'NotionSourceInitializationUnavailable'});
  assert.deepEqual(missing.events, []);
  const accessor = fixture(), services = {...accessor.services};
  Object.defineProperty(services, 'openRowSite', {get() {assert.fail('Service accessor invoked');}});
  await assert.rejects(accessor.load({installationServices: services}), {code: 'InstalledNotionSourceServicesUnavailable'});
  assert.deepEqual(accessor.events, []);
});

test('Notion standard loader retains original implementation refusal and failed Source children', async () => {
  const original = Object.assign(new Error('OriginalImplementationPending'), {cleanupPending: true,
    cleanupHandle: Object.freeze({retry() {assert.fail('No constructor retry');}})});
  const implementation = fixture({implementationFailure: original});
  await assert.rejects(implementation.load(), cause => cause === original);
  assert.deepEqual(implementation.events, ['configuration', 'profile', 'implementation']);
  assert.deepEqual(implementation.cleanup, []);
  const sourceFailure = Object.assign(new Error('OriginalSourceConstructionPending'), {cleanupPending: true});
  const source = fixture({sourceFailure});
  await assert.rejects(source.load(), cause => cause === sourceFailure);
  assert.equal(source.cleanup.length, 1);
  assert.equal(sourceFailure.cleanupPending, true);
});

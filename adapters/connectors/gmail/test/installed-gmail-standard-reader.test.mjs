import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {parse} from 'acorn';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import * as labelModule from '../site/gmail-label-list-read.mjs';
import {gmailThreadReaderLimitNames} from '../site/gmail-thread-limits.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding, callHttpsCredentialResource}
  from '../../../site-node/https-credential-resource.mjs';

// Actual loader/page source with explicit Core and Host service ports. This
// issues no Request, Ledger, Account decision, physical read or normal runtime.
const source = readFileSync(new URL('../host/installed-gmail-source.mjs', import.meta.url), 'utf8');
const declarations = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node).filter(node => ['VariableDeclaration', 'FunctionDeclaration'].includes(node.type));
const body = declarations.map(node => source.slice(node.start, node.end)).join('\n');
const limits = Object.freeze({maxResponseBytes: 4096, maxNodes: 256, maxDepth: 8, maxRows: 3,
  maxMailboxBytes: 128, maxTargetBytes: 1024, maxValueNodes: 32, maxValueTextBytes: 4096,
  maxRowsWireBytes: 4096, maxRowsWireNodes: 64, maxRowsWireDepth: 6,
  maxDeclarationBytes: 4096, maxDeclarationNodes: 256, maxSecretBytes: 128, maxCaBytes: 16384});
const projected = Object.freeze({maxResponseBytes: 4096, maxTotalResponseBytes: 4096,
  maxNodes: 256, maxDepth: 8, maxRows: 3, maxTotalRows: 3, maxPages: 1, pageSize: 3,
  maxCursorBytes: 1, maxIdentityBytes: 4096, maxTargetBytes: 1024, maxValueNodes: 32,
  maxValueTextBytes: 4096, maxRowsWireBytes: 4096, maxRowsWireNodes: 64, maxRowsWireDepth: 6,
  maxSecretBytes: 128});
const ok = value => ({$tag: 1, _0: value});
function fixture({implementationFailure, sourceFailure, foreignCapacity = false} = {}) {
  const events = [], cleanup = [], installation = {}, capacity = {}, acquisition = {}, declaration = {}, result = {};
  const environment = Object.freeze({wire: 'original-environment'});
  const declared = Object.freeze({views: [{resource: 'labels', fields: ['id', 'name', 'type']}]});
  const profile = {version: 'actql-installed-gmail-source/0.1', connectorId: 'mailbox',
    mailbox: 'support+box@example.test', siteProfilePath: '/UNOPENED/site.json', accountConfigurationWire: '{}', limits};
  const siteProfile = {version: 'actql-installed-gmail-site/0.1', apiOrigin: 'https://gmail.invalid',
    credentialAuthorityId: 'authority', credentialKeyId: 'key', credentialPrivateKeyPath: '/UNOPENED/key',
    environment: 'test', journalRoot: '/UNOPENED/journal', namespaceId: 'test', siteGeneration: 1, siteKey: 'gmail'};
  const sourceInitialization = {prepareDeclaration(views) {
    assert.equal(this, sourceInitialization); events.push('declaration');
    assert.deepEqual(views, [{resource: 'labels', resource_kind: 'gmail_labels', schema_wire: 'schema',
      schema_cid: `sha256:${createHash('sha256').update('schema').digest('hex')}`, facts_wire: 'facts'}]);
    return {declaration, declared, environment};
  }};
  const provider = {gmailLabelListSchemaWire() {assert.equal(this, provider); events.push('schema'); return ok('schema');},
    gmailLabelListRelationFactsWire() {assert.equal(this, provider); return 'facts';},
    gmailLabelListColumnNames() {assert.equal(this, provider); return ['id', 'name', 'type'];},
    gmailProjectLabelList() {assert.fail('No response in loader scope');},
    gmailLabelListRowsWire() {assert.fail('No response');}, gmailLabelListMetadataJson() {assert.fail('No response');}};
  const authorization = {context: {contextCid: 'original-context'}}, site = {};
  const implementation = Object.freeze({capacity, runAcquisitionLimits: acquisition});
  const reader = Object.freeze({capacity: foreignCapacity ? {} : capacity});
  let readerInput;
  const services = {
    sourceReaderImplementationProfile(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.metadataResponses, 0);
      assert.equal(input.originUnits, siteProfile.apiOrigin.length); events.push('profile');
      return {maxDeclarationBytes: 4096, maxDeclarationNodes: 256};
    },
    sourceReaderImplementation(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.deepEqual(input.limits, projected);
      assert.equal(input.columnCount, 3); events.push('implementation');
      if (implementationFailure) throw implementationFailure;
      return implementation;
    },
    async openRowSite(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.runAcquisitionLimits, acquisition);
      events.push('site'); return {authorization, site};
    },
    createSourceReader(input) {
      assert.equal(this, services); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.implementation, implementation);
      assert.equal(input.site, site); readerInput = input; events.push('reader'); return reader;
    },
  };
  const configurationReader = {readJson(path) {
    assert.equal(this, configurationReader); assert.equal(path, profile.siteProfilePath); events.push('configuration');
    for (const name of Object.keys(provider)) provider[name] = () => assert.fail('late provider method');
    for (const name of Object.keys(services)) services[name] = () => assert.fail('late service method');
    sourceInitialization.prepareDeclaration = () => assert.fail('late declaration constructor');
    return siteProfile;
  }, readText() {assert.fail('No CA selected');}};
  const ports = {createHash, isAbsolute, nodeTypes, canonicalJson, checked, captureConfigurationReaders, gmailThreadReaderLimitNames,
    readSourceProfileJson: path => configurationReader.readJson(path),
    readBoundedConfigurationText: () => assert.fail('No CA selected'),
    captureInstalledSourceServices, GMAIL_LABEL_LIST_OPERATION: 'gmail:labels:list',
    prepareGmailLabelListPages: labelModule.prepareGmailLabelListPages,
    createInstalledRowSource(input) {
      assert.equal(input.declaration, declaration); assert.equal(input.environment, environment);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.providerReader, reader);
      assert.deepEqual(input.limits, {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3});
      events.push('source'); if (sourceFailure) throw sourceFailure; return result;
    },
    retainInstalledHostInitializationFailure(cause, original) {cleanup.push(original); return cause;},
  };
  const load = Function(...Object.keys(ports), body + '\nreturn loadInstalledGmailSource;')(...Object.values(ports));
  return {events, cleanup, result, site, reader, services, sourceInitialization, profile,
    readerInput: () => readerInput,
    load: overrides => load(profile, {moon: {}, providerMoon: provider, runtimeBundleCid: 'runtime',
      installation, sourceInitialization, configurationReader, installationServices: services,
      resolveSecret() {assert.fail('No secret resolution');}, ...overrides})};
}

test('Gmail labels constructs through the same original Host Source services without external capacity', async () => {
  const f = fixture(); assert.equal(await f.load(), f.result);
  assert.deepEqual(f.events, ['configuration', 'profile', 'implementation', 'schema', 'declaration', 'site', 'reader', 'source']);
  assert.equal(f.readerInput().operation, 'gmail:labels:list');
  assert.equal(typeof f.readerInput().preparePageReader, 'function');
});

test('Gmail labels refuses absent or accessor original Source services before configuration', async () => {
  const f = fixture();
  await assert.rejects(f.load({sourceInitialization: undefined}), {code: 'GmailSourceInitializationUnavailable'});
  assert.deepEqual(f.events, []);
  const g = fixture(), replacement = {...g.services};
  Object.defineProperty(replacement, 'openRowSite', {get() {assert.fail('Accessor must not run');}});
  await assert.rejects(g.load({installationServices: replacement}), {code: 'InstalledGmailSourceServicesUnavailable'});
  assert.deepEqual(g.events, []);
});

test('Gmail labels preserves original implementation failure and failed reader cleanup custody', async () => {
  const primary = Object.freeze({code: 'original', cleanupPending: true});
  const f = fixture({implementationFailure: primary});
  await assert.rejects(f.load(), error => error === primary); assert.equal(f.cleanup.length, 0);
  const g = fixture({sourceFailure: primary});
  await assert.rejects(g.load(), error => error === primary);
  assert.deepEqual(g.cleanup, [{sourceReader: g.reader, sourceProfile: g.site}]);
  const h = fixture({foreignCapacity: true});
  await assert.rejects(h.load(), {code: 'InstalledGmailReaderImplementationMismatch'});
  assert.equal(h.cleanup.length, 1); assert(!h.events.includes('source'));
});

test('Gmail labels shared reader preserves exact TLS request full cells accounting and original binding retirement', async t => {
  const rows = [{id: 'INBOX', name: 'Inbox', type: 'system'}, {id: 'Label_1', name: '顧客 / é 📩', type: 'user'}];
  const wire = JSON.stringify({labels: rows}), body = Buffer.from(wire), columns = ['id', 'name', 'type'];
  const target = '/gmail/v1/users/support%2Bbox%40example.test/labels';
  const server = await openHttpsExchangeFixture(t, {routes: [{method: 'GET', pathname: target,
    handle: () => ({body: wire})}]});
  const scope = Object.freeze({issuerAuthority: 'authority', principal: 'principal', namespaceId: 'fixture',
    environment: 'test', siteKey: 'gmail', siteGeneration: 1, runtimeBundleCid: 'runtime',
    connectorRegistration: 'gmail', connectorRevision: 'gmail/0.1', resourceOrigin: server.origin,
    runInvocationCid: 'run', taskAttempt: 1, dispatchRequestCid: 'dispatch', operation: 'gmail:labels:list'});
  const grant = {}, raw = Object.freeze({grant, scope}), control = {identity: () => 'original-grant'};
  const journal = {claim: () => ({replayed: false, grant, use: {}, record: {useCid: 'use', grantCid: 'original-grant'}}),
    authorize() {}, finish() {}};
  let resolutions = 0, charges = 0, bindings = 0;
  const resolveSecret = async () => {resolutions++; return 'fixture-secret';};
  const originalSite = Object.freeze({site: {}, referenceCurrent: () => true,
    authorizationPurpose(original) {assert.equal(original, raw); return {kind: 'read'};},
    bindRunAcquisition(original, callbacks) {
      assert.equal(original, raw); callbacks.assertCurrent(); bindings++;
      const binding = openHttpsCredentialBinding({scope, control, journal, resolveSecret,
        maxSecretBytes: limits.maxSecretBytes, assertCurrent: callbacks.assertCurrent});
      return Object.freeze({credential: Object.freeze({binding, control, journal, resolveSecret, ca: server.ca,
        currentBeforeSend: callbacks.observeCurrent}), close: () => closeHttpsCredentialBinding(binding)});
    }, callResource: callHttpsCredentialResource});
  const page = {}, events = [];
  const provider = {gmailLabelListColumnNames() {assert.equal(this, provider); return columns;},
    gmailProjectLabelList(bytes, ...bounds) {
      assert.equal(this, provider); assert.equal(bytes.toString(), wire);
      assert.deepEqual(bounds, [4096, 256, 8, 3, 32, 4096]); events.push('project'); return ok(page);
    }, gmailLabelListMetadataJson(original) {assert.equal(original, page); return '{"rowCount":2}';},
    gmailLabelListRowsWire(original, names) {assert.equal(original, page); assert.deepEqual(names, columns); return ok(JSON.stringify(rows));}};
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite, assertCurrent() {},
    maxResponses: 1, maxResponseBytes: 4096, maxTotalResponseBytes: 4096, maxSecretBytes: 128,
    operation: 'gmail:labels:list', preparePageReader({columns: names}, apply) {
      return labelModule.prepareGmailLabelListPages({moon: provider, mailbox: 'support+box@example.test', names, limits}, apply);
    }});
  let held, delivered;
  const reader = factory.prepare(Object.freeze({resource: 'labels', columns: ['name'], originalAuthorization: raw,
    verifyRead() {}, authorizationFor(index) {assert.equal(index, 0); return {...raw, useId: 'use'};},
    chargePage(bytes) {assert.equal(bytes.toString(), body.toString()); charges++; held = {}; return held;},
    consumePage(value, metadata) {assert.equal(metadata.charge, held); delivered = value;}}));
  try {
    assert.deepEqual(await reader.read(), {pages: 1, rowCount: 2});
    assert.deepEqual(delivered, rows); assert.deepEqual(events, ['project']);
    assert.equal(bindings, 1); assert.equal(resolutions, 1); assert.equal(charges, 1);
    const actual = server.seen(); assert.equal(actual.length, 1);
    assert.equal(actual[0].path, target + '?fields=labels%28id%2Cname%2Ctype%29');
    assert.equal(reader.observe().cleanupConfirmed, false);
    reader.requestStop(); assert.equal(reader.observe().cleanupConfirmed, true);
    assert.equal(factory.retire(), true);
  } finally {reader.requestStop(); factory.retire();}
});

test('Gmail labels shared page constructor keeps original target limit and callback custody boundaries', () => {
  const names = ['id', 'name', 'type'], original = {name: 'page'}, calls = [];
  const provider = {gmailLabelListColumnNames: () => names,
    gmailProjectLabelList: () => ok(original), gmailLabelListMetadataJson: () => '{"rowCount":0}',
    gmailLabelListRowsWire: () => ok('[]')};
  const apply = (method, receiver, args) => {calls.push(method); return Reflect.apply(method, receiver, args);};
  const pages = labelModule.prepareGmailLabelListPages({moon: provider, mailbox: 'a/b@example.test', names: ['name'], limits}, apply);
  const request = pages.fetchPage({pageIndex: 0});
  assert.equal(request.path, '/gmail/v1/users/a%2Fb%40example.test/labels');
  assert.throws(() => pages.fetchPage({pageIndex: 1}), {code: 'GmailLabelListReadAlreadyCompleted'});
  assert.throws(() => labelModule.prepareGmailLabelListPages({moon: provider, mailbox: 'a/b@example.test', names,
    limits: {...limits, maxTargetBytes: 1}}, apply), {code: 'GmailLabelListTargetLimit'});
  assert.throws(() => pages.decodePage({accepted: false, statusCode: 403}), {code: 'GmailLabelListReadRejected'});
  assert.deepEqual(pages.decodePage({accepted: true, statusCode: 200, body: Buffer.from('{}')}), {rows: [], rowCount: 0, done: true});
  assert.equal(calls.length, 5);
});

test('Gmail labels shared reader charges its original response even when physical current refuses after receipt', async () => {
  const primary = new Error('original after-response current refusal'), body = Buffer.from('retained original body');
  const raw = Object.freeze({grant: {}, scope: Object.freeze({operation: 'gmail:labels:list'})});
  let charges = 0, sends = 0;
  const originalSite = Object.freeze({site: {}, referenceCurrent: () => true,
    authorizationPurpose: () => ({kind: 'read'}),
    bindRunAcquisition: () => Object.freeze({credential: {}, close: () => 'closed'}),
    callResource(input) {
      sends++;
      input.responseCustody.retain(Object.freeze({body}));
      throw primary;
    }});
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite, assertCurrent() {},
    maxResponses: 1, maxResponseBytes: 4096, maxTotalResponseBytes: 4096, maxSecretBytes: 128,
    operation: 'gmail:labels:list', preparePageReader() {return Object.freeze({
      fetchPage: () => ({method: 'GET', path: '/original'}), decodePage() {assert.fail('No decoding after current refusal');},
    });}});
  const reader = factory.prepare(Object.freeze({resource: 'labels', columns: ['id'], originalAuthorization: raw,
    verifyRead() {}, authorizationFor: () => ({...raw, useId: 'original-use'}),
    chargePage(original) {assert.strictEqual(original, body); charges++; return {};},
    consumePage() {assert.fail('No row admission after physical refusal');}}));
  await assert.rejects(reader.read(), error => error === primary);
  assert.equal(sends, 1); assert.equal(charges, 1);
  assert.equal(reader.observe().responseCount, 1); assert.equal(reader.observe().receivedBodyBytes, BigInt(body.byteLength));
  reader.requestStop(); assert.equal(reader.observe().cleanupConfirmed, true); assert.equal(factory.retire(), true);
});

// Actual installed identity/loader/readInputs code with explicit configuration
// ports. Stop before schema/provider/Account/transport construction. This is
// original reader/limit/custody evidence, not Source or resource admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const sources = Object.fromEntries(await Promise.all(['notion', 'slack'].map(async role => [role,
  await readFile(new URL(`../../${role}/host/installed-${role}-source.mjs`, import.meta.url), 'utf8')])));
const sharedCode = await readFile(new URL('../../../host-node/source-profile-json.mjs', import.meta.url), 'utf8');
const sharedReader = parse(sharedCode, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node).find(node => node.id?.name === 'captureConfigurationReaders');
assert(sharedReader);
const serviceCode = await readFile(new URL('../../../host-node/installed-host-services.mjs', import.meta.url), 'utf8');
const serviceCapture = parse(serviceCode, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node).find(node => node.id?.name === 'captureInstalledSourceServices');
assert(serviceCapture);
// Exact pure capture helper; initialization and service issuance remain explicit ports.
const captureInstalledSourceServices = new Function('nodeTypes',
  serviceCode.slice(serviceCapture.start, serviceCapture.end) + '\nreturn captureInstalledSourceServices;')(types);
const readerLimits = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth', 'maxRows',
  'maxTotalRows', 'maxPages', 'pageSize', 'maxCursorBytes', 'maxIdentityBytes', 'maxTargetBytes',
  'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const pem = '-----BEGIN CERTIFICATE-----\nORIGINAL\n-----END CERTIFICATE-----\n';
const sha = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

function fixture(role, {textFailure, mutateMethods = false, badMethod, noCa = false,
  authority = pem, legacy = false, allowDirect = false} = {}) {
  const limits = Object.fromEntries([...readerLimits, 'maxDeclarationBytes', 'maxDeclarationNodes',
    'maxSecretBytes', 'maxCaBytes'].map(name => [name, 100]));
  Object.assign(limits, {maxTotalResponseBytes: 200, maxRows: 10, maxTotalRows: 20, maxPages: 2,
    pageSize: 10, maxCaBytes: 16_000_000});
  const profile = {version: `actql-installed-${role}-source/0.1`, connectorId: 'workspace',
    siteProfilePath: '/UNOPENED/site.json', accountConfigurationWire: '{}', limits,
    ...(role === 'slack' ? {workspaceId: 'T-e\u0301'} : {})};
  const site = {version: `actql-installed-${role}-site/0.1`, apiOrigin: `https://${role}.example.test`,
    credentialAuthorityId: 'original-authority', credentialKeyId: 'original-key',
    credentialPrivateKeyPath: '/UNOPENED/private-key', environment: 'fixture', journalRoot: '/UNOPENED/journal',
    namespaceId: 'original', siteGeneration: 1, siteKey: role, ...(noCa ? {} : {caPath: '/UNOPENED/authority.pem'})};
  const calls = []; let directJson = 0, directText = 0;
  const stop = Object.freeze(new Error('OriginalConfigurationCompleteBeforeProvider'));
  const reader = {
    readJson(path) {
      assert.equal(this, reader); assert.equal(path, profile.siteProfilePath); calls.push({kind: 'json', path});
      if (mutateMethods) reader.readJson = reader.readText = () => assert.fail('late reader method consumed');
      return site;
    },
    readText(path, bounds) {
      assert.equal(this, reader); assert.equal(path, site.caPath); assert.deepEqual(bounds, {maxBytes: 16_000_000});
      calls.push({kind: 'text', path, bounds});
      if (textFailure) throw textFailure;
      return authority;
    },
  };
  const originalJson = reader.readJson;
  const read = (...args) => Reflect.apply(originalJson, reader, args);
  if (badMethod) Object.defineProperty(reader, badMethod, {get() {assert.fail('reader accessor invoked');}});
  const code = sources[role];
  const bodies = sharedCode.slice(sharedReader.start, sharedReader.end) + '\n' + parse(code, {ecmaVersion: 'latest', sourceType: 'module'}).body.flatMap(node => {
    const declaration = node.declaration ?? node;
    return ['VariableDeclaration', 'FunctionDeclaration'].includes(declaration.type) ?
      [code.slice(declaration.start, declaration.end)] : [];
  }).join('\n');
  const ports = {createHash, isAbsolute, types, nodeTypes: types, canonicalJson, checked,
    captureInstalledSourceServices, installedJsonSourceReaderLimitNames: readerLimits,
    readSourceProfileJson(path) {
      directJson++; assert(allowDirect, 'original supplied JSON reader was ignored');
      assert.equal(path, profile.siteProfilePath); return site;
    },
    readBoundedConfigurationText(path, bounds) {
      directText++; assert(allowDirect, 'original supplied text reader was ignored');
      assert.equal(path, site.caPath); assert.deepEqual(bounds, {maxBytes: 16_000_000}); return authority;
    },
  };
  const cap = role[0].toUpperCase() + role.slice(1);
  const functions = new Function(...Object.keys(ports), bodies +
    `\nreturn {identity: installed${cap}SourceIdentityParts, load: loadInstalled${cap}Source};`)(...Object.values(ports));
  const provider = Object.fromEntries(['notionUserListSchemaWire', 'notionUserListRelationFactsWire',
    'notionUserListColumnNames', 'notionProjectUserList', 'notionUserListMetadataJson',
    'notionUserListRowsWire', 'notionUserListIds',
    'slackUserListSchemaWire', 'slackUserListRelationFactsWire', 'slackChannelListSchemaWire',
    'slackChannelListRelationFactsWire', 'slackMessageSchemaWire', 'slackMessageRelationFactsWire',
    'slackUserListColumnNames', 'slackChannelListColumnNames', 'slackMessageColumnNames'].map(name =>
    [name, () => name === 'notionUserListColumnNames' ? ['id'] : (() => {throw stop;})()]));
  const installation = Object.freeze({original: role});
  const sourceInitialization = Object.freeze({prepareDeclaration() {assert.fail('no declaration before schema');}});
  const installationServices = {
    sourceReaderImplementationProfile(input) {
      assert.equal(this, installationServices); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization);
      assert.equal(input.metadataResponses, role === 'slack' ? 1 : 0);
      assert.equal(input.originUnits, site.apiOrigin.length);
      return Object.freeze({maxDeclarationBytes: 100, maxDeclarationNodes: 100});
    },
    sourceReaderImplementation(input) {
      assert.equal(this, installationServices); assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization); assert.equal(input.columnCount, 1);
      return Object.freeze({original: 'unexecuted implementation'});
    },
    openRowSite() {assert.fail('no Site before provider schema');},
    createSourceReader() {assert.fail('no reader before provider schema');},
  };
  return {profile, site, reader, calls, stop,
    direct: () => ({json: directJson, text: directText}),
    identity({withThird = true} = {}) {
      return functions.identity(profile, profile, withThird ? read : undefined, Object.freeze({original: role}),
        legacy ? undefined : Object.freeze({configurationReader: reader}));
    },
    load() {return functions.load(profile, {sourceInitialization, installation,
      ...(role === 'slack' ? {moon: Object.freeze({
        clientProgramInstalledSlackSourceReaderCapacity() {
          assert.fail('no runtime capacity before provider declaration');
        },
      })} : {}),
      resolveSecret() {assert.fail('no secret lookup');}, installationServices,
      ...(legacy ? {} : {configurationReader: reader}), providerMoon: provider});},
  };
}

test('installed Source configuration identity retains original JSON and bounded text reader for Notion and Slack', async () => {
  for (const role of ['notion', 'slack']) {
    const f = fixture(role), parts = await f.identity();
    assert.deepEqual(f.calls.map(c => c.kind), ['json', 'text']); assert.deepEqual(f.direct(), {json: 0, text: 0});
    assert.equal(parts[2].caSha256, sha(Buffer.from(pem, 'ascii')));
    if (role === 'slack') assert.equal(parts[2].workspaceBytesCid, sha(Buffer.from('T-e\u0301')));
  }
});

test('installed Source configuration loaders use original readers before provider construction', async () => {
  for (const role of ['notion', 'slack']) {
    const f = fixture(role); await assert.rejects(f.load(), cause => cause === f.stop);
    assert.deepEqual(f.calls.map(c => c.kind), ['json', 'text']); assert.deepEqual(f.direct(), {json: 0, text: 0});
  }
});

test('installed Source configuration preserves same pending read failure without cleanup or fallback', async () => {
  for (const role of ['notion', 'slack']) for (const entry of ['identity', 'load']) {
    let retries = 0;
    const original = Object.assign(new Error('OriginalTextReadPending'), {cleanupPending: true,
      cleanupHandle: Object.freeze({retry() {retries++;}})});
    const f = fixture(role, {textFailure: original});
    await assert.rejects(f[entry](), cause => cause === original);
    assert.deepEqual(f.calls.map(c => c.kind), ['json', 'text']); assert.deepEqual(f.direct(), {json: 0, text: 0});
    assert.equal(retries, 0); assert.equal(original.cleanupPending, true);
  }
});

test('installed Source configuration captures both methods before the first JSON await', async () => {
  for (const role of ['notion', 'slack']) for (const entry of ['identity', 'load']) {
    const f = fixture(role, {mutateMethods: true});
    if (entry === 'identity') await f.identity(); else await assert.rejects(f.load(), cause => cause === f.stop);
    assert.deepEqual(f.calls.map(c => c.kind), ['json', 'text']); assert.deepEqual(f.direct(), {json: 0, text: 0});
  }
});

test('installed Source configuration refuses reader accessors before any read', async () => {
  for (const role of ['notion', 'slack']) for (const entry of ['identity', 'load']) for (const badMethod of ['readJson', 'readText']) {
    const f = fixture(role, {badMethod}), cap = role[0].toUpperCase() + role.slice(1);
    await assert.rejects(f[entry](), {code: `Installed${cap}ConfigurationReaderUnavailable`});
    assert.equal(f.calls.length, 0); assert.deepEqual(f.direct(), {json: 0, text: 0});
  }
});

test('installed Source configuration preserves exact CA bound ASCII refusal and absent-CA behavior', async () => {
  for (const role of ['notion', 'slack']) {
    const cap = role[0].toUpperCase() + role.slice(1), invalid = fixture(role, {authority: 'é'});
    await assert.rejects(invalid.identity(), {code: `InvalidInstalled${cap}TlsAuthority`});
    assert.equal(invalid.calls[1].bounds.maxBytes, 16_000_000);
    const absent = fixture(role, {noCa: true}), parts = await absent.identity();
    assert.deepEqual(absent.calls.map(c => c.kind), ['json']); assert.equal(Object.hasOwn(parts[2], 'caSha256'), false);
  }
});

test('installed Source configuration identity honors the existing third JSON port without a reader context', async () => {
  for (const role of ['notion', 'slack']) {
    const f = fixture(role, {legacy: true, noCa: true}); await f.identity();
    assert.deepEqual(f.calls.map(c => c.kind), ['json']); assert.deepEqual(f.direct(), {json: 0, text: 0});
  }
});

test('installed Source configuration legacy omission retains the original direct bounded readers', async () => {
  for (const role of ['notion', 'slack']) {
    const f = fixture(role, {legacy: true, allowDirect: true}); await f.identity({withThird: false});
    assert.equal(f.calls.length, 0); assert.deepEqual(f.direct(), {json: 1, text: 1});
  }
});

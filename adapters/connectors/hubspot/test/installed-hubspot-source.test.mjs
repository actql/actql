import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledSource, installedSourceIdentity} from '../../../host-node/installed-source.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const base = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
const properties = {results: [
  {name: 'amount', type: 'number', fieldType: 'number'},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', options: [{value: 'a'}, {value: 'b'}]},
]};
const expected = {id: '9007199254740993', amount: '9007199254740993.0100000000', tags: ['a', 'b']};
const objectBody = JSON.stringify({results: [{id: expected.id, archived: false,
  properties: {amount: '9007199254740993.01', tags: 'a;b'}}]});

async function fixture(t, {account = 'allow', propertyRead = 'allow'} = {}) {
  // The helper owns loopback TLS and a separate unused credential namespace.
  // The Source below opens its own actual installed Site/journal/binding.
  const f = await accountFixture(t, {accounted: false});
  const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: f.scope.resourceOrigin,
    credentialAuthorityId: 'installed-hubspot', credentialKeyId: 'key',
    credentialPrivateKeyPath: join(f.root, 'credential-authority.key'), environment: 'test',
    journalRoot: join(f.root, 'installed-credential-journal'), namespaceId: 'installed-hubspot',
    siteGeneration: 1, siteKey: 'installed-hubspot', tokenEnvironment: 'ACTQL_HUBSPOT_TEST_TOKEN',
    caPath: join(f.root, 'server.crt')};
  const siteProfilePath = join(f.root, 'installed-site.json');
  await writeFile(siteProfilePath, JSON.stringify(site));
  const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'hubspot',
    portalId: '7', apiOrigin: site.apiOrigin,
    accountBody: Buffer.from('{"portalId":7,"accountType":"STANDARD"}').toString('base64'),
    objects: [{resource: 'companies', objectType: 'companies',
      propertiesBody: Buffer.from(JSON.stringify(properties)).toString('base64')}]};
  const metadataPath = join(f.root, 'installed-metadata.json');
  await writeFile(metadataPath, JSON.stringify(metadata));
  const policy = canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'installed',
    entries: [['records', 'companies', 'allow'], ['identity', 'account', account],
      ['schema', 'properties', propertyRead]].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([entry_id, resource, outcome]) => ({
      entry_id, outcome, principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
      resource: {any_of: [resource]}, operation: {any_of: ['read']}, exclusions: []}))});
  // Explicit test units, not adoption of a normal numerical Host profile.
  const profile = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'hubspot', portalId: '7',
    resources: [{resource: 'companies', objectType: 'companies'}], metadataPath, siteProfilePath,
    metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire: policy,
    limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20, maxProperties: 10,
      maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
      maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
      maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
      maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128}};
  const path = join(f.root, 'installed-source.json');
  await writeFile(path, JSON.stringify(profile));
  const sources = [], captures = [];
  t.after(async () => {
    for (const captured of captures) await captured.close();
    for (const source of sources) await source.close();
  });
  const load = async () => {
    const source = await loadInstalledSource(path, {root: f.root, principalId: 'operator',
      moon: common, runtimeUrl, baseEnvironmentWire: base,
      resolveSecret: f.options.credential.resolveSecret});
    sources.push(source); return source;
  };
  const prepare = async source => {
    const env = JSON.parse(source.environmentWire);
    const environment = common.clientProgramCheckEnvironment(source.environmentWire,
      env.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const view = env.schema_snapshots.find(value =>
      value.source_ref === source.sourceReadAccesses[0].sourceRef);
    const publication = JSON.stringify({environmentCid: env.evidence_bundle_cid,
      aliases: [{name: 'hubspot.companies', sourceRef: view.source_ref,
        sourceViewContractCid: view.source_view_contract_cid,
        schemaContractCid: view.carrier_schema_contract_cid}]});
    const outcome = common.clientProgramPrepareSourceWithParameters(
      'SELECT id, amount, tags FROM hubspot.companies', 'sql', environment,
      publication, undefined, undefined);
    const program = common.clientProgramPreparationReady(outcome);
    assert.ok(program, inspect(common.clientProgramPreparationIssue(outcome), {depth: 8, maxStringLength: 2000}));
    const repo = new URL('../../../../', import.meta.url);
    const [registry, aoa, query, evidence] = await Promise.all([
      readFile(new URL('spec/dependencies/aoa-pipeline-registry.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-aoa.json', repo), 'utf8').then(JSON.parse),
      readFile(new URL('spec/contracts/actql-query-acquisition.json', repo), 'utf8'),
      readFile(new URL('spec/contracts/actql-query-process-evidence.json', repo), 'utf8')]);
    return {preparedProgram: program, registry,
      values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered']), query, evidence};
  };
  const ledger = () => checked(common.clientProgramAcquisitionLedger(1, 1, 32768n,
    100000000n, 100000000n, 0));
  const requestBodies = [];
  f.state.onRequest = async (request, response) => {
    if (request.url === '/account-info/v3/details') return false;
    const body = request.url === '/crm/v3/properties/companies' ? JSON.stringify(properties)
      : request.url.startsWith('/crm/v3/objects/companies?') ? objectBody
      : assert.fail(`Unexpected request ${request.url}`);
    requestBodies.push(Buffer.from(body));
    response.writeHead(200, {'content-type': 'application/json'}); response.end(body); return true;
  };
  return {...f, site, siteProfilePath, metadata, metadataPath, profile, path,
    load, prepare, ledger, captures, requestBodies};
}

test('installed HubSpot restores every observed property without a credential read', async t => {
  const f = await fixture(t), source = await f.load();
  assert.equal(source.connectorRegistration, 'hubspot');
  assert.equal(source.connectorRevision, 'hubspot/0.1');
  assert.deepEqual(source.sourceReadAccesses.map(value => value.resource), ['companies']);
  const environment = JSON.parse(source.environmentWire);
  const carrier = environment.contract_registry.find(value => value.kind === 'carrier_schema');
  assert.deepEqual(carrier.body.fields, {id: {type: 'string', nullable: false},
    amount: {type: 'decimal', nullable: true, precision: 38, scale: 10},
    tags: {type: 'array', nullable: true, items: {type: 'string', nullable: false}}});
  await source.prepare(await f.prepare(source));
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('installed HubSpot keeps identity, schema and pages on the original accounted RowRun', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const ledger = f.ledger();
  const opened = await source.openCapture({...preparation, ledger}); f.captures.push(opened);
  const exported = checked(common.clientProgramExportSourceCapture(opened.capture.source(),
    opened.requirement, 'installed-hubspot-read-test'));
  const rows = common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
  assert.deepEqual(rows, [expected]);
  assert.deepEqual(f.state.requests.map(value => value.path.split('?')[0]),
    ['/account-info/v3/details', '/crm/v3/properties/companies',
      '/crm/v3/objects/companies', '/crm/v3/properties/companies']);
  assert.equal(f.state.resolutions, 4);
  const received = Buffer.byteLength(f.state.body) + f.requestBodies.reduce((total, bytes) => total + bytes.length, 0);
  assert.equal(common.clientProgramMultiCapturedLedgerUsage(ledger)[3], BigInt(received));
  await opened.close();
  assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('a data read grant cannot authorize identity or property metadata', async t => {
  for (const choice of [{account: 'deny'}, {propertyRead: 'deny'}]) {
    const f = await fixture(t, choice), source = await f.load(), preparation = await f.prepare(source);
    const ledger = f.ledger();
    await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'HubSpotMetadataReadDenied'});
    assert.equal(f.state.requests.length, choice.account === 'deny' ? 0 : 1);
    assert.equal(f.state.resolutions, choice.account === 'deny' ? 0 : 1);
    assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
  }
});

test('a changed current resolver cannot substitute another token for the data page', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  f.state.resolve = async () => {if (f.state.resolutions === 3) f.state.secret = 'foreign-account-token';};
  const ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'RemoteCredentialBindingChanged'});
  assert.equal(f.state.requests.length, 2); assert.equal(f.state.resolutions, 3);
  assert(f.state.requests.every(value => value.authorization === 'Bearer provider-secret'));
  assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('foreign original account metadata and incomplete property metadata refuse before Site I/O', async t => {
  const f = await fixture(t);
  for (const metadata of [
    {...f.metadata, accountBody: Buffer.from('{"portalId":8}').toString('base64')},
    {...f.metadata, objects: [{...f.metadata.objects[0], propertiesBody: Buffer.from(
      '{"results":[{"name":"unprojectable","type":"unsupported","fieldType":"unknown"}]}').toString('base64')}]},
  ]) {
    await writeFile(f.metadataPath, JSON.stringify(metadata));
    await assert.rejects(f.load());
    assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  }
});

test('installed identity binds original metadata, Site generation and declared authority resources', async t => {
  const f = await fixture(t), original = await installedSourceIdentity(f.path);
  await writeFile(f.siteProfilePath, JSON.stringify({...f.site, siteGeneration: 2}));
  assert.notEqual(await installedSourceIdentity(f.path), original);
  await writeFile(f.siteProfilePath, JSON.stringify(f.site));
  assert.equal(await installedSourceIdentity(f.path), original);
  await writeFile(f.path, JSON.stringify({...f.profile,
    metadataResources: {...f.profile.metadataResources, properties: 'different-permission'}}));
  assert.notEqual(await installedSourceIdentity(f.path), original);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('the declared record id remains conditional until cross-page duplicates are refused', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const original = f.state.onRequest;
  let pages = 0;
  f.state.onRequest = async (request, response) => {
    if (!request.url.startsWith('/crm/v3/objects/companies?')) return original(request, response);
    pages++;
    const body = JSON.parse(objectBody);
    if (pages === 1) body.paging = {next: {after: 'next-a'}};
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(body)); return true;
  };
  const ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'HubSpotReadDuplicateRecord'});
  assert.equal(pages, 2); assert.equal(f.state.requests.length, 4);
  assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('schema drift after the last data page prevents Source completion without a replacement lookup', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const original = f.state.onRequest;
  let schemas = 0;
  f.state.onRequest = async (request, response) => {
    if (request.url !== '/crm/v3/properties/companies') return original(request, response);
    schemas++;
    const changed = structuredClone(properties);
    if (schemas === 2) changed.results[0].hasUniqueValue = true;
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(changed)); return true;
  };
  const ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'MoonBitHostFailure'});
  assert.equal(schemas, 2); assert.equal(f.state.requests.length, 4);
  assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('cancellation of the original identity response closes the same bound transport before releasing the RowRun', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  let observed, resume;
  const requestSeen = new Promise(resolve => {observed = resolve;});
  const continueResponse = new Promise(resolve => {resume = resolve;});
  const original = f.state.onRequest;
  f.state.onRequest = async (request, response) => {
    if (request.url !== '/account-info/v3/details') return original(request, response);
    observed(); await continueResponse;
    if (!response.destroyed) {response.writeHead(200); response.end(f.state.body);}
    return true;
  };
  const controller = new AbortController(), ledger = f.ledger();
  const opening = source.openCapture({...preparation, ledger, signal: controller.signal});
  const rejected = assert.rejects(opening, error => {
    // The original acquisition Owner wraps the transport cause and separately
    // reports confirmed transport retirement. It does not copy Error.name.
    assert.equal(error.code, 'ABORT_ERR');
    assert.equal(error.cause.name, 'AbortError');
    assert.equal(error.outcome, 'stopped');
    return true;
  });
  await requestSeen;
  controller.abort(); resume();
  await rejected;
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.resolutions, 1);
  assert.deepEqual(common.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

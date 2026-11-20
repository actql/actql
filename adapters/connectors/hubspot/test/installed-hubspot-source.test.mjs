import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import './installed-hubspot-wide-source.actual.test.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {loadInstalledHubSpotSource} from '../host/installed-hubspot-source.mjs';
import {installedHubSpotFixture as fixture, properties, expected, objectBody} from './installed-hubspot.fixture.mjs';

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
  assert.equal(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes, BigInt(received));
  await opened.close();
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('a data read grant cannot authorize identity or property metadata', async t => {
  for (const choice of [{account: 'deny'}, {propertyRead: 'deny'}]) {
    const f = await fixture(t, choice), source = await f.load(), preparation = await f.prepare(source);
    const ledger = f.ledger();
    await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'ExecutionAuthorizationDenied'});
    assert.equal(f.state.requests.length, choice.account === 'deny' ? 0 : 1);
    assert.equal(f.state.resolutions, choice.account === 'deny' ? 0 : 1);
    assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
});

test('managed metadata children retain the same parent target and their independent current decisions', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const original = source.sourceAccess.authorization, observations = [];
  const sourceAccess = Object.freeze({...source.sourceAccess, authorization: Object.freeze({...original,
    async authorize(boundary, tuple, context) {
      const decision = await original.authorize(boundary, tuple, context);
      observations.push({boundary, tuple, subjectCid: context.subjectCid, decision});
      return decision;
    }})});
  const preparedSource = await source.prepare({...preparation, sourceAccess});
  const ledger = f.ledger();
  const opened = await source.openCapture({...preparation, preparedSource, sourceAccess, ledger});
  f.captures.push(opened);
  const digest = operation => 'sha256:' + createHash('sha256').update(canonicalJson(
    {binding: preparedSource.physicalBinding, operation}, {dataKeys: true})).digest('hex');
  for (const [resource, operation] of [['account', 'hubspot:account:details'],
    ['properties', 'hubspot:properties:read']]) {
    const decisions = observations.filter(value => value.tuple.resource === resource);
    assert(decisions.length > 1, 'initial decision and later physical current checks are independent');
    for (const value of decisions) {
      assert.equal(value.boundary, 'acquisition');
      assert.deepEqual(value.tuple, {connection: 'hubspot:hubspot', resource, operation: 'read'});
      assert.equal(value.subjectCid, digest(operation));
      assert.equal(value.decision.action, 'dispatch');
    }
  }
  assert.equal(f.state.requests.length, 4);
  await opened.close();
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger),
    ['reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']), [0n, 0n, 0n, 0n]);
});

test('metadata current loss after its first observation cannot send the later property recheck', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const original = source.sourceAccess.authorization, failure = new Error('OriginalMetadataCurrentLost');
  const sourceAccess = Object.freeze({...source.sourceAccess, authorization: Object.freeze({...original,
    async authorize(boundary, tuple, context) {
      // The first real metadata read was allowed. Lose its current authority
      // only after the data page, before the second original property request.
      if (tuple.resource === 'properties' && f.state.requests.length === 3) throw failure;
      return original.authorize(boundary, tuple, context);
    }})});
  const preparedSource = await source.prepare({...preparation, sourceAccess}), ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, preparedSource, sourceAccess, ledger}), cause => cause.cause === failure);
  assert.deepEqual(f.state.requests.map(value => value.path.split('?')[0]),
    ['/account-info/v3/details', '/crm/v3/properties/companies', '/crm/v3/objects/companies']);
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger),
    ['reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']), [0n, 0n, 0n, 0n]);
});

test('metadata authorization retains the Reader cancellation signal across its original await', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  const original = source.sourceAccess.authorization, controller = new AbortController();
  let entered, release, metadataSignal;
  const observed = new Promise(resolve => {entered = resolve;});
  const pending = new Promise(resolve => {release = resolve;});
  const sourceAccess = Object.freeze({...source.sourceAccess, authorization: Object.freeze({...original,
    async authorize(boundary, tuple, context) {
      const decision = await original.authorize(boundary, tuple, context);
      if (tuple.resource === 'account') {
        metadataSignal = context.signal;entered();await pending;
      }
      return decision;
    }})});
  const preparedSource = await source.prepare({...preparation, sourceAccess}), ledger = f.ledger();
  const capturing = source.openCapture({...preparation, preparedSource, sourceAccess, ledger, signal: controller.signal});
  // Attach the rejection observer before releasing the original await.
  const stopped = assert.rejects(capturing, cause => cause.cause === controller.signal.reason);
  await observed;
  try {assert(metadataSignal instanceof AbortSignal);controller.abort();assert.equal(metadataSignal.aborted, true);}
  finally {release();}
  await stopped;
  assert.equal(f.state.requests.length, 0);assert.equal(f.state.resolutions, 0);
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger),
    ['reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']), [0n, 0n, 0n, 0n]);
});

test('a changed current resolver cannot substitute another token for the data page', async t => {
  const f = await fixture(t), source = await f.load(), preparation = await f.prepare(source);
  f.state.resolve = async () => {if (f.state.resolutions === 3) f.state.secret = 'foreign-account-token';};
  const ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, ledger}), {code: 'RemoteCredentialBindingChanged'});
  assert.equal(f.state.requests.length, 2); assert.equal(f.state.resolutions, 3);
  assert(f.state.requests.every(value => value.authorization === 'Bearer provider-secret'));
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
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
  const f = await fixture(t), original = await f.identity();
  await writeFile(f.siteProfilePath, JSON.stringify({...f.site, siteGeneration: 2}));
  assert.notEqual(await f.identity(), original);
  await writeFile(f.siteProfilePath, JSON.stringify(f.site));
  assert.equal(await f.identity(), original);
  await writeFile(f.path, JSON.stringify({...f.profile,
    metadataResources: {...f.profile.metadataResources, properties: 'different-permission'}}));
  assert.notEqual(await f.identity(), original);
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
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
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
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
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
  assert.deepEqual(ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('HubSpot loader without original initialization refuses before raw metadata or provider entry',async()=>{
  await assert.rejects(loadInstalledHubSpotSource({metadataPath:'/UNOPENED-original-metadata'},{}),
    {code:'HubSpotSourceConstructionUnavailable'});
});

test('registered HubSpot malformed property bytes preserve original input failure and initial cleanup',async t=>{
  const f=await fixture(t);
  await writeFile(f.metadataPath,JSON.stringify({...f.metadata,objects:[{...f.metadata.objects[0],
    propertiesBody:f.metadata.objects[0].propertiesBody+'\n'}]}));
  await assert.rejects(f.load(),cause=>{
    assert.equal(cause.primaryFailure?.code,'InvalidInstalledHubSpotMetadata');
    assert.equal(cause.cleanupPending,false);assert.deepEqual(cause.cleanupErrors,[]);return true;
  });
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('registered HubSpot retains every original resource on the same initial parent before Source finish',async t=>{
  const f=await fixture(t);
  await writeFile(f.path,JSON.stringify({...f.profile,resources:[...f.profile.resources,
    {resource:'contacts',objectType:'contacts'}]}));
  await writeFile(f.metadataPath,JSON.stringify({...f.metadata,objects:[...f.metadata.objects,
    {resource:'contacts',objectType:'contacts',propertiesBody:f.metadata.objects[0].propertiesBody}]}));
  const source=await f.load();
  assert.deepEqual(source.sourceReadAccesses.map(value=>value.resource).sort(),['companies','contacts']);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});


test('HubSpot standard Source publishes its actual same-owner managed Effect Plan selection before provider I/O', async t => {
  const f = await fixture(t), source = await f.load();
  const selected = source.managedEffectPlanSelection();
  assert(selected.declaration);assert(selected.provider);assert(selected.inputLimits);
  assert.equal(typeof selected.transferBytes, 'bigint');assert.equal(typeof selected.executionBytes, 'bigint');
  assert.equal(f.state.requests.length, 0);assert.equal(f.state.resolutions, 0);
});

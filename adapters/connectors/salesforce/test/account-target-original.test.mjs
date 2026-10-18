import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as moon from '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {installSalesforceAuthorization} from '../host/installed-salesforce-site.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import * as targets from '../site/salesforce-target-observation.mjs';
import {openSalesforceEffectSiteFixture} from './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
async function fixture(t, headers = {etag: '"original-account-tag"'}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-target-'));
  t.after(async () => {
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      t.diagnostic(`Retained Account target authority: ${root}`);
    } else await rm(root, {recursive: true, force: true});
  });
  const authorization = await installSalesforceAuthorization({root,
    principalId: 'principal-a', accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'account-target-test',
      entries: [{entry_id: 'explicit-records', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {any_of: ['salesforce:00D000000000001EAA']},
        resource: {any_of: ['Account', 'Test_Record__c']},
        operation: {any_of: ['effect', 'read']}}]})});
  const setup = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon: moon, authorization, writableObjects: ['Account'],
    accountTargetHeaders: headers, runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const b = JSON.parse(moon.salesforceCatalogObservationJson(setup.catalog.observation)).binding;
  const makeRequest = (resource = 'Account', id = '001000000000001') => {
    const projection = checked(moon.salesforcePrepareWriteProjection(setup.catalog.observation,
      b.namespace_id, b.principal, b.environment, b.connection_revision, b.org_id,
      b.site_key, b.site_generation, b.connector_registration, b.connector_revision,
      b.resource_origin, b.run_invocation_cid, b.dispatch_request_cid,
      b.sync_occurrence, resource, 1, '', ['Name'], 1));
    const body = checked(moon.salesforcePrepareWriteBody(projection,
      Buffer.from('{"Name":"approved"}'), 1024, 32, 5));
    return checked(moon.salesforcePrepareSingleWriteRequest(body, 'v62.0', 1, id, 0, 256, 128, 1024));
  };
  const request = makeRequest();
  const decision = await authorization.authorize('acquisition', {
    connection: setup.site.connection, resource: 'Account', operation: 'read'}, {subjectCid: cid('1')});
  const grant = setup.site.issueGrant({operation: 'salesforce:record:observe', decision,
    resource: 'Account', runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    taskAttempt: 2, maxUses: 32, subjectCid: cid('1')});
  let ordinal = 0;
  const options = () => ({moon, request, currentCatalog: setup.catalog.observation,
    credential: setup.credential, authorization: {...grant, useId: `account-target-${ordinal++}`},
    limits: {maxResponseBytes: 4096, maxNodes: 64, maxDepth: 5, maxIdentityBytes: 4096}});
  const originals = {moon, request, currentCatalog: setup.catalog.observation, credential: setup.credential};
  const read = () => (targets.observeSalesforceAccountConditionalTarget ??
    targets.observeSalesforceSingleTarget)(options());
  const count = () => setup.seen.filter(item => item.method === 'GET' &&
    item.path === '/services/data/v62.0/sobjects/Account/001000000000001').length;
  return {setup, request, makeRequest, options, originals, read, count};
}

test('Account target original captures the actual identity representation and strong ETag', async t => {
  const f = await fixture(t);
  const target = await f.read();
  assert.equal(target.statusCode, 200);
  const physical = f.setup.seen.at(-1);
  assert.equal(physical.accept, 'application/json');
  assert.equal(physical.acceptEncoding, 'identity');
  assert.equal(typeof targets.withSalesforceAccountTargetOriginal, 'function');
  const result = targets.withSalesforceAccountTargetOriginal(target, f.originals, facts => {
    assert.equal(facts.request, f.request);
    assert.equal(facts.targetObservation, target.record);
    assert.equal(facts.versionCid, target.versionCid);
    assert.equal(facts.etag, '"original-account-tag"');
    assert.equal(facts.response.body, target.body);
    assert.equal(facts.response.useCid, target.useCid);
    assert.equal(facts.credentialFacts.method, 'GET');
    assert.equal(facts.credentialFacts.requestBodyBytes, 0);
    assert.equal(Object.isFrozen(facts), true);
    assert.equal(Object.isFrozen(facts.credentialFacts.requestRepresentation), true);
    return 17;
  });
  assert.equal(result, 17);
  assert.equal(f.count(), 1);
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
});

test('Account target original detects finisher mutation and remains refused after byte restoration', async t => {
  const f = await fixture(t);
  const target = await f.read();
  assert.equal(f.count(), 1);
  assert.equal(typeof targets.withSalesforceAccountTargetOriginal, 'function');
  const saved = Buffer.from(target.body);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, facts => {
    facts.response.body[0] ^= 1;
    return 'not publishable';
  }), {code: 'RemoteCredentialRunResponseChanged'});
  target.body.set(saved);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {}),
    {code: 'RemoteCredentialRunResponseChanged'});
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
  assert.equal(f.count(), 1);
});

test('Account target original rejects copied, foreign request, Catalog and Credential pairs', async t => {
  const f = await fixture(t);
  const target = await f.read();
  const consume = () => assert.fail('foreign pair reached receiver');
  for (const [candidate, originals] of [[{...target}, f.originals],
    [target, {...f.originals, request: f.makeRequest()}],
    [target, {...f.originals, currentCatalog: {}}],
    [target, {...f.originals, credential: {...f.setup.credential, control: {}}}],
    [target, {...f.originals, credential: {...f.setup.credential, journal: {}}}]]) {
    assert.throws(() => targets.withSalesforceAccountTargetOriginal(candidate, originals, consume),
      {code: 'SalesforceAccountTargetOriginalUnavailable'});
  }
  targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {});
  assert.equal(f.count(), 1);
});

test('Account target original rejects missing weak wildcard list and non-identity representation', async t => {
  const headers = {};
  const f = await fixture(t, headers);
  for (const etag of [undefined, 'W/"weak"', '*', '"one", "two"', 'bare',
    ['"first"', '"second"']]) {
    if (etag === undefined) delete headers.etag; else headers.etag = etag;
    const target = await f.read();
    assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {}),
      {code: 'SalesforceAccountConditionalRepresentationUnavailable'});
    assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
  }
  headers.etag = '"strong"'; headers['content-encoding'] = 'gzip';
  const compressed = await f.read();
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(compressed, f.originals, () => {}),
    {code: 'SalesforceAccountConditionalRepresentationUnavailable'});
  delete headers['content-encoding']; headers.etag = '""';
  const emptyTag = await f.read();
  targets.withSalesforceAccountTargetOriginal(emptyTag, f.originals, facts => assert.equal(facts.etag, '""'));
  assert.equal(f.count(), 8);
});

test('Account target original keeps finisher exceptions and rejects asynchronous consumers', async t => {
  const f = await fixture(t);
  const target = await f.read();
  const original = new Error('OriginalFinisherFailed');
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => { throw original; }),
    error => error === original);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => Promise.resolve()),
    {code: 'InvalidSalesforceAccountTargetConsumer'});
  targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {});
  assert.equal(f.count(), 1);
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
});

test('Account target original checks result inspection and preserves the original throwing getter', async t => {
  const f = await fixture(t);
  const target = await f.read();
  const saved = Buffer.from(target.body);
  const primary = new Error('OriginalResultInspectionFailed');
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => ({
    get then() { target.body[0] ^= 1; throw primary; },
  })), error => error === primary);
  target.body.set(saved);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {}),
    {code: 'RemoteCredentialRunResponseChanged'});
  assert.equal(f.count(), 1);
});

test('Account target original retires only its borrow and never changes the original confirmed outcome', async t => {
  const f = await fixture(t);
  const target = await f.read();
  targets.retireSalesforceAccountTargetOriginal(target);
  targets.retireSalesforceAccountTargetOriginal(target);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {}),
    {code: 'SalesforceAccountTargetOriginalUnavailable'});
  assert.ok(target.body.byteLength > 0);
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
  assert.equal(f.count(), 1);
});

test('Account target original rejects other object profiles before target I/O', async t => {
  const f = await fixture(t);
  const before = f.setup.seen.length;
  await assert.rejects(targets.observeSalesforceAccountConditionalTarget({
    ...f.options(), request: f.makeRequest('Test_Record__c', 'a00000000000001'),
  }), {code: 'SalesforceAccountConditionalProfileUnavailable'});
  assert.equal(f.setup.seen.length, before);
});

test('Account target original refuses an earlier confirmed response substituted for a different use', async t => {
  const f = await fixture(t);
  let raw;
  const first = await targets.observeSalesforceAccountConditionalTarget({...f.options(),
    async callResource(options) { raw = await callHttpsCredentialResource(options); return raw; }});
  targets.withSalesforceAccountTargetOriginal(first, f.originals, () => {});
  const substituted = await targets.observeSalesforceAccountConditionalTarget({...f.options(),
    async callResource() { return raw; }});
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(substituted, f.originals, () => {}),
    {code: 'SalesforceAccountConditionalRepresentationUnavailable'});
  targets.withSalesforceAccountTargetOriginal(first, f.originals, () => {});
  assert.equal(f.setup.journal.inspect(first.useCid).outcome, 'succeeded');
  assert.equal(f.count(), 1);
});

test('Account target original refuses retirement during its finisher without changing physical outcome', async t => {
  const f = await fixture(t);
  const target = await f.read();
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {
    targets.retireSalesforceAccountTargetOriginal(target);
    return 'retired result';
  }), {code: 'SalesforceAccountTargetOriginalUnavailable'});
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
  assert.equal(f.count(), 1);
});

test('Account target original keeps cancellation after receive separate from the confirmed Journal outcome', async t => {
  const f = await fixture(t);
  const controller = new AbortController();
  const target = await targets.observeSalesforceAccountConditionalTarget({...f.options(), signal: controller.signal});
  const primary = new Error('OriginalAbortAfterReceive');
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {
    controller.abort(primary);
    return 'cancelled result';
  }), cause => cause === primary);
  assert.throws(() => targets.withSalesforceAccountTargetOriginal(target, f.originals, () => {}), cause => cause === primary);
  assert.equal(f.setup.journal.inspect(target.useCid).outcome, 'succeeded');
  assert.equal(f.count(), 1);
});

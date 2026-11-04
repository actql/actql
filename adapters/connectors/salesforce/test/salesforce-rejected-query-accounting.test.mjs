// Actual exported JS sequencers with explicit compiler, authorization, current,
// transport and accounting ports. No nominal Core, RowRun, Account or HTTPS
// acceptance is inferred from these callback-boundary cases.
import assert from 'node:assert/strict';
import {checked} from '../../../host-common/runtime-result.mjs';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {readSalesforceQuery, readSalesforceManagedQuery} from
  '../site/salesforce-query-read.mjs';
import {credentialInvocationBindingKeys} from
  '../../../host-common/credential-scope-fields.generated.mjs';
import {createInstalledCredentialSourceReader} from
  '../../../host-node/installed-credential-source-reader.mjs';
import {installedJsonSourceReaderLimitNames} from
  '../../../host-node/installed-credential-source-reader.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {prepareSalesforceSourceReadSequence, readSalesforceSourceChild} from
  '../site/salesforce-query-read.mjs';

const operation = 'salesforce:query:read';
const path = '/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account';
// Explicit pinned-compiler Result port, not an opaque-value issuer or ABI test.
const ok = value => ({$tag: 1, _0: value});
const forbidden = () => assert.fail('Rejected response reached provider admission or delivery');
const fail = code => {throw Object.assign(new Error(code), {code});};

// Extract the original private caller, without replacing its implementation.
// Core quantities, bound initialization and provider work are explicit ports;
// this is source/caller correspondence, not nominal or normal acceptance.
async function originalFunction(path, name, ports) {
  const {parse} = await import('acorn');
  const source = await readFile(new URL(path, import.meta.url), 'utf8');
  let node;
  const walk = value => {
    if (value === null || typeof value !== 'object') return;
    if (value.type === 'FunctionDeclaration' && value.id.name === name) {
      assert.equal(node, undefined, `Unique original function ${name}`);node = value;
    }
    for (const child of Object.values(value)) {
      if (Array.isArray(child)) child.forEach(walk);else walk(child);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.ok(node, `Original function ${name}`);
  return Function(...Object.keys(ports), `return (${source.slice(node.start, node.end)});`)(...Object.values(ports));
}

test('actual Salesforce caller selects the same complete native Reader before pure original read facts', async () => {
  const events = [], capacity = Object.freeze({}), providerReader = Object.freeze({});
  const site = Object.freeze({namespaceId: 'namespace', principal: 'principal', environment: 'environment',
    connectionRevision: 'revision', orgId: 'org', siteKey: 'site', siteGeneration: 1,
    instanceOrigin: 'https://salesforce.invalid', apiVersion: 'v62.0', connection: 'original-connection',
    referenceCurrent() {return true;},
    async describeForAcquisition() {assert.fail('No Describe before original Reader invocation');}});
  const limits = Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 32,
    maxRows: 2000, maxLocatorUnits: 2048, maxPages: 10, maxTotalRows: 100});
  const describe = Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 32,
    maxFields: 1000, maxNameUnits: 200_000});
  const policy = Object.freeze([65536, 100000, 100]);
  const moon = Object.freeze({
    clientProgramInstalledSourceReaderPolicy() {assert.equal(this, moon);return policy;},
    clientProgramInstalledSalesforceSourceReaderResponseCapacity() {
      assert.fail('The current Reader cannot select the retired full-envelope quote');
    },
    clientProgramInstalledSalesforceCurrentResponseCapacity(...args) {
      assert.equal(this, moon);assert.deepEqual(args[0].slice(0, 8),
        [4_000_000, 48_000_000, 400_000, 32, 2000, 100, 12, 2000]);
      assert.equal(args[1], policy[2]);assert.equal(args[2], policy[0]);
      assert.deepEqual(args[3], Object.values(describe));assert.equal(args[4], 8_000_000);
      assert.ok(args[5] >= 2 * 71 + 44);assert.equal(args[6], 'Account'.length);
      assert.equal(args[7], 10);assert.equal(args[8], site.apiVersion.length);assert.equal(args[9], 4096);
      assert.equal(args.length, 16);
      assert.equal(args[10], 0, 'No Describe body precedes the original Reader');
      assert.equal(args[11], undefined, 'No QueryRead precedes preparation');
      assert.equal(args[12], '', 'No query path precedes preparation');
      assert.equal(args[13], undefined, 'No response body precedes acquisition');
      assert.equal(args[14], 0n, 'No raw response bytes have been received');
      assert.equal(args[15], 0, 'No response originals have been received');
      events.push('quote');return ok(capacity);
    },
  });
  let selected, row;
  const construction = Object.freeze({
    sourceReaderImplementation(input) {
      assert.equal(input.readSequenceConstruction.capacity, capacity);
      assert.equal(input.readSequenceConstruction.originalLimits, limits);
      assert.deepEqual(input.readSequenceConstruction.sequence, {operation, maxUses: 10,
        children: [{operation: 'salesforce:catalog:describe', maxUses: 2}]});
      events.push('implementation');selected = Object.freeze({capacity, limits: input.limits,
        runAcquisitionLimits: Object.freeze({maxBindings: policy[1], maxSecretBytes: policy[0]})});return selected;
    },
    createSourceReader(input) {
      assert.equal(input.implementation, selected);assert.equal(typeof input.prepareReadSequence, 'function');
      events.push('reader');return providerReader;
    },
    createRowSource(input) {row = input;events.push('source');return input;},
  });
  const create = await originalFunction('../host/installed-salesforce-source.mjs', 'installedSalesforceAdapter', {
    cid() {return 'original-cid';}, fail, checked, readLimits: limits,
    declarationLimits: {maxBytes: 4_000_000}, installedJsonSourceReaderLimitNames,
    DEFAULT_SALESFORCE_CATALOG_LIMITS: {describe, maxObservationBytes: 8_000_000},
    installedSalesforceSiteBinding(actual) {assert.equal(actual, site);return {bindingCid: 'binding'};},
    prepareSalesforceSourceReadSequence() {assert.fail('No protocol before original Reader preparation');},
    readSalesforceQuery() {assert.fail('Retired pre-Run query path');},
  });
  const prepared = Object.freeze({physicalBinding: {catalog_cid: 'catalog', fields: ['Id']}});
  const acquisition = Object.freeze({});
  await create({moon, queryMoon: {}, site, authorization: {}, declaration: {}, recover() {}, discovery: {},
    construction, readerPolicy: policy, resources: Object.freeze(['Account']), generationCid: 'generation', catalogCid: 'catalog', connectorId: 'crm'});
  assert.equal(row.providerReader, providerReader);assert.equal(Object.hasOwn(row, 'readPages'), false);
  // The ordinary Row Source consumes the SAME Reader's whole response
  // inventory. Native query uses remain ten; the two metadata responses
  // belong to that original shared twelve-response demand too.
  assert.equal(row.limits.maxPages, selected.limits.maxPages);
  assert.equal(row.limits.maxPageBytes, selected.limits.maxResponseBytes);
  assert.equal(row.limits.maxPageRows, selected.limits.maxRows);
  assert.equal(row.limits.maxCaptureRows, selected.limits.maxTotalRows);
  assert.equal(row.projectSite().referenceCurrent, site.referenceCurrent);
  for (const name of ['managedCaptureCapacity', 'managedWholeSourceCapacity', 'managedEffectPlanSelection']) {
    assert.ok(row.publicationSurface.includes(name), `Normal caller retains ${name}`);
  }
  const facts = await row.prepareRead({prepared, acquisition, decision: {basis: 'policy'}, resource: 'Account',
    nonce: 'original-nonce', runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch'});
  assert.equal(facts.acquisition, acquisition);assert.equal(facts.resource, 'Account');
  assert.equal(facts.wholeInput, false);
  const inputFacts = await row.prepareRead({prepared, acquisition, wholeInput: true,
    decision: {basis: 'policy'}, resource: 'Account', nonce: 'original-input-nonce',
    runInvocationCid: 'original-input-run', dispatchRequestCid: 'original-input-dispatch'});
  assert.equal(inputFacts.acquisition, acquisition);assert.equal(inputFacts.wholeInput, true);
  assert.equal(facts.runInvocationCid, 'original-run');assert.equal(facts.dispatchRequestCid, 'original-dispatch');
  assert.equal(facts.nonce, 'original-nonce');assert.equal(facts.approval, undefined);
  assert.deepEqual(events, ['quote', 'implementation', 'reader', 'source']);
});

test('actual bound specialized Site enters the same installation Reader association', async () => {
  const installation = Object.freeze({}), context = Object.freeze({}), site = Object.freeze({close() {}});
  const authorization = Object.freeze({}), reader = Object.freeze({}), services = {};
  const original = {root: 'original-root', principalId: 'principal', moon: {},
    selected: new WeakMap([[installation, 'original-runtime']]), siteInstallations: new WeakMap(), current() {}};
  const material = {phase: 'working', inputs: []}, scope = {active: true, installation};
  const sourceContexts = new WeakMap([[context, {original, material, scope}]]);
  services.createSourceReader = input => {
    assert.equal(input.sourceInitialization, context);assert.equal(input.installation, installation);
    assert.equal(input.site, site);assert.equal(original.siteInstallations.get(site), context);
    return reader;
  };
  const bind = await originalFunction('../../../host-node/installed-host-services.mjs', 'bindInstalledSourceConstruction', {
    sourceContexts, installations: new WeakMap([[services, original]]), boundConstructions: new WeakMap(),
    nodeTypes: (await import('node:util')).types, fail,
    installedSourceConfigurationReader() {return {};}, captureConfigurationReaders() {return Object.freeze({});},
  });
  const bound = bind(services, context, {});
  const opened = await bound.openSpecializedSite({authorizationConstructor: async () => authorization,
    siteConstructor: async () => site, siteArgument: 'original-profile', accountConfiguration: 'original-account'});
  assert.equal(opened.site, site);assert.equal(opened.authorization, authorization);
  assert.equal(bound.createSourceReader({implementation: {}}), reader);
});

for (const refused of [true, false]) {
  test(`actual native read facts ${refused ? 'never precede refused Run backing' : 'keep failed preparation in the same admitted Run cleanup'}`, async () => {
    const prepared = Object.freeze({checkedSource: Object.freeze({requirementCid: 'original-requirement'})});
    const program = Object.freeze({}), access = Object.freeze({});
    const acquisition = Object.freeze({}), ledger = Object.freeze({}), run = Object.freeze({}), state = {};
    const failure = Object.freeze({originalFailure: true}), events = [];
    const owner = {checkedOwner: program, effectful: false, access, occurrence: {stage: 0, input: 0, task: 0},
      acquisition, resource: 'Account', wholeInput: false};
    const ports = {preparations: new WeakMap([[prepared, owner]]), originalReader: {capacity: {}},
      sourceAccess: access, captureCapacity(actual) {assert.equal(actual, owner);events.push('quote');},
      currentRead: async () => ({basis: 'policy'}), directReadIdentity: undefined,
      moon: {clientProgramRowSourceColumns(actual) {assert.equal(actual, acquisition);return ['Id'];}},
      randomUUID: () => 'original-nonce', cid: () => 'original-cid', maxTransferBytes: 12n,
      limits: {maxPageBytes: 4}, listingReportCapacity: undefined, preparingSourceReads: new Set(),
      closeSourceRead: undefined, fail,
      async prepareRead(input) {
        assert.equal(input.prepared, prepared);assert.equal(input.acquisition, acquisition);
        events.push('facts');throw failure;
      },
      startInstalledRowRun(input) {
        assert.equal(input.ledger, ledger);assert.equal(input.acquisition, acquisition);
        events.push('reserve');if (refused) throw failure;
        return {run, closeAfterFailure(actual) {assert.equal(actual, state);events.push('original-cleanup');}};
      },
    };
    const acquire = await originalFunction('../../../host-node/installed-row-source.mjs', 'acquire', ports);
    await assert.rejects(acquire(state, {preparedProgram: program, sourceAccess: access,
      preparedSource: prepared, ledger}), cause => cause === failure);
    assert.deepEqual(events, refused ? ['quote', 'reserve'] : ['quote', 'reserve', 'facts', 'original-cleanup']);
  });
}

function fixture(mode, accounting) {
  const plan = Object.freeze({port: 'projection'});
  const read = Object.freeze({port: 'original-read'});
  const values = Object.freeze({port: 'managed-values'});
  const observation = Object.freeze({port: 'current-catalog'});
  const grant = Object.freeze({port: 'original-grant'});
  const scope = Object.freeze({
    ...Object.fromEntries(credentialInvocationBindingKeys.map(key => [key, 'same'])),
    operation, siteGeneration: 1,
  });
  const response = {accepted: false, statusCode: 503,
    body: Buffer.from('original rejected response')};
  const events = [];
  let requests = 0;
  const moon = {
    salesforceReadProjectionScopeMatches(actualPlan, ...fields) {
      assert.equal(actualPlan, plan);
      assert.deepEqual(fields, ['namespaceId', 'principal', 'environment',
        'siteKey', 'siteGeneration', 'connectorRegistration',
        'connectorRevision', 'resourceOrigin', 'runInvocationCid',
        'dispatchRequestCid'].map(key => scope[key]));
      return true;
    },
    salesforceRecheckReadProjection(actualPlan, actualObservation) {
      assert.equal(actualPlan, plan); assert.equal(actualObservation, observation);
      events.push('current'); return ok(undefined);
    },
  };
  const prefix = mode === 'raw' ? 'salesforceQueryRead' : 'salesforceManagedQuery';
  const begin = (...args) => {
    assert.equal(args[0], plan); assert.equal(args[1], 'v62.0');
    assert.equal(args[8], 2n);
    if (mode === 'managed') assert.equal(args[9], values);
    events.push('begin'); return ok(read);
  };
  moon[mode === 'raw' ? 'salesforceBeginQueryRead' : 'salesforcePrepareManagedQuery'] = begin;
  moon[prefix + 'NextPath'] = actual => {
    assert.equal(actual, read); events.push('next'); return ok(path);
  };
  for (const suffix of ['AcceptPage', 'Complete', 'RowCount', 'Finish', 'AcknowledgePage']) {
    moon[prefix + suffix] = forbidden;
  }
  moon[prefix + (mode === 'raw' ? 'Interrupt' : 'Cancel')] = actual => {
    assert.equal(actual, read); events.push('interrupt');
  };
  const options = {
    moon, plan, values, apiVersion: 'v62.0',
    initialAuthorization: {grant, scope, useId: 'same-query-use'},
    authorizationForPage: forbidden,
    credential: {port: 'credential'},
    refreshCatalog: async () => ({status: 'complete', observation}),
    limits: {maxBytes: 1024, maxNodes: 100, maxDepth: 8, maxRows: 2,
      maxLocatorUnits: 1024, maxPages: 2, maxTotalRows: 2},
    async callResource(input) {
      assert.equal(++requests, 1); assert.equal(input.grant, grant);
      assert.equal(input.returnRejectedResponse, true);
      assert.equal(input.maxResponseBytes, 1024);
      assert.deepEqual([...input.operations], [[operation, {method: 'GET', path}]]);
      events.push('response'); return response;
    },
    async chargePage(body) {
      assert.equal(body, response.body); events.push('charge');
      if (accounting) await accounting({response, events});
      events.push('charged'); return Object.freeze({port: 'original-charge'});
    },
    consumePage: forbidden,
  };
  return {events, response,
    run: () => (mode === 'raw' ? readSalesforceQuery : readSalesforceManagedQuery)(options)};
}

for (const mode of ['raw', 'managed']) {
  test(`Salesforce ${mode} query charges the original rejected body before refusal`, async () => {
    const f = fixture(mode);
    await assert.rejects(f.run(), error => error.code === 'SalesforceQueryResourceRejected');
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'charged', 'interrupt']);
  });
}

// Actual shared Reader plus the existing Salesforce query sequencer. The Site
// issuer, typed codecs, same-parent capacity and physical Resource are explicit
// ports; this is not normal Common/HTTPS or numerical backing acceptance.
function managedSourceFixture({rejected = false, consumeFailure = false, responseBacking = false, currentBacking = false, wholeInput = false} = {}) {
  const events = [], cells = Object.freeze([Object.freeze([Object.freeze({typed: true})])]);
  const columns = Object.freeze(['Id']), acquisition = Object.freeze({}), declaration = Object.freeze({});
  const plan = Object.freeze({}), query = Object.freeze({}), observation = Object.freeze({});
  const root = Object.freeze({grant: Object.freeze({}), scope: Object.freeze({
    ...Object.fromEntries(credentialInvocationBindingKeys.map(key => [key, 'same'])), operation,
    runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch', siteGeneration: 1})});
  const originalCredential = Object.freeze({}), boundCredential = Object.freeze({});
  const originals = new Set([root]), chargeByBody = new Map();
  let pages = 0, closes = 0, charges = 0, consumed = 0;
  const preparedRead = Object.freeze({acquisition, wholeInput, resource: 'Account', nonce: 'original',
    runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch'});
  const site = Object.freeze({credential: originalCredential, apiVersion: 'v62.0',
    async describeForAcquisition(request) {
      assert.equal(this, site);assert.equal(request.resource, 'Account');
      assert.equal(request.runInvocationCid, 'original-run');
      assert.equal(request.dispatchRequestCid, 'original-dispatch');
      const metadata = Object.freeze({grant: Object.freeze({}),
        scope: Object.freeze({...root.scope, operation: 'salesforce:catalog:describe'})});
      originals.add(metadata);
      await invokeScopedCredentialOperation({authorization: {...metadata, useId: request.occurrence},
        credential: originalCredential, operation: 'salesforce:catalog:describe', method: 'GET',
        path: '/services/data/v62.0/sobjects/Account/describe', maxResponseBytes: 1024,
        callResource: input => request.readChild(metadata, input)});
      return {evidence: {observationJson: '{}'}, observationCid: 'original-observation'};
    }});
  const quotes = [], quantityTokens = new Set();
  const quantity = (retained, execution) => {
    const token = Object.freeze({retained, execution});quantityTokens.add(token);return token;
  };
  const moon = Object.freeze({
    clientProgramSerializationCapacityBytes(token) {
      assert(quantityTokens.has(token));return {_0:token.retained,_1:token.execution};
    },
    clientProgramRowSourceProviderCapacity: quantity,
    [wholeInput ? 'clientProgramRecheckSalesforceInputProjection'
      : 'clientProgramRecheckSalesforceRowProjection'](d, a, o, max) {
      assert.equal(this, moon);assert.equal(d, declaration);assert.equal(a, acquisition);assert.equal(o, observation);
      assert.equal(max, 4096);events.push(wholeInput ? 'input-plan' : 'plan');return ok(plan);
    }, [wholeInput ? 'clientProgramRecheckSalesforceRowProjection'
      : 'clientProgramRecheckSalesforceInputProjection']() {
      assert.fail('The original acquisition kind cannot select the other typed recheck');
    }, clientProgramSalesforceQueryPageValues(page) {
      assert.equal(page, query);events.push('values');return {_0: columns, _1: cells};
    }});
  const queryMoon = Object.freeze({
    salesforceReadProjectionScopeMatches(p) {assert.equal(p, plan);return true;},
    salesforceRecheckReadProjection(p, o) {assert.equal(p, plan);assert.equal(o, observation);return ok(undefined);},
    salesforceBeginQueryRead(p) {assert.equal(p, plan);events.push('begin');return ok(query);},
    salesforceQueryReadNextPath(q) {assert.equal(q, query);return ok(pages === 0 ? path : undefined);},
    salesforceQueryReadAcceptPage(q, actualPath, body) {
      assert.equal(q, query);assert.equal(actualPath, path);assert(chargeByBody.has(body));
      events.push('decode');return ok(query);
    }, salesforceQueryReadAcknowledgePage(page) {assert.equal(page, query);pages++;return ok(undefined);},
    salesforceQueryReadComplete(q) {assert.equal(q, query);return pages === 1;},
    salesforceQueryReadRowCount(q) {assert.equal(q, query);return 1;},
    salesforceQueryPageResponseSha256() {return 'original-digest';},
    salesforceQueryPageRowCount() {return 1;},
    salesforceQueryReadInterrupt(q) {assert.equal(q, query);events.push('interrupt');},
  });
  const originalBinding = Object.freeze({credential: boundCredential, close() {closes++;return 'closed';}});
  const originalSite = Object.freeze({site, referenceCurrent() {return true;},
    authorizationPurpose(original) {assert.equal(original, root);return {kind: 'read'};},
    bindRunAcquisition(original) {assert.equal(original, root);events.push('bind');return originalBinding;},
    readChildCredential(binding, original) {
      assert.equal(binding, originalBinding);assert(originals.has(original));return boundCredential;
    }, async callResource(input) {
      assert.equal(this, site);assert([...originals].some(original => original.grant === input.grant));
      await input.currentBeforeSend();
      const selected = [...input.operations.keys()][0], isQuery = selected === operation;
      events.push(isQuery ? 'query-response' : 'describe-response');
      const response = Object.freeze({accepted: !isQuery || !rejected, statusCode: isQuery && rejected ? 503 : 200,
        body: Buffer.from(isQuery ? 'query bytes' : 'metadata bytes'), useCid: 'original-use'});
      input.responseCustody.retain(response);return response;
    }});
  const limits = Object.freeze({maxBytes: 1024, maxNodes: 100, maxDepth: 8, maxRows: 2,
    maxLocatorUnits: 1024, maxPages: 1, maxTotalRows: 2});
  const responseCapacity = Object.freeze({});
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite, assertCurrent() {},
    maxResponses: 3, maxResponseBytes: 1024,
    prepareReadSequence(input) {
      assert.equal(input.preparedRead, preparedRead);assert.equal(input.originalAuthorization, root);
      assert.deepEqual(events, []);
      return prepareSalesforceSourceReadSequence({moon, queryMoon, site, declaration,
        preparedRead: input.preparedRead, originalAuthorization: input.originalAuthorization,
        recover(_evidence, run) {assert.equal(run, 'original-run');events.push('recover');return observation;}, limits,
        ...(currentBacking ? {currentResponseCapacity(input) {
          assert(chargeByBody.has(input.body));
          assert.equal(input.receivedBytes, [...chargeByBody.keys()].reduce((sum, body) => sum + BigInt(body.byteLength), 0n));
          assert.equal(input.responseCount, chargeByBody.size);
          if (input.path === path) assert.equal(input.read, query);
          else assert.equal(input.read, undefined);
          quotes.push(input);events.push('current-quote');
          return quantity(4096n + input.receivedBytes, input.read === query ? 8192n : 16384n);
        }} : {}),
        ...(responseBacking ? {responseCapacity(bytes) {
          assert.equal(bytes,Buffer.byteLength('metadata bytes'));events.push('response-quote');return responseCapacity;
        }} : {})});
    }});
  const reader = factory.prepare(Object.freeze({originalAuthorization: root, preparedRead, columns,
    verifyRead() {}, authorizationFor() {return {...root, useId: 'original-query-0'};},
    authorizeReadChild(_operation, _index, _occurrence, supplied) {return supplied;},
    chargePage(body) {const charge = Object.freeze({});charges++;chargeByBody.set(body, charge);events.push('charge');return charge;},
    consumeObservation(charge) {assert([...chargeByBody.values()].includes(charge));events.push('observation');},
    consumeValues(names, rows, {charge}) {
      assert.equal(names, columns);assert.equal(rows, cells);assert([...chargeByBody.values()].includes(charge));
      consumed++;events.push('consume');if (consumeFailure) throw undefined;return rows.length;
    }}), undefined, currentBacking ? capacity => {
      assert(quantityTokens.has(capacity));
      assert.equal(capacity.execution,16384n);events.push('current-grow');
    } : responseBacking ? capacity => {
      assert.equal(capacity,responseCapacity);events.push('response-grow');
    } : undefined);
  return {reader, factory, events, quotes, counts: () => ({charges, consumed, closes, pages})};
}

test('Salesforce response backing quotes its largest original body once before both metadata and typed query consumers', async () => {
  const f=managedSourceFixture({responseBacking:true});
  await f.reader.read();
  assert.equal(f.events.filter(v=>v==='response-quote').length,1);
  assert.equal(f.events.filter(v=>v==='response-grow').length,3);
  assert(f.events.indexOf('charge')<f.events.indexOf('response-quote'));
  assert(f.events.indexOf('response-grow')<f.events.indexOf('recover'));
  assert(f.events.lastIndexOf('response-grow')<f.events.indexOf('decode'));
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);
});

test('Salesforce managed source joins two original describes and typed query on the same Reader', async () => {
  const f = managedSourceFixture();assert.deepEqual(f.events, []);
  assert.deepEqual(await f.reader.read(), {pages: 3, rowCount: 1});
  assert.deepEqual(f.events, ['bind', 'describe-response', 'charge', 'recover', 'observation', 'plan',
    'describe-response', 'charge', 'recover', 'observation', 'begin', 'query-response', 'charge', 'decode', 'values', 'consume']);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 1, closes: 1, pages: 1});
});

test('Salesforce managed source charges a rejected query once and keeps its original refusal', async () => {
  const f = managedSourceFixture({rejected: true});
  await assert.rejects(f.reader.read(), {code: 'SalesforceQueryResourceRejected'});
  assert(!f.events.includes('decode'));assert.equal(f.events.at(-1), 'interrupt');
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 0, closes: 1, pages: 0});
});

test('Salesforce managed source preserves thrown undefined without replaying a typed page', async () => {
  const f = managedSourceFixture({consumeFailure: true});let caught = false;
  try {await f.reader.read();} catch (cause) {caught = true;assert.equal(cause, undefined);}
  assert.equal(caught, true);assert.equal(f.events.at(-1), 'interrupt');
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 1, closes: 1, pages: 0});
});

test('Salesforce managed child refuses a copied-scope field substitution before the Reader', () => {
  const original = Object.freeze({grant: {}, scope: Object.freeze({operation, expiresUnixMilliseconds: 1n})});
  assert.throws(() => readSalesforceSourceChild({readChild: forbidden}, original,
    {grant: original.grant, scope: {...original.scope, expiresUnixMilliseconds: 2n},
      operations: new Map([[operation, {method: 'GET', path}]]), useId: 'original'}),
  {code: 'ForeignSalesforceSourceReadChild'});
});

for (const mode of ['raw', 'managed']) {
  test(`Salesforce ${mode} query preserves accounting failure and interrupts the original read`, async () => {
    const originalError = new Error('Original accounting refusal');
    const f = fixture(mode, () => { throw originalError; });
    await assert.rejects(f.run(), error => error === originalError);
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'interrupt']);
  });

  test(`Salesforce ${mode} query awaits pending accounting without upgrading the original rejection`, async () => {
    let entered, release;
    const started = new Promise(resolve => { entered = resolve; });
    const pending = new Promise(resolve => { release = resolve; });
    const f = fixture(mode, async ({response}) => {
      response.accepted = true;
      entered();
      await pending;
    });
    let settled = false;
    const rejected = assert.rejects(f.run(), error => error.code === 'SalesforceQueryResourceRejected')
      .finally(() => { settled = true; });
    try {
      await started;
      assert.equal(settled, false);
      assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge']);
    } finally {
      release();
    }
    await rejected;
    assert.deepEqual(f.events, ['current', 'begin', 'next', 'response', 'charge', 'charged', 'interrupt']);
  });
}


test('Salesforce complete-input sequence selects its original typed projection and retains Reader cleanup', async () => {
  const f = managedSourceFixture({wholeInput: true});
  assert.deepEqual(await f.reader.read(), {pages: 3, rowCount: 1});
  assert.equal(f.events.filter(value => value === 'input-plan').length, 1);
  assert.equal(f.events.includes('plan'), false);
  assert.deepEqual(f.events, ['bind', 'describe-response', 'charge', 'recover', 'observation', 'input-plan',
    'describe-response', 'charge', 'recover', 'observation', 'begin', 'query-response', 'charge', 'decode', 'values', 'consume']);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {charges: 3, consumed: 1, closes: 1, pages: 1});
});


test('Salesforce current constructor receives the original body and query with exact raw-prefix counters', async () => {
  const f=managedSourceFixture({currentBacking:true});
  assert.deepEqual(await f.reader.read(),{pages:3,rowCount:1});
  assert.deepEqual(f.quotes.map(value=>value.metadataBytes),[14,14,14]);
  assert.deepEqual(f.quotes.map(value=>value.receivedBytes),[14n,28n,39n]);
  assert.deepEqual(f.quotes.map(value=>value.responseCount),[1,2,3]);
  assert.equal(f.events.filter(value=>value==='current-grow').length,3);
  assert(f.events.indexOf('current-grow')<f.events.indexOf('recover'));
  assert(f.events.lastIndexOf('current-grow')<f.events.indexOf('decode'));
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);
});

import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import test from 'node:test';
import * as commonMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {openSalesforceEffectSiteFixture} from './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const current = () => ({assertCurrent() {}, async observeCurrent() {}});
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
}
async function fixture(t, options = {}) {
  let secret = 'test-only-secret', resolutions = 0;
  const setup = await openSalesforceEffectSiteFixture(t, {commonMoon, salesforceMoon,
    runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    runAcquisitionLimits: {maxBindings: 2, maxSecretBytes: 64},
    resolveSecret: async () => { resolutions++; return secret; }, ...options});
  const initialRequests = setup.seen.length;
  const invoke = (borrow, useId, write = false) => callHttpsCredentialResource({
    ...borrow.credential, ...borrow.authorization, useId,
    operations: new Map([[write ? 'salesforce:record:update' : 'salesforce:record:observe',
      {method: write ? 'PATCH' : 'GET',
        path: '/services/data/v62.0/sobjects/Test_Record__c/001000000000001',
        ...(write ? {body: '{"Name":"approved"}'} : {})}]]),
    maxRequestBytes: 1024, maxResponseBytes: 4096, retainRunResponseOriginal: true});
  return {setup, invoke, initialRequests,
    resolutions: () => resolutions, rotate: value => { secret = value; }};
}

test('Salesforce Site binds original Account read and write grants to the same private material', async t => {
  const f = await fixture(t);
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, current());
  const read = await f.invoke(acquired, 'same-original-read');
  const write = acquired.forAuthorization(f.setup.write, current());
  assert.equal(acquired.authorization, f.setup.observe);
  assert.equal(write.authorization, f.setup.write);
  assert.equal(acquired.credential.binding, write.credential.binding);
  const result = await f.invoke(write, 'same-original-write', true);
  assert.equal(read.statusCode, 200);
  assert.equal(result.statusCode, 204);
  const journal = f.setup.journal;
  assert.equal(journal.inspect(read.useCid).outcome, 'succeeded');
  assert.equal(journal.inspect(result.useCid).outcome, 'succeeded');
  assert.notEqual(read.useCid, result.useCid);
  withHttpsCredentialRunResponseOriginal(read, acquired.credential.control, journal, facts => {
    assert.equal(facts.scope, f.setup.observe.scope);
    assert.equal(facts.method, 'GET');
  });
  withHttpsCredentialRunResponseOriginal(result, write.credential.control, journal, facts => {
    assert.equal(facts.scope, f.setup.write.scope);
    assert.equal(facts.method, 'PATCH');
  });
  assert.equal(f.setup.seen.length - f.initialRequests, 2);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site refuses copied grants and a foreign acquisition without replacing its original', async t => {
  const f = await fixture(t);
  assert.throws(() => f.setup.site.bindRecordAcquisition({...f.setup.observe}, current()),
    {code: 'ForeignSalesforceRecordAcquisitionAuthorization'});
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, current());
  assert.throws(() => acquired.forAuthorization({...f.setup.write}, current()),
    {code: 'ForeignSalesforceRecordAcquisitionAuthorization'});
  const decision = await f.setup.authorization.authorize('acquisition', {
    connection: f.setup.site.connection, resource: 'Test_Record__c', operation: 'read'},
  {subjectCid: cid('9')});
  const foreign = f.setup.site.issueGrant({operation: 'salesforce:record:observe',
    decision, resource: 'Test_Record__c', runInvocationCid: cid('9'),
    dispatchRequestCid: cid('2'), taskAttempt: 2, maxUses: 2});
  assert.throws(() => acquired.forAuthorization(foreign, current()),
    {code: 'ForeignSalesforceRecordAcquisitionAuthorization'});
  assert.equal(f.setup.seen.length, f.initialRequests);
  const result = await f.invoke(acquired, 'still-original-read');
  assert.equal(result.statusCode, 200);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site rechecks the original Account after an awaited Host current observation', async t => {
  const f = await fixture(t);
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, {
    assertCurrent() {}, async observeCurrent() { f.setup.authorization.close(); },
  });
  let failure;
  await assert.rejects(f.invoke(acquired, 'closed-account-before-send'), cause => {
    failure = cause; return typeof cause?.code === 'string';
  });
  assert.throws(() => acquired.forAuthorization(f.setup.write, current()), cause => cause === failure);
  assert.equal(f.setup.seen.length, f.initialRequests);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site refuses changed original profile and stays refused after byte restoration', async t => {
  const f = await fixture(t);
  const original = await readFile(f.setup.profilePath);
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, {
    assertCurrent() {}, async observeCurrent() {
      const changed = JSON.parse(original);
      changed.siteGeneration++;
      await writeFile(f.setup.profilePath, JSON.stringify(changed));
    },
  });
  let failure;
  try {
    await assert.rejects(f.invoke(acquired, 'changed-profile-before-send'), cause => {
      failure = cause; return cause.code === 'SalesforceRecordAcquisitionProfileChanged';
    });
  } finally { await writeFile(f.setup.profilePath, original); }
  assert.throws(() => acquired.forAuthorization(f.setup.write, current()), cause => cause === failure);
  assert.equal(f.setup.seen.length, f.initialRequests);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site cannot send replacement material after its original read', async t => {
  const f = await fixture(t);
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, current());
  await f.invoke(acquired, 'before-material-rotation');
  const write = acquired.forAuthorization(f.setup.write, current());
  f.rotate('different-account-material');
  await assert.rejects(f.invoke(write, 'after-material-rotation', true),
    {code: 'RemoteCredentialBindingChanged'});
  const resolutions = f.resolutions();
  await assert.rejects(f.invoke(write, 'no-material-reprobe', true),
    {code: 'RemoteCredentialBindingChanged'});
  assert.equal(f.resolutions(), resolutions);
  assert.equal(f.setup.seen.length - f.initialRequests, 1);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site holds the original Journal while a closing borrow is awaiting currentness', async t => {
  const f = await fixture(t);
  const entered = deferred(), released = deferred();
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, {
    assertCurrent() {}, async observeCurrent() { entered.resolve(); await released.promise; },
  });
  const result = f.invoke(acquired, 'held-current-observation');
  try {
    await entered.promise;
    assert.equal(acquired.close(), 'pending');
    assert.throws(() => f.setup.site.close(), {code: 'RowSourceCredentialAcquisitionCleanupPending'});
    assert.equal(f.setup.site.cleanupPending(), true);
  } finally { released.resolve(); }
  await assert.rejects(result);
  assert.equal(f.setup.seen.length, f.initialRequests);
  assert.equal(acquired.close(), 'closed');
  f.setup.site.close();
  assert.equal(f.setup.site.cleanupPending(), false);
});

test('Salesforce Site keeps a lost write reply Unknown without a second physical send', async t => {
  const f = await fixture(t, {loseWriteReplyOnce: true});
  const acquired = f.setup.site.bindRecordAcquisition(f.setup.observe, current());
  await f.invoke(acquired, 'before-lost-write-reply');
  const write = acquired.forAuthorization(f.setup.write, current());
  await assert.rejects(f.invoke(write, 'original-lost-write-reply', true));
  const uses = f.setup.journal.recover();
  assert.equal(uses.at(-1).outcome, 'unknown');
  const count = f.setup.seen.length;
  await assert.rejects(f.invoke(write, 'original-lost-write-reply', true));
  assert.equal(f.setup.seen.length, count);
  assert.equal(count - f.initialRequests, 2);
  assert.equal(acquired.close(), 'closed');
});

test('Salesforce Site does not infer acquisition capacity from its issued grants', async t => {
  const f = await fixture(t, {runAcquisitionLimits: undefined});
  assert.throws(() => f.setup.site.bindRecordAcquisition(f.setup.observe, current()),
    {code: 'SalesforceRecordAcquisitionUnavailable'});
  assert.equal(f.setup.seen.length, f.initialRequests);
});

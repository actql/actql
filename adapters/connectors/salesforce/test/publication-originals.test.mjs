import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import test from 'node:test';
import * as commonMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {describeSalesforceGeneration, restoreSalesforceGeneration,
  observeSalesforcePublicationOriginals as observe,
  withSalesforcePublicationOriginals as originals} from '../host/salesforce-publication.mjs';
import {openSalesforceEffectSiteFixture} from './salesforce-effect-site.fixture.mjs';

const cid = x => 'sha256:' + x.repeat(64);
const digest = b => createHash('sha256').update(b).digest('hex');
async function fixture(t) {
  const f = await openSalesforceEffectSiteFixture(t, {commonMoon, salesforceMoon,
    runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const describe = async (options = {}) => {
    const result = await describeSalesforceGeneration({site: f.site,
      connectorId: 'crm-main', resources: ['Test_Record__c'],
      retainPublicationOriginals: true, ...options});
    return {...result, body: JSON.stringify(result.generation)};
  };
  return {...f, describe};
}

test('actual Salesforce publication retains its same Describe response claim and original declaration', async t => {
  const f = await fixture(t), before = f.seen.length, x = await f.describe();
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}),
    {code: 'SalesforcePublicationCurrentUnobserved'});
  await observe(f.site, x.declared, x.body);
  const view = originals(f.site, x.declared, x.body, value => value);
  assert(Object.isFrozen(view));
  assert.equal(view.site, f.site); assert.equal(view.declared, x.declared);
  assert.equal(view.declaration, x.declared.declaration);
  assert.equal(view.generationText, x.body);
  assert.equal(view.generationCid, 'sha256:' + digest(Buffer.from(x.body)));
  assert.equal(view.control, f.credential.control); assert.equal(view.journal, f.journal);
  assert.deepEqual(JSON.parse(view.declarationWire).catalog_cid, x.declared.catalog_cid);
  assert.equal(view.observation, x.declared.observed.observation);
  assert.equal(view.evidence, x.declared.evidence);
  assert.equal(view.operations.length, 1);
  const op = view.operations[0];
  assert(Object.isFrozen(op)); assert.equal(op.name, 'Test_Record__c');
  assert.equal(op.method, 'GET'); assert.equal(op.path, '/services/data/v62.0/sobjects/Test_Record__c/describe');
  assert.equal(op.requestBodyBytes, 0); assert.equal(op.scope.operation, 'salesforce:catalog:describe');
  assert.equal(view.control.useIdentity(op.use), op.response.useCid);
  assert.equal(view.control.identity(op.grant), f.journal.inspect(op.response.useCid).grantCid);
  assert.equal(f.journal.inspect(op.response.useCid).outcome, 'succeeded');
  assert.equal(op.response.body.toString('base64'), view.evidence.describeBodyBase64[0]);
  assert.equal(digest(op.response.body), op.responseSha256);
  assert.equal(Object.hasOwn(op, 'secret'), false);
  assert.equal(f.seen.length, before + 1, 'Current observations and receiver never rediscover metadata');
});

test('default generation behavior retains exact bytes but cannot issue live publication originals', async t => {
  const f = await fixture(t), x = await f.describe({retainPublicationOriginals: false});
  assert.equal(JSON.stringify(x.generation), x.body);
  await assert.rejects(observe(f.site, x.declared, x.body), {code: 'SalesforcePublicationOriginalUnavailable'});
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}),
    {code: 'SalesforcePublicationOriginalUnavailable'});
});

test('copies mixed Sites and modified generation text cannot acquire original publication correspondence', async t => {
  const f = await fixture(t), other = await fixture(t), x = await f.describe();
  const before = f.seen.length;
  for (const [site, declared, body] of [[{...f.site}, x.declared, x.body],
    [other.site, x.declared, x.body], [f.site, {...x.declared}, x.body],
    [f.site, x.declared, x.body + ' ']]) {
    await assert.rejects(observe(site, declared, body), {code: 'SalesforcePublicationOriginalUnavailable'});
    assert.throws(() => originals(site, declared, body, () => {}), {code: 'SalesforcePublicationOriginalUnavailable'});
  }
  assert.equal(f.seen.length, before);
});

test('restoring exact saved generation evidence never registers another live Describe result', async t => {
  const f = await fixture(t), x = await f.describe();
  const before = f.seen.length;
  const restored = restoreSalesforceGeneration({site: f.site,
    generation: JSON.parse(x.body), connectorId: 'crm-main', resources: ['Test_Record__c']});
  assert.equal(restored.declared.catalog_cid, x.declared.catalog_cid);
  await assert.rejects(observe(f.site, restored.declared, x.body), {code: 'SalesforcePublicationOriginalUnavailable'});
  assert.throws(() => originals(f.site, restored.declared, x.body, () => {}),
    {code: 'SalesforcePublicationOriginalUnavailable'});
  assert.equal(f.seen.length, before);
});

test('an observed original Site profile change permanently refuses this live publication', async t => {
  const f = await fixture(t), x = await f.describe();
  const body = await readFile(f.profilePath, 'utf8'), changed = JSON.parse(body);
  changed.siteGeneration++;
  await writeFile(f.profilePath, JSON.stringify(changed));
  let originalFailure;
  await assert.rejects(observe(f.site, x.declared, x.body), cause => {
    originalFailure = cause; return cause.code === 'SalesforcePublicationSiteChanged';
  });
  await writeFile(f.profilePath, body);
  await assert.rejects(observe(f.site, x.declared, x.body), cause => cause === originalFailure);
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}), cause => cause === originalFailure);
});

test('receiver rechecks the same Account decision and closed Site without reopening either', async t => {
  for (const close of [site => site.authorization.close(), site => site.close()]) {
    const f = await fixture(t), x = await f.describe();
    await observe(f.site, x.declared, x.body); const before = f.seen.length;
    close(f.site);
    assert.throws(() => originals(f.site, x.declared, x.body, () => {}));
    await assert.rejects(observe(f.site, x.declared, x.body));
    assert.equal(f.seen.length, before);
  }
});

test('the original signal can stop a prepared live receiver with no replacement metadata call', async t => {
  const f = await fixture(t), stop = new AbortController(), x = await f.describe({signal: stop.signal});
  await observe(f.site, x.declared, x.body); const before = f.seen.length;
  const failure = new Error('OriginalPublicationCancelled'); stop.abort(failure);
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}), cause => cause === failure);
  await assert.rejects(observe(f.site, x.declared, x.body), cause => cause === failure);
  assert.equal(f.seen.length, before);
});

test('mutating then restoring the same raw response cannot restore original-response membership', async t => {
  const f = await fixture(t), x = await f.describe();
  await observe(f.site, x.declared, x.body);
  const op = originals(f.site, x.declared, x.body, value => value.operations[0]);
  const first = op.response.body[0]; op.response.body[0] ^= 1;
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}), {code: 'RemoteCredentialRunResponseChanged'});
  op.response.body[0] = first;
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}), {code: 'RemoteCredentialRunResponseChanged'});
  assert.equal(f.journal.inspect(op.response.useCid).outcome, 'succeeded');
});

test('synchronous consumer failure and async refusal do not reclassify confirmed physical outcomes', async t => {
  const f = await fixture(t), x = await f.describe();
  await observe(f.site, x.declared, x.body);
  const op = originals(f.site, x.declared, x.body, v => v.operations[0]), before = f.seen.length;
  const failure = new Error('OriginalFinisherFailed');
  assert.throws(() => originals(f.site, x.declared, x.body, () => { throw failure; }), cause => cause === failure);
  assert.throws(() => originals(f.site, x.declared, x.body, () => Promise.resolve()),
    {code: 'InvalidSalesforcePublicationConsumer'});
  assert.equal(f.journal.inspect(op.response.useCid).outcome, 'succeeded');
  assert.equal(f.seen.length, before);
});

test('pending current observation admits neither a competing observation nor a premature receiver', async t => {
  const f = await fixture(t), x = await f.describe();
  const pending = observe(f.site, x.declared, x.body);
  await assert.rejects(observe(f.site, x.declared, x.body), {code: 'SalesforcePublicationObservationPending'});
  assert.throws(() => originals(f.site, x.declared, x.body, () => {}),
    {code: 'SalesforcePublicationCurrentUnobserved'});
  await pending;
  originals(f.site, x.declared, x.body, () => {});
});


test('a lost original Describe reply remains Unknown with no live capture or automatic resend', async t => {
  const f = await fixture(t), before = f.seen.length;
  f.loseNextDescribeReply();
  await assert.rejects(f.describe(), {code: 'SalesforceCatalogRefreshInterrupted'});
  const unknown = f.journal.recover().filter(row => row.outcome === 'unknown');
  assert.equal(unknown.length, 1);
  assert.equal(f.seen.length, before + 1);
  // The older equal Catalog cannot stand in for the lost live observation.
  assert.throws(() => originals(f.site, f.declared, '{}', () => {}),
    {code: 'SalesforcePublicationOriginalUnavailable'});
  assert.equal(f.journal.inspect(unknown[0].useCid).outcome, 'unknown');
  assert.equal(f.seen.length, before + 1);
});

test('an actual rejected Describe cannot issue live publication originals from the previous Catalog', async t => {
  const f = await fixture(t), before = f.seen.length;
  f.setDescribeStatus(503);
  await assert.rejects(f.describe());
  assert.equal(f.seen.length, before + 1);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 0);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'failed').length, 1);
  assert.throws(() => originals(f.site, f.declared, '{}', () => {}),
    {code: 'SalesforcePublicationOriginalUnavailable'});
});

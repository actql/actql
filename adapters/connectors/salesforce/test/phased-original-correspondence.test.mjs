import assert from 'node:assert/strict';
import test from 'node:test';
import * as commonMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {openSalesforceEffectSiteFixture} from './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const fixture = t => openSalesforceEffectSiteFixture(t, {
  commonMoon, salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
});
const input = f => ({connectorId: 'crm-main', resources: ['Test_Record__c'],
  evidence: f.declared.evidence, observationCid: f.declared.observationCid,
  catalogCid: f.declared.catalog_cid});

test('Salesforce direct restored caller keeps full original declaration without a staged context', async t => {
  const f = await fixture(t), requests = f.seen.length;
  const restored = f.site.restoreDeclaration(input(f));
  assert.equal(restored.catalog, f.declared.catalog);
  assert.equal(restored.catalog_cid, f.declared.catalog_cid);
  assert.deepEqual(restored.contracts, f.declared.contracts);
  assert.deepEqual(restored.source_views, f.declared.source_views);
  assert.equal(f.seen.length, requests);
});

test('Salesforce staged caller cannot replace either actual original constructor output', async t => {
  const f = await fixture(t);
  for (const replace of [1, 2]) {
    let calls = 0;
    const construction = {prepareNativeInput(projection) {
      calls++;
      if (calls === replace) return Object.freeze({});
      return projection.project();
    }};
    assert.throws(() => f.site.restoreDeclaration({...input(f), construction}),
      {code: 'InvalidSalesforceDeclaration'});
    assert.equal(calls, replace);
  }
});

test('Salesforce staged caller retains actual Site lifetime and one-shot producer boundaries', async t => {
  const f = await fixture(t);
  const repeated = {prepareNativeInput(projection) {
    projection.project(); return projection.project();
  }};
  assert.throws(() => f.site.restoreDeclaration({...input(f), construction: repeated}),
    {code: 'InvalidSalesforceDeclaration'});
  const closed = {prepareNativeInput(projection) {
    const value = projection.project(); f.site.close(); return value;
  }};
  assert.throws(() => f.site.restoreDeclaration({...input(f), construction: closed}),
    {code: 'SalesforceSiteClosed'});
});

test('Salesforce phased dimensions never replace original Site binding or final Catalog identity checks', async t => {
  const f = await fixture(t);
  let calls = 0;
  const construction = {prepareNativeInput(projection) {calls++; return projection.project();}};
  const evidence = f.declared.evidence;
  const observation = JSON.parse(evidence.observationJson);
  observation.binding.principal = 'another-operator';
  assert.throws(() => f.site.restoreDeclaration({...input(f), construction,
    evidence: {...evidence, observationJson: JSON.stringify(observation)}}),
  {code: 'ForeignSalesforceDeclaration'});
  assert.equal(calls, 0, 'original binding refusal precedes both constructors');
  assert.throws(() => f.site.restoreDeclaration({...input(f), construction, catalogCid: cid('0')}),
    {code: 'ForeignSalesforceDeclaration'});
  assert.equal(calls, 2, 'full recovery and generation precede final Catalog mismatch');
});

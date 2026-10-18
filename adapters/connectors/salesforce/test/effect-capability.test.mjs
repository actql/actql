import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {issueSalesforceEffectCapability, inspectSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';
import {fixtureWrites, openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';
import {capabilityRequest, capabilitySite} from './effect-capability.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

test('Salesforce capability requires the exact execution Mapping before any use',
  async t => {
    const {site, options} = await capabilitySite(t);
    const other = await openSalesforceEffectSiteFixture(t, {
      commonMoon: moon, salesforceMoon, runInvocationCid: cid('b'),
      dispatchRequestCid: cid('c'), writeOperation: 'create',
      orgId: '00D000000000002EAA'});
    // A later declaration that no longer allows creating Name cannot even
    // prepare this write's Mapping.
    site.setNameCreateable(false);
    const narrowed = await site.refreshDeclaration();
    site.setNameCreateable(true);
    assert.equal(narrowed.writables[0].create_fields.includes('Name'), false);
    assert.throws(() => site.executionMapping(fixtureWrites.create,
      narrowed.declaration), {code: 'MoonBitHostFailure'});
    // The schema changes under the same Site binding: a request projected
    // from the new describe no longer matches what was declared.
    site.setNameUpdateable(false);
    const changed = await site.refreshCatalog();
    const drifted = capabilityRequest(site, changed.observation);
    site.setNameUpdateable(true);
    const uses = site.journal.recover().length;
    const sent = site.seen.length;
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: undefined}), {code: 'InvalidSalesforceEffectCapability'});
    // Same connection id and schema, another org: a foreign Mapping.
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: other.executionMapping(fixtureWrites.create).mapping}),
    {code: 'MoonBitHostFailure'});
    // Another write's Mapping: an update of Name is not this create.
    assert.throws(() => issueSalesforceEffectCapability({...options,
      mapping: site.executionMapping(fixtureWrites.update).mapping}),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      requests: [drifted], currentObservation: changed.observation}),
    {code: 'MoonBitHostFailure'});
    // Refused before any credential use or request.
    assert.equal(site.journal.recover().length, uses);
    assert.equal(site.seen.length, sent);
    assert.ok(issueSalesforceEffectCapability(options).identity);
  });

test('Salesforce capability requires current signed authority without a use',
  async t => {
    const {site, request, options} = await capabilitySite(t);
    const uses = site.journal.recover().length;
    const sent = site.seen.length;
    const capability = issueSalesforceEffectCapability(options);
    assert.equal(inspectSalesforceEffectCapability(capability, [request]).route, 0);
    assert.equal(JSON.parse(capability.wire).binding.runtime_bundle_cid, cid('a'));
    assert.throws(() => inspectSalesforceEffectCapability({...capability},
      [request]), {code: 'InvalidSalesforceEffectCapability'});
    assert.throws(() => inspectSalesforceEffectCapability(capability,
      [request], {collection: true}), {code: 'InvalidSalesforceEffectCapability'});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      credential: {...site.credential, now: () => 2_000_000_000_000}}));
    for (const changed of [{namespaceId: 'foreign'}, {siteGeneration: 5},
      {runtimeBundleCid: cid('f')}]) {
      assert.throws(() => issueSalesforceEffectCapability({...options,
        authorization: {...site.write, scope: {...site.write.scope, ...changed}}}));
    }
    const unsigned = site.credential.control.prepare({...site.write.scope,
      dispatchRequestCid: cid('f')});
    assert.throws(() => issueSalesforceEffectCapability({...options,
      authorization: {...site.write, grant: unsigned}}),
    {code: 'RemoteCredentialGrantMissing'});
    assert.equal(site.journal.recover().length, uses);
    assert.equal(site.seen.length, sent);
    const refreshed = await site.refreshCatalog();
    assert.equal(issueSalesforceEffectCapability({...options,
      currentObservation: refreshed.observation}).identity, capability.identity);
    site.setNameUpdateable(false);
    const changed = await site.refreshCatalog();
    assert.throws(() => inspectSalesforceEffectCapability(capability, [request],
      {currentObservation: changed.observation}));
    const beforeRevoke = site.journal.recover().length;
    site.journal.revoke(site.credential.control.identity(site.write.grant));
    assert.throws(() => inspectSalesforceEffectCapability(capability, [request]));
    assert.equal(site.journal.recover().length, beforeRevoke);
  });


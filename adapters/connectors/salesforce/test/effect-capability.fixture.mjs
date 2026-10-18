import * as moon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {fixtureWrites, openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

// One create request of the fixture Site, projected from `observation`.
export function capabilityRequest(site, observation = site.catalog.observation) {
  const binding = JSON.parse(
    salesforceMoon.salesforceCatalogObservationJson(observation)).binding;
  const projection = checked(salesforceMoon.salesforcePrepareWriteProjection(
    observation, binding.namespace_id, binding.principal, binding.environment,
    binding.connection_revision, binding.org_id, binding.site_key,
    binding.site_generation, binding.connector_registration,
    binding.connector_revision, binding.resource_origin,
    binding.run_invocation_cid, binding.dispatch_request_cid,
    binding.sync_occurrence,
    'Test_Record__c', 0, '', ['Name', 'External_Key__c'], 2));
  const body = checked(salesforceMoon.salesforcePrepareWriteBody(projection,
    Buffer.from('{"Name":"value","External_Key__c":"value"}'), 1024, 32, 5));
  return checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
    body, 'v62.0', 0, '', 0, 256, 128, 1024));
}

export async function capabilitySite(t) {
  const site = await openSalesforceEffectSiteFixture(t, {
    commonMoon: moon, salesforceMoon, runInvocationCid: cid('b'),
    dispatchRequestCid: cid('c'), writeOperation: 'create',
  });
  const request = capabilityRequest(site);
  const options = {moon: salesforceMoon, requests: [request],
    currentObservation: site.catalog.observation,
    authorization: site.write, credential: site.credential,
    mapping: site.executionMapping(fixtureWrites.create).mapping,
    maxRows: 2, maxBytes: 20000};
  return {site, request, options};
}


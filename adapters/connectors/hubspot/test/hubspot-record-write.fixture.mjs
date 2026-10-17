// Shared original physical fixture; existing defaults and raw assertions are unchanged.
import assert from 'node:assert/strict';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {sendRawHubSpotRecordBatch, projectHubSpotRecordWriteObservation,
  HUBSPOT_BATCH_WRITE_OPERATIONS, HubSpotRecordWriteFailure} from '../site/hubspot-record-write.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false,
    modificationMetadata: {readOnlyValue: false}},
  {name: 'external_key', type: 'string', fieldType: 'text', hasUniqueValue: true,
    calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
export const recordWriteProperties = JSON.stringify(metadata);
const bounds = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const limits = Object.freeze({maxResponseBytes: 4096, maxRequestBytes: 4096,
  maxNodes: 1000, maxDepth: 20, maxProperties: 10, maxNameUnits: 100, maxRows: 100});
export const recordWriteResultBody = (kind = 'update') => JSON.stringify({status: 'COMPLETE', results: [{
  id: '9007199254740993', archived: false, properties: {},
  ...(kind === 'upsert' ? {new: false} : {})}]});

export async function recordWriteFixture(t, kind = 'update', accountOperations = ['effect', 'read'],
  {requestFactory, metadataOverride} = {}) {
  const properties = JSON.stringify(metadataOverride ?? metadata);
  const f = await accountFixture(t, {resources: ['account', 'companies'], accountOperations});
  const catalog = checked(moon.hubspotProjectProperties(Buffer.from(properties), 'companies',
    4096, 1000, 20, 10, 100));
  const body = checked(moon.hubspotPrepareWriteBody(catalog, ['amount'],
    Buffer.from('{"amount":"9007199254740993.0100000000"}'), ...bounds));
  const target = kind === 'create' ? undefined : checked(moon.hubspotPrepareRecordTarget(
    catalog, kind === 'update' ? 'id' : 'external_key',
    Buffer.from(kind === 'update' ? '"9007199254740993"' : '"original-key"'), ...bounds));
  const input = kind === 'create' ? moon.hubspotCreateRecordWriteInput(body, 'original-write')
    : moon.hubspotTargetedRecordWriteInput(body, target, 'original-write');
  const request = requestFactory === undefined ? checked(moon.hubspotPrepareRecordBatch(catalog,
    {create: 0, update: 1, upsert: 2}[kind], {create: '', update: 'id', upsert: 'external_key'}[kind],
    [input], 100, 100, 100, 4096, 1000, 20))
    : requestFactory({catalog, kind, body, target, input});
  const state = {properties, body: recordWriteResultBody(kind), status: kind === 'create' ? 201 : 200,
    writes: [], responseHook: undefined};
  f.state.onRequest = async (request, response) => {
    if (await state.responseHook?.(request, response)) return true;
    if (request.url === '/account-info/v3/details') return false;
    let reply;
    if (request.url === '/crm/v3/properties/companies') {
      assert.equal(request.method, 'GET'); reply = state.properties;
    } else {
      assert.equal(request.url, `/crm/v3/objects/companies/batch/${kind}`);
      assert.equal(request.method, 'POST');
      assert.equal(request.headers['content-type'], 'application/json');
      const chunks = []; for await (const chunk of request) chunks.push(chunk);
      state.writes.push(Buffer.concat(chunks).toString()); reply = state.body;
    }
    response.writeHead(request.url.endsWith(`/batch/${kind}`) ? state.status : 200,
      {'content-type': 'application/json'}); response.end(reply); return true;
  };
  const operation = HUBSPOT_BATCH_WRITE_OPERATIONS[kind];
  const grants = new Map();
  for (const selected of [HUBSPOT_PROPERTIES_READ_OPERATION, operation]) {
    const scope = Object.freeze({...f.scope, operation: selected});
    const grant = f.control.prepare(scope); f.journal.acceptGrant(f.sign(grant), f.control);
    grants.set(selected, {scope, grant});
  }
  const options = {moon, originalPortalId: '7', originalCatalog: catalog, request,
    initialAuthorization: f.options.authorization, credential: f.options.credential, limits,
    authorizationFor: ({operation, index}) => ({...grants.get(operation), useId: `write-${index}`}),
    current: selected => selected === operation
      ? f.current('companies', 'effect', 'effect_commit')
      : f.current(selected === HUBSPOT_ACCOUNT_DETAILS_OPERATION ? 'account' : 'companies'),
    chargeResponse: f.options.chargeResponse, consumeObservation: f.options.consumeObservation};
  return {...f, writeState: state, request, options,
    send: overrides => sendRawHubSpotRecordBatch({...options, ...overrides}),
    project: observation => projectHubSpotRecordWriteObservation({moon, request, observation, limits})};
}

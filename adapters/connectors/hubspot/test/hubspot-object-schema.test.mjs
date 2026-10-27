import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readHubSpotObjects, HUBSPOT_PROPERTIES_READ_OPERATION,
  HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {accountFixture} from './hubspot-account.fixture.mjs';

const properties = '{"results":[{"name":"amount","type":"number","fieldType":"number"},{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"a"},{"value":"b"}]}]}';
// Independently authored full Common field-map, not inferred from sample rows.
const expectedSchema = '{"amount":{"nullable":true,"precision":38,"scale":10,"type":"decimal"},"id":{"nullable":false,"type":"string"},"tags":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"}}';
const project = () => checked(provider.hubspotProjectProperties(Buffer.from(properties),
  'companies', 4096, 1000, 20, 10, 100));
const schema = original => checked(provider.hubspotObjectSchemaWire(original,
  ['tags', 'amount'], 3, 100, 4096, 100, 10));

test('actual provider schema restores through the original Common full relation declaration', () => {
  const original = project();
  assert.deepEqual(provider.hubspotPropertyCatalogNames(original), ['amount', 'tags']);
  assert.equal(provider.hubspotObjectRelationFactsWire(),
    '{"relation_keys":{"candidate_keys":[["id"]]}}');
  const wire = schema(original);
  assert.equal(wire, expectedSchema);
  const view = {resource: 'companies', resource_kind: 'object', schema_wire: wire,
    schema_cid: 'sha256:13fc10be1d9680b918191baa0c4c324da72be7479bd4dc6b8dc1ffa85db84b8b'};
  const restore = original => checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    'hubspot-fixture', 'hubspot', 'hubspot/0.1', JSON.stringify({views: [original]}), undefined));
  const declaration = restore(view);
  const admitted = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  assert.deepEqual(admitted.views[0].fields, ['amount', 'id', 'tags']);
  const carrier = admitted.contracts.map(JSON.parse).find(value => value.kind === 'carrier_schema');
  assert.deepEqual(carrier.body.fields, JSON.parse(expectedSchema));
  assert.throws(() => restore({...view, schema_cid: `sha256:${'0'.repeat(64)}`}),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => restore({...view,
    schema_wire: wire.replace('"precision":38', '"precision":37')}),
  {code: 'MoonBitHostFailure'});
});

test('projected schema admits actual bound HubSpot pages into the same accounted RowRun', async t => {
  const originalCatalog = project();
  const wire = schema(originalCatalog);
  assert.equal(wire, expectedSchema);
  const f = await accountFixture(t, {rowSchema: JSON.parse(wire), resources: ['account', 'companies']});
  const rows = [];
  f.state.onRequest = async (request, response) => {
    if (request.url === '/account-info/v3/details') return false;
    const body = request.url === '/crm/v3/properties/companies' ? properties
      : request.url.startsWith('/crm/v3/objects/companies?')
        ? '{"results":[{"id":"9007199254740993","archived":false,"properties":{"amount":"9007199254740993.01","tags":"a;b"}}]}'
        : assert.fail(`Unexpected original request ${request.url}`);
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(body);
    return true;
  };
  const grants = new Map();
  for (const operation of [HUBSPOT_PROPERTIES_READ_OPERATION, HUBSPOT_OBJECT_LIST_OPERATION]) {
    const scope = Object.freeze({...f.scope, operation, maxUses: 2});
    const grant = f.control.prepare(scope);
    f.journal.acceptGrant(f.sign(grant), f.control);
    grants.set(operation, {scope, grant});
  }
  const result = await readHubSpotObjects({moon: provider, originalCatalog,
    originalPortalId: '7', objectType: 'companies', properties: ['amount', 'tags'],
    initialAuthorization: f.options.authorization, credential: f.options.credential,
    authorizationFor: ({operation, index}) => ({...grants.get(operation), useId: `schema-read-${index}`}),
    current: operation => f.current(operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION ? 'account' : 'companies'),
    chargeResponse: f.options.chargeResponse, consumeObservation: f.options.consumeObservation,
    consumePage: (page, {charge}) => {f.row.page(page, charge); rows.push(...page);},
    limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20,
      maxProperties: 10, maxNameUnits: 100, maxPages: 2, maxRows: 2,
      maxRequests: 4, perPage: 1, maxColumns: 3, maxCursorUnits: 64,
      maxValueNodes: 100, maxValueTextBytes: 4096,
      maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10}});
  assert.equal(result.pages, 1);
  assert.equal(result.rowCount, 1);
  assert.equal(f.state.requests.length, 4);
  assert.equal(f.state.charges, 4);
  assert.equal(f.state.consumed, 3);
  assert.deepEqual(rows, [{id: '9007199254740993',
    amount: '9007199254740993.0100000000', tags: ['a', 'b']}]);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.observations.reduce((n, r) => n + BigInt(r.body.length), 0n));
  // Only the existing original Host completes/captures and retires the binding.
  f.row.finish();
  assert.equal(f.row.captureCount(), 1);
});

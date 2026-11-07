// Real initialization parent, Ledger, Common declaration and Native Mapping.
// The fixture supplies immutable input metadata only. No Site, Client, Run,
// provider I/O, physical acknowledgement or complete installation is claimed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../../../local-node/request-preparation-adapter.mjs';
import {createInstalledHostServices, retainInstalledHostServiceInstallation,
  beginInstalledSourceInitialization, finishInstalledSourceInitialization, retireInstalledSourceInitialization}
  from '../../../host-node/installed-host-services.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {prepareInstalledHubSpotUpdateMappings} from '../host/hubspot-effect-mappings.mjs';

const mappingLimits = Object.freeze({maxProperties: 10, maxFields: 4, maxNameBytes: 100,
  maxBytes: 4096, maxNodes: 1000, maxDepth: 20});
const writes = Object.freeze([Object.freeze({resource: 'companies', fields: Object.freeze(['name'])})]);
const body = Buffer.from(JSON.stringify({results: [
  {name: 'name', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
]}));
const runtimeCid = 'sha256:' + 'a'.repeat(64);

function fixture(common, native, baseEnvironmentWire, role = 'effect') {
  const state = {}, root = '/unopened-hubspot-mapping-parent-' + role;
  let pending = false, closed = false, finished = false;
  const current = () => assert.equal(closed, false);
  const parent = openHostInitializationPreparation(state, common,
    Object.freeze({root, purpose: 'actual original Mapping constructor controls'}), current, () => pending);
  const services = createInstalledHostServices({root, principalId: 'component', moon: common,
    initialPreparation: parent, assertCurrent: current});
  pending = true;
  const installation = installedConnectors.find(value => value.name === 'hubspot');
  retainInstalledHostServiceInstallation(services, installation, runtimeCid);
  const context = beginInstalledSourceInitialization(services, installation, 'hubspot', baseEnvironmentWire, role);
  const input = context.prepareNativeInput(Object.freeze({
    capacity: () => common.clientProgramHubSpotObjectConstructionCapacity(body.length,
      body.toString('base64').length, 'companies'.length, 4096, 1000, 20, 10, 100, 3, 100, 4096, 1000, 20),
    project() {
      const catalog = checked(native.hubspotProjectProperties(body, 'companies', 4096, 1000, 20, 10, 100));
      const names = native.hubspotPropertyCatalogNames(catalog);
      const schema = checked(native.hubspotObjectSchemaWire(catalog, names, 3, 100, 4096, 1000, 20));
      return Object.freeze({catalog, view: Object.freeze({resource: 'companies', resource_kind: 'object',
        schema_wire: schema, schema_cid: 'sha256:' + createHash('sha256').update(schema).digest('hex'),
        facts_wire: native.hubspotObjectRelationFactsWire()})});
    },
  }));
  const prepared = context.prepareDeclaration([input.view]);
  return {context, prepared, catalog: input.catalog,
    close() {
      if (closed) return;
      // A constructor-only component deliberately stops before any Site or
      // adapter. Retire this exact unfinished construction, not a fake adapter.
      if (!finished) {
        finishInstalledSourceInitialization(context, undefined, new Error('pure component terminal'), true);
        finished = true;
      }
      assert.equal(retireInstalledSourceInitialization(services), true);
      pending = false; closeHostInitializationPreparation(state); closed = true;
    }};
}

function prepare(f, common, native) {
  return prepareInstalledHubSpotUpdateMappings({construction: f.context, moon: common, providerMoon: native,
    connectorId: 'hubspot', declared: f.prepared.declared, catalogFor: () => f.catalog,
    writes, limits: mappingLimits});
}

export function registerHubSpotMappingParentTests(common, native, baseEnvironmentWire) {
  test('HubSpot real initial parent funds Native Mapping after its same declaration and completes its original Environment', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let attempted = 0, completed = 0;
    const counted = {...native, hubspotPrepareExecutionMapping(...args) {
      attempted++; const result = native.hubspotPrepareExecutionMapping(...args); checked(result); completed++; return result;
    }};
    try {
      const result = prepare(f, common, counted);
      assert.equal(attempted, 1); assert.equal(completed, 1);
      assert.strictEqual(result.prepared.declaration, f.prepared.declaration);
      assert.strictEqual(result.prepared.declared, f.prepared.declared);
      assert.equal(result.prepared.mappings.length, 1);
      assert.equal(result.prepared.mappings[0].body, result.originals[0].body);
      const environment = JSON.parse(result.prepared.environment.wire);
      assert(environment.mapping_contracts.some(mapping => mapping.mapping_contract_cid === result.originals[0].mappingCid));
      const projection = Object.freeze({capacity() {assert.fail('no quote after mappings');}, project() {assert.fail('no native input after mappings');}});
      assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
      assert.throws(() => f.context.prepareNativeMappings(f.prepared.declared, result.originals),
        {code: 'ForeignInstalledSourceInitialization'});
    } finally {f.close();}
  });

  test('HubSpot real initial parent keeps Source post-declaration and retired native input paths closed', () => {
    const f = fixture(common, native, baseEnvironmentWire, 'source');
    const projection = Object.freeze({capacity() {assert.fail('no Source quote after declaration');}, project() {assert.fail('no Source native input after declaration');}});
    try {assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});}
    finally {f.close();}
    assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
  });

  test('HubSpot real initial Ledger refuses excess post-declaration quantity before Native projection', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let quoted = 0, projected = 0;
    try {
      assert.throws(() => f.context.prepareNativeInput(Object.freeze({
        capacity() {quoted++; return checked(common.clientProgramInstalledSourceConstructionCapacity(
          100000000n, 0n, 0n, 0n, 0n, 0n));},
        project() {projected++; return Object.freeze({});},
      })));
      assert.equal(quoted, 1, 'Reach the real original Ledger, not the old phase refusal');
      assert.equal(projected, 0);
    } finally {f.close();}
  });

  test('HubSpot Mapping originals cannot move to another actual initialization parent or be copied', () => {
    const original = fixture(common, native, baseEnvironmentWire);
    const other = fixture(common, native, baseEnvironmentWire);
    try {
      const result = prepare(original, common, native);
      assert.throws(() => other.context.prepareNativeMappings(other.prepared.declared, result.originals),
        {code: 'ForeignInstalledSourceInitialization'});
      assert.throws(() => other.context.prepareNativeMappings(other.prepared.declared,
        Object.freeze(result.originals.map(value => Object.freeze({...value})))),
      {code: 'ForeignInstalledSourceInitialization'});
      assert.equal(prepare(other, common, native).prepared.mappings.length, 1);
    } finally {other.close(); original.close();}
  });

  test('HubSpot post-declaration Native projection cannot reenter or reuse its original attempt', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let projected = 0;
    const nested = Object.freeze({capacity() {assert.fail('no reentrant quote');},
      project() {assert.fail('no reentrant projection');}});
    const projection = Object.freeze({
      capacity() {return checked(common.clientProgramInstalledSourceConstructionCapacity(1n, 0n, 0n, 0n, 0n, 0n));},
      project() {
        projected++;
        assert.throws(() => f.context.prepareNativeInput(nested), {code: 'ForeignInstalledSourceInitialization'});
        assert.throws(() => f.context.prepareNativeMappings(f.prepared.declared, Object.freeze([])),
          {code: 'ForeignInstalledSourceInitialization'});
        return Object.freeze({});
      },
    });
    try {
      assert.deepEqual(f.context.prepareNativeInput(projection), {});
      assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
      assert.equal(projected, 1);
    } finally {f.close();}
  });
}

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import * as provider from '../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {composeInstalledSourceEnvironment} from './installed-funded-environment.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {installedUpdateTargets} from './installed-effect-inventory.mjs';

// Actual unchanged policy/Ledger and provider constructors. No public Run,
// real provider, credential, caller budget replacement or successful mock.
const input = () => {
  const value = {results: Array.from({length: 245}, (_, i) => ({name: `field_${i}`,
    type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}})), ignored: ''};
  value.ignored = 'x'.repeat(361489 - Buffer.byteLength(JSON.stringify(value)));
  const body = Buffer.from(JSON.stringify(value)); assert.equal(body.length, 361489);
  return body;
};
const quote = moon => {
  const value = moon.clientProgramHubSpotObjectConstructionCapacity(
    361489, 481988, 9, 524288, 65536, 32, 256, 6003, 256, 6003, 65536, 8000, 32);
  assert(value !== null && typeof value === 'object');
  return value;
};
const latestReserve = events => events.findLast(event => event.operation === 'clientProgramReserveInstalledSourceConstruction');

async function wideEffectFixture(t, {maxProperties = 256, readOnly = false, propertyNameUnits, propertyKinds} = {}) {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const source = await f.metadataSourceProfile('hubspot');
  const metadata = JSON.parse(await readFile(source.value.metadataPath, 'utf8'));
  const variableUnits = propertyNameUnits === undefined ? undefined : propertyNameUnits - 15;
  const names = ['name', 'description', ...Array.from({length: 243}, (_, i) => {
    const name = `field_${i}`;
    return variableUnits === undefined ? name : name.padEnd(Math.floor(variableUnits / 243) +
      (i < variableUnits % 243 ? 1 : 0), 'x');
  })];
  if (propertyNameUnits !== undefined) assert.equal(names.reduce((sum, name) => sum + name.length, 0), propertyNameUnits);
  const results = names
    .map((name, index) => ({name, ...(propertyKinds?.[index] ?? {type: 'string', fieldType: 'text'}), calculated: false,
      modificationMetadata: {readOnlyValue: readOnly && name === 'name'}}));
  const properties = {results, ignored: ''};
  properties.ignored = 'x'.repeat(361489 - Buffer.byteLength(JSON.stringify(properties)));
  metadata.objects[0].propertiesBody = Buffer.from(JSON.stringify(properties)).toString('base64');
  await writeFile(source.value.metadataPath, JSON.stringify(metadata));
  Object.assign(source.value.limits, {maxResponseBytes: 524288, maxNodes: 65536, maxDepth: 32,
    maxProperties, maxNameUnits: 6003, maxColumns: 256, maxDeclarationBytes: 65536,
    maxDeclarationNodes: 8000});
  await writeFile(source.path, JSON.stringify(source.value));
  const value = {version: 'actql-installed-hubspot-effect/0.1', connectorId: source.value.connectorId,
    sourceProfilePath: source.path,
    writes: [{resource: 'companies', fields: ['name'], markerProperty: 'description'}]};
  const path = join(f.root, 'wide-effect.json');
  await writeFile(path, JSON.stringify(value));
  return {f, events, source, selection: {path, value, role: 'effect', registration: 'hubspot'}};
}

test('wide HubSpot Source and Effect compose on the same original default preparation parent', async t => {
  const {f, events, source, selection} = await wideEffectFixture(t);
  const installedSource = await f.load(source), installedEffect = await f.load(selection);
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  let composed;
  try {
    composed = composeInstalledSourceEnvironment(f.services, f.moon, base,
      installedSource.environmentWire, installedEffect.environmentWire);
  } finally {
    t.diagnostic(JSON.stringify({lastConstructionCalls: events.slice(-4)}, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value));
  }
  assert.equal(composed.runtime, f.moon);
  assert.equal(composed.body.schema_snapshots.length, 1);
  assert.equal(composed.body.mapping_contracts.length, 1);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('real-shape HubSpot Source and Effect composition funds sequential canonical workspace and retains full originals', async t => {
  // Same aggregate Catalog shape and name bytes as the observed metadata;
  // only authored synthetic names and property definitions are used here.
  const propertyKinds = [
    ['string', 'text', 69], ['number', 'number', 68], ['datetime', 'date', 58],
    ['enumeration', 'checkbox', 15], ['enumeration', 'select', 22],
    ['bool', 'booleancheckbox', 9], ['date', 'date', 2], ['object_coordinates', 'text', 2],
  ].flatMap(([type, fieldType, count]) => Array.from({length: count}, () =>
    ({type, fieldType, ...(type === 'enumeration' ? {options: []} : {})})));
  assert.equal(propertyKinds.length, 245);
  const {f, events, source, selection} = await wideEffectFixture(t, {propertyNameUnits: 6001, propertyKinds});
  const installedSource = await f.load(source), installedEffect = await f.load(selection);
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  const first = events.length;
  const composed = composeInstalledSourceEnvironment(f.services, f.moon, base,
    installedSource.environmentWire, installedEffect.environmentWire);
  const carrier = composed.body.contract_registry.find(value => value.kind === 'carrier_schema');
  assert.equal(Object.keys(carrier.body.fields).length, 246);
  assert.equal(composed.body.schema_snapshots.length, 1);
  assert.equal(composed.body.mapping_contracts.length, 1);
  const reservations = events.slice(first).filter(event => event.operation === 'clientProgramReserveInstalledSourceConstruction');
  assert(reservations.length > 0 && reservations.every(event => event.accepted));
  assert(reservations.every(event => event.retained <= 536870912n && event.peak <= 536870912n));
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('same-parent Environment composition still refuses excessive retained input before its unfunded next stage', async t => {
  const {f, events, source, selection} = await wideEffectFixture(t, {propertyNameUnits: 6001});
  const installedSource = await f.load(source), installedEffect = await f.load(selection);
  const reader = installedSourceConfigurationReader(f.services);
  const text = 'x'.repeat(1024 * 1024);
  for (let index = 0; index < 24; index++) {
    const path = join(f.root, `other-retained-original-${index}.txt`);
    await writeFile(path, text);
    assert.equal((await reader.readText(path, {maxBytes: text.length})).length, text.length);
  }
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  t.diagnostic(JSON.stringify({retainedBeforeComposition: events.at(-1).retained.toString()}));
  assert.throws(() => composeInstalledSourceEnvironment(f.services, f.moon, base,
    installedSource.environmentWire, installedEffect.environmentWire), {code: 'MoonBitHostFailure'});
  const refused = latestReserve(events);
  assert.equal(refused.accepted, false);
  assert(refused.retained > 536870912n || refused.peak > 536870912n);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('real-width HubSpot Source and Effect compose on the same original default preparation parent', async t => {
  // The 6003-byte schema-name bound includes the original two-byte id key.
  const {f, events, source, selection} = await wideEffectFixture(t, {propertyNameUnits: 6001});
  const installedSource = await f.load(source), installedEffect = await f.load(selection);
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  let composed;
  try {
    composed = composeInstalledSourceEnvironment(f.services, f.moon, base,
      installedSource.environmentWire, installedEffect.environmentWire);
  } finally {
    t.diagnostic(JSON.stringify({lastConstructionCalls: events.slice(-4)}, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value));
  }
  assert.equal(composed.runtime, f.moon);
  assert.equal(composed.body.schema_snapshots.length, 1);
  assert.equal(composed.body.mapping_contracts.length, 1);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('wide HubSpot Effect keeps the admitted Source Catalog limit through its actual Mapping and driver constructors', async t => {
  const {f, events, selection} = await wideEffectFixture(t);
  const effect = await f.load(selection);
  const environment = JSON.parse(effect.environmentWire);
  const carrier = environment.contract_registry.find(value => value.kind === 'carrier_schema');
  assert.equal(Object.keys(carrier.body.fields).length, 246);
  assert.equal(effect.mappings.length, 1);
  const mapping = environment.mapping_contracts.find(value => value.mapping_ref === effect.mappings[0].mappingRef);
  assert.deepEqual(mapping.writable_fields, ['name']);
  assert.equal(latestReserve(events).accepted, true);
  assert.equal(f.secretReads(), 0, 'initialization grants no provider operation');
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('same full HubSpot Source and original approval Program compile with held checked projection demand', async t => {
  const {f, source, selection} = await wideEffectFixture(t, {propertyNameUnits: 6001});
  const installedSource = await f.load(source), installedEffect = await f.load(selection);
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  const composed = composeInstalledSourceEnvironment(f.services, f.moon, base,
    installedSource.environmentWire, installedEffect.environmentWire);
  const view = composed.body.schema_snapshots[0];
  const alias = {name: 'hubspot.companies', sourceRef: view.source_ref,
    sourceViewContractCid: view.source_view_contract_cid, schemaContractCid: view.carrier_schema_contract_cid};
  const updateTargets = installedUpdateTargets(installedEffect,
    [{name: alias.name, targetRef: installedEffect.mappings[0].target}], composed.wire);
  const publication = sourceAliasPublication(f.moon, composed.admitted, [alias], [], {updateTargets});
  const program = await readFile(new URL('../../scripts/fixtures/hubspot-approval/update.aql', import.meta.url), 'utf8');
  const outcome = f.moon.clientProgramPreparePublicSourceComputationWithParameters(program, 'aql-text',
    composed.admitted, JSON.stringify(publication),
    JSON.stringify({record_id: {type: 'string'}, next_name: {type: 'string'}}),
    JSON.stringify({record_id: 'component-record', next_name: 'component-updated'}), true, []);
  const prepared = f.moon.clientProgramSourceComputationEffect(outcome);
  assert(prepared);
  const ready = f.moon.clientProgramEffectPreparationReady(prepared);
  assert(ready);
  assert(checked(f.moon.clientProgramCompileLocalEffects(ready)));
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('wide HubSpot Effect still rejects a Catalog beyond its original Source property limit before Mapping', async t => {
  const {f, selection} = await wideEffectFixture(t, {maxProperties: 244});
  await assert.rejects(f.load(selection), {code: 'InstalledHostInitializationFailed'});
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('wide HubSpot Effect preserves the original read-only property refusal under the same Source limit', async t => {
  const {f, selection} = await wideEffectFixture(t, {readOnly: true});
  await assert.rejects(f.load(selection), error => {
    const cause = error.primaryFailure?.cause;
    return cause?.constructor?.name.endsWith('MappingIssue8Property') &&
      cause._0?.constructor?.name.endsWith('PropertyIssue16ReadOnlyProperty');
  });
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('actual HubSpot Source projection releases completed native workspace before the next original reservation', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const reader = installedSourceConfigurationReader(f.services), quantity = quote(f.moon);
  const pair = f.moon.clientProgramSerializationCapacityBytes(quantity), retained = runtimeField(pair, 0), peak = runtimeField(pair, 1);
  let completed = 0, inConstruction, body;
  const output = reader.prepareNativeInput(Object.freeze({capacity: () => quantity, project() {
    inConstruction = latestReserve(events); assert.equal(inConstruction.accepted, true);
    body = input();
    const catalog = checked(provider.hubspotProjectProperties(body, 'companies', 524288, 65536, 32, 256, 6003));
    const names = provider.hubspotPropertyCatalogNames(catalog);
    const wire = checked(provider.hubspotObjectSchemaWire(catalog, names, 256, 6003, 65536, 8000, 32));
    assert.equal(names.length, 245); assert.equal(Object.keys(JSON.parse(wire)).length, 246);
    completed++;
    return Object.freeze({body, catalog, names, wire, view: Object.freeze({resource: 'companies', schema_wire: wire})});
  }}));
  assert.equal(completed, 1); assert.strictEqual(output.body, body);
  const after = events.at(-1); assert.equal(after.operation, 'clientProgramReconcileInstalledSourceConstruction');
  assert.equal(after.accepted, true); assert.equal(after.retained, retained);
  assert(inConstruction.retained >= peak, 'the real parent held the full constructor before projection');
  assert(after.retained < inConstruction.retained, 'only a completed original projection shrinks');
  const path = join(f.root, 'next.txt'); await writeFile(path, 'next');
  assert.equal(await reader.readText(path, {maxBytes: 4}), 'next');
  assert(events.at(-1).retained < peak, 'the next actual reservation does not carry the ended native peak');
  assert.equal(output.names.length, 245); assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('actual HubSpot Source still refuses an overlapping native peak before entering its constructor', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const reader = installedSourceConfigurationReader(f.services), text = 'x'.repeat(4 * 1024 * 1024);
  for (let i = 0; i < 6; i++) {
    const path = join(f.root, `prefix-${i}.txt`); await writeFile(path, text);
    assert.equal((await reader.readText(path, {maxBytes: text.length})).length, text.length);
  }
  let entered = 0;
  assert.throws(() => reader.prepareNativeInput(Object.freeze({capacity: () => quote(f.moon),
    project() {entered++; assert.fail('An unadmitted original constructor must not start');}})), {code: 'MoonBitHostFailure'});
  assert.equal(entered, 0); assert.equal(latestReserve(events).accepted, false);
  assert(latestReserve(events).retained > 536870912n);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

// The same constructor that failed at the real Effect boundary, preceded by
// distinct retained configuration originals. No whole-install budget override.
test('completed configuration JSON retains its actual tree before the next real HubSpot constructor', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const reader = installedSourceConfigurationReader(f.services), payload = 'A'.repeat(482480);
  const originals = [];
  for (let index = 0; index < 6; index++) {
    const path = join(f.root, `metadata-${index}.json`);
    const wire = JSON.stringify({payload, unicode: 'é😀', ordinal: index});
    await writeFile(path, wire);
    const value = await reader.readJson(path, {maxBytes: Buffer.byteLength(wire)});
    assert.equal(value.payload, payload); assert.equal(value.unicode, 'é😀'); assert.equal(value.ordinal, index);
    originals.push(value);
  }
  const quantity = quote(f.moon); let entered = 0;
  const output = reader.prepareNativeInput(Object.freeze({capacity: () => quantity, project() {
    entered++;
    const body = input();
    const catalog = checked(provider.hubspotProjectProperties(body, 'companies', 524288, 65536, 32, 256, 6003));
    const names = provider.hubspotPropertyCatalogNames(catalog);
    const wire = checked(provider.hubspotObjectSchemaWire(catalog, names, 256, 6003, 65536, 8000, 32));
    return Object.freeze({body, catalog, names, wire, view: Object.freeze({resource: 'companies', schema_wire: wire})});
  }}));
  assert.equal(entered, 1); assert.equal(output.names.length, 245);
  assert.equal(Object.keys(JSON.parse(output.wire)).length, 246);
  assert.equal(originals.length, 6); assert.equal(originals[0].payload, payload);
  assert(events.at(-1).retained < 100000000n, 'completed parser/identity peaks do not remain in this original prefix');
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

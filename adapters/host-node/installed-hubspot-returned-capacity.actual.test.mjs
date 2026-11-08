import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import * as provider from '../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';

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

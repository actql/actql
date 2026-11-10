// Installer call-contract controls with explicit doubles. Native Mapping
// semantics, the real initial Ledger and ordinary packages are separate tests.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledHubSpotUpdateMappings} from '../host/hubspot-effect-mappings.mjs';

function fixture() {
  const events = [], declared = Object.freeze({manifest_entry_cid: 'sha256:' + 'a'.repeat(64)});
  const writes = Object.freeze(['companies', 'contacts'].map(resource =>
    Object.freeze({resource, fields: Object.freeze(['amount', 'tags'])})));
  const catalogs = new Map(writes.map(write => [write.resource, Object.freeze({resource: write.resource})]));
  const limits = Object.freeze({maxProperties: 100, maxFields: 16, maxNameBytes: 256,
    maxBytes: 10000, maxNodes: 1000, maxDepth: 20});
  const moon = {clientProgramHubSpotMappingConstructionCapacity(fields, sources, units, ...bounds) {
    events.push('quote'); assert.equal(fields, 2); assert.equal(sources, 0);
    assert(units >= 71n); assert.deepEqual(bounds, [100, 16, 256, 10000, 1000, 20]);
    return Object.freeze({testQuote: true});
  }};
  const providerMoon = {
    hubspotPrepareExecutionMapping(catalog, connector, manifest, resource, kind, key, selected, sources, ...bounds) {
      events.push('native'); assert.strictEqual(catalog, catalogs.get(resource));
      assert.equal(connector, 'hubspot'); assert.equal(manifest, declared.manifest_entry_cid);
      assert.equal(kind, 1); assert.equal(key, 'id'); assert.deepEqual(selected, ['amount', 'tags']);
      assert.deepEqual(sources, []); assert.deepEqual(bounds, [100, 16, 256, 10000, 1000, 20]);
      return {$tag: 1, _0: Object.freeze({resource})};
    },
    hubspotExecutionMappingBody: mapping => 'complete-original-' + mapping.resource,
    hubspotExecutionMappingRef: mapping => 'mapping:' + mapping.resource,
    hubspotExecutionMappingCid: mapping => 'cid:' + mapping.resource,
  };
  const construction = {
    prepareNativeInput(projection) {
      assert.equal(projection.capacity().testQuote, true); events.push('reserve');
      const original = projection.project(); events.push('returned');
      assert(Object.isFrozen(original)); return original;
    },
    prepareNativeMappings(originalDeclared, originals) {
      events.push('environment'); assert.strictEqual(originalDeclared, declared);
      assert(Object.isFrozen(originals)); assert.equal(originals.length, 2);
      return Object.freeze({declared, originals});
    },
  };
  return {events, construction, moon, providerMoon, connectorId: 'hubspot',
    declared, catalogFor: resource => catalogs.get(resource), writes, limits};
}

test('HubSpot installer retains exact declared/native outputs and captures methods before reserve reentry', () => {
  const f = fixture(), original = f.construction.prepareNativeInput;
  f.construction.prepareNativeInput = function (projection) {
    const result = original(projection);
    // The next original constructor must keep its captured methods; a current
    // callback is not permission to replace an export table mid-initialization.
    for (const name of Object.keys(f.providerMoon)) f.providerMoon[name] = () => assert.fail('Changed export');
    f.moon.clientProgramHubSpotMappingConstructionCapacity = () => assert.fail('Changed issuer');
    return result;
  };
  const result = prepareInstalledHubSpotUpdateMappings(f);
  assert.deepEqual(f.events, ['quote', 'reserve', 'native', 'returned',
    'quote', 'reserve', 'native', 'returned', 'environment']);
  assert.strictEqual(result.prepared.declared, f.declared);
  assert.strictEqual(result.prepared.originals, result.originals);
  assert.deepEqual(result.originals.map(value => [value.resource, value.body, value.mappingRef, value.mappingCid]), [
    ['companies', 'complete-original-companies', 'mapping:companies', 'cid:companies'],
    ['contacts', 'complete-original-contacts', 'mapping:contacts', 'cid:contacts'],
  ]);
});

test('HubSpot installer preserves actual reserve refusal before any native Mapping or Environment', () => {
  const f = fixture(), refusal = new Error('Actual original reserve refused');
  f.construction.prepareNativeInput = projection => {
    projection.capacity(); f.events.push('refused'); throw refusal;
  };
  assert.throws(() => prepareInstalledHubSpotUpdateMappings(f), error => error === refusal);
  assert.deepEqual(f.events, ['quote', 'refused']);
});

test('HubSpot installer preserves original native refusal without assembling a partial Environment', () => {
  const f = fixture(), issue = Object.freeze({testNativeIssue: 'readonly'});
  f.providerMoon.hubspotPrepareExecutionMapping = () => ({$tag: 0, _0: issue});
  assert.throws(() => prepareInstalledHubSpotUpdateMappings(f),
    error => error.code === 'MoonBitHostFailure' && error.cause === issue);
  assert.deepEqual(f.events, ['quote', 'reserve']);
});

for (const invalid of ['writes-proxy', 'write-accessor', 'manifest-accessor', 'limit-accessor', 'export-accessor']) {
  test(`HubSpot installer refuses ${invalid} without invoking accessor or native construction`, () => {
    const f = fixture(); let reads = 0;
    const get = () => {reads++; throw new Error('Accessor must not run');};
    if (invalid === 'writes-proxy') f.writes = new Proxy(f.writes, {get, ownKeys: get, getOwnPropertyDescriptor: get});
    if (invalid === 'write-accessor') f.writes = Object.freeze([
      Object.freeze(Object.defineProperty({fields: Object.freeze(['amount'])}, 'resource', {get})),
    ]);
    if (invalid === 'manifest-accessor') f.declared = Object.freeze(Object.defineProperty({}, 'manifest_entry_cid', {get}));
    if (invalid === 'limit-accessor') f.limits = Object.freeze(Object.defineProperty({}, 'maxProperties', {get}));
    if (invalid === 'export-accessor') Object.defineProperty(f.providerMoon, 'hubspotPrepareExecutionMapping', {get});
    assert.throws(() => prepareInstalledHubSpotUpdateMappings(f), TypeError);
    assert.equal(reads, 0); assert.deepEqual(f.events, []);
  });
}

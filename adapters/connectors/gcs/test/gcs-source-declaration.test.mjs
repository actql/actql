import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as objectFixture from '../../../../_build/js/release/build/connectors/gcs/fixtures/object_source_node/object_source_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {checkInstalledGcsSourceProfile, restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';

const baseWire = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
const profile = () => ({version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
  project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/e\u0301/',
  mediaType: 'application/pdf', siteProfilePath: '/fixture/site.json', accountConfigurationWire: '{}',
  limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
    maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
    maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}});

test('GCS declares listing and content as separate common Catalog acquisitions', () => {
  const input = profile();
  const restored = restoreGcsSourceDeclaration(moon, input);
  const catalog = JSON.parse(restored.declared.catalog);
  const listing = catalog.source_views.find(value => value.acquisition.authority === 'read_metadata');
  const capture = catalog.source_views.find(value => value.acquisition.authority === 'read_content');
  assert.equal(catalog.source_views.length, 2);
  assert.ok(listing);
  assert.equal(listing.acquisition.kind, 'scan');
  assert.notEqual(restored.declared.views.find(value => value.resource === 'files').source_ref,
    restored.declared.views.find(value => value.resource === 'contents').source_ref);
  assert.equal(capture.acquisition.kind, 'fetch');
  assert.deepEqual(capture.acquisition.correlation, {request_fields: ['resource', 'version'],
    response_fields: ['resource', 'version'], identity: ['resource', 'version'], cardinality: 'one'});
  const environment = rowSourceCheckEnvironment(baseWire.trimEnd(), restored.declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const document = {version: 'actql/0.1', id: 'gcs-declaration-check', stages: [{id: 'stage', inputs: {},
    steps: [{values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'rows'}],
    results: {r: {from: 'rows', fields: ['id']}}}], results: {r: {from: {stage: 'stage', result: 'r'}}}};
  const prepared = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(document), 'json',
    checkedEnvironment, undefined);
  assert.ok(moon.clientProgramPreparationReady(prepared));
  const repeated = restoreGcsSourceDeclaration(moon, input, restored.declared.catalog_cid);
  assert.equal(repeated.declared.catalog, restored.declared.catalog);
  assert.equal(repeated.scopeCid, restored.scopeCid);
  assert.deepEqual(repeated.declared.contracts, restored.declared.contracts);
});

test('exact decomposed/composed GCS scope strings never share a declaration scope identity', () => {
  const input = profile();
  const original = restoreGcsSourceDeclaration(moon, input);
  const composed = restoreGcsSourceDeclaration(moon, {...input, prefix: 'test/é/'});
  assert.notEqual(original.scopeCid, composed.scopeCid);
  assert.notEqual(original.declared.catalog_cid, composed.declared.catalog_cid);
  assert.equal(original.versionCid, composed.versionCid);
});

test('ordinary objects declare exact Decimal contracts and genuine Sources beside the unchanged listing', () => {
  const input = profile(), legacy = restoreGcsSourceDeclaration(moon, input);
  const original = restoreGcsSourceDeclaration(moon, input, undefined, {includeObjects: true});
  assert.equal(original.declared.views.length, 3);
  assert.deepEqual(original.declared.views.find(view => view.resource === 'files'),
    legacy.declared.views.find(view => view.resource === 'files'));
  assert.notEqual(original.declared.catalog_cid, legacy.declared.catalog_cid);
  const catalog = JSON.parse(original.declared.catalog);
  const objects = original.declared.views.find(view => view.resource === 'objects');
  const schema = original.declared.contracts.map(JSON.parse).find(value => value.cid === objects.carrier_schema_cid);
  for (const field of ['size', 'generation', 'metageneration']) {
    assert.deepEqual(schema.body.fields[field], {nullable: false, precision: 19, scale: 0, type: 'decimal'});
  }
  assert.deepEqual(schema.body.fields.metadata, {nullable: true, type: 'json'});
  const environment = rowSourceCheckEnvironment(baseWire.trimEnd(), original.declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const document = {version: 'actql/0.1', id: 'gcs-real-object-source', stages: [{id: 's',
    inputs: {objects: {connector: 'storage', resource: 'objects', view: 'records', request: {prefix: null}}},
    steps: [{from: 'objects', filter: 'name IS NOT NULL', as: 'listed'},
      {from: 'listed', select: ['resource', 'version', 'name', 'size', 'content_type', 'generation',
        'metageneration', 'storage_class', 'updated', 'md5', 'crc32c', 'metadata'], as: 'rows'}],
    results: {r: {from: 'rows', fields: ['name', 'size', 'generation', 'metageneration', 'metadata']}}}],
    results: {r: {from: {stage: 's', result: 'r'}}}};
  const unordered = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(document),
    'json', checkedEnvironment, undefined);
  assert.equal(moon.clientProgramPreparationReady(unordered), undefined,
    'a JSON-bearing Source Result cannot invent deterministic publication order');
  document.stages[0].steps.push(
    {from: 'rows', assert_rows: {unique_by: ['name']}, as: 'unique_names'},
    {from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered'});
  document.stages[0].results.r.from = 'ordered';
  const prepared = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(document),
    'json', checkedEnvironment, undefined);
  assert.ok(moon.clientProgramPreparationReady(prepared),
    inspect(moon.clientProgramPreparationIssue(prepared), {depth: 8, maxStringLength: 1000}));
  assert.equal(catalog.source_views.length, 3);
});

test('actual installed object contracts consume GCS Int64 as Decimal and metadata as exact JSON', () => {
  const original = restoreGcsSourceDeclaration(moon, profile(), undefined, {includeObjects: true});
  const objects = original.declared.views.find(view => view.resource === 'objects');
  const schema = original.declared.contracts.map(JSON.parse).find(value => value.cid === objects.carrier_schema_cid);
  const body = Buffer.from('{"kind":"storage#objects","items":[{"bucket":"actql-fixture",' +
    '"name":"test/e\u0301/file","generation":"9007199254740993","metageneration":"2",' +
    '"size":"9223372036854775807","metadata":{"actql-request":"private","$json":"user","e\u0301":"e\u0301\\r\\n"}}]}');
  const page = checked(provider.gcsObjectMetadataPage(body, 'actql-fixture', 'test/e\u0301/',
    3, 8192, 8192, 64, 8192));
  const row = checked(provider.gcsObjectMetadataPageRowJson(page, 0, 8192, 8192, 64));
  const wire = checked(objectFixture.fixtureGcsObjectDataWire(JSON.stringify(schema.body.fields), row));
  assert.equal(wire,
    '["9223372036854775807","9007199254740993","2",{"$json":{"$json":"user","e\u0301":"e\u0301\\r\\n"}}]');
  const wrong = structuredClone(schema.body.fields);
  wrong.size = {type: 'string', nullable: false};
  assert.throws(() => checked(objectFixture.fixtureGcsObjectDataWire(JSON.stringify(wrong), row)),
    'the same textual transport must not masquerade as an admitted String carrier');
});

test('ordinary contents declares five public fields and retains its original lookup identity', () => {
  const input = profile(), legacy = restoreGcsSourceDeclaration(moon, input);
  const ordinary = restoreGcsSourceDeclaration(moon, input, undefined, {includeObjects: true});
  const carrier = (owner, resource) => {
    const view = owner.declared.views.find(value => value.resource === resource);
    return owner.declared.contracts.map(JSON.parse).find(value => value.cid === view.carrier_schema_cid).body.fields;
  };
  const fields = carrier(ordinary, 'contents'), old = carrier(legacy, 'contents');
  assert.deepEqual(Object.keys(fields).sort(), ['content', 'media_type', 'name', 'resource', 'version']);
  assert.deepEqual(fields.name, {nullable: false, type: 'string'});
  assert.deepEqual(fields.media_type, {nullable: false, type: 'string'});
  for (const name of ['content', 'resource', 'version']) assert.deepEqual(fields[name], old[name]);
  assert.deepEqual(Object.keys(old).sort(), ['content', 'resource', 'version']);
  assert.notEqual(ordinary.declared.views.find(value => value.resource === 'contents').carrier_schema_cid,
    legacy.declared.views.find(value => value.resource === 'contents').carrier_schema_cid);
  const catalog = JSON.parse(ordinary.declared.catalog);
  assert.deepEqual(catalog.source_views.find(value => value.acquisition.authority === 'read_content').acquisition,
    {kind: 'fetch', authority: 'read_content', correlation: {request_fields: ['resource', 'version'],
      response_fields: ['resource', 'version'], identity: ['resource', 'version'], cardinality: 'one'}});
});

test('checked profile owns nested limits before later asynchronous installation', () => {
  const input = profile(); const owned = checkInstalledGcsSourceProfile(input);
  input.limits.maxPageBytes = 1; input.prefix = 'foreign/';
  assert.equal(owned.limits.maxPageBytes, 8192);
  assert.equal(owned.prefix, 'test/e\u0301/');
  assert.equal(Object.isFrozen(owned.limits), true);
});

for (const [name, change] of [
  ['unknown option', value => { value.endpoint = 'https://foreign.example'; }],
  ['invalid scalar', value => { value.prefix = 'test/\ud800'; }],
  ['relative site profile', value => { value.siteProfilePath = 'site.json'; }],
  ['unbounded pages', value => { value.limits.maxPages = 0; }],
  ['oversized provider page', value => { value.limits.maxPageItems = 1001; }],
  ['content beyond reserved page', value => { value.limits.maxContentBytes = 8193; }],
  ['insufficient attempts', value => { value.limits.maxAttempts = 3; }],
]) {
  test(`GCS ${name} is refused before declaration or credential use`, () => {
    const input = profile(); change(input);
    assert.throws(() => checkInstalledGcsSourceProfile(input), {code: 'InvalidInstalledGcsSourceProfile'});
  });
}

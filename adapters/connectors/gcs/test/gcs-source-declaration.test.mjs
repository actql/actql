import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import {createHash} from 'node:crypto';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as objectFixture from '../../../../_build/js/release/build/connectors/gcs/fixtures/object_source_node/object_source_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {selectInstalledHostEnvironment} from '../../../host-node/installed-host-policy.mjs';
import {checkInstalledGcsSourceProfile, restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';

const baseWire = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
const profile = () => ({version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
  project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/e\u0301/',
  mediaType: 'application/pdf', siteProfilePath: '/fixture/site.json', accountConfigurationWire: '{}',
  limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
    maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
    maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}});

test('signed64 correction preserves the complete legacy declaration and refuses old objects Catalog substitution', () => {
  // Historical complete declaration snapshots, taken before this correction.
  // They are not expected identities recomputed from the new declaration.
  const legacy = restoreGcsSourceDeclaration(moon, profile());
  assert.equal(legacy.declared.catalog_cid,
    'sha256:8f89f35c41829a021e74d721c0be3fb6b8512fb8fdc10e2647abc1c66eafc5cf');
  assert.equal(createHash('sha256').update(JSON.stringify(legacy.declared)).digest('hex'),
    'fe2014f60d585294551069e7b24dd076d78260230a50b9a37340ddd83deb3982');
  const oldObjectsCatalog = 'sha256:ac2a85c1b2979f61a3d71cec092eeb5d5735b9a18ef789b8faa686dcda2e205d';
  const current = restoreGcsSourceDeclaration(moon, profile(), undefined, {includeObjects: true});
  assert.notEqual(current.declared.catalog_cid, oldObjectsCatalog);
  assert.throws(() => restoreGcsSourceDeclaration(moon, profile(), oldObjectsCatalog,
    {includeObjects: true}), {code: 'MoonBitHostFailure'});
  const same = restoreGcsSourceDeclaration(moon, profile(), current.declared.catalog_cid,
    {includeObjects: true});
  assert.equal(same.declared.catalog, current.declared.catalog);
});

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

test('ordinary objects declare exact signed64 contracts and genuine Sources beside the unchanged listing', () => {
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
    assert.deepEqual(schema.body.fields[field], {nullable: false, type: 'int64'});
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

test('actual installed object contracts consume GCS Int64 in its own logical domain and metadata as exact JSON', () => {
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
  wrong.size = {type: 'decimal', precision: 19, scale: 0, nullable: false};
  assert.throws(() => checked(objectFixture.fixtureGcsObjectDataWire(JSON.stringify(wrong), row)),
    'equal emitted text must not substitute the old Decimal logical domain');
  for (const size of ['0', '9007199254740992', '9007199254740993', '9223372036854775807']) {
    const cells = JSON.parse(row); cells.size = size;
    assert.equal(JSON.parse(checked(objectFixture.fixtureGcsObjectDataWire(
      JSON.stringify(schema.body.fields), JSON.stringify(cells))))[0], size);
  }
  for (const size of ['9223372036854775808', '01', '-0', '1.0', 1]) {
    const cells = JSON.parse(row); cells.size = size;
    assert.throws(() => checked(objectFixture.fixtureGcsObjectDataWire(
      JSON.stringify(schema.body.fields), JSON.stringify(cells))),
    'signed64 admission must neither round, parse a Number nor widen the declared domain');
  }
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
  const acquisition = catalog.source_views.find(value => value.acquisition.authority === 'read_content').acquisition;
  const previous = JSON.parse(legacy.declared.catalog).source_views.find(value =>
    value.acquisition.authority === 'read_content').acquisition;
  assert.deepEqual(acquisition, previous,
    'preserve the complete existing request schema, modes and correlation, not a new fetch policy');
  assert.equal(acquisition.kind, 'fetch');
  assert.equal(acquisition.authority, 'read_content');
  assert.deepEqual(acquisition.correlation, {request_fields: ['resource', 'version'],
    response_fields: ['resource', 'version'], identity: ['resource', 'version'], cardinality: 'one'});
});

test('the actual checker binds original resource/version lookup to public content companion columns', () => {
  const input = profile();
  const policy = {version: 'actql-lookup-execution-policy/0.1',
    max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
    max_total_request_bytes: 73728, max_total_response_bytes: 49152,
    max_total_decoded_response_bytes: 49152, max_total_duration_ms: 30000};
  const selectedBase = selectInstalledHostEnvironment(moon, baseWire.trimEnd(), undefined, policy);
  const program = {version: 'actql/0.1', id: 'gcs-original-content-columns', stages: [{id: 's', inputs: {
    files: {connector: 'storage', resource: 'files', view: 'records',
      request: {paths: ['test/e\u0301/invoice.pdf'], glob: null}},
    contents: {connector: 'storage', resource: 'contents', view: 'records'},
  }, steps: [
    {from: 'files', filter: 'name IS NOT NULL', as: 'listed'},
    {from: 'listed', select: ['resource', 'version', 'name', 'path', 'media_type', 'size_bytes', 'modified_at'], as: 'listing'},
    {join: {left: 'listing', with: 'contents', kind: 'inner',
      on: [{left: 'resource', right: 'resource'}, {left: 'version', right: 'version'}],
      select: {name: 'right.name', media_type: 'right.media_type', content: 'right.content', version: 'right.version'}}, as: 'rows'},
    {from: 'rows', assert_rows: {unique_by: ['name']}, as: 'unique_names'},
    {from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered'},
  ], results: {r: {from: 'ordered', fields: ['name', 'media_type', 'content', 'version']}}}],
  results: {r: {from: {stage: 's', result: 'r'}}}};
  for (const includeObjects of [false, true]) {
    const original = restoreGcsSourceDeclaration(moon, input, undefined, {includeObjects});
    const environment = rowSourceCheckEnvironment(selectedBase, original.declared);
    const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
      environment.evidenceCid, false, false, true, false, false, false, false);
    assert.ok(checkedEnvironment);
    const prepared = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program), 'json', checkedEnvironment, undefined);
    assert.equal(moon.clientProgramPreparationReady(prepared) !== undefined, includeObjects,
      inspect(moon.clientProgramPreparationIssue(prepared), {depth:8,maxStringLength:200}));
  }
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

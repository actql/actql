// Real compiled GCS declaration/collection provider, not installed permission,
// Content acquisition, an original ReferenceIssuer or a live upload.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {gcsUploadCommandDeclaration, gcsUploadCatalogDeclaration} from '../host/gcs-upload-declaration.mjs';
import {prepareGcsCollectionTarget, gcsCollectionUploadMapping} from '../host/gcs-collection-target.mjs';

const limits = {maxBytes: 32768, maxNodes: 4096, maxDepth: 32};
const catalogCid = 'sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a';
const inputCid = 'sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac';
const commandCid = 'sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2';
function original() {
  return JSON.stringify({connector_id: 'exports', connector_registration: 'gcs',
    connector_version: 'gcs/0.1', catalog_cid: catalogCid,
    catalog: '{"catalog_cid":"sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a","commands":[],"connector_id":"exports","connector_version":"gcs/0.1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}',
    contracts: [], views: [], view_bodies: [],
    manifest_entry: '{"connector":"gcs","connector_id":"exports","connector_version":"gcs/0.1"}',
    manifest_entry_cid: 'sha256:770110acd081a211ff71ba28f48fcd784e388ca4d5207e9a7a43402c1bd3e6a0',
    evidence_schemas: [], evidence_capabilities: []});
}
const declared = () => gcsUploadCatalogDeclaration(moon, original(), 'exports', limits);
const target = (wire, overrides) => prepareGcsCollectionTarget(moon, {
  project: 'project', bucket: 'bucket', prefix: 'in/é%2F/',
  targetRef: 'connector://exports/objects', resourceKind: 'file_collection',
  catalogCid: JSON.parse(wire).catalog_cid, installationCid: `sha256:${'b'.repeat(64)}`,
  ...limits, ...overrides,
});

test('real GCS upload declares the independent complete presence role and Command CIDs', () => {
  const {command, contracts} = JSON.parse(gcsUploadCommandDeclaration(moon, 'exports', limits));
  assert.equal(command.contract_cid, commandCid);
  assert.equal(contracts[0].cid, inputCid);
  assert.equal(contracts[1].cid, 'sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad');
  assert.deepEqual(command.input_contract, {
    additional_properties: false,
    fields: {content: {nullable: false, type: 'content_ref'},
      content_type: {nullable: false, type: 'string'}, name: {nullable: false, type: 'string'},
      overwrite: {nullable: false, type: 'boolean'}},
    required_fields: ['content', 'name'],
  });
  assert.deepEqual(contracts[0].body, command.input_contract);
  assert.deepEqual(command.permissions, ['storage.objects.create', 'storage.objects.delete', 'storage.objects.get']);
  assert.equal(Object.hasOwn(command, 'minimum_approval'), false);
});

test('original declared Catalog retains Source data and exact complete role registration', () => {
  const before = JSON.parse(original()), wire = declared(), after = JSON.parse(wire);
  for (const field of ['views', 'view_bodies', 'manifest_entry', 'manifest_entry_cid',
    'evidence_schemas', 'evidence_capabilities']) assert.deepEqual(after[field], before[field]);
  assert.notEqual(after.catalog_cid, before.catalog_cid);
  const catalog = JSON.parse(after.catalog);
  assert.equal(catalog.catalog_cid, after.catalog_cid);
  assert.deepEqual(after.command_bodies.map(JSON.parse), catalog.commands);
  assert.deepEqual(after.contracts.map(JSON.parse), catalog.contracts);
  assert.equal(gcsUploadCatalogDeclaration(moon, wire, 'exports', limits), wire);
});

test('real original collection Mapping retains complete ContentRef and collection-only create-none', () => {
  const wire = declared(), owner = target(wire);
  const mapping = JSON.parse(gcsCollectionUploadMapping(owner, wire, 'exports', limits));
  assert.equal(mapping.resource_identity_cid, owner.identityCid);
  assert.equal(mapping.target_ref, 'connector://exports/objects');
  assert.equal(mapping.primary_identity, null);
  assert.deepEqual(mapping.required_fields, ['content', 'name']);
  assert.deepEqual(mapping.target_schema.fields.content, {nullable: false, type: 'content_ref'});
  assert.deepEqual(mapping.store_command, {catalog_cid: JSON.parse(wire).catalog_cid,
    command_ref: 'command:exports.gcs.upload.v1', command_contract_cid: commandCid});
  assert.equal(mapping.permission_rules.length, 4);
  for (const rule of mapping.permission_rules) {
    assert.equal(rule.effect_kind, 'create');
    assert.equal(rule.selector_class, 'none');
  }
  assert.equal(owner.referenceIssuer, undefined);
});

test('copied frames and changed kind-target-Catalog cannot substitute original collection binding', () => {
  const wire = declared(), owner = target(wire);
  assert.throws(() => gcsCollectionUploadMapping({...owner}, wire, 'exports', limits),
    {code: 'ForeignGcsCollectionTarget'});
  for (const change of [{resourceKind: 'file'}, {targetRef: 'connector://alias/objects'},
    {catalogCid: `sha256:${'a'.repeat(64)}`}]) {
    assert.throws(() => gcsCollectionUploadMapping(target(wire, change), wire, 'exports', limits),
      {code: 'GcsInvalidUploadDeclarationBinding'});
  }
  assert.throws(() => gcsCollectionUploadMapping(owner, wire, 'other', limits),
    {code: 'GcsInvalidUploadDeclaration'});
});

test('invalid numeric ABI limits are refused before the actual Moon entry is called', () => {
  let calls = 0;
  const provider = {...moon, gcsUploadCommandJson(...args) { calls++; return moon.gcsUploadCommandJson(...args); }};
  for (const value of [0, -1, 0.5, Infinity, 2 ** 32 + 32768, Number.MAX_SAFE_INTEGER]) {
    for (const field of ['maxBytes', 'maxNodes', 'maxDepth']) {
      assert.throws(() => gcsUploadCommandDeclaration(provider, 'exports', {...limits, [field]: value}),
        {code: 'GcsInvalidUploadDeclarationLimits'});
    }
  }
  assert.equal(calls, 0);
  assert.throws(() => gcsUploadCommandDeclaration(provider, null, limits),
    {code: 'GcsInvalidUploadDeclarationBinding'});
  assert.equal(calls, 0);
});

test('complete output exact-fit succeeds and one-short remains a typed provider refusal', () => {
  const wire = gcsUploadCommandDeclaration(moon, 'exports', limits), size = Buffer.byteLength(wire);
  assert.equal(gcsUploadCommandDeclaration(moon, 'exports', {...limits, maxBytes: size}), wire);
  assert.throws(() => gcsUploadCommandDeclaration(moon, 'exports', {...limits, maxBytes: size - 1}),
    {code: 'GcsUploadDeclarationCapacityExceeded'});
  assert.throws(() => gcsUploadCatalogDeclaration(moon, original(), 'other', limits),
    {code: 'GcsInvalidUploadDeclaration'});
  assert.throws(() => gcsUploadCatalogDeclaration(moon, '{', 'exports', limits),
    {code: 'GcsInvalidUploadDeclaration'});
});

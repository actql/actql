// Actual compiled Connector declaration -> ordinary environment assembly.
// This does not issue a target, admit current permissions, or execute STORE.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {gcsUploadCatalogDeclaration} from '../connectors/gcs/host/gcs-upload-declaration.mjs';
import {prepareGcsCollectionTarget, gcsCollectionUploadMapping} from '../connectors/gcs/host/gcs-collection-target.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {canonicalJson} from './local-account-config.mjs';

const base = {version: 'actql-check-environment/0.1', schema_snapshots: [],
  connector_capabilities: [], mapping_contracts: [], source_views: [],
  command_contracts: [], model_task_contracts: [], contract_registry: [],
  connector_catalogs: [], host_policy_profile: {}};
const oldCatalog = {schema: 'actql.connector_catalog/0.1',
  catalog_cid: 'sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a',
  connector_id: 'exports', connector_version: 'gcs/0.1', commands: [], contracts: [], source_views: []};
const manifest = {connector: 'gcs', connector_id: 'exports', connector_version: 'gcs/0.1'};
const original = () => ({connector_id: 'exports', connector_registration: 'gcs',
  connector_version: 'gcs/0.1', catalog: canonicalJson(oldCatalog), catalog_cid: oldCatalog.catalog_cid,
  contracts: [], views: [], view_bodies: [], manifest_entry: canonicalJson(manifest),
  manifest_entry_cid: 'sha256:770110acd081a211ff71ba28f48fcd784e388ca4d5207e9a7a43402c1bd3e6a0',
  evidence_schemas: [], evidence_capabilities: []});
const limits = {maxBytes: 32768, maxNodes: 4096, maxDepth: 32};
const declared = () => JSON.parse(gcsUploadCatalogDeclaration(moon,
  canonicalJson(original()), 'exports', limits));
const commandCid = 'sha256:01b4437a23e585b15309e958d28d7069d58f3f9002ec6fffe8458dc24b58fa39';
const inputCid = 'sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac';

test('legacy read-only declaration and explicit empty Commands retain the original complete bytes', () => {
  const expected = canonicalJson({...base, connector_catalogs: [oldCatalog],
    connector_manifest: {version: 'actql-connectors/0.1', connectors: [manifest]}});
  const expectedCid = 'sha256:6a124a679778ee5d84e10650fa4689945308699d89d9a76c8758623db01d03fd';
  for (const declaration of [original(), {...original(), command_bodies: []}]) {
    const actual = rowSourceCheckEnvironment(canonicalJson(base), declaration);
    assert.equal(actual.evidenceCid, expectedCid);
    assert.equal(actual.wire, canonicalJson({...JSON.parse(expected), evidence_bundle_cid: expectedCid}));
  }
});

test('real GCS complete Command and original input role survive ordinary Check Environment assembly', () => {
  const declaration = declared(), before = canonicalJson(declaration);
  const target = prepareGcsCollectionTarget(moon, {project: 'project', bucket: 'bucket',
    prefix: 'exports/', targetRef: 'connector://exports/objects', resourceKind: 'file_collection',
    catalogCid: declaration.catalog_cid, installationCid: `sha256:${'b'.repeat(64)}`, ...limits});
  const mappingWire = gcsCollectionUploadMapping(target, canonicalJson(declaration), 'exports', limits);
  const actual = rowSourceCheckEnvironment(canonicalJson(base), declaration, [mappingWire]);
  const body = JSON.parse(actual.wire), catalog = JSON.parse(declaration.catalog);
  assert.deepEqual(body.mapping_contracts, [JSON.parse(mappingWire)]);
  assert.equal(body.mapping_contracts[0].primary_identity, null);
  assert.deepEqual(body.mapping_contracts[0].required_fields, ['content', 'name']);
  assert.equal(body.mapping_contracts[0].store_command.command_contract_cid, commandCid);
  assert.deepEqual(body.command_contracts, catalog.commands);
  assert.equal(body.command_contracts.length, 1);
  assert.equal(body.command_contracts[0].contract_cid, commandCid);
  assert.equal(body.command_contracts[0].input_schema.cid, inputCid);
  const input = body.contract_registry.find(value => value.cid === inputCid);
  assert.equal(input.kind, 'command_input');
  assert.deepEqual(input.body, {additional_properties: false,
    fields: {content: {nullable: false, type: 'content_ref'},
      content_type: {nullable: false, type: 'string'}, name: {nullable: false, type: 'string'},
      overwrite: {nullable: false, type: 'boolean'}}, required_fields: ['content', 'name']});
  assert.deepEqual(input.body, body.command_contracts[0].input_contract);
  assert.deepEqual(body.connector_catalogs, [catalog]);
  assert.deepEqual(body.connector_manifest.connectors, [JSON.parse(declaration.manifest_entry)]);
  for (const contract of declaration.contracts.map(JSON.parse)) {
    assert.deepEqual(body.contract_registry.find(value => value.cid === contract.cid), contract);
  }
  assert.equal(canonicalJson(declaration), before, 'the original declaration is not rewritten');
  assert.deepEqual(body.command_contracts[0].permissions,
    ['storage.objects.create', 'storage.objects.delete', 'storage.objects.get']);
  assert.equal(body.command_contracts[0].minimum_approval, 'required');
  // Independently sealed full input, not a count or name-only registration.
  const {evidence_bundle_cid: observed, ...preimage} = body;
  assert.equal(observed, `sha256:${createHash('sha256').update(canonicalJson(preimage)).digest('hex')}`);
});

test('present malformed Command arrays are rejected instead of becoming the legacy absent form', () => {
  for (const value of [undefined, null, {}, '[]', false]) {
    assert.throws(() => rowSourceCheckEnvironment(canonicalJson(base),
      {...original(), command_bodies: value}), {code: 'InvalidRowSourceCheckEnvironmentBase'});
  }
  assert.throws(() => rowSourceCheckEnvironment(canonicalJson(base),
    {...original(), command_bodies: ['{']}), SyntaxError);
});

test('new Commands never discard or replace an already populated base registry', () => {
  const declaration = declared();
  for (const commands of [undefined, null, declaration.command_bodies.map(JSON.parse)]) {
    assert.throws(() => rowSourceCheckEnvironment(canonicalJson({...base, command_contracts: commands}),
      declaration), {code: 'InvalidRowSourceCheckEnvironmentBase'});
  }
  const existing = declaration.command_bodies.map(JSON.parse);
  const retained = rowSourceCheckEnvironment(canonicalJson({...base, command_contracts: existing}), original());
  assert.deepEqual(JSON.parse(retained.wire).command_contracts, existing,
    'legacy absence retains existing originals instead of clearing them');
});

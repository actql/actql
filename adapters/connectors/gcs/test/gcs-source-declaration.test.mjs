import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
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

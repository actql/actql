import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createCompositeVectorPageDriver, installCompositeVectorFixture,
  compositeVectorSchemaWire, compositeVectorSchemaCid, compositeVectorFactsWire,
  compositeVectorFactsCid, compositeVectorReadOperations}
  from './fixtures/composite-vector-installed-source.mjs';
import {compositeVectorRows} from './fixtures/composite-vector-source-input.mjs';

const counts = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
const request = overrides => ({resource: 'queries', columns: ['a', 'b', 'embedding'],
  requestWire: '{}', operation: compositeVectorReadOperations.queries, ...overrides});
test('composite declarations retain independent mixed schema and exact ordered key bytes', () => {
  assert.equal(compositeVectorSchemaWire, '{"a":{"max_utf8_bytes":1,"nullable":false,"type":"string"},"b":{"nullable":false,"type":"number"},"embedding":{"dimensions":2,"element_type":"f32","nullable":false,"type":"vector"}}');
  assert.equal(compositeVectorSchemaCid, 'sha256:5a8be37ab2b6e29c46b4fffb85022ff8642f6152897b75a7eec858392ded4f3d');
  assert.equal(compositeVectorFactsWire, '{"relation_keys":{"candidate_keys":[["b","a"]]}}');
  assert.equal(compositeVectorFactsCid, 'sha256:60d02a4d17b31c7595b4f177b0330266610a8cb48c6e311a83d339d4718de985');
});
test('raw tuple and vector values cross the original charge and consume boundary once', async () => {
  const observations = counts(), ticket = {}, calls = [];
  await createCompositeVectorPageDriver(observations)(request({
    authorizationFor: index => {assert.equal(index, 0); calls.push('grant');},
    chargePage: bytes => {assert.deepEqual(JSON.parse(bytes), compositeVectorRows.queries); calls.push('charge'); return ticket;},
    consumePage: (rows, {charge}) => {
      assert.equal(charge, ticket); assert.deepEqual(rows, compositeVectorRows.queries);
      rows[0].embedding[0] = 99; calls.push('consume');
    },
  }));
  assert.deepEqual(calls, ['grant', 'charge', 'consume']);
  assert.deepEqual(compositeVectorRows.queries[0].embedding, [0, 1]);
  assert.deepEqual([observations.sourceReads, observations.sourceReadSessions, observations.acceptedPages], [1, 1, 1]);
});
test('invalid requests cancellation and original consumption refusal cannot become accepted pages', async () => {
  for (const wrong of [{columns: ['a', 'embedding']}, {columns: ['a', 'b', 'b', 'embedding']},
    {resource: 'foreign'}, {operation: compositeVectorReadOperations.candidates},
    {requestWire: '{"filter":true}'}, {signal: AbortSignal.abort(new Error('cancel'))}]) {
    const observations = counts(); let grants = 0;
    await assert.rejects(createCompositeVectorPageDriver(observations)(request({...wrong,
      authorizationFor: () => {grants++;}, chargePage: () => {}, consumePage: () => {}})));
    assert.equal(grants, 0); assert.equal(observations.sourceIo, 0);
  }
  const refusal = new Error('original input validation'), observations = counts();
  await assert.rejects(createCompositeVectorPageDriver(observations)(request({
    authorizationFor: () => {}, chargePage: () => ({}), consumePage: () => {throw refusal;},
  })), error => error === refusal);
  assert.equal(observations.acceptedPages, 0);
});
test('fixture aliases retain exact declared source schema and view references', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-composite-profile-unit-'));
  const declared = {views: ['queries', 'candidates'].map(resource => ({resource,
    source_ref: `connector://composite_fixture/${resource}#records`, view_cid: resource + '-view'})),
  view_bodies: ['candidates', 'queries'].map(resource => JSON.stringify({
    contract_cid: resource + '-view', output: {schema: {cid: 'original-schema'}}}))};
  try {
    const installed = await installCompositeVectorFixture({directory,
      moon: {clientProgramRowSourceRestoreRelationDeclaration: () => ({}),
        clientProgramRowSourceDeclarationJson: () => JSON.stringify(declared)},
      helpers: {checked: value => value}, createInstalledConnectorTable: entries => entries});
    const profile = JSON.parse(await readFile(installed.sourceProfilePath, 'utf8'));
    assert.deepEqual(profile.queryAliases, declared.views.map(view => ({name: view.resource,
      sourceRef: view.source_ref, sourceViewContractCid: view.view_cid, schemaContractCid: 'original-schema'})));
    assert.equal(installed.connectorTable[0].registration, 'composite_fixture');
    assert.equal(installed.observations.sourceIo, 0);
  } finally {await rm(directory, {recursive: true});}
});

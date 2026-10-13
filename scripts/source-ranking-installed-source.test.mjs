import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createSourceRankingPageDriver, installSourceRankingFixture,
  sourceRankingSchemaWire, sourceRankingSchemaCid, sourceRankingFactsWire,
  sourceRankingFactsCid, sourceRankingViewSpecification, sourceRankingReadOperations}
  from './fixtures/source-ranking-installed-source.mjs';
import {sourceRankingRows, sourceRankingPublicSuccesses, sourceRankingPublicRefusals}
  from './fixtures/source-ranking-public-input.mjs';

const counts = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
const options = overrides => ({resource: 'left', columns: ['id', 's'],
  requestWire: '{}', operation: 'score_fixture:left:read', ...overrides});
const hash = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');

test('original Source rows, schema and score facts have independent fixed identities', () => {
  assert.equal(hash(sourceRankingSchemaWire), sourceRankingSchemaCid);
  assert.equal(hash(sourceRankingFactsWire), sourceRankingFactsCid);
  const corpus = JSON.parse(readFileSync('portability/corpus/source-relation-scores.json', 'utf8'));
  assert.deepEqual(sourceRankingRows, corpus.controls.inputs);
  assert.deepEqual(JSON.parse(sourceRankingFactsWire), corpus.cases.find(item => item.id === 'keys_and_scores').body);
  assert.equal(sourceRankingViewSpecification.views.length, 2);
  for (const view of sourceRankingViewSpecification.views) {
    assert.equal(view.schema_wire, sourceRankingSchemaWire);
    assert.equal(view.facts_wire, sourceRankingFactsWire);
  }
});

test('trusted page supplier sends raw scores once through authorization and exact charge', async () => {
  const observations = counts(), calls = [], ticket = {};
  await createSourceRankingPageDriver(observations)(options({
    authorizationFor(index) { calls.push(['authorize', index]); },
    chargePage(bytes) { assert.deepEqual(JSON.parse(bytes), [{id: 1, s: 0.5}]); calls.push(['charge']); return ticket; },
    consumePage(rows, {charge}) { assert.equal(charge, ticket); assert.deepEqual(rows, [{id: 1, s: 0.5}]); calls.push(['consume']); rows[0].s = 9; },
  }));
  assert.deepEqual(calls, [['authorize', 0], ['charge'], ['consume']]);
  assert.equal(sourceRankingRows.left[0].s, 0.5);
  assert.equal(observations.sourceReadSessions, 1);
  assert.equal(observations.sourceIo, 1);
  assert.equal(observations.acceptedPages, 1);
});

test('right Source preserves requested field order and its own operation binding', async () => {
  await createSourceRankingPageDriver(counts())(options({resource: 'right', columns: ['s', 'id'],
    operation: sourceRankingReadOperations.right, authorizationFor() {}, chargePage: () => ({}),
    consumePage(rows) { assert.deepEqual(rows, [{s: 0.5, id: 2}]); assert.deepEqual(Object.keys(rows[0]), ['s', 'id']); },
  }));
});

test('supplier rejects a missing score field, foreign operation and request before grant', async () => {
  const observations = counts(); let grants = 0;
  const hooks = {authorizationFor() { grants++; }, chargePage() { throw new Error('unexpected charge'); }};
  for (const wrong of [{columns: ['id']}, {columns: ['id', 's', 's']},
    {columns: ['id', 'score']}, {resource: 'foreign'},
    {operation: sourceRankingReadOperations.right}, {requestWire: '{"id":1}'}]) {
    await assert.rejects(createSourceRankingPageDriver(observations)(options({...hooks, ...wrong})));
  }
  const controller = new AbortController(); controller.abort(new Error('pre-read cancellation'));
  await assert.rejects(createSourceRankingPageDriver(observations)(options({...hooks, signal: controller.signal})),
    /pre-read cancellation/u);
  assert.equal(grants, 0);
  assert.equal(observations.sourceIo, 0);
});

test('common page refusal is retained and cannot become a successful page', async () => {
  const observations = counts(), refusal = new Error('original common admission refusal');
  await assert.rejects(createSourceRankingPageDriver(observations)(options({authorizationFor() {},
    chargePage: () => ({}), consumePage() { throw refusal; }})), error => error === refusal);
  assert.equal(observations.sourceIo, 1); assert.equal(observations.acceptedPages, 0);
});

test('public JSON/text controls retain independent values, ordered schema and real Source counts', () => {
  const corpus = JSON.parse(readFileSync('portability/corpus/source-relation-scores.json', 'utf8'));
  assert.equal(sourceRankingPublicSuccesses.length, 6);
  for (const fixture of sourceRankingPublicSuccesses) {
    const control = fixture.name.endsWith('weighted') ? corpus.controls.weighted_sum : corpus.controls.max;
    assert.deepEqual(fixture.results.answer.rows, control.rows);
    assert.deepEqual(fixture.results.answer.columns, ['id', 'score', 'rank'].map(name =>
      ({name, contract: {type: 'number', nullable: false}})));
    assert.equal(fixture.sourceReadCount, 2);
    if (fixture.format === 'json') {
      const body = JSON.parse(fixture.text);
      assert.deepEqual(body.stages[0].inputs, {left: {connector: 'score_fixture', resource: 'left'},
        right: {connector: 'score_fixture', resource: 'right'}});
      assert.equal(body.stages[0].steps[0].merge_rankings.score, 's');
    }
  }
  assert.equal(sourceRankingPublicRefusals.length, 4);
  assert.ok(sourceRankingPublicRefusals.every(item => item.sourceReadCount === 0));
});

test('profile alias mapping uses exact declared view CIDs rather than array position or resource-kind', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-score-fixture-profile-'));
  // Mock declaration projection only. This test does not admit a Catalog or run
  // an installed product; real generated declarations require the allocated gate.
  const declared = {catalog_cid: 'fixture-catalog', views: [
    {resource: 'left', source_ref: 'connector://score_fixture/left#records', view_cid: 'left-cid'},
    {resource: 'right', source_ref: 'connector://score_fixture/right#records', view_cid: 'right-cid'},
  ], view_bodies: [
    JSON.stringify({contract_cid: 'right-cid', output: {schema: {cid: 'right-schema'}}}),
    JSON.stringify({contract_cid: 'left-cid', output: {schema: {cid: 'left-schema'}}}),
  ]};
  try {
    const fixture = await installSourceRankingFixture({directory,
      moon: {clientProgramRowSourceRestoreRelationDeclaration() { return {}; },
        clientProgramRowSourceDeclarationJson() { return JSON.stringify(declared); }},
      helpers: {checked: value => value}, createInstalledConnectorTable: rows => rows});
    const profile = JSON.parse(await readFile(fixture.sourceProfilePath, 'utf8'));
    assert.deepEqual(profile.queryAliases, [
      {name: 'l', sourceRef: declared.views[0].source_ref, sourceViewContractCid: 'left-cid', schemaContractCid: 'left-schema'},
      {name: 'r', sourceRef: declared.views[1].source_ref, sourceViewContractCid: 'right-cid', schemaContractCid: 'right-schema'},
    ]);
    assert.equal(fixture.connectorTable.length, 1);
    assert.equal(fixture.observations.sourceIo, 0);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

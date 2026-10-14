import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {selectInitialFromJoinCases, initialFromJoinFixture, initialFromJoinNames}
  from './release-initial-from-join-cases.mjs';
import {installTwoSourceFixtures} from './fixtures/two-source-public-query.mjs';

const vector = JSON.parse(readFileSync('scripts/fixtures/initial-from-join/independent-vector.json'));
const environments = Object.fromEntries(['left', 'right'].map(side => [side,
  JSON.parse(readFileSync(`adapters/host-node/fixtures/two-source/${side}.environment.json`))]));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = body => 'sha256:' + createHash('sha256').update(canonical(body)).digest('hex');

test('only three forms retain the independent four ordered rows, schema and both Source inputs', () => {
  const selected = selectInitialFromJoinCases(vector);
  assert.deepEqual(selected.map(value => value.name), initialFromJoinNames);
  assert.deepEqual(selected.map(value => value.format), ['aql-text', 'sql', 'aql-text']);
  for (const value of selected) {
    assert.strictEqual(value.expected, vector.expected_rows);
    assert.deepEqual(value.columns, [{name: 'id', contract: {type: 'number', nullable: false}},
      {name: 'amount', contract: {type: 'number', nullable: true}},
      {name: 'tag', contract: {type: 'string', nullable: false}}]);
    assert.equal(value.sourceReadSessionCount, 2);
    assert.equal(value.text.split('FROM left_records').length - 1, 1);
    assert.equal(value.text.split('JOIN right_records').length - 1, 1);
    assert.match(value.text, /MAX_OUTPUT_ROWS 10/);
    assert.match(value.text, /ORDER BY amount ASC NULLS FIRST, tag/);
    assert.doesNotMatch(value.text, /UNION ALL|SELECT 1|SELECT 10/);
  }
});

test('missing rows and changed nullable or ordered field declarations cannot be silently selected', () => {
  for (const change of [v => v.expected_rows.pop(), v => v.left_rows.pop(), v => v.right_rows.pop(),
    v => { v.expected_fields[1].nullable = false; }, v => v.expected_fields.reverse()]) {
    const value = structuredClone(vector); change(value);
    assert.throws(() => selectInitialFromJoinCases(value));
  }
});

test('typed right Source has new exact schema/View/Catalog/Environment identities, with existing policy unchanged', () => {
  const before = structuredClone(environments);
  const fixture = initialFromJoinFixture(vector, environments);
  assert.deepEqual(environments, before);
  assert.deepEqual(fixture.environments.left, environments.left);
  const right = fixture.environments.right, view = right.source_views[0];
  const schema = right.contract_registry.find(value => value.kind === 'carrier_schema');
  assert.deepEqual(schema.body.fields, {id: {type: 'number', nullable: false},
    tag: {type: 'string', nullable: false}});
  const {cid: schemaCid, ...schemaBody} = schema; assert.equal(schemaCid, cid(schemaBody));
  assert.equal(view.output.schema.cid, schemaCid);
  const {contract_cid: viewCid, ...viewBody} = view; assert.equal(viewCid, cid(viewBody));
  const {catalog_cid: catalogCid, ...catalogBody} = right.connector_catalogs[0];
  assert.equal(catalogCid, cid(catalogBody));
  const {evidence_bundle_cid: environmentCid, ...environmentBody} = right;
  assert.equal(environmentCid, cid(environmentBody));
  for (const value of right.schema_snapshots) {
    assert.equal(value.carrier_schema_contract_cid, schemaCid);
    assert.equal(value.source_contract_cid, viewCid);
  }
  assert.notEqual(viewCid, before.right.source_views[0].contract_cid);
  assert.notEqual(environmentCid, before.right.evidence_bundle_cid);
  assert.deepEqual(right.host_policy_profile, before.right.host_policy_profile);
  assert.deepEqual(right.connector_capabilities.map(value => value.capability_contract_cids),
    before.right.connector_capabilities.map(value => value.capability_contract_cids));
  assert.deepEqual(right.schema_snapshots.map(value => value.source_ref),
    before.right.schema_snapshots.map(value => value.source_ref));
});

test('wrong base Carrier grammar is rejected rather than retyped as a fallback', () => {
  const changed = structuredClone(environments);
  changed.right.contract_registry.find(value => value.kind === 'carrier_schema').body.fields.amount.nullable = false;
  assert.throws(() => initialFromJoinFixture(vector, changed));
});

// This records fixture setup commands only, not product/Provider execution.
async function recordInstall(fixture) {
  const root = await mkdtemp(join(tmpdir(), 'actql-initial-join-setup-'));
  const commands = [];
  const duckdb = {DuckDBInstance: {async create(database) {
    return {async connect() { return {async run(sql, values) { commands.push({database, sql, values}); },
      closeSync() {}}; }, closeSync() {}};
  }}};
  try {
    const result = await installTwoSourceFixtures({root, fixture, duckdb});
    const profiles = Object.fromEntries(await Promise.all(Object.entries(result.profiles)
      .map(async ([name, path]) => [name, JSON.parse(await readFile(path, 'utf8'))])));
    return {commands, result, profiles};
  } finally { await rm(root, {recursive: true}); }
}

test('typed selection installs just two Source tables and preserves duplicate/NULL/string values verbatim', async () => {
  const observed = await recordInstall(initialFromJoinFixture(vector, environments));
  assert.deepEqual(Object.keys(observed.result.databases), ['left', 'right']);
  assert.deepEqual(Object.keys(observed.profiles), ['left', 'right']);
  assert.deepEqual(observed.commands.filter(value => value.sql.startsWith('CREATE')).map(value => value.sql),
    ['CREATE TABLE records(id DOUBLE, amount DOUBLE)', 'CREATE TABLE records(id DOUBLE, tag VARCHAR)']);
  assert.deepEqual(observed.commands.filter(value => value.sql.startsWith('INSERT')).map(value => value.values),
    [[1, 10], [1, null], [2, 20], [1, 'x'], [1, 'y'], [3, 'z']]);
  assert.equal(observed.profiles.left.queryAliases[0].name, 'left_records');
  assert.equal(observed.profiles.right.queryAliases[0].name, 'right_records');
});

test('legacy P15 setup retains three original tables and all seven Source profile variants', async () => {
  const fixture = {rows: {left: [{id: 1, amount: null}], right: [{id: 2, amount: 20}],
    equal_content: [{id: 1, amount: null}]}, environments};
  const observed = await recordInstall(fixture);
  assert.equal(Object.keys(observed.result.databases).length, 3);
  assert.deepEqual(Object.keys(observed.profiles), ['left', 'right', 'right_equal', 'right_missing',
    'left_broad', 'right_broad', 'right_missing_broad']);
  assert.equal(observed.commands.filter(value => value.sql === 'CREATE TABLE records(id DOUBLE, amount DOUBLE)').length, 3);
});

test('retyped environment members and Catalog contracts retain their independent canonical orderings', () => {
  const fixture = initialFromJoinFixture(vector, environments);
  for (const environment of Object.values(fixture.environments)) {
    const registryOrder = environment.contract_registry.map(value => cid(value));
    assert.deepEqual(registryOrder, [...registryOrder].sort(),
      'Environment registry uses full-member hashes, including each self-CID');
    for (const catalog of environment.connector_catalogs) {
      const contractOrder = catalog.contracts.map(value => value.cid);
      assert.deepEqual(contractOrder, [...contractOrder].sort(),
        'Catalog contracts use their self-CIDs');
      for (const view of catalog.source_views) {
        assert.equal(view.connector_id, catalog.connector_id);
        assert.equal(view.connector_version, catalog.connector_version);
        assert.ok(environment.source_views.some(value => canonical(value) === canonical(view)));
      }
    }
  }
});

test('right schema has its own logical identity and only byte-identical shared contracts coalesce', () => {
  const fixture = initialFromJoinFixture(vector, environments);
  const right = fixture.environments.right;
  const schema = right.contract_registry.find(value => value.kind === 'carrier_schema');
  const expectedBody = {schema: 'actql.contract/0.1',
    id: 'fixture-initial-join-right-carrier-schema', version: 'fixture', kind: 'carrier_schema',
    body: {type: 'object', nullable: false, additional_properties: false,
      fields: {id: {type: 'number', nullable: false}, tag: {type: 'string', nullable: false}}}};
  assert.deepEqual(schema, {...expectedBody, cid: cid(expectedBody)});
  assert.deepEqual(right.source_views[0].output.schema,
    {id: expectedBody.id, version: expectedBody.version, cid: cid(expectedBody)});
  const members = new Map();
  for (const environment of Object.values(fixture.environments)) {
    for (const contract of environment.contract_registry) {
      const key = `${contract.id}\0${contract.version}`, body = canonical(contract);
      assert.ok(!members.has(key) || members.get(key) === body,
        'A repeated logical identity must retain the exact full contract body');
      members.set(key, body);
    }
  }
  assert.equal(members.size, 7); // Three exact shared contracts, two schemas and two data policies.
  assert.equal(right.source_views[0].connector_id, 'crm/right');
  assert.equal(right.connector_catalogs[0].connector_id, 'crm/right');
  assert.equal(right.schema_snapshots[0].source_ref, 'connector://crm/right/r#v');
});

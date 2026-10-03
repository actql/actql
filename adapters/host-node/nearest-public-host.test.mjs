import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build/nearest-public-host');
const {DuckDBInstance} = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');

const textSchema = Object.freeze({
  queries: {request_id: {type: 'string', nullable: false},
    embedding: {type: 'vector', element_type: 'f32', dimensions: 2,
      nullable: false},
    note: {type: 'string', nullable: true}},
  candidates: {item_id: {type: 'string', nullable: false},
    embedding: {type: 'vector', element_type: 'f32', dimensions: 2,
      nullable: false},
    label: {type: 'string', nullable: false}},
});
const withCid = (value, key = 'cid') => {
  const { [key]: previous, ...body } = value;
  return contentCid(body);
};

async function installedVectorSource(root, name) {
  const base = JSON.parse(await readFile(join(repository,
    'adapters/host-node/fixtures/two-source/left.environment.json'), 'utf8'));
  const sourceRef = `connector://nearest/${name}/r#v`;
  const connectorId = `nearest/${name}`;
  const schema = base.contract_registry.find(item => item.kind === 'carrier_schema');
  schema.id = `nearest-${name}-schema`;
  schema.body = {type: 'object', nullable: false,
    additional_properties: false, fields: textSchema[name]};
  schema.cid = withCid(schema);
  const policy = base.contract_registry.find(item => item.kind === 'data_policy');
  policy.id = `nearest-${name}-policy`;
  policy.body.source_ref = sourceRef;
  policy.cid = withCid(policy);
  const catalog = base.connector_catalogs[0];
  catalog.connector_id = connectorId;
  for (const contract of catalog.contracts) {
    if (contract.kind === 'carrier_schema') {
      contract.body = schema.body; contract.cid = schema.cid;
      contract.id = schema.id;
    }
    if (contract.kind === 'data_policy') {
      contract.body = policy.body; contract.cid = policy.cid;
      contract.id = policy.id;
    }
  }
  catalog.contracts.sort((left, right) =>
    left.cid.localeCompare(right.cid, 'en'));
  base.contract_registry.sort((left, right) =>
    contentCid(left).localeCompare(contentCid(right), 'en'));
  const view = base.source_views[0];
  view.connector_id = connectorId;
  view.output.schema.cid = schema.cid;
  view.output.schema.id = schema.id;
  view.output.data_policy.cid = policy.cid;
  view.output.data_policy.id = policy.id;
  delete view.contract_cid;
  view.contract_cid = withCid(view, 'contract_cid');
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = withCid(catalog, 'catalog_cid');
  const snapshot = base.schema_snapshots[0];
  snapshot.source_ref = sourceRef;
  snapshot.source_contract_cid = view.contract_cid;
  snapshot.source_view_contract_cid = view.contract_cid;
  snapshot.carrier_schema_contract_cid = schema.cid;
  snapshot.source_data_policy_cid = policy.cid;
  const capability = base.connector_capabilities[0];
  capability.source_ref = sourceRef;
  capability.source_contract_cid = view.contract_cid;
  capability.source_view_contract_cid = view.contract_cid;
  delete base.evidence_bundle_cid;
  base.evidence_bundle_cid = contentCid(base);
  const moon = await import(new URL('../../_build/js/release/build/' +
    'connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
  assert.notEqual(moon.clientProgramCheckEnvironment(canonicalJson(base),
    base.evidence_bundle_cid, false, false, true, false, false, false, false),
  undefined, `${name} source environment must admit independently`);
  const database = join(root, `${name}.duckdb`);
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    if (name === 'queries') {
      await connection.run('CREATE TABLE records(request_id VARCHAR, embedding DOUBLE[2], note VARCHAR)');
      await connection.run("INSERT INTO records VALUES ('q1', [1.0, 0.0], NULL)");
    } else {
      await connection.run('CREATE TABLE records(item_id VARCHAR, embedding DOUBLE[2], label VARCHAR)');
      await connection.run("INSERT INTO records VALUES ('b', [0.0, 1.0], 'second'), ('a', [1.0, 0.0], 'first')");
    }
  } finally {connection.closeSync(); instance.closeSync();}
  const profile = join(root, `${name}.profile.json`);
  await writeFile(profile, canonicalJson({
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef,
    queryAliases: [{name, sourceRef, sourceViewContractCid: view.contract_cid,
      schemaContractCid: schema.cid}],
    checkEnvironmentWire: canonicalJson(base),
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: `nearest-${name}`, entries: [{entry_id: 'read',
        outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}],
    }),
  }));
  return profile;
}

test('installed typed vector source admits a scalar projection', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'read-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const profile = await installedVectorSource(root, 'queries');
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: join(root, 'state'), sourceProfilePath: profile}});
  const program = {version: 'actql/0.1', id: 'nearest.typed-source-read',
    stages: [{id: 'read', inputs: {remote: {connector: 'nearest/queries',
      resource: 'r'}},
    steps: [{from: 'remote', filter: 'true', as: 'filtered'},
      {from: 'filtered', select: ['request_id'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['request_id']}}},
    {id: 'project', inputs: {rows: {result: {stage: 'read', result: 'rows'}}},
      steps: [{from: 'rows', filter: 'true', as: 'out'}],
      results: {rows: {from: 'out', fields: ['request_id']}}}],
    results: {answer: {from: {stage: 'project', result: 'rows'}}}};
  const execution = await client.aql(JSON.stringify(program), {format: 'json',
    requestId: 'nearest-typed-source-read'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = [];
  for await (const row of execution.result('answer').rows()) rows.push(row);
  assert.deepEqual(rows, [{request_id: 'q1'}]);
});

// Install independently authored typed rows through the ordinary DuckDB
// Source View profile. No Client-side resolver or vector coercion is involved.
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {canonical} from './two-source-public-query.mjs';

const schemas = Object.freeze({
  queries: {request_id: {type: 'string', nullable: false},
    embedding: {type: 'vector', element_type: 'f32', dimensions: 2,
      nullable: false},
    note: {type: 'string', nullable: true}},
  candidates: {item_id: {type: 'string', nullable: false},
    embedding: {type: 'vector', element_type: 'f32', dimensions: 2,
      nullable: false},
    label: {type: 'string', nullable: false}},
});
const cid = value => 'sha256:' + createHash('sha256')
  .update(canonical(value)).digest('hex');
const withCid = (value, key = 'cid') => {
  const {[key]: ignored, ...body} = value;
  void ignored;
  return cid(body);
};

export async function installNearestSource({root, name, templatePath, duckdb}) {
  if (!(name in schemas)) throw new TypeError('UnknownNearestSource');
  const base = JSON.parse(await readFile(templatePath, 'utf8'));
  const sourceRef = `connector://nearest/${name}/r#v`;
  const connectorId = `nearest/${name}`;
  const schema = base.contract_registry.find(item => item.kind === 'carrier_schema');
  schema.id = `nearest-${name}-schema`;
  schema.body = {type: 'object', nullable: false,
    additional_properties: false, fields: schemas[name]};
  schema.cid = withCid(schema);
  const policy = base.contract_registry.find(item => item.kind === 'data_policy');
  policy.id = `nearest-${name}-policy`;
  policy.body.source_ref = sourceRef;
  policy.cid = withCid(policy);
  const catalog = base.connector_catalogs[0];
  catalog.connector_id = connectorId;
  for (const contract of catalog.contracts) {
    if (contract.kind === 'carrier_schema') {
      contract.body = schema.body;
      contract.cid = schema.cid;
      contract.id = schema.id;
    }
    if (contract.kind === 'data_policy') {
      contract.body = policy.body;
      contract.cid = policy.cid;
      contract.id = policy.id;
    }
  }
  catalog.contracts.sort((left, right) =>
    left.cid.localeCompare(right.cid, 'en'));
  base.contract_registry.sort((left, right) =>
    cid(left).localeCompare(cid(right), 'en'));
  const view = base.source_views[0];
  view.connector_id = connectorId;
  view.output.schema.cid = schema.cid;
  view.output.schema.id = schema.id;
  view.output.data_policy.cid = policy.cid;
  view.output.data_policy.id = policy.id;
  view.contract_cid = withCid(view, 'contract_cid');
  catalog.source_views = [structuredClone(view)];
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
  base.evidence_bundle_cid = withCid(base, 'evidence_bundle_cid');

  const database = join(root, `${name}.duckdb`);
  const instance = await duckdb.DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    if (name === 'queries') {
      await connection.run('CREATE TABLE records(request_id VARCHAR, embedding DOUBLE[2], note VARCHAR)');
      await connection.run("INSERT INTO records VALUES ('q1', [1.0, 0.0], NULL)");
    } else {
      await connection.run('CREATE TABLE records(item_id VARCHAR, embedding DOUBLE[2], label VARCHAR)');
      await connection.run("INSERT INTO records VALUES ('b', [0.0, 1.0], 'second'), ('a', [1.0, 0.0], 'first')");
    }
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
  const profile = join(root, `${name}.profile.json`);
  await writeFile(profile, canonical({
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef,
    queryAliases: [{name, sourceRef, sourceViewContractCid: view.contract_cid,
      schemaContractCid: schema.cid}],
    checkEnvironmentWire: canonical(base),
    accountConfigurationWire: canonical({
      version: 'actql-execution-account-config/0.1',
      account_id: `nearest-${name}`, entries: [{entry_id: 'read',
        outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}],
    }),
  }));
  return {profile, database, environment: base};
}

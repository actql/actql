// Actual installed Host -> public SDK -> approval -> Iceberg/Catalog. This
// source-tree diagnostic is not a packed distribution or Hosted CI campaign.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {inspect} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';

const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const tableContract = JSON.parse(await readFile(new URL('../../spec/contracts/actql-table-effect.json', import.meta.url), 'utf8'));
const connection = 'table-local', resource = 'rows';
const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
const schema = {id: {nullable: false, type: 'number'},
  tag: {nullable: true, type: 'string'}};
const expectedRows = [{id: 1, tag: 'e\u0301\r\n'}, {id: 2, tag: null}, {id: 2, tag: null}];
const multiset = rows => [...rows].sort((a, b) => a.id - b.id);
const account = () => canonicalJson({version: 'actql-execution-account-config/0.1',
  account_id: 'table-public', entries: [
    {entry_id: 'effect', outcome: 'delegate', principal: {all: true},
      connection: {any_of: [connection]}, resource: {any_of: [resource]},
      operation: {any_of: ['effect']}, exclusions: []},
    {entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {any_of: [connection]}, resource: {any_of: [resource]},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'run', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}, exclusions: []}]});

function declaration() {
  const body = JSON.parse(baseWire), manifest = withFixtureConnector(body, targetRef);
  const targetSchema = {additional_properties: false,
    fields: {Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}},
    nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: manifest, conversions: [], mapping_ref: mappingRef,
    minimum_approval: 'required', permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id', required_fields: [],
    required_permissions: [], resource_identity_cid: contentCid(tableContract),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: targetRef, target_schema: targetSchema,
    target_schema_identity: contentCid(targetSchema), version: 'reference-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = contentCid(mapping);
  body.mapping_contracts = [mapping];
  delete body.evidence_bundle_cid;
  return {mapping, wire: canonicalJson({...body, evidence_bundle_cid: contentCid(body)})};
}
function program(rows, id = 'table-public-create') {
  return {version: 'actql/0.1', id, stages: [{id: 'source', inputs: {},
    steps: [{values: {schema, rows}, as: 'output'}],
    results: {rows: {from: 'output', fields: ['id', 'tag']}},
    effects: {save: {store: {target: targetRef, mapping: mappingRef, from: {result: 'rows'}}}}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}};
}
function commits(catalog) {
  const database = new DatabaseSync(catalog.database, {readOnly: true});
  try { return database.prepare('SELECT request_wire,receipt_wire FROM actql_table_commits ORDER BY request_cid').all()
    .map(row => ({operation: JSON.parse(row.request_wire), receipt: JSON.parse(row.receipt_wire)})); }
  finally { database.close(); }
}
async function waiting(run, observations, t) {
  const signal = AbortSignal.timeout(30000);
  for (;;) {
    signal.throwIfAborted();
    const state = await run.status();
    if (state.status === 'waiting_checkpoint') return state;
    if (['failed', 'cancelled', 'needs_reconciliation', 'succeeded'].includes(state.status)) {
      t.diagnostic(inspect(observations, {depth: 10}));
      assert.fail(`Expected approval wait: ${JSON.stringify(state)}`);
    }
    await delay(20, undefined, {signal});
  }
}

async function terminal(run, observations, t) {
  const signal = AbortSignal.timeout(30000);
  for (;;) {
    if (signal.aborted || observations.some(item => item.name.endsWith('_failed'))) {
      t.diagnostic(inspect(observations, {depth: 10}));
      signal.throwIfAborted();
      assert.fail('Installed Host reported a failure during resume');
    }
    const state = await run.wait({signal});
    if (!['running', 'resuming'].includes(state.status)) return state;
    await delay(20, undefined, {signal});
  }
}

for (const rows of [expectedRows, []]) {
test(`Table public ${rows.length ? 'nonempty' : 'empty'} create resumes approval and survives Host close`, async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const effectProfilePath = join(f.root, 'table-effect.json');
  const profile = {version: 'actql-installed-table-effect/0.1', connectorId: 'table', connection,
    python: process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)),
    catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create', catalogCid: f.catalog.catalogCid,
      namespace: ['test'], tableName: 'rows', expectedTable: null, permissions: ['scope:store'],
      footprint: {kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}], limits: {}};
  await writeFile(effectProfilePath, JSON.stringify(profile));
  const keys = generateKeyPairSync('ed25519'), observations = [];
  const authorization = {accountConfiguration: account(),
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'host'), effectProfilePath, authorization}};
  let client = await connectEmbeddedLocal(options).catch(error => {
    assert.fail(error.primaryFailure?.stack ?? error.cause?.stack ?? error.stack);
  });
  try {
    const input = JSON.stringify(program(rows));
    let run = await client.aql(input, {format: 'json', requestId: 'table-create-1'}).catch(error => {
      t.diagnostic(inspect(error, {depth: 10}));
      t.diagnostic(inspect(observations, {depth: 10}));
      throw error;
    });
    await waiting(run, observations, t);
    assert.deepEqual(commits(f.catalog), []);
    const page = await client.checkpoints();
    assert.equal(page.items.length, 1);
    const checkpoint = page.items[0];
    assert.equal(checkpoint.kind, 'effect_set');
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
    const preview = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
    assert.equal(preview.version, 'actql-effect-preview/0.1');
    assert.equal(preview.effects.length, 1);
    assert.equal(preview.effects[0].count, 1, 'One operation, not one write per input row');
    assert.equal(preview.effects[0].approval, 'required');
    const operation = preview.effects[0].changes[0].intended_changes.value;
    assert.equal(operation.action, 'create');
    assert.equal(operation.table_name, 'rows');
    assert.deepEqual(operation.namespace, ['test']);
    assert.equal(operation.expected_table, null);
    const originalRef = run.ref;
    await client.close();
    client = await connectEmbeddedLocal(options);
    run = await client.aql(input, {format: 'json', requestId: 'table-create-1'});
    assert.deepEqual(run.ref, originalRef);
    assert.deepEqual(commits(f.catalog), [], 'Restart does not approve or send');
    assert.equal((await client.checkpoints()).items[0].checkpointCid, checkpoint.checkpointCid);
    const answered = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    assert.deepEqual(answered.results.map(value => value.status), ['committed']);
    const state = await terminal(run, observations, t);
    if (state.status !== 'succeeded') t.diagnostic(inspect(observations, {depth: 10}));
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.equal(commits(f.catalog).length, 1);
    assert.deepEqual(commits(f.catalog)[0].operation, operation);
    assert.equal(commits(f.catalog)[0].receipt.row_count, rows.length);
    assert.deepEqual(multiset(await run.result('answer').all()), multiset(rows));
    const repeated = await client.aql(input, {format: 'json', requestId: 'table-create-1'});
    assert.deepEqual(repeated.ref, run.ref);
    assert.deepEqual(multiset(await (await client.attach(run.ref)).result('answer').all()), multiset(rows));
    assert.equal(commits(f.catalog).length, 1);
  } finally { await client.close(); }
  assert.equal(commits(f.catalog).length, 1);
  const committed = commits(f.catalog)[0];
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'], table_name: 'rows',
    table_uuid: committed.receipt.table_uuid, schema_cid: committed.receipt.schema_cid};
  const frozen = await f.bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  assert.deepEqual(JSON.parse(JSON.stringify((await f.bridge.read(frozen.result.receipt,
    frozen.result.mapping)).result)), rows, 'Actual Iceberg values survive origin Host shutdown');
  const sourceProfilePath = join(f.root, 'table-source.json');
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-table-source/0.1',
    connectorId: 'table', connection, python: profile.python, catalog: f.catalog,
    accountConfigurationWire: account(), targets: [{resource, selector, schemaWire: frozen.result.schema_wire}],
    limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
  const later = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'reader-host'), sourceProfilePath, authorization}});
  try {
    // This public reader exercises the existing guaranteed-column projection.
    // The exact complete values were separately checked through actual Iceberg
    // I/O above; it does not certify public sparse/all-column read support.
    const reader = {version: 'actql/0.1', id: 'read-committed-table', stages: [
      {id: 'read', inputs: {input: {connector: 'table', resource}},
        steps: [{filter: 'id >= 0', as: 'kept'}, {select: ['id'], as: 'output'}],
        results: {rows: {from: 'output', fields: ['id']}}},
      {id: 'compute', inputs: {input: {result: {stage: 'read', result: 'rows'}}},
        steps: [{derive: {doubled: 'id * 2'}, as: 'output'}],
        results: {rows: {from: 'output', fields: ['id', 'doubled']}}}],
      results: {answer: {from: {stage: 'compute', result: 'rows'}}}};
    const readRun = await later.start(reader, {requestId: 'new-table-reader'});
    const state = await terminal(readRun, observations, t);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(multiset(await readRun.result('answer').all()),
      multiset(rows.map(row => ({id: row.id, doubled: row.id * 2}))));
    assert.equal(commits(f.catalog).length, 1);
  } finally { await later.close(); }
});
}

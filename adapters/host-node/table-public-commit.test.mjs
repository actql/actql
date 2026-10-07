// Actual installed Host -> public SDK -> approval -> Iceberg/Catalog. This
// source-tree diagnostic is not a packed distribution or Hosted CI campaign.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {readFile, writeFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {inspect} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';

const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const tableContract = JSON.parse(await readFile(new URL('../../spec/contracts/actql-table-effect.json', import.meta.url), 'utf8'));
const connection = 'table-local', resource = 'rows';
const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
const schema = {id: {nullable: false, type: 'number'},
  tag: {nullable: true, type: 'string'}};
const expectedRows = [{id: 1, tag: 'e\u0301\r\n'}, {id: 2, tag: null}, {id: 2, tag: null}];
const multiset = rows => [...rows].sort((a, b) => a.id - b.id);
const plain = value => JSON.parse(JSON.stringify(value));
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
function readerProgram(id = 'read-committed-table') {
  return {version: 'actql/0.1', id, stages: [
    {id: 'read', inputs: {input: {connector: 'table', resource}},
      steps: [{filter: 'id >= 0', as: 'kept'}, {select: ['id'], as: 'output'}],
      results: {rows: {from: 'output', fields: ['id']}}},
    {id: 'compute', inputs: {input: {result: {stage: 'read', result: 'rows'}}},
      steps: [{derive: {doubled: 'id * 2'}, as: 'output'}],
      results: {rows: {from: 'output', fields: ['id', 'doubled']}}}],
    results: {answer: {from: {stage: 'compute', result: 'rows'}}}};
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
    let state;
    try { state = await run.wait({signal}); }
    catch (error) {
      t.diagnostic(inspect({ref: run.ref, state: await run.status(), observations}, {depth: 12}));
      throw error;
    }
    if (!['running', 'resuming'].includes(state.status)) return state;
    await delay(20, undefined, {signal});
  }
}

test('Table public lost commit reply reconciles the original Run without another write', async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  const launcher = join(f.root, 'lost-commit-reply');
  // The configured optional Python executable runs the product worker. Only
  // the real Catalog's post-commit hook is faulted; no receipt is fabricated.
  await writeFile(launcher, `#!${python}
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from process_worker import serve
root = Path(__file__).parent
def factory(*args):
    # Match the product worker: optional heavy libraries load after handshake.
    from catalog import TableCatalog
    class LostReplyCatalog(TableCatalog):
        def write_claimed(self, *args, **kwargs):
            with (root / "writes.log").open("a") as stream:
                stream.write("write\\n")
            return super().write_claimed(*args, **kwargs)
        def after_publication(self):
            marker = root / "lost-reply"
            if not marker.exists():
                marker.write_text("committed")
                os._exit(9)
    return LostReplyCatalog(*args)
with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
`, {mode: 0o700});
  const effectProfilePath = join(f.root, 'table-effect.json');
  const profile = {version: 'actql-installed-table-effect/0.1',
    connectorId: 'table', connection, python: launcher, catalog: f.catalog,
    accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'],
      footprint: {kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}],
    limits: {reservation: {bytes: 1048576, files: 16}}};
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
  let client = await connectEmbeddedLocal(options);
  try {
    const input = JSON.stringify(program(expectedRows, 'table-lost-reply'));
    let run = await client.aql(input, {format: 'json', requestId: 'table-lost-reply'});
    await waiting(run, observations, t);
    assert.equal(commits(f.catalog).length, 0, 'No write before approval');
    const checkpoint = (await client.checkpoints()).items[0];
    await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    assert.equal((await terminal(run, observations, t)).status, 'needs_reconciliation');
    const original = commits(f.catalog);
    if (original.length !== 1) {
      const read = name => readFile(join(f.root, name), 'utf8')
        .catch(error => ({unavailable: error.code}));
      t.diagnostic(inspect({phase: 'fault-not-reached', state: await run.status(),
        commits: original, writes: await read('writes.log'),
        fault: await read('lost-reply'), observations}, {depth: 10}));
    }
    assert.equal(original.length, 1, 'Catalog actually committed before reply loss');
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), 'write\n');
    t.diagnostic(JSON.stringify({phase: 'committed-reply-lost', ref: run.ref,
      originalCommit: original[0]}));
    const ref = run.ref;
    await client.close();
    // Advance the Table head through a different approved public operation
    // before resolving the original uncertainty. Head equality cannot prove
    // the first operation's outcome; its own durable commit record must.
    const replacementPath = join(f.root, 'replacement-effect.json');
    await writeFile(replacementPath, JSON.stringify({...profile,
      targets: profile.targets.map(target => ({...target, action: 'replace',
        expectedTable: {table_uuid: original[0].receipt.table_uuid,
          generation_cid: original[0].receipt.generation_cid}}))}));
    const replacement = await connectEmbeddedLocal({...options,
      installation: {...options.installation,
        directory: join(f.root, 'replacement-host'), effectProfilePath: replacementPath}});
    try {
      const replaced = await replacement.aql(JSON.stringify(program([{id: 9, tag: null}],
        'table-later-replacement')), {format: 'json', requestId: 'table-later-replacement'});
      await waiting(replaced, observations, t);
      const laterCheckpoint = (await replacement.checkpoints()).items[0];
      await replacement.resolveCheckpoints([{checkpoint: laterCheckpoint, decision: 'approved'}], {signer: {
        keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: replaced.ref.authorityScopeCid,
        sign: bytes => sign(null, bytes, keys.privateKey)}});
      assert.equal((await terminal(replaced, observations, t)).status, 'succeeded');
      assert.deepEqual(await replaced.result('answer').all(), [{id: 9, tag: null}]);
    } finally { await replacement.close(); }
    const afterReplacement = commits(f.catalog);
    assert.equal(afterReplacement.length, 2);
    assert.deepEqual(afterReplacement.find(item => item.operation.request_cid ===
      original[0].operation.request_cid), original[0]);
    const head = await f.bridge.resolveGeneration({catalog_identity_cid: f.catalog.catalogCid,
      namespace: ['test'], table_name: 'rows', table_uuid: original[0].receipt.table_uuid,
      schema_cid: original[0].receipt.schema_cid});
    assert.equal(head.ok, true);
    assert.notEqual(head.result.receipt.generation_cid, original[0].receipt.generation_cid);
    client = await connectEmbeddedLocal(options);
    run = await client.attach(ref);
    assert.equal((await run.status()).status, 'needs_reconciliation');
    let reconciled;
    try { reconciled = await Promise.all([run.reconcile(), run.reconcile()]); }
    catch (error) {
      t.diagnostic(inspect({phase: 'public-reconcile', error, observations}, {depth: 10}));
      throw error;
    }
    assert.deepEqual(reconciled.map(state => state.status), ['succeeded', 'succeeded']);
    assert.deepEqual(commits(f.catalog), afterReplacement);
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), 'write\nwrite\n',
      'Unknown commit is never resent');
    assert.deepEqual(multiset(await run.result('answer').all()), multiset(expectedRows));
    await client.close();
    client = await connectEmbeddedLocal(options);
    run = await client.attach(ref);
    assert.equal((await run.reconcile()).status, 'succeeded');
    assert.deepEqual(multiset(await run.result('answer').all()), multiset(expectedRows));
    assert.deepEqual(commits(f.catalog), afterReplacement);
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), 'write\nwrite\n');
  } finally { await client.close(); }
});

test('Table installed HTTP Host retires capture custody before completing close', async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const effectProfilePath = join(f.root, 'table-effect-close.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-table-effect/0.1', connectorId: 'table', connection,
    python: process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)),
    catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'],
      footprint: {kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}], limits: {}}));
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const host = await openInstalledRemoteHttpHost({directory: join(f.root, 'http-host'),
    authenticate: () => principalId, effectProfilePath, authorization: {
      accountConfiguration: account(), reviewReaders: [principalId],
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    }});
  const first = await host.close();
  assert.equal(first.storeCleanupPending, false);
  assert.equal(first.authorizationCleanupPending, false);
  assert.deepEqual(first.pendingRetention, []);
  assert.deepEqual(await host.close(), first, 'Repeated close completes without reopening or re-retiring');
  assert.equal(commits(f.catalog).length, 0, 'Closing an installed writer sends no operation');
});

for (const rows of [expectedRows, []]) {
test(`Table public ${rows.length ? 'nonempty create and replace' : 'empty create'} resume approval and survive Host close`, async t => {
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
        resource_kind: 'Table', provider_object_identity_cids: []}}],
    // Committed generations retain their reservations; reserve a finite 1 MiB
    // per operation so three generations fit the fixture's 16 MiB Catalog.
    // The empty create still exercises the installed default limits.
    limits: rows.length ? {reservation: {bytes: 1048576, files: 16}} : {}};
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
    assert.deepEqual((await client.resolveCheckpoints(answered.signed)).results.map(value => value.status),
      ['duplicate'], 'Repeating the signed approval does not authorize another operation');
    assert.equal(commits(f.catalog).length, 1);
  } finally { await client.close(); }
  assert.equal(commits(f.catalog).length, 1);
  const committed = commits(f.catalog)[0];
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'], table_name: 'rows',
    table_uuid: committed.receipt.table_uuid, schema_cid: committed.receipt.schema_cid};
  const frozen = await f.bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  assert.deepEqual(JSON.parse(frozen.result.schema_wire), schema);
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
    const readRun = await later.start(readerProgram(), {requestId: 'new-table-reader'});
    const state = await terminal(readRun, observations, t);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(multiset(await readRun.result('answer').all()),
      multiset(rows.map(row => ({id: row.id, doubled: row.id * 2}))));
    assert.equal(commits(f.catalog).length, 1);
  } finally { await later.close(); }
  if (rows.length) {
    // Each replacement is an ordinary submitted Program, not a direct writer
    // fixture. Restart at approval before entering the original send claim.
    let previous = committed;
    const replacementRows = [{id: 7, tag: null}, {id: 9, tag: 'replaced'},
      {id: 9, tag: 'replaced'}];
    for (const [index, replacement] of [replacementRows, []].entries()) {
      const expectedTable = {table_uuid: previous.receipt.table_uuid,
        generation_cid: previous.receipt.generation_cid};
      const replaceProfilePath = join(f.root, `replace-${index}.json`);
      await writeFile(replaceProfilePath, JSON.stringify({...profile,
        targets: profile.targets.map(target => ({...target, action: 'replace', expectedTable}))}));
      const replaceOptions = {...options, installation: {...options.installation,
        directory: join(f.root, `replace-host-${index}`), effectProfilePath: replaceProfilePath}};
      let replacing = await connectEmbeddedLocal(replaceOptions);
      const input = JSON.stringify(program(replacement, `table-public-replace-${index}`));
      const requestId = `replace-${index}`;
      const before = commits(f.catalog).length;
      let operation;
      try {
        let run = await replacing.aql(input, {format: 'json', requestId});
        await waiting(run, observations, t);
        assert.equal(commits(f.catalog).length, before, 'No replacement before approval');
        const checkpoint = (await replacing.checkpoints()).items[0];
        const review = await replacing.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
        const preview = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
        assert.equal(preview.effects.length, 1);
        assert.equal(preview.effects[0].count, 1);
        assert.equal(preview.effects[0].approval, 'required');
        operation = preview.effects[0].changes[0].intended_changes.value;
        assert.equal(operation.action, 'replace');
        assert.deepEqual(operation.expected_table, expectedTable);
        assert.equal(operation.schema_cid, committed.receipt.schema_cid);
        const originalRef = run.ref;
        await replacing.close();
        replacing = await connectEmbeddedLocal(replaceOptions);
        run = await replacing.aql(input, {format: 'json', requestId});
        assert.deepEqual(run.ref, originalRef);
        assert.equal((await replacing.checkpoints()).items[0].checkpointCid, checkpoint.checkpointCid);
        assert.equal(commits(f.catalog).length, before, 'Restart does not send the replacement');
        const answered = await replacing.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
          keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, keys.privateKey)}});
        assert.deepEqual(answered.results.map(value => value.status), ['committed']);
        const state = await terminal(run, observations, t);
        if (state.status !== 'succeeded') {
          const root = replaceOptions.installation.directory;
          const ledgers = [];
          for (const path of await readdir(join(root, 'state', 'effects', 'ledger'), {recursive: true})) {
            if (!path.endsWith('effect-ledger.sqlite3')) continue;
            const database = new DatabaseSync(join(root, 'state', 'effects', 'ledger', path), {readOnly: true});
            try { ledgers.push({responses: database.prepare(
              'SELECT status_code,CAST(response_bytes AS TEXT) AS body FROM effect_ledger_responses').all(),
              entries: database.prepare('SELECT entry_json FROM effect_ledger_entries ORDER BY revision').all()}); }
            finally { database.close(); }
          }
          t.diagnostic(inspect({operation, observedCommits: commits(f.catalog), ledgers, observations}, {depth: 12}));
        }
        assert.equal(state.status, 'succeeded', JSON.stringify(state));
        assert.deepEqual(multiset(await run.result('answer').all()), multiset(replacement));
        assert.deepEqual((await replacing.resolveCheckpoints(answered.signed)).results.map(value => value.status),
          ['duplicate']);
        assert.equal(commits(f.catalog).length, before + 1);
      } finally { await replacing.close(); }
      const updated = commits(f.catalog).find(value => value.operation.request_cid === operation.request_cid);
      assert.deepEqual(updated.operation, operation);
      assert.equal(updated.receipt.table_uuid, committed.receipt.table_uuid);
      assert.equal(updated.receipt.schema_cid, committed.receipt.schema_cid);
      assert.notEqual(updated.receipt.generation_cid, previous.receipt.generation_cid);
      assert.equal(updated.receipt.row_count, replacement.length);
      const current = await f.bridge.resolveGeneration(selector);
      assert.equal(current.ok, true);
      assert.equal(current.result.receipt.generation_cid, updated.receipt.generation_cid);
      assert.deepEqual(JSON.parse(current.result.schema_wire), schema);
      assert.deepEqual(plain((await f.bridge.read(current.result.receipt, current.result.mapping)).result), replacement);
      const currentSourceProfilePath = join(f.root, `replacement-source-${index}.json`);
      await writeFile(currentSourceProfilePath, JSON.stringify({version: 'actql-installed-table-source/0.1',
        connectorId: 'table', connection, python: profile.python, catalog: f.catalog,
        accountConfigurationWire: account(), targets: [{resource, selector, schemaWire: current.result.schema_wire}],
        limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
      const reader = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
        installation: {directory: join(f.root, `replacement-reader-${index}`),
          sourceProfilePath: currentSourceProfilePath, authorization}});
      try {
        const run = await reader.start(readerProgram(`read-replacement-${index}`), {requestId: `read-${index}`});
        assert.equal((await terminal(run, observations, t)).status, 'succeeded');
        assert.deepEqual(multiset(await run.result('answer').all()),
          multiset(replacement.map(row => ({id: row.id, doubled: row.id * 2}))));
        assert.equal(commits(f.catalog).length, before + 1);
      } finally { await reader.close(); }
      previous = updated;
    }
    assert.equal(commits(f.catalog).length, 3);
    const original = await f.bridge.reconcileOperation(committed.operation);
    assert.equal(original.ok, true);
    assert.deepEqual(plain(original.result), committed.receipt,
      'Original operation reconciliation is independent of the latest Table head');
    assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result), rows,
      'A frozen generation remains readable after later replacements');
  }
});
}

// Actual installed Host -> public SDK -> approval -> Iceberg/Catalog. The
// packed runner selects installed product modules, never a source overlay.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {execFile, execFileSync} from 'node:child_process';
import {readFile, writeFile, readdir, unlink} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {inspect, promisify} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';
import {tableTestModule} from './fixtures/table-test-modules.mjs';
import {ctasResultControl, ctasRetainedResult} from './fixtures/table-ctas-result-control.mjs';

const {connect, getSubmissionOutcome} = await tableTestModule(
  new URL('../../packages/sdk/index.mjs', import.meta.url), '@actql/sdk');
const {canonicalJson, contentCid} = await tableTestModule(
  new URL('./local-account-config.mjs', import.meta.url), 'adapters/host-node/local-account-config.mjs');
const local = await tableTestModule(new URL('./embedded-local.mjs', import.meta.url), '@actql/local-node');
const connectEmbeddedLocal = local.connectEmbeddedLocal ?? local.connect;
const {openInstalledRemoteHttpHost} = await tableTestModule(
  new URL('./embedded-local.mjs', import.meta.url), '@actql/local-node/http-host');

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
    {entry_id: 'original-run-result-read', outcome: 'allow',
      principal: {any_of: [userInfo().username]},
      connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {any_of: [connection]}, resource: {any_of: [resource]},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'run', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}, exclusions: []}]});

function declaration(inputField = 'id') {
  const body = JSON.parse(baseWire), manifest = withFixtureConnector(body, targetRef);
  const targetSchema = {additional_properties: false,
    fields: {Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}},
    nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: manifest, conversions: [], mapping_ref: mappingRef,
    minimum_approval: 'required', permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id', required_fields: [],
    required_permissions: [], resource_identity_cid: contentCid(tableContract),
    row_mapping: {Name: {field: inputField, null_behavior: 'reject'}},
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
function commits(catalog, busyTimeout = 0) {
  const database = new DatabaseSync(catalog.database, {readOnly: true});
  try {
    // Only a live-commit observation needs this bounded read wait. It does
    // not retry a writer or infer publication from a locked Catalog.
    if (busyTimeout === 1000) database.exec('PRAGMA busy_timeout=1000');
    else assert.equal(busyTimeout, 0);
    return database.prepare('SELECT request_wire,receipt_wire FROM actql_table_commits ORDER BY request_cid').all()
      .map(row => ({operation: JSON.parse(row.request_wire), receipt: JSON.parse(row.receipt_wire)}));
  }
  finally { database.close(); }
}
function readerProgram(id = 'read-committed-table') {
  return {version: 'actql/0.1', id, stages: [
    {id: 'read', inputs: {input: {connector: 'table', resource}},
      steps: [{filter: 'id >= 0', as: 'kept'}, {select: ['id', 'tag'], as: 'output'}],
      results: {rows: {from: 'output', fields: ['id', 'tag']}}},
    {id: 'compute', inputs: {input: {result: {stage: 'read', result: 'rows'}}},
      steps: [{derive: {doubled: 'id * 2'}, as: 'output'}],
      results: {rows: {from: 'output', fields: ['id', 'tag', 'doubled']}}}],
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
      t.diagnostic(inspect({ref: run.ref, state: await run.status(), observations,
        waitAborted: signal.aborted, waitReason: signal.reason}, {depth: 12}));
      throw error;
    }
    if (!['running', 'resuming'].includes(state.status)) return state;
    await delay(20, undefined, {signal});
  }
}

for (const replyMode of ['saved', 'lost']) {
for (const format of replyMode === 'saved' ? ['json', 'sql'] : ['json']) {
test(`Table public concurrent replace ${replyMode} noncommit reply preserves the original failure` +
  (format === 'sql' ? ' (Effect-only SQL)' : ''), async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  const launcher = join(f.root, 'concurrent-replace');
  await writeFile(launcher, `#!${python}
import json, os, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from process_worker import serve
root = Path(__file__).parent
def factory(*args):
    from catalog import TableCatalog
    class ConcurrentCatalog(TableCatalog):
        def write_claimed(self, *args, **kwargs):
            with (root / "writes.log").open("a") as stream:
                stream.write(args[0]["request_cid"] + "\\n")
            return super().write_claimed(*args, **kwargs)
        def confirm_noncommit(self, request, reason):
            result = super().confirm_noncommit(request, reason)
            if ${replyMode === 'lost' ? 'True' : 'False'} and result["version"] == "actql-table-noncommit-receipt/0.1":
                # Persist the product's original fact and fence, then lose
                # the reply. No fixture supplies a receipt or terminal Run.
                (root / "lost-noncommit-reply").write_text(request["request_cid"])
                os._exit(9)
            return result
        def before_publication(self):
            request = self.context[0]
            if request["action"] != "replace":
                return
            path = root / ("staged-" + request["request_cid"][7:])
            path.write_text(json.dumps(request))
            deadline = time.monotonic() + 30
            while not (root / ("release-" + request["request_cid"][7:])).exists():
                if time.monotonic() >= deadline:
                    raise TimeoutError("FixturePublicationBarrier")
                time.sleep(0.01)
    return ConcurrentCatalog(*args)
with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
`, {mode: 0o700});
  const keys = generateKeyPairSync('ed25519'), observations = [];
  const authorization = {accountConfiguration: account(),
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const opened = [];
  const open = async (name, rows, expectedTable = null) => {
    const effectProfilePath = join(f.root, `${name}-effect.json`);
    await writeFile(effectProfilePath, JSON.stringify({version: 'actql-installed-local-table-effect/0.1',
      connectorId: 'table', connection, python: launcher, catalog: f.catalog,
      accountConfigurationWire: account(), environmentWire: declared.wire,
      targets: [{effectId: 'save', resource, targetRef, mappingRef,
        ...(format === 'sql' ? {queryName: 'analytics.report'} : {}),
        mappingCid: declared.mapping.mapping_contract_cid, action: expectedTable === null ? 'create' : 'replace',
        catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows', expectedTable,
        permissions: ['scope:store'], footprint: {kind: 'collection',
          resource_identity_scheme_cid: contentCid(tableContract), provider_namespace: 'table',
          provider_boundary_cid: f.catalog.catalogCid, resource_kind: 'Table', provider_object_identity_cids: []}}],
      limits: {reservation: {bytes: 1048576, files: 16}}}));
    const options = {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: join(f.root, name), effectProfilePath, authorization}};
    const client = await connectEmbeddedLocal(options);
    opened.push(client);
    const text = `${expectedTable === null ? 'CREATE TABLE' : 'CREATE OR REPLACE TABLE'} analytics.report AS ` +
      `SELECT ${rows[0].id} AS id, CAST(NULL AS STRING) AS tag`;
    const run = await client.startSource(format === 'sql' ? text : JSON.stringify(program(rows, name)), {format});
    await waiting(run, observations, t);
    const checkpoint = (await client.checkpoints()).items[0];
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
    const preview = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
    const operation = preview.effects[0].changes[0].intended_changes.value;
    assert.deepEqual(operation.expected_table, expectedTable);
    const approve = () => client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    return {client, run, operation, approve, options};
  };
  try {
    const created = await open('create-base', expectedRows);
    assert.equal(commits(f.catalog).length, 0);
    await created.approve();
    assert.equal((await terminal(created.run, observations, t)).status, 'succeeded');
    const original = commits(f.catalog)[0];
    const expected = {table_uuid: original.receipt.table_uuid, generation_cid: original.receipt.generation_cid};
    const winnerRows = [{id: 10, tag: null}, {id: 10, tag: null}];
    const first = await open('replace-first', winnerRows, expected);
    const second = await open('replace-second', [{id: 20, tag: 'second'}], expected);
    assert.equal(commits(f.catalog).length, 1, 'Both replacements still require approval');
    await Promise.all([first.approve(), second.approve()]);
    const signal = AbortSignal.timeout(30000);
    const staged = value => join(f.root, `staged-${value.operation.request_cid.slice(7)}`);
    for (;;) {
      signal.throwIfAborted();
      const ready = await Promise.all([first, second].map(value =>
        readFile(staged(value), 'utf8').then(wire => {
          assert.deepEqual(JSON.parse(wire), value.operation);
          return true;
        }).catch(error => { if (error.code === 'ENOENT') return false; throw error; })));
      if (ready.every(Boolean)) break;
      await delay(20, undefined, {signal});
    }
    assert.equal(commits(f.catalog).length, 1, 'Both writers staged against the same old head');
    await writeFile(join(f.root, `release-${first.operation.request_cid.slice(7)}`), 'commit');
    assert.equal((await terminal(first.run, observations, t)).status, 'succeeded');
    await writeFile(join(f.root, `release-${second.operation.request_cid.slice(7)}`), 'commit');
    const loser = await terminal(second.run, observations, t);
    t.diagnostic(JSON.stringify({phase: 'concurrent-replace', loser, commits: commits(f.catalog),
      firstOperation: first.operation, secondOperation: second.operation}));
    assert.equal(loser.status, replyMode === 'lost' ? 'needs_reconciliation' : 'failed',
      'Reply loss is uncertain until original durable evidence is observed');
    assert.equal(commits(f.catalog).length, 2);
    if (format === 'sql') {
      assert.deepEqual((await first.run.status()).result_availability, {});
      const frozen = await f.bridge.resolveGeneration({catalog_identity_cid: f.catalog.catalogCid,
        namespace: ['test'], table_name: 'rows', table_uuid: original.receipt.table_uuid,
        schema_cid: original.receipt.schema_cid});
      assert.equal(frozen.ok, true);
      assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result),
        [{id: 10, tag: null}], 'The conflict cannot overwrite the approved winning SQL input');
    } else assert.deepEqual(multiset(await first.run.result('answer').all()), winnerRows);
    const noncommit = await f.bridge.reconcileOperation(second.operation);
    assert.equal(noncommit.ok, false);
    assert.equal(noncommit.result.version, 'actql-table-noncommit-receipt/0.1');
    assert.equal(noncommit.result.request_cid, second.operation.request_cid);
    assert.equal(noncommit.result.reason, 'ExpectedGenerationConflict');
    if (replyMode === 'lost') {
      assert.equal(await readFile(join(f.root, 'lost-noncommit-reply'), 'utf8'), second.operation.request_cid);
      assert.equal((await second.run.status()).status, 'needs_reconciliation',
        'A direct Catalog fixture lookup is not a public Run settlement');
    } else assert.equal((await second.run.reconcile()).status, 'failed');
    await second.client.close();
    const audit = new DatabaseSync(f.catalog.database, {readOnly: true});
    try {
      assert.deepEqual(plain(audit.prepare('SELECT reserved_bytes,reserved_files FROM actql_table_allocations WHERE request_cid=?')
        .get(second.operation.request_cid)), {reserved_bytes: 0, reserved_files: 0},
      'Only the losing operation reservation is returned after confirmed cleanup');
      assert.equal(audit.prepare('SELECT cleanup_complete FROM actql_table_publication_fences WHERE request_cid=?')
        .get(second.operation.request_cid).cleanup_complete, 1);
    } finally { audit.close(); }
    const later = replyMode === 'lost' ? await open('replace-later', [{id: 30, tag: 'later'}], {
      table_uuid: original.receipt.table_uuid,
      generation_cid: commits(f.catalog).find(item => item.operation.request_cid ===
        first.operation.request_cid).receipt.generation_cid}) : undefined;
    if (later !== undefined) {
      await later.approve();
      // The first two writers still use their barriers; a subsequent operation
      // is likewise released only after actual staging, not before preflight.
      const signal = AbortSignal.timeout(30000);
      for (;;) {
        signal.throwIfAborted();
        const ready = await readFile(staged(later), 'utf8').then(wire => {
          assert.deepEqual(JSON.parse(wire), later.operation);
          return true;
        }).catch(error => { if (error.code === 'ENOENT') return false; throw error; });
        if (ready) break;
        await delay(20, undefined, {signal});
      }
      await writeFile(join(f.root, `release-${later.operation.request_cid.slice(7)}`), 'commit');
      assert.equal((await terminal(later.run, observations, t)).status, 'succeeded');
      assert.deepEqual(await later.run.result('answer').all(), [{id: 30, tag: 'later'}]);
    }
    const committedBeforeRecovery = commits(f.catalog);
    const restarted = await connectEmbeddedLocal(second.options);
    opened.push(restarted);
    const recovered = await restarted.attach(second.run.ref);
    assert.equal((await recovered.status()).status, replyMode === 'lost' ? 'needs_reconciliation' : 'failed');
    assert.deepEqual((await Promise.all([recovered.reconcile(), recovered.reconcile()]))
      .map(state => state.status), ['failed', 'failed']);
    assert.equal((await recovered.reconcile()).status, 'failed');
    assert.deepEqual(plain(await f.bridge.reconcileOperation(second.operation)), plain(noncommit),
      'The original noncommit receipt remains exact after Host restart and cleanup');
    assert.deepEqual(commits(f.catalog), committedBeforeRecovery,
      'Concurrent recovery uses original evidence, not the later Table head');
    assert.deepEqual((await readFile(join(f.root, 'writes.log'), 'utf8')).trim().split('\n').sort(),
      [created.operation.request_cid, first.operation.request_cid, second.operation.request_cid,
        ...(later === undefined ? [] : [later.operation.request_cid])].sort(),
      'Each approved occurrence enters the writer once; conflict never retries');
  } finally {
    // Release either barrier on a failed assertion, then let each existing Host
    // drain its own process/custody. Never kill another test or delete a live file.
    for (const name of await readdir(f.root)) {
      if (name.startsWith('staged-')) await writeFile(join(f.root, name.replace('staged-', 'release-')), 'stop');
    }
    for (const client of opened.reverse()) await client.close();
  }
});
}
}

for (const lossPoint of ['before', 'after']) {
for (const format of ['json', 'sql']) {
test((lossPoint === 'before'
  ? 'Table public precommit crash remains unknown across repeated reconciliation'
  : 'Table public lost commit reply reconciles the original Run without another write') +
  (format === 'sql' ? ' (Effect-only SQL)' : ''), async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  const launcher = join(f.root, 'lost-commit-reply');
  // The configured optional Python executable runs the product worker. The
  // crash is before the Catalog write or after publication; no receipt is fabricated.
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
            if ${lossPoint === 'before' ? 'True' : 'False'}:
                os._exit(9)
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
  const profile = {version: 'actql-installed-local-table-effect/0.1',
    connectorId: 'table', connection, python: launcher, catalog: f.catalog,
    accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', resource, targetRef, mappingRef,
      ...(format === 'sql' ? {queryName: 'analytics.report'} : {}),
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
    const input = format === 'sql'
      ? 'CREATE TABLE analytics.report AS SELECT 1 AS id, CAST(NULL AS STRING) AS tag'
      : JSON.stringify(program(expectedRows, 'table-lost-reply'));
    let run = await client.startSource(input, {format});
    await waiting(run, observations, t);
    assert.equal(commits(f.catalog).length, 0, 'No write before approval');
    const checkpoint = (await client.checkpoints()).items[0];
    await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    assert.equal((await terminal(run, observations, t)).status, 'needs_reconciliation');
    const original = commits(f.catalog);
    if (lossPoint === 'before') {
      assert.equal(original.length, 0, 'The real Catalog has no original receipt');
      const writes = await readFile(join(f.root, 'writes.log'), 'utf8');
      assert.equal(writes.split('write').length - 1, 1);
      const ref = run.ref;
      await client.close();
      client = await connectEmbeddedLocal(options);
      run = await client.attach(ref);
      const before = await run.status();
      assert.equal(before.status, 'needs_reconciliation');
      assert.equal(before.control.physical_stop, 'confirmed');
      const retained = () => {
        const database = new DatabaseSync(join(f.root, 'host', 'requests',
          'client-requests.sqlite3'), {readOnly: true});
        try { return {...database.prepare(`SELECT revision, reconciliation_state_wire
          FROM client_requests WHERE run_definition_cid = ?`).get(ref.runDefinitionCid)}; }
        finally { database.close(); }
      };
      const originalState = retained();
      assert.equal(JSON.parse(originalState.reconciliation_state_wire).status,
        'needs_reconciliation');
      for (let observation = 0; observation < 2; observation++) {
        await delay(20);
        const state = await run.reconcile();
        assert.deepEqual(state, before, '[table-still-unknown:original-observation]');
        assert.deepEqual(retained(), originalState, '[table-still-unknown:journal-custody]');
        assert.deepEqual(run.ref, ref);
        assert.equal(commits(f.catalog).length, 0);
        assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), writes,
          '[table-still-unknown:no-resend]');
      }
      return;
    }
    if (original.length !== 1) {
      const read = name => readFile(join(f.root, name), 'utf8')
        .catch(error => ({unavailable: error.code}));
      t.diagnostic(inspect({phase: 'fault-not-reached', state: await run.status(),
        commits: original, writes: await read('writes.log'),
        fault: await read('lost-reply'), observations}, {depth: 10}));
    }
    assert.equal(original.length, 1, 'Catalog actually committed before reply loss');
    if (format === 'sql') {
      const frozen = await f.bridge.resolveGeneration({catalog_identity_cid: f.catalog.catalogCid,
        namespace: ['test'], table_name: 'rows', table_uuid: original[0].receipt.table_uuid,
        schema_cid: original[0].receipt.schema_cid});
      assert.equal(frozen.ok, true);
      assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result),
        [{id: 1, tag: null}], 'The uncertain original SQL operation really saved its input');
    }
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
      const replaced = await replacement.startSource(format === 'sql'
        ? 'CREATE OR REPLACE TABLE analytics.report AS SELECT 9 AS id, CAST(NULL AS STRING) AS tag'
        : JSON.stringify(program([{id: 9, tag: null}], 'table-later-replacement')), {format});
      await waiting(replaced, observations, t);
      const laterCheckpoint = (await replacement.checkpoints()).items[0];
      await replacement.resolveCheckpoints([{checkpoint: laterCheckpoint, decision: 'approved'}], {signer: {
        keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: replaced.ref.authorityScopeCid,
        sign: bytes => sign(null, bytes, keys.privateKey)}});
      assert.equal((await terminal(replaced, observations, t)).status, 'succeeded');
      if (format === 'sql') assert.deepEqual((await replaced.status()).result_availability, {});
      else assert.deepEqual(await replaced.result('answer').all(), [{id: 9, tag: null}]);
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
    if (format === 'sql') assert.deepEqual(
      plain((await f.bridge.read(head.result.receipt, head.result.mapping)).result),
      [{id: 9, tag: null}], 'OR REPLACE commits its fixed approved generation, not a public Result');
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
    const expectedWrites = 'write\nwrite\n';
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), expectedWrites,
      'Unknown commit is never resent');
    if (format === 'sql') assert.deepEqual((await run.status()).result_availability, {});
    else assert.deepEqual(multiset(await run.result('answer').all()), multiset(expectedRows));
    await client.close();
    client = await connectEmbeddedLocal(options);
    run = await client.attach(ref);
    assert.equal((await run.reconcile()).status, 'succeeded');
    if (format === 'sql') assert.deepEqual((await run.status()).result_availability, {});
    else assert.deepEqual(multiset(await run.result('answer').all()), multiset(expectedRows));
    assert.deepEqual(commits(f.catalog), afterReplacement);
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), expectedWrites);
  } finally { await client.close(); }
});
}
}

async function sparseTableClientOpener(t, root, transport) {
  if (transport === 'Local') return connectEmbeddedLocal;
  const priorCertificates = getCACertificates('default');
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
  const key = await readFile(join(root, 'host.key'));
  const cert = await readFile(join(root, 'host.crt'));
  setDefaultCACertificates([...priorCertificates, cert.toString()]);
  t.after(() => setDefaultCACertificates(priorCertificates));
  return async options => {
    const host = await openInstalledRemoteHttpHost({...options.installation,
      authenticate: header => header === 'Bearer table-fixture' ? userInfo().username : undefined});
    const server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const client = await connect({mode: 'remote', durability: 'durable', token: 'table-fixture',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
    let closed = false;
    return Object.freeze({...client, async close() {
      if (closed) return;
      await client.close();
      if (server.listening) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      const result = await host.close();
      assert.equal(result.storeCleanupPending, false);
      assert.equal(result.authorizationCleanupPending, false);
      assert.deepEqual(result.pendingRetention, []);
      closed = true;
    }});
  };
}

for (const transport of ['Local', 'HTTPS']) {
for (const empty of [false, true]) {
test(`Table text Effect-only CTAS through ${transport} (${empty ? 'empty' : 'nonempty'}) retains approval and reads after origin release`, async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const openClient = await sparseTableClientOpener(t, f.root, transport);
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const observations = [];
  const authorization = {accountConfiguration: account(), reviewReaders: [principalId],
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const effectProfilePath = join(f.root, 'text-table-effect.json');
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
    python, catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', queryName: 'analytics.report', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'], footprint: {
        kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}],
    limits: {reservation: {bytes: 1048576, files: 16}}}));
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'text-host'), effectProfilePath, authorization}};
  // These values and the absence of public Results are independent expected
  // facts. No serializer output is used to construct an oracle.
  const text = 'CREATE TABLE analytics.report AS SELECT 1 AS id, CAST(NULL AS STRING) AS tag' +
    (empty ? ' WHERE 1 = 0' : '');
  let client = await openClient(options).catch(error => {
    t.diagnostic(inspect(error, {depth: 10})); throw error;
  });
  try {
    const template = await client.check(text, {kind: 'text', scope: 'template_only', format: 'sql'});
    assert.equal(template.outcome, 'completed', JSON.stringify(template));
    assert.equal(template.report.verdict, 'undetermined', JSON.stringify(template));
    assert.deepEqual(commits(f.catalog), [], 'Incomplete static scope performs no write');
    const checked = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(checked.outcome, 'completed', JSON.stringify(checked));
    assert.equal(checked.report.verdict, 'verified', JSON.stringify(checked));
    const run = await client.startSource(text, {format: 'sql'}).catch(error => {
      t.diagnostic(inspect({phase: 'text-submit', error, observations}, {depth: 15}));
      throw error;
    });
    const state = await waiting(run, observations, t);
    assert.deepEqual(state.result_availability, {});
    assert.deepEqual(commits(f.catalog), [], 'Checking and approval wait perform no write');
    const checkpoint = (await client.checkpoints()).items[0];
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
    const preview = JSON.parse(Buffer.from(review.bytes).toString());
    assert.equal(preview.effects.length, 1);
    assert.equal(preview.effects[0].count, 1);
    assert.equal(preview.effects[0].approval, 'required');
    const operation = preview.effects[0].changes[0].intended_changes.value;
    assert.equal(operation.action, 'create');
    assert.equal(operation.expected_table, null);
    const ref = run.ref;
    await client.close();
    const restartInput = join(f.root, 'text-restart.json');
    // Only synthetic fixture keys enter this owned directory. Observers are
    // process-local diagnostics, not persisted authorization or Run facts.
    const {observe: _observe, ...restartAuthorization} = authorization;
    const restartRequest = {ref, options: {...options,
      installation: {...options.installation, authorization: restartAuthorization}}};
    await writeFile(restartInput, JSON.stringify(restartRequest), {mode: 0o600});
    const restarted = await promisify(execFile)(process.execPath,
      [fileURLToPath(new URL('./fixtures/table-text-restart.mjs', import.meta.url)), restartInput],
      {timeout: 30000, killSignal: 'SIGKILL', maxBuffer: 1048576});
    assert.deepEqual(JSON.parse(restarted.stdout),
      {status: 'waiting_checkpoint', result_availability: {}});
    assert.deepEqual(commits(f.catalog), [], 'A separate process cannot approve or write implicitly');
    client = await openClient(options);
    let restored = await client.attach(ref);
    assert.equal((await restored.status()).status, 'waiting_checkpoint');
    assert.deepEqual(commits(f.catalog), [], 'Restart neither approves nor resends');
    await client.close();
    // Approval, restored private capture and commit must occur in a genuinely
    // fresh process, not merely a second in-process Host object.
    await writeFile(restartInput, JSON.stringify({...restartRequest, approval: {
      checkpointCid: checkpoint.checkpointCid, keyId: 'reviewer', reviewerId: 'reviewer',
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
    }}), {mode: 0o600});
    const resumed = await promisify(execFile)(process.execPath,
      [fileURLToPath(new URL('./fixtures/table-text-restart.mjs', import.meta.url)), restartInput],
      {timeout: 30000, killSignal: 'SIGKILL', maxBuffer: 1048576});
    assert.deepEqual(JSON.parse(resumed.stdout),
      {status: 'succeeded', result_availability: {}});
    assert.equal(commits(f.catalog).length, 1, 'The fresh process commits the original operation once');
    client = await openClient(options);
    restored = await client.attach(ref);
    const finished = await terminal(restored, observations, t);
    assert.equal(finished.status, 'succeeded', JSON.stringify(finished));
    assert.deepEqual(finished.result_availability, {});
    assert.equal(commits(f.catalog).length, 1);
    assert.deepEqual(commits(f.catalog)[0].operation, operation);
    assert.equal(commits(f.catalog)[0].receipt.row_count, empty ? 0 : 1);
  } finally { await client.close(); }
  const committed = commits(f.catalog)[0];
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'], table_name: 'rows',
    table_uuid: committed.receipt.table_uuid, schema_cid: committed.receipt.schema_cid};
  const frozen = await f.bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result),
    empty ? [] : [{id: 1, tag: null}], 'Physical generation survives origin Run cleanup');
  const sourceProfilePath = join(f.root, 'text-table-source.json');
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-local-table-source/0.1',
    connectorId: 'table', connection, python, catalog: f.catalog, accountConfigurationWire: account(),
    targets: [{resource, selector, schemaWire: frozen.result.schema_wire}],
    limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
  const reader = await openClient({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'text-reader'), sourceProfilePath, authorization}});
  try {
    const readRun = await reader.start(readerProgram('read-text-created-table'));
    assert.equal((await terminal(readRun, observations, t)).status, 'succeeded');
    const result = readRun.result('answer');
    assert.deepEqual((await result.describe()).columns.map(column => column.name),
      ['id', 'tag', 'doubled'], 'The schema does not depend on nonempty data');
    assert.deepEqual(await result.all(), empty ? [] : [{id: 1, tag: null, doubled: 2}]);
    assert.equal(commits(f.catalog).length, 1);
  } finally { await reader.close(); }
});
}
}

for (const transport of ['Local', 'HTTPS']) {
for (const format of ['json', 'sql', 'aql']) {
test(`Table retained Result before filtered CTAS through ${transport} (${format})`, async t => {
  const f = await tablePhysicalFixture(t, undefined, {preserve: true}), declared = declaration();
  const openClient = await sparseTableClientOpener(t, f.root, transport);
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const observations = [];
  const authorization = {accountConfiguration: account(), reviewReaders: [principalId],
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const effectProfilePath = join(f.root, 'ctas-result-effect.json');
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
    python, catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', queryName: 'analytics.report', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'], footprint: {
        kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}],
    limits: {reservation: {bytes: 1048576, files: 16}}}));
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'ctas-result-host'), effectProfilePath, authorization}};
  const control = ctasResultControl(format, {targetRef, mappingRef});
  let client = await openClient(options), observation;
  try {
    const submissionRef = client.newSubmission({nonce: 'ctas-before-filter-' + format});
    const run = await client.startSource(control.document, {format, submissionRef});
    await waiting(run, observations, t);
    assert.deepEqual(commits(f.catalog), [], 'Neither the retained Result nor approval wait may write');
    const checkpoints = (await client.checkpoints()).items;
    assert.equal(checkpoints.length, 1);
    const checkpoint = checkpoints[0];
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
    const preview = JSON.parse(Buffer.from(review.bytes).toString());
    assert.equal(preview.effects.length, 1);
    const operation = preview.effects[0].changes[0].intended_changes.value;
    assert.equal(operation.action, 'create');
    const ref = run.ref;
    await client.close();
    const {observe: _observe, ...restartAuthorization} = authorization;
    const restartInput = join(f.root, 'ctas-result-restart.json');
    await writeFile(restartInput, JSON.stringify({ref, transport,
      retainedResult: ctasRetainedResult,
      options: {...options, installation: {...options.installation, authorization: restartAuthorization}},
      approval: {checkpointCid: checkpoint.checkpointCid, keyId: 'reviewer', reviewerId: 'reviewer',
        privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}), {mode: 0o600});
    const resumed = await promisify(execFile)(process.execPath,
      [fileURLToPath(new URL('./fixtures/table-text-restart.mjs', import.meta.url)), restartInput],
      {timeout: 30000, killSignal: 'SIGKILL', maxBuffer: 1048576,
        env: {...process.env, ...(transport === 'HTTPS'
          ? {NODE_EXTRA_CA_CERTS: join(f.root, 'host.crt')} : {})}});
    const fresh = JSON.parse(resumed.stdout);
    assert.equal(fresh.status, 'succeeded');
    assert.deepEqual(fresh.observedResult, ctasRetainedResult);
    assert.equal(commits(f.catalog).length, 1);
    client = await openClient(options);
    const restored = await client.attach(ref);
    assert.equal((await restored.status()).status, 'succeeded');
    const result = restored.result('before_write');
    const actual = {name: 'before_write', rows: await result.all(), columns: (await result.describe()).columns};
    assert.deepEqual(actual, ctasRetainedResult);
    const replayed = await client.startSource(control.document, {format, submissionRef});
    assert.deepEqual(replayed.ref, ref);
    assert.equal((await replayed.status()).status, 'succeeded');
    assert.equal(commits(f.catalog).length, 1, 'Attach and identical request do not repeat the write');
    const committed = commits(f.catalog)[0];
    assert.deepEqual(committed.operation, operation);
    assert.equal(committed.receipt.row_count, 0, 'WHERE filters the Table input, not the earlier Result');
    const frozen = await f.bridge.resolveGeneration({catalog_identity_cid: f.catalog.catalogCid,
      namespace: ['test'], table_name: 'rows', table_uuid: committed.receipt.table_uuid,
      schema_cid: committed.receipt.schema_cid});
    assert.equal(frozen.ok, true);
    assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result), []);
    observation = {format, transport, ref, submissionRef, observedResult: actual,
      freshProcessResult: fresh.observedResult, tableRowCount: committed.receipt.row_count,
      catalogCommits: 1, sameRequestSameRun: true, scratch: f.root};
  } finally { await client.close(); }
  await writeFile(join(f.root, 'ctas-result-observation.json'), JSON.stringify(observation), {mode: 0o600});
  console.log('TABLE_CTAS_RETAINED_RESULT ' + JSON.stringify(observation));
});
}
}

for (const transport of ['Local', 'HTTPS']) {
test(`Table text Effect-only cleanup retry through ${transport} retains the committed generation`, async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  const launcher = join(f.root, 'cleanup-retry');
  const blocked = join(f.root, 'block-cleanup');
  await writeFile(blocked, 'The fixture withholds physical cleanup confirmation.');
  await writeFile(launcher, `#!${python}
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from process_worker import serve
root = Path(__file__).parent
def factory(*args):
    from catalog import TableCatalog
    from physical import PhysicalRefusal
    class CleanupCatalog(TableCatalog):
        def write_claimed(self, *args, **kwargs):
            with (root / "writes.log").open("a") as stream:
                stream.write(args[0]["request_cid"] + "\\n")
            return super().write_claimed(*args, **kwargs)
        def cleanup_after_stop(self, request, **kwargs):
            # Keep the real original-operation lookup and committed-file
            # protection. Only physical cleanup confirmation is withheld.
            result = super().cleanup_after_stop(request, **kwargs)
            with (root / "cleanup.log").open("a") as stream:
                stream.write(request["request_cid"] + "\\n")
            if (root / "block-cleanup").exists():
                raise PhysicalRefusal("FixtureCleanupPending")
            return result
    return CleanupCatalog(*args)
with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
`, {mode: 0o700});
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const observations = [];
  const authorization = {accountConfiguration: account(), reviewReaders: [principalId],
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const effectProfilePath = join(f.root, 'cleanup-effect.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
    python: launcher, catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', queryName: 'analytics.report', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'], footprint: {
        kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}],
    limits: {reservation: {bytes: 1048576, files: 16}}}));
  const openClient = await sparseTableClientOpener(t, f.root, transport);
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'cleanup-host'), effectProfilePath, authorization}};
  let client = await openClient(options);
  try {
    const run = await client.startSource(
      'CREATE TABLE analytics.report AS SELECT 1 AS id, CAST(NULL AS STRING) AS tag', {format: 'sql'});
    await waiting(run, observations, t);
    assert.deepEqual(commits(f.catalog), []);
    const checkpoint = (await client.checkpoints()).items[0];
    await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    const signal = AbortSignal.timeout(30000);
    while (commits(f.catalog, 1000).length === 0) await delay(20, undefined, {signal});
    const original = commits(f.catalog);
    assert.equal(original.length, 1);
    await assert.rejects(client.close(), error => {
      assert.equal(error.cleanupPending, true);
      return true;
    });
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), original[0].operation.request_cid + '\n');
    assert.ok((await readFile(join(f.root, 'cleanup.log'), 'utf8')).length > 0,
      'The real retained physical cleanup owner was attempted');
    for (const failure of observations.filter(item => item.name.endsWith('_failed'))) {
      assert.equal(failure.name, 'effect_resume_failed');
      assert.equal(failure.detail.code, 'ClientDispatchCleanupPending');
      assert.equal(failure.detail.ref.runDefinitionCid, run.ref.runDefinitionCid);
    }
    assert.deepEqual(commits(f.catalog), original, 'Pending cleanup cannot delete or replace the original commit');
    await unlink(blocked);
    await client.close();
    await client.close();
    assert.deepEqual(commits(f.catalog), original);
    assert.equal(await readFile(join(f.root, 'writes.log'), 'utf8'), original[0].operation.request_cid + '\n');
    client = await openClient(options);
    const restored = await client.attach(run.ref);
    const state = await restored.status();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(state.result_availability, {});
  } finally {
    await unlink(blocked).catch(error => { if (error.code !== 'ENOENT') throw error; });
    await client.close();
  }
  const receipt = commits(f.catalog)[0].receipt;
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'], table_name: 'rows',
    table_uuid: receipt.table_uuid, schema_cid: receipt.schema_cid};
  const frozen = await f.bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result),
    [{id: 1, tag: null}], 'Cleanup retry never reclaims a committed generation');
  const sourceProfilePath = join(f.root, 'cleanup-source.json');
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-local-table-source/0.1',
    connectorId: 'table', connection, python, catalog: f.catalog, accountConfigurationWire: account(),
    targets: [{resource, selector, schemaWire: frozen.result.schema_wire}],
    limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
  const readerObservations = [];
  const reader = await openClient({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'cleanup-reader'), sourceProfilePath,
      authorization: {...authorization,
        observe: (name, detail) => readerObservations.push({name, detail})}}});
  try {
    const run = await reader.start(readerProgram('read-after-cleanup-retry'));
    assert.equal((await terminal(run, readerObservations, t)).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{id: 1, tag: null, doubled: 2}]);
  } finally { await reader.close(); }
});
}

for (const transport of ['Local', 'HTTPS']) {
for (const format of ['json', 'aql-text']) {
test(`Table sparse private input commits through ${transport} (${format}) after approval while ordinary Result presence remains required`, async t => {
  const f = await tablePhysicalFixture(t), declared = declaration('person_key');
  const openClient = await sparseTableClientOpener(t, f.root, transport);
  const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
  const effectProfilePath = join(f.root, 'sparse-effect.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
    python: process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)),
    catalog: f.catalog, accountConfigurationWire: account(), environmentWire: declared.wire,
    targets: [{effectId: 'save', queryName: 'analytics.report', resource, targetRef, mappingRef,
      mappingCid: declared.mapping.mapping_contract_cid, action: 'create',
      catalogCid: f.catalog.catalogCid, namespace: ['test'], tableName: 'rows',
      expectedTable: null, permissions: ['scope:store'], footprint: {
        kind: 'collection', resource_identity_scheme_cid: contentCid(tableContract),
        provider_namespace: 'table', provider_boundary_cid: f.catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}], limits: {}}));
  const observations = [];
  const authorization = {accountConfiguration: account(), reviewReaders: [principalId],
    observe: (name, detail) => observations.push({name, detail}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'sparse-host'), effectProfilePath, authorization}};
  let client = await openClient(options);
  try {
    const sparse = JSON.parse(await readFile(new URL('../../scripts/fixtures/graph-presence.program.json', import.meta.url), 'utf8'));
    sparse.id = 'sparse-table';
    const stage = sparse.stages[0];
    stage.steps[1].values = {schema: {
      person_key: {type: 'number', nullable: false},
      tenant_key: {type: 'string', nullable: false}},
      rows: [{person_key: 3, tenant_key: 'a'}]};
    stage.steps[3].graph.nodes[1].key = ['person_key', 'tenant_key'];
    stage.steps.pop();
    stage.results = {rows: {from: 'rows', fields: ['person_key', 'p']},
      answer: {from: 'rows', fields: ['person_key']}};
    stage.effects = program([]).stages[0].effects;
    sparse.results.answer.from.result = 'answer';
    // The root public Result exports only guaranteed person_key. The stage's
    // Result-based spelling still requires p. The separate private Table input
    // below must not weaken this ordinary Named Result contract.
    await assert.rejects(client.startSource(JSON.stringify(sparse), {format: 'json'}), error => {
      t.diagnostic(inspect({phase: 'sparse-table-input', error}, {depth: 8}));
      assert.equal(error.code, 'SubmissionNotAccepted');
      const outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'not_accepted');
      assert.equal(outcome.problem.code, 'ClientProgramRejected');
      assert.equal(Object.hasOwn(outcome, 'admission'), false);
      return true;
    });
    assert.deepEqual(commits(f.catalog), [], 'An unpublishable input is not staged or committed');
    assert.equal((await client.checkpoints()).items.length, 0, 'Checking does not admit a Run');
    const dense = plain(sparse);
    dense.stages[0].steps[4].node_rows = {definition: 'N'};
    const moon = await tableTestModule(new URL(
      '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url),
    '@actql/local-node/runtime');
    const numericProfile = JSON.parse(await readFile(new URL('../../spec/contracts/actql-numeric-reduction.json', import.meta.url), 'utf8'));
    const graphLaw = JSON.parse(await readFile(new URL('../../spec/dependencies/actql-graph-laws.json', import.meta.url), 'utf8'));
    // The direct checker control must receive the same explicit construction
    // ceilings as the installed Host; the bare fixture has no Graph budget.
    const {evidence_bundle_cid: unusedEvidence, ...checkBody} = JSON.parse(declared.wire);
    void unusedEvidence;
    checkBody.host_policy_profile.capacity = {
      max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
      max_graph_construction_nodes: 1000, ...checkBody.host_policy_profile.capacity};
    const checkEvidence = contentCid(checkBody);
    const environment = moon.clientProgramCheckEnvironmentWithGraphProfile(
      canonicalJson({...checkBody, evidence_bundle_cid: checkEvidence}),
      checkEvidence, false, true, true, true, true, false, false,
      contentCid(numericProfile), contentCid(graphLaw));
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(sparse), 'json', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationResultPresenceField(outcome), 'p',
      'The actual common checker rejects Conditional p at Result closure');
    const invalidFormat = moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(sparse), 'invalid-format', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidFormat), 'invalid_format');
    assert.equal(moon.clientProgramEffectPreparationResultPresenceField(invalidFormat), undefined,
      'A different refusal cannot masquerade as Result presence rejection');
    // Validate the same Graph and selected schemas through ordinary public
    // execution, independently of the Effect computation capability boundary.
    delete dense.stages[0].effects;
    dense.results.rows = {from: {stage: 'source', result: 'rows'}};
    const denseRun = await client.startSource(JSON.stringify(dense), {format: 'json'});
    assert.equal((await terminal(denseRun, [], t)).status, 'succeeded');
    assert.deepEqual(plain(await denseRun.result('answer').all()).map(row => row.person_key).sort(), [1, 2]);
    assert.deepEqual(plain(await denseRun.result('rows').all()).sort((a, b) => a.person_key - b.person_key),
      [{person_key: 1, p: 7}, {person_key: 2, p: null}],
      'Definition selection preserves the actual and explicitly NULL property');
    const projection = plain(sparse);
    projection.stages[0].steps.push({select: ['person_key'], as: 'projected'});
    projection.stages[0].results.rows.from = 'projected';
    projection.stages[0].results.answer.from = 'projected';
    projection.stages[0].results.rows.fields = ['person_key'];
    delete projection.stages[0].effects;
    const projectedRun = await client.startSource(JSON.stringify(projection), {format: 'json'});
    assert.equal((await terminal(projectedRun, [], t)).status, 'succeeded');
    assert.deepEqual(plain(await projectedRun.result('answer').all()).map(row => row.person_key).sort(), [1, 2, 3]);
    assert.deepEqual(commits(f.catalog), [], 'Read-only Graph controls write no Table');
    const privateInput = plain(sparse);
    privateInput.id = 'sparse-private-table';
    const privateStage = privateInput.stages[0];
    privateStage.table_inputs = {rows: privateStage.results.rows};
    delete privateStage.results.rows;
    privateStage.effects.save.store.from = {table_input: 'rows'};
    privateStage.steps.push({from: 'rows', sort: [
      {field: 'person_key', dir: 'asc', nulls: 'first'}], as: 'ordered'});
    privateStage.table_inputs.rows.from = 'ordered';
    privateStage.results.answer.from = 'ordered';
    const input = format === 'json' ? JSON.stringify(privateInput)
      : 'WITH persons AS (SELECT 2 AS person_key, \'a\' AS tenant_key, CAST(NULL AS FLOAT64) AS p '
        + 'UNION ALL SELECT 1 AS person_key, \'a\' AS tenant_key, 7 AS p), '
        + 'companies AS (SELECT 3 AS person_key, \'a\' AS tenant_key), '
        + 'g AS (GRAPH (NODE TABLES '
        + '(persons AS N KEY (person_key, tenant_key) LABEL Person PROPERTIES (p), '
        + 'companies AS M KEY (person_key, tenant_key) LABEL Company NO PROPERTIES))) '
        + 'FROM g |> node_rows() |> DROP id, labels, tenant_key |> ORDER BY person_key '
        + '|> EFFECT save CREATE TABLE analytics.report';
    const privatePreparation = moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(privateInput), 'json', environment, undefined, []);
    assert.ok(moon.clientProgramEffectPreparationReady(privatePreparation),
      inspect(moon.clientProgramEffectPreparationIssue(privatePreparation), {depth: 20}));
    assert.equal(moon.clientProgramEffectPreparationResultPresenceField(privatePreparation), undefined,
      'The accepted private input is not an ordinary Result presence refusal');
    const submissionRef = client.newSubmission();
    if (format === 'aql-text') {
      // Ordinary SELECT still cannot read a Conditional value. DROP removes
      // unrelated fields without reading p; the closed private capture owns
      // its presence, independently of Named Result publication.
      const unproven = input.replace('DROP id, labels, tenant_key', 'SELECT person_key, p');
      await assert.rejects(client.startSource(unproven, {format}), error => {
        assert.equal(getSubmissionOutcome(error).kind, 'not_accepted');
        return true;
      });
      assert.deepEqual(commits(f.catalog), []);
    }
    if (format === 'aql-text') {
      const checkedInput = await client.check(input, {kind: 'text', scope: 'bound_input', format});
      assert.equal(checkedInput.outcome, 'completed', JSON.stringify(checkedInput));
      assert.equal(checkedInput.report.verdict, 'verified', JSON.stringify(checkedInput));
    } else {
      // Public advisory check accepts query text, not a JSON Program string.
      // The actual common preparation above and public submission below must
      // still admit the private input; a diagnostic API refusal is no substitute.
      await assert.rejects(client.check(input, {kind: 'text', scope: 'bound_input', format}), {code: 'InvalidCheckRequest'});
      assert.deepEqual(commits(f.catalog), []);
      assert.equal((await client.checkpoints()).items.length, 0);
    }
    let run = await client.startSource(input, {format, submissionRef}).catch(error => {
      t.diagnostic(inspect({phase: 'sparse-private-submit', error, observations}, {depth: 15}));
      throw error;
    });
    await waiting(run, observations, t);
    assert.deepEqual(commits(f.catalog), [], 'Private capture does not authorize a commit');
    const checkpoint = (await client.checkpoints()).items[0];
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1000000});
    const preview = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
    assert.equal(preview.effects[0].source_table_input,
      format === 'json' ? 'rows' : 'aql_table_input');
    assert.equal(preview.effects[0].count, 1);
    assert.equal(preview.effects[0].approval, 'required');
    const operation = preview.effects[0].changes[0].intended_changes.value;
    const originalRef = run.ref;
    await client.close();
    client = await openClient(options);
    run = await client.startSource(input, {format, submissionRef});
    assert.deepEqual(run.ref, originalRef);
    assert.equal((await client.checkpoints()).items[0].checkpointCid, checkpoint.checkpointCid);
    assert.deepEqual(commits(f.catalog), [], 'Restart does not send a private Table operation');
    const answered = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: {
      keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
    assert.deepEqual(answered.results.map(value => value.status), ['committed']);
    assert.equal((await terminal(run, observations, t)).status, 'succeeded');
    if (format === 'json') assert.deepEqual(plain(await run.result('answer').all()),
      [{person_key: 1}, {person_key: 2}, {person_key: 3}]);
    else assert.deepEqual((await run.status()).result_availability, {});
    assert.equal(commits(f.catalog).length, 1);
    assert.deepEqual(commits(f.catalog)[0].operation, operation);
    assert.deepEqual((await client.resolveCheckpoints(answered.signed)).results.map(value => value.status),
      ['duplicate']);
    assert.equal(commits(f.catalog).length, 1, 'Duplicate approval does not resend');
  } finally { await client.close(); }
  const committed = commits(f.catalog)[0];
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'], table_name: 'rows',
    table_uuid: committed.receipt.table_uuid, schema_cid: committed.receipt.schema_cid};
  const frozen = await f.bridge.resolveGeneration(selector);
  assert.equal(frozen.ok, true);
  assert.deepEqual(JSON.parse(frozen.result.schema_wire), {
    person_key: {nullable: false, type: 'number'},
    p: {contract: {nullable: true, type: 'number'}, presence: 'conditional'}});
  assert.deepEqual(plain((await f.bridge.read(frozen.result.receipt, frozen.result.mapping)).result),
    [{person_key: 1, p: 7}, {person_key: 2, p: null}, {person_key: 3}],
    'Iceberg preserves value, explicit NULL and omission after the origin Host closes');
  const sourceProfilePath = join(f.root, 'sparse-source.json');
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-local-table-source/0.1',
    connectorId: 'table', connection,
    python: process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)),
    catalog: f.catalog, accountConfigurationWire: account(),
    targets: [{resource, selector, schemaWire: frozen.result.schema_wire}],
    limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
  const later = await openClient({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'sparse-reader'), sourceProfilePath, authorization}});
  try {
    const reader = {version: 'actql/0.1', id: 'read-sparse-table', stages: [{id: 'read',
      inputs: {input: {connector: 'table', resource}},
      steps: [{filter: 'person_key >= 0', as: 'kept'},
        {select: ['person_key'], as: 'output'}],
      results: {rows: {from: 'output', fields: ['person_key']}}},
      // Use the existing acquisition -> Compute publication path. Direct
      // publication of an acquisition-only task has no receipt capability.
      {id: 'compute', inputs: {input: {result: {stage: 'read', result: 'rows'}}},
        steps: [{derive: {checked_key: 'person_key + 0'}, as: 'checked'},
          {select: ['person_key'], as: 'output'}],
        results: {rows: {from: 'output', fields: ['person_key']}}}],
      results: {answer: {from: {stage: 'compute', result: 'rows'}}}};
    const run = await later.start(reader);
    assert.equal((await terminal(run, observations, t)).status, 'succeeded');
    assert.deepEqual(plain(await run.result('answer').all()),
      [{person_key: 1}, {person_key: 2}, {person_key: 3}]);
    assert.equal(commits(f.catalog).length, 1, 'A new reader never resends the originating Effect');
  } catch (error) {
    t.diagnostic(inspect({readerError: error, observations}, {depth: 12}));
    throw error;
  } finally { await later.close(); }
});
}
}

test('Table installed HTTP Host retires capture custody before completing close', async t => {
  const f = await tablePhysicalFixture(t), declared = declaration();
  const effectProfilePath = join(f.root, 'table-effect-close.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
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
    }}).catch(error => {
      t.diagnostic(inspect(error, {depth: 8}));
      throw error;
    });
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
  const profile = {version: 'actql-installed-local-table-effect/0.1', connectorId: 'table', connection,
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
  const submissionRef = client.newSubmission();
  try {
    const input = JSON.stringify(program(rows));
    let run = await client.startSource(input, {format: 'json', submissionRef}).catch(error => {
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
    run = await client.startSource(input, {format: 'json', submissionRef});
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
    const repeated = await client.startSource(input, {format: 'json', submissionRef});
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
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-local-table-source/0.1',
    connectorId: 'table', connection, python: profile.python, catalog: f.catalog,
    accountConfigurationWire: account(), targets: [{resource, selector, schemaWire: frozen.result.schema_wire}],
    limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
  const later = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'reader-host'), sourceProfilePath, authorization}});
  try {
    // Read the complete required schema, including nullable text, through the
    // public Source and two-task Relation path after the origin Host closes.
    const readRun = await later.start(readerProgram());
    const state = await terminal(readRun, observations, t);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(multiset(await readRun.result('answer').all()),
      multiset(rows.map(row => ({id: row.id, tag: row.tag, doubled: row.id * 2}))));
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
      const submissionRef = replacing.newSubmission();
      const before = commits(f.catalog).length;
      let operation;
      try {
        let run = await replacing.startSource(input, {format: 'json', submissionRef});
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
        run = await replacing.startSource(input, {format: 'json', submissionRef});
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
      await writeFile(currentSourceProfilePath, JSON.stringify({version: 'actql-installed-local-table-source/0.1',
        connectorId: 'table', connection, python: profile.python, catalog: f.catalog,
        accountConfigurationWire: account(), targets: [{resource, selector, schemaWire: current.result.schema_wire}],
        limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}}));
      const reader = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
        installation: {directory: join(f.root, `replacement-reader-${index}`),
          sourceProfilePath: currentSourceProfilePath, authorization}});
      try {
        const run = await reader.start(readerProgram(`read-replacement-${index}`));
        assert.equal((await terminal(run, observations, t)).status, 'succeeded');
        assert.deepEqual(multiset(await run.result('answer').all()),
          multiset(replacement.map(row => ({id: row.id, tag: row.tag, doubled: row.id * 2}))));
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

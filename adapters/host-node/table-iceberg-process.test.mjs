// Real optional Host I/O and the existing common Ledger, not public admission.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, rm, access} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {createIcebergPhysicalBridge} from './table-iceberg-process.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {machineCid} from '../../scripts/actql-spec-family.mjs';

const python = pathToFileURL(process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)));
const directory = fileURLToPath(new URL('../table-iceberg/', import.meta.url));
const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).effectApplicationControl;
const seal = (value, field) => ({...value, [field]: machineCid(value)});
// The bounded channel snapshots plain records with null prototypes. Compare
// exact JSON data, not that defensive in-memory layout. No normalization,
// sorting, omission/defaulting or identity recomputation occurs here.
const wireValue = value => JSON.parse(JSON.stringify(value));

async function fixture(t, entry) {
  const root = await mkdtemp(join(tmpdir(), 'actql-table-process-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const catalog = {database: join(root, 'catalog.db'), warehouse: join(root, 'warehouse'),
    catalogCid: cid('3'), limits: {bytes: 16777216, files: 256, operations: 32}};
  // Explicit Host installation setup. No operation or user data is written.
  const setup = spawnSync(fileURLToPath(python), ['-c',
    'import json,sys; from catalog import TableCatalog; c=json.loads(sys.argv[1]); t=TableCatalog(c["database"],c["warehouse"],c["catalogCid"],c["limits"]); t.create_namespace("test"); t.engine.dispose()',
    JSON.stringify(catalog)], {cwd: directory, encoding: 'utf8', timeout: 20000});
  assert.ifError(setup.error);
  assert.equal(setup.status, 0, setup.stderr);
  const mapping = JSON.parse(await readFile(new URL('../table-iceberg/fixtures/presence-mapping.json', import.meta.url), 'utf8'));
  const scope = control.logicalRequestScope(cid('a'), 'table-operation', 32);
  const operation = (action = 'create', expected = null, suffix = 'rows') => seal({
    version: 'actql-table-operation/0.1', logical_request_scope_cid: control.logicalRequestScopeCid(scope),
    effect_identity_cid: cid('2'), action, catalog_identity_cid: catalog.catalogCid,
    namespace: ['test'], table_name: suffix, expected_table: expected,
    input_artifact_cid: cid('4'), input_relation_cid: cid('5'),
    schema_cid: mapping.schema_cid, storage_mapping_cid: mapping.mapping_cid,
    data_policy_cid: cid('6')}, 'request_cid');
  const bridge = createIcebergPhysicalBridge({python, run: 'table-run', catalog, ...(entry ? {entry} : {})});
  const prepare = (operation, rows) => bridge.prepareWrite({operation, mapping, rows,
    reservation: {bytes: 1048576, files: 16}});
  const claim = operation => {
    // One logical whole-Relation operation; no per-row content/item key. This
    // test constructs a common claim directly, not a Program approval fixture.
    const key = control.dispatchKey(scope, cid('b'), canonicalText({operation: operation.request_cid}), 256, 16, 4);
    const locator = control.logicalItemLocator(scope, 'program-1', 'node-1', 'Store',
      canonicalText({operation: operation.request_cid}), 256, 512, 16, 4);
    const basis = control.ledgerBasis(scope, locator, key, cid('c'), cid('d'), cid('e'),
      operation.request_cid, cid('0'), 'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis, intentFingerprintCid: cid('e'), canonicalRequestCid: operation.request_cid};
  };
  const open = () => openEffectLedger({moon, root: join(root, 'ledger'), authorityScopeCid: cid('a'),
    callerRequestId: 'table-operation', maxEntryBytes: 4096});
  return {root, catalog, mapping, operation, bridge, prepare, claim, open};
}

test('Table managed framing rejects malformed material and performs partial I/O exactly', () => {
  const result = spawnSync(fileURLToPath(python), ['-m', 'unittest', '-v', 'process_worker_test'],
    {cwd: directory, encoding: 'utf8', timeout: 10000});
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /Ran 7 tests/u);
});

test('real whole-Relation commit is captured once, frozen generations survive later replace', async t => {
  const f = await fixture(t);
  const rows = [{id: 1, p: 'e\u0301\r\n'}, {id: 2, p: null}, {id: 3}, {id: 3}];
  const operation = f.operation();
  const prepared = f.prepare(operation, rows);
  rows[0].p = 'changed-after-preparation';
  operation.table_name = 'changed-after-preparation';
  const claim = f.claim({...operation, table_name: 'rows'});
  const ledger = f.open();
  t.after(() => ledger.close());
  await assert.rejects(f.bridge.cleanup(prepared), {code: 'TableWriterNotStopped'});
  const sent = await captureClaimedEffectResponse({ledger, claim,
    requestCid: operation.request_cid, execute: () => f.bridge.execute(prepared, {useCid: cid('7')})});
  const first = JSON.parse(Buffer.from(sent.response.responseBytes).toString('utf8'));
  assert.equal(first.ok, true);
  assert.equal(first.result.row_count, 4);
  assert.deepEqual(f.bridge.status(prepared), {attempted: true, stopped: true});
  const again = await captureClaimedEffectResponse({ledger, claim, requestCid: operation.request_cid,
    execute: () => { assert.fail('Durable claim must not send twice'); }});
  assert.equal(again.claimed, false);
  await assert.rejects(f.bridge.execute(prepared, {useCid: cid('7')}), {code: 'TablePhysicalReconcileOnly'});
  const replacement = f.operation('replace', {table_uuid: first.result.table_uuid,
    generation_cid: first.result.generation_cid});
  const second = f.prepare(replacement, [{id: 9}]);
  const replaced = await f.bridge.execute(second, {useCid: cid('7')});
  assert.equal(JSON.parse(replaced.observation.body).ok, true);
  const reconciled = await f.bridge.reconcile(prepared);
  assert.deepEqual(wireValue(reconciled), first);
  const old = await f.bridge.read(first.result, f.mapping);
  assert.deepEqual(wireValue(old.result), [{id: 1, p: 'e\u0301\r\n'}, {id: 2, p: null}, {id: 3}, {id: 3}]);
  assert.deepEqual(wireValue(await f.bridge.cleanup(prepared)), {ok: true,
    result: {retained: true, pending: false, removed: 0}});
});

test('typed empty input performs one operation rather than zero row dispatches', async t => {
  const f = await fixture(t);
  const operation = f.operation();
  const prepared = f.prepare(operation, []);
  const ledger = f.open();
  t.after(() => ledger.close());
  const sent = await captureClaimedEffectResponse({ledger, claim: f.claim(operation),
    requestCid: operation.request_cid, execute: () => f.bridge.execute(prepared, {useCid: cid('7')})});
  const receipt = JSON.parse(Buffer.from(sent.response.responseBytes).toString('utf8')).result;
  assert.equal(receipt.row_count, 0);
  assert.equal(receipt.snapshot_id, null);
  assert.deepEqual((await f.bridge.read(receipt, f.mapping)).result, []);
});

test('real commit followed by process loss stays possible-dispatch after Ledger restart', async t => {
  const f = await fixture(t, new URL('../table-iceberg/fixtures/lost-reply-process.py', import.meta.url));
  const operation = f.operation(), prepared = f.prepare(operation, [{id: 1}]), claim = f.claim(operation);
  const ledger = f.open();
  await assert.rejects(captureClaimedEffectResponse({ledger, claim, requestCid: operation.request_cid,
    execute: () => f.bridge.execute(prepared, {useCid: cid('7')})}));
  assert.deepEqual(f.bridge.status(prepared), {attempted: true, stopped: true});
  assert.equal(ledger.readClaimedResponse(claim), undefined);
  ledger.close();
  const reopened = f.open();
  t.after(() => reopened.close());
  const replay = await captureClaimedEffectResponse({ledger: reopened, claim, requestCid: operation.request_cid,
    execute: () => { assert.fail('Unknown physical commit cannot be resent'); }});
  assert.equal(replay.claimed, false);
  const recovered = await f.bridge.reconcile(prepared);
  assert.equal(recovered.ok, true);
  assert.equal(recovered.result.request_cid, operation.request_cid);
  assert.deepEqual(wireValue((await f.bridge.read(recovered.result, f.mapping)).result), [{id: 1}]);
  assert.equal((await f.bridge.cleanup(prepared)).result.retained, true);
});

test('positive staging then cancellation waits for actual stop before fenced cleanup', async t => {
  const f = await fixture(t, new URL('../table-iceberg/fixtures/stalled-process.py', import.meta.url));
  const operation = f.operation(), prepared = f.prepare(operation, [{id: 1}]);
  const ledger = f.open();
  t.after(() => ledger.close());
  const controller = new AbortController();
  const work = captureClaimedEffectResponse({ledger, claim: f.claim(operation), requestCid: operation.request_cid,
    execute: () => f.bridge.execute(prepared, {useCid: cid('7'), signal: controller.signal})});
  const rejected = assert.rejects(work, {code: 'ExecutionCancelled'});
  const deadline = Date.now() + 15000;
  while (true) {
    try { await access(join(f.root, 'staged')); break; }
    catch (error) {
      if (Date.now() >= deadline) { controller.abort(); await rejected; assert.fail(`Staging notification unavailable: ${error.code}`); }
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  }
  assert.deepEqual(f.bridge.status(prepared), {attempted: true, stopped: false});
  await assert.rejects(f.bridge.cleanup(prepared), {code: 'TableWriterNotStopped'});
  controller.abort();
  await rejected;
  assert.deepEqual(f.bridge.status(prepared), {attempted: true, stopped: true});
  assert.equal((await f.bridge.reconcile(prepared)).result, null);
  const cleaned = await f.bridge.cleanup(prepared);
  assert.equal(cleaned.result.retained, false);
  assert.equal(cleaned.result.pending, false);
  assert.ok(cleaned.result.removed > 0);
  assert.deepEqual(wireValue((await f.bridge.cleanup(prepared)).result), {retained: false, pending: false, removed: 0});
});

test('whole transport and unsupported configuration are refused before any process or Catalog I/O', () => {
  const catalog = {database: '/missing-table-host/catalog.db', warehouse: '/missing-table-host/warehouse',
    catalogCid: cid('3'), limits: {bytes: 16777216, files: 256, operations: 32}};
  assert.throws(() => createIcebergPhysicalBridge({python: new URL('https://example.invalid/python'),
    run: 'run', catalog}), {code: 'InvalidTablePhysicalConfiguration'});
  const bridge = createIcebergPhysicalBridge({python, run: 'run', catalog});
  assert.throws(() => bridge.prepareWrite({operation: {request_cid: cid('1')}, mapping: {},
    rows: [{p: 'x'.repeat(4 * 1024 * 1024)}], reservation: {bytes: 1048576, files: 16}}),
  {code: 'FrameByteLimit'});
  let getterCalls = 0;
  const row = {get p() { getterCalls++; return 'value'; }};
  assert.throws(() => bridge.prepareWrite({operation: {request_cid: cid('1')}, mapping: {},
    rows: [row], reservation: {bytes: 1048576, files: 16}}), {code: 'InvalidFrameValue'});
  assert.equal(getterCalls, 0);
});

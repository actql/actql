// Real optional Host I/O and the existing common Ledger, not public admission.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, access} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';
import {machineCid} from '../../scripts/actql-spec-family.mjs';
import {expectedLogicalTableReceipt} from './fixtures/table-logical-receipt.mjs';

const python = pathToFileURL(process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url)));
const directory = fileURLToPath(new URL('../connectors/local/iceberg/', import.meta.url));
const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).effectApplicationControl;
const publicationControl = runtimeCore(moon).publicationControl;
// The bounded channel snapshots plain records with null prototypes. Compare
// exact JSON data, not that defensive in-memory layout. No normalization,
// sorting, omission/defaulting or identity recomputation occurs here.
const wireValue = value => JSON.parse(JSON.stringify(value));

// Share this exact physical setup with installed read acceptance.
const fixture = tablePhysicalFixture;

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
  const projected = JSON.parse(checked(moon.clientProgramTableOperationCommitOutcome(
    canonicalText({...operation, table_name: 'rows'}),
    publicationControl.localTableCommitResponse(Buffer.from(sent.response.responseBytes).toString('utf8'),
      sent.response.statusCode, {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 16}),
    sent.response.statusCode, 4n, 65536, 4096, 16)));
  assert.deepEqual(projected, {state: 'applied', result: expectedLogicalTableReceipt(first.result)});
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
  // A reconstructed reader has no writer preparation, input rows or physical
  // stop token. It still resolves the original commit after a later head.
  const restarted = createIcebergPhysicalBridge({python, run: 'table-run', catalog: f.catalog});
  const reconciled = await restarted.reconcileOperation({...operation, table_name: 'rows'});
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
  assert.deepEqual(JSON.parse(checked(moon.clientProgramTableOperationCommitOutcome(
    canonicalText(operation), publicationControl.localTableCommitResponse(
      Buffer.from(sent.response.responseBytes).toString('utf8'), sent.response.statusCode,
      {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 16}),
    sent.response.statusCode, 0n, 65536, 4096, 16))),
  {state: 'applied', result: expectedLogicalTableReceipt(receipt)});
  assert.deepEqual((await f.bridge.read(receipt, f.mapping)).result, []);
});

test('Table generation resolution freezes a new reader before later head replacement', async t => {
  const f = await fixture(t);
  const rows = [{id: 1, p: 'e\u0301\r\n'}, {id: 2, p: null}, {id: 3}, {id: 3}];
  const prepared = f.prepare(f.operation(), rows);
  const committed = await f.bridge.execute(prepared, {useCid: cid('7')});
  const receipt = JSON.parse(committed.observation.body).result;
  const reader = createIcebergPhysicalBridge({python, run: 'independent-read-run', catalog: f.catalog});
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'],
    table_name: 'rows', table_uuid: receipt.table_uuid, schema_cid: f.mapping.schema_cid};
  const resolved = wireValue(await reader.resolveGeneration(selector));
  assert.deepEqual(resolved, {ok: true, result: {receipt, mapping: f.mapping, schema_wire: f.schemaWire}});
  const replacement = f.prepare(f.operation('replace', {table_uuid: receipt.table_uuid,
    generation_cid: receipt.generation_cid}), [{id: 9}]);
  const replaced = await f.bridge.execute(replacement, {useCid: cid('7')});
  const nextReceipt = JSON.parse(replaced.observation.body).result;
  const restarted = createIcebergPhysicalBridge({python, run: 'restarted-read-run', catalog: f.catalog});
  assert.deepEqual(wireValue(await restarted.read(resolved.result.receipt, resolved.result.mapping)),
    {ok: true, result: rows});
  assert.deepEqual(wireValue(await restarted.resolveGeneration(selector)),
    {ok: true, result: {receipt: nextReceipt, mapping: f.mapping, schema_wire: f.schemaWire}});
  for (const changed of [{table_uuid: '00000000-0000-0000-0000-000000000000'},
    {schema_cid: cid('9')}]) {
    assert.deepEqual(wireValue(await restarted.resolveGeneration({...selector, ...changed})),
      {ok: false, code: 'TableReadPublicationBinding'});
  }
  await assert.rejects(reader.resolveGeneration({...selector, extra: true}), {code: 'InvalidTableReadSelector'});
  await assert.rejects(reader.resolveGeneration({...selector, namespace: ['test.other']}),
    {code: 'InvalidTableReadSelector'});
  assert.deepEqual(wireValue(await f.bridge.cleanup(prepared)),
    {ok: true, result: {retained: true, pending: false, removed: 0}});
});

test('real commit followed by process loss stays possible-dispatch after Ledger restart', async t => {
  const f = await fixture(t, new URL('../connectors/local/iceberg/fixtures/lost-reply-process.py', import.meta.url));
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
  const restarted = createIcebergPhysicalBridge({python, run: 'table-run', catalog: f.catalog});
  const recovered = await restarted.reconcileOperation(operation);
  assert.equal(recovered.ok, true);
  assert.equal(recovered.result.request_cid, operation.request_cid);
  assert.deepEqual(wireValue((await f.bridge.read(recovered.result, f.mapping)).result), [{id: 1}]);
  assert.equal((await f.bridge.cleanup(prepared)).result.retained, true);
});

test('lost noncommit reply recovers the original durable fence without resending', async t => {
  const f = await fixture(t);
  const first = await f.bridge.execute(f.prepare(f.operation(), [{id: 1}]), {useCid: cid('7')});
  const committed = JSON.parse(first.observation.body).result;
  const {request_cid: _, ...body} = f.operation();
  const preimage = {...body, input_relation_cid: cid('9')};
  const operation = {...preimage, request_cid: machineCid(preimage)};
  const lost = createIcebergPhysicalBridge({python, run: 'table-run', catalog: f.catalog,
    entry: new URL('../connectors/local/iceberg/fixtures/lost-noncommit-process.py', import.meta.url)});
  const prepared = lost.prepareWrite({operation, mapping: f.mapping, rows: [{id: 2}],
    reservation: {bytes: 1048576, files: 16}, schemaWire: f.schemaWire});
  const claim = f.claim(operation), ledger = f.open();
  try {
    await assert.rejects(captureClaimedEffectResponse({ledger, claim, requestCid: operation.request_cid,
      execute: () => lost.execute(prepared, {useCid: cid('7')})}));
    assert.equal(ledger.readClaimedResponse(claim), undefined, 'Lost reply is not a terminal fact');
    assert.deepEqual(lost.status(prepared), {attempted: true, stopped: true});
  } finally { ledger.close(); }
  const reopened = f.open();
  t.after(() => reopened.close());
  const recovered = wireValue(await f.bridge.reconcileOperation(operation));
  assert.equal(recovered.ok, false);
  assert.equal(recovered.result.reason, 'CreateNameConflict');
  assert.equal(recovered.result.request_cid, operation.request_cid);
  const projection = JSON.parse(checked(moon.clientProgramTableOperationCommitOutcome(
    canonicalText(operation), JSON.stringify(recovered), 409, 1n, 65536, 4096, 16)));
  assert.equal(projection.state, 'failed');
  assert.deepEqual(projection.error.details, recovered.result);
  assert.equal((await captureClaimedEffectResponse({ledger: reopened, claim,
    requestCid: operation.request_cid, execute: () => assert.fail('Lost refusal must not send again')})).claimed, false);
  const cleaned = wireValue(await lost.cleanup(prepared));
  assert.equal(cleaned.result.retained, false);
  assert.equal(cleaned.result.pending, false);
  assert.deepEqual(wireValue(await f.bridge.reconcileOperation(operation)), recovered,
    'Cleanup cannot erase the original noncommit fact');
  assert.deepEqual(wireValue((await f.bridge.read(committed, f.mapping)).result), [{id: 1}],
    'Conflict cleanup must preserve the winning Table');
});

test('positive staging then cancellation waits for actual stop before fenced cleanup', async t => {
  const f = await fixture(t, new URL('../connectors/local/iceberg/fixtures/stalled-process.py', import.meta.url));
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
  assert.throws(() => bridge.prepareWrite({operation: {request_cid: cid('1'), schema_cid: cid('2')},
    mapping: {}, rows: [], reservation: {bytes: 1048576, files: 16}, schemaWire: '{}'}),
  {code: 'InvalidTableLogicalSchema'});
  assert.throws(() => bridge.prepareWrite({operation: {request_cid: cid('1')}, mapping: {}, schemaWire: '{}',
    rows: [{p: 'x'.repeat(4 * 1024 * 1024)}], reservation: {bytes: 1048576, files: 16}}),
  {code: 'FrameByteLimit'});
  let getterCalls = 0;
  const row = {get p() { getterCalls++; return 'value'; }};
  assert.throws(() => bridge.prepareWrite({operation: {request_cid: cid('1')}, mapping: {}, schemaWire: '{}',
    rows: [row], reservation: {bytes: 1048576, files: 16}}), {code: 'InvalidFrameValue'});
  assert.equal(getterCalls, 0);
});

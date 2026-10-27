import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';

// Actual Common acquisition/planner/Ledger/capture; the authority, reader and
// retirement observation are explicit test ports. No physical or normal
// numerical adequacy is inferred from these private declaration amounts.
async function fixture({withCompute = true} = {}) {
  const read = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{resource: 'records',
      resource_kind: 'record', fields: [{name: 'id', type: 'number', nullable: false}]}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(
    (await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: 'original-provider-reader', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'records'}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: ['id'], as: 'output'}],
      results: {r: {from: 'output', fields: ['id']}}},
    ...(withCompute ? [{id: 'compute', inputs: {x: {result: {stage: 'scan', result: 'r'}}},
      steps: [{filter: 'id > 0'}, {select: ['id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}}}] : [])],
    results: {r: {from: {stage: withCompute ? 'compute' : 'scan', result: 'r'}}}}), 'json', checkedEnvironment, undefined);
  const preparedProgram = moon.clientProgramPreparationReady(outcome);
  assert.ok(preparedProgram, inspect(moon.clientProgramPreparationIssue(outcome), {depth: 5}));
  assert.equal(moon.clientProgramTaskCount(preparedProgram), withCompute ? 2 : 1);
  const [registry, aoa] = await Promise.all([read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse)]);
  const preparation = {preparedProgram, registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  const originalCapacity = moon.clientProgramRowSourceProviderCapacity(4096n, 8192n);
  assert.ok(originalCapacity);
  let retired = false, readers = 0, reads = 0, stops = 0, fallback = 0, generation = 1;
  let originalReader, originalOptions;
  const providerReader = {capacity: originalCapacity, prepare(options) {
    assert.equal(this, providerReader);
    assert.equal(Object.isFrozen(options), true);
    assert.equal(Object.isFrozen(options.rowRun), true);
    assert.equal(typeof options.rowRun.requestId, 'string');
    originalOptions = options;
    readers++;
    originalReader = {
      async read() {
        assert.equal(this, originalReader); reads++;
        await options.verifyRead();
        const rows = [{id: 1}], charge = options.chargePage(Buffer.from(JSON.stringify(rows)));
        options.consumePage(rows, {charge});
      },
      requestStop() {assert.equal(this, originalReader); stops++;},
      observe() {assert.equal(this, originalReader); return {cleanupConfirmed: retired};},
    };
    return originalReader;
  }};
  const adapter = await createInstalledRowSource({moon, declaration, declared,
    environmentWire: environment.wire, connectorId: 'fixture', connectorRegistration: 'fixture',
    connectorRevision: 'fixture/0.1', bindingCid: `sha256:${'a'.repeat(64)}`,
    site: {connection: 'fixture:records', issueReadGrant: () => ({}), close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: 'context'}},
    readOperation: 'read', physicalTarget: (resource, fields) => ({resource, fields, generation}),
    readPages() {fallback++; assert.fail('ordinary fallback used');}, providerReader,
    limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}});
  const preparedSource = await adapter.prepare(preparation);
  const planned = adapter.ledgerCapacity(preparedSource);
  const ledger = moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
    planned.capacity, planned.transferBytes, planned.executionBytes,
    preparation.registry, preparation.values, preparation.fragment, preparation.ordered);
  if (withCompute) assert.ok(ledger);
  return {adapter, preparation, preparedSource, ledger, providerReader, originalCapacity,
    usage: () => [...moon.clientProgramMultiCapturedLedgerUsage(ledger)],
    options: () => originalOptions,
    counts: () => ({readers, reads, stops, fallback}),
    retire() {retired = true;}, stale() {generation++;}};
}

test('original acquisition-only graph remains outside the Source-plus-Compute Ledger planner', async () => {
  const f = await fixture({withCompute: false});
  assert.equal(f.ledger, undefined);
  assert.deepEqual(f.counts(), {readers: 0, reads: 0, stops: 0, fallback: 0});
});

test('actual Common provider projection and original reader retain one reservation through capture', async () => {
  const f = await fixture();
  assert.equal(f.adapter.retainedCapture(f.preparedSource).capacity,
    f.adapter.ledgerCapacity(f.preparedSource).capacity);
  const original = f.usage();
  // Mutation cannot replace the installation's original snapshot or supplier.
  f.providerReader.capacity = moon.clientProgramRowSourceProviderCapacity(1n, 1n);
  f.providerReader.prepare = () => {assert.fail('replacement supplier used');};
  const capture = await f.adapter.openCapture({...f.preparation,
    preparedSource: f.preparedSource, ledger: f.ledger});
  assert.ok(capture.capturedSource);
  assert.ok(capture.capture.originalRead());
  assert.deepEqual(f.counts(), {readers: 1, reads: 1, stops: 0, fallback: 0});
  assert.equal(moon.clientProgramInstalledProviderRowCaptureCapacityMatches(
    f.adapter.ledgerCapacity(f.preparedSource).capacity,
    f.options().rowRun.acquisition, f.originalCapacity), true);
  const held = f.usage();
  assert.equal(held[1], original[1] + 1n);
  assert.ok(held[6] >= 4096n); assert.ok(held[7] >= 8192n);
  assert.throws(() => capture.close(), {code: 'MoonBitHostFailure'});
  assert.deepEqual(f.usage(), held);
  f.retire();
  let closed = false;
  for (let index = 0; index < 128 && !closed; index++) {
    try {capture.close(); closed = true;}
    catch (error) {assert.equal(error.code, 'MoonBitHostFailure');}
  }
  assert.equal(closed, true);
  assert.equal(ledgerUsageSnapshot(f.usage()).reservedRetentionBytes, 0n); assert.equal(ledgerUsageSnapshot(f.usage()).reservedExecutionBytes, 0n);
  assert.equal(f.counts().stops, 1);
});

test('actual Common provider caller rejects copied preparation and stale installation before a reader', async () => {
  const f = await fixture();
  assert.throws(() => f.adapter.ledgerCapacity({...f.preparedSource}),
    {code: 'InstalledSourcePreparationMismatch'});
  const before = f.usage();
  await assert.rejects(f.adapter.openCapture({...f.preparation,
    preparedSource: f.preparedSource}),
  error => error.cause?.code === 'InstalledProviderSourceLedgerRequired');
  f.stale();
  await assert.rejects(f.adapter.openCapture({...f.preparation,
    preparedSource: f.preparedSource, ledger: f.ledger}),
  error => error.cause?.code === 'InstalledSourcePreparationMismatch');
  assert.deepEqual(f.usage(), before);
  assert.deepEqual(f.counts(), {readers: 0, reads: 0, stops: 0, fallback: 0});
});

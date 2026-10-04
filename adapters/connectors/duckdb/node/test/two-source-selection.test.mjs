// Adapter connection tests only. Real candidate eligibility, reservations and
// provider lifecycle are exercised by the shared two-source public harness.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareCapturedDuckDBSource, capturedDuckDBConfiguration,
  capturedDuckDBPhysicalCapacity} from '../../../../host-node/captured-duckdb-source.mjs';
import {installNodeClientDispatchOwner} from '../../../../host-node/client-dispatch-owner.mjs';
import {acquisitionFailure} from '../../../../host-common/acquisition-outcome.mjs';

const ok = value => ({$tag: 1, _0: value});
const limits = {maxRows: 100, maxCells: 200, maxTransportBytes: 10000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 2,
  memoryBytes: 1024 * 1024, threads: 1};
const sourceRef = 'connector://fixture/records#v';
function fixture({decision = 'dispatch', selected = 'nativeQuery'} = {}) {
  const calls = [], preparedProgram = {}, preparedEffect = {}, requirement = {};
  const native = {}, broad = {};
  const moon = {
    clientProgramAcquisitionCount: () => 2,
    clientProgramPrepareQueryAcquisition: () => ok({}),
    clientProgramEffectPrepareQueryAcquisition: () => ok({}),
    clientProgramPrepareLocalQueryRequirement: () => ok(requirement),
    clientProgramEffectPrepareLocalQueryRequirement: () => ok(requirement),
    clientProgramQueryRequirementSourceEvidenceFacts: () => ok([
      sourceRef, 'contract', 'schema', 'policy', 'internal', 'view']),
    clientProgramQueryRequirementCid: () => 'sha256:' + 'a'.repeat(64),
    clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
    clientProgramPrepareDuckDBSourceEvidenceContext: () => ok({}),
    clientProgramDuckDBAcquisitionEstimate: (...args) => { calls.push({estimate: args}); return ok({}); },
    clientProgramSelectDuckDBAcquisition: (...args) => {
      calls.push({selection: args}); return ok({});
    },
    clientProgramDuckDBSelectionDocument: () => JSON.stringify({
      status: selected === undefined ? 'deferred' : 'selected',
      selectedCandidate: selected, missing: [],
      candidates: [{candidate: 'nativeQuery'}, {candidate: 'broadQuery'}]}),
    clientProgramDuckDBSelectionNative: () => selected === 'nativeQuery' ? native : undefined,
    clientProgramDuckDBSelectionBroad: () => selected === 'broadQuery' ? broad : undefined,
    clientProgramCapturedNativeConfiguration: value => ({kind: 'native', value}),
    clientProgramCapturedBroadConfiguration: value => ({kind: 'broad', value}),
    clientProgramPrepareDuckDBAcquisition() { assert.fail('plural execution must use common selection'); },
  };
  const sourceAccess = {sourceRef, authorization: {authorize: async () => ({action: decision})}};
  const options = {moon, preparedProgram, registry: '{}', values: '{}', fragment: '{}', ordered: '{}',
    database: '/fixture.db', schema: 'main', table: 'records', sourceAccess,
    transportLimits: limits, acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']}};
  return {moon, calls, native, broad, preparedProgram, preparedEffect, options};
}

for (const selected of ['nativeQuery', 'broadQuery']) {
  test(`pure and Effect two-input preparation keep the selected ${selected} owner`, async () => {
    const f = fixture({selected});
    for (const effectful of [false, true]) for (const task of [0, 1]) {
      const prepared = await prepareCapturedDuckDBSource({...f.options,
        ...(effectful ? {preparedProgram: undefined, preparedEffect: f.preparedEffect} : {}),
        occurrence: {stage: task, input: 0, task}});
      assert.equal(prepared.selection.selectedCandidate, selected);
      assert.deepEqual(capturedDuckDBConfiguration(prepared),
        {kind: selected === 'nativeQuery' ? 'native' : 'broad', value: selected === 'nativeQuery' ? f.native : f.broad});
      assert.ok(capturedDuckDBPhysicalCapacity(prepared).executionBytes > 0n);
    }
    assert.equal(f.calls.filter(call => call.selection).length, 4);
    for (const call of f.calls.filter(call => call.estimate)) {
      assert.deepEqual(call.estimate, [[], [], [undefined, undefined, undefined]],
        'explicit priority does not fabricate estimated cost or quantities');
    }
  });
}

test('held and denied plural reads cannot select or manufacture a configuration', async () => {
  const held = fixture({decision: 'hold'});
  const prepared = await prepareCapturedDuckDBSource(held.options);
  assert.equal(prepared.selection, undefined);
  assert.equal(held.calls.length, 0);
  assert.throws(() => capturedDuckDBConfiguration(prepared), {message: 'InstalledSourceSelectionRequired'});
  assert.throws(() => capturedDuckDBConfiguration({}), {message: 'InstalledSourcePreparationMismatch'});
  const denied = fixture({decision: 'deny'});
  await assert.rejects(prepareCapturedDuckDBSource(denied.options));
  assert.equal(denied.calls.length, 0);
});

test('unknown plural comparison stays deferred instead of taking the old Native shortcut', async () => {
  const f = fixture({selected: null});
  f.moon.clientProgramDuckDBSelectionDocument = () => JSON.stringify({status: 'deferred',
    candidates: [{candidate: 'nativeQuery'}, {candidate: 'broadQuery'}], missing: ['cost']});
  await assert.rejects(prepareCapturedDuckDBSource({...f.options, acquisitionPlanning: undefined}),
    {code: 'InstalledSourceSelectionDeferred'});
  assert.equal(f.calls.filter(call => call.selection).length, 1);
});

test('resumed two-input preparations size one ledger before opening and keep first cleanup on second failure', async () => {
  const f = fixture({decision: 'hold', selected: 'broadQuery'});
  const sourceAccess = f.options.sourceAccess;
  const accesses = [0, 1].map(() => ({...sourceAccess,
    authorization: {authorize: async () => ({action: 'dispatch'})}}));
  const preparedSources = [];
  const order = [], closes = [], stopped = [], ledger = {}, ref = {runDefinitionCid: 'run'};
  let cleanupBlocked = true, selections;
  for (let task = 0; task < 2; task++) {
    const occurrence = {stage: task, input: 0, task};
    preparedSources.push({occurrence, sourceAccess,
      prepared: await prepareCapturedDuckDBSource({...f.options, occurrence}),
      adapter: {async open(options) {
        order.push(`open-${task}`); assert.equal(options.ledger, ledger);
        assert.equal(options.sourceAccess, accesses[task]);
        assert.equal(capturedDuckDBConfiguration(options.preparedSource).value, f.broad);
        if (task === 1) throw acquisitionFailure(new Error('second source failed'), 'stopped');
        return {occurrence, checkedSource: {sourceDataPolicyCid: 'policy'},
          acquisition: {selection: options.preparedSource.selection},
          issueSourceEvidence: async () => 'evidence',
          async close() { closes.push(0); if (cleanupBlocked) throw new Error('cleanup pending'); }};
      }}});
  }
  f.moon.clientProgramPrepareMultiCapturedLocalAcquisitionLedger = (_owner, configurations, transfers, execution) => {
    order.push('ledger'); selections = configurations;
    assert.equal(configurations.length, 2);
    assert.ok(transfers.every(value => value > 0n));
    assert.ok(execution.every(value => value > 0n));
    return ledger;
  };
  f.moon.clientProgramMultiCapturedLedgerUsage = value => { assert.equal(value, ledger); return Array(10).fill(0n); };
  const owner = installNodeClientDispatchOwner({moon: f.moon, control: {},
    journal: {reservePhysicalStart: () => true, markPhysicalClose: (...args) => stopped.push(args)},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    observed() {}, planFor: () => ({runDefinition: {wire: 'definition'}}),
    sourceProfile: {sources: []}, registry: '{}', values: '{}', fragment: '{}', ordered: '{}',
    now: () => '2026-10-03T00:00:00Z',
    checkpoints: {heldOrigin: () => undefined, acquisitionAccess: (_request, base, occurrence) => {
      if (occurrence === undefined) return undefined;
      assert.equal(base, sourceAccess); return accesses[occurrence.task]; }, releaseAcquisition() {}},
    prepareAcquisition: async (_program, access, occurrence) => {
      order.push(`prepare-${occurrence.task}`);
      return prepareCapturedDuckDBSource({...f.options, sourceAccess: access, occurrence});
    },
    runPublished() { assert.fail('second-source failure cannot start computation'); },
  });
  assert.equal(await owner.start({preparedProgram: f.preparedProgram, principalId: 'owner',
    connection: {}, requestId: 'request'}, {}, {ref, runDefinition: {wire: 'definition'},
    dispatchReserved: false, cancellationRequested: false}, {preparedSources}), 'started');
  await owner.operation(ref);
  assert.deepEqual(order, ['prepare-0', 'prepare-1', 'ledger', 'open-0', 'open-1']);
  assert.ok(selections.every(value => value.kind === 'broad' && value.value === f.broad));
  assert.deepEqual(stopped, []);
  await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
  cleanupBlocked = false;
  await owner.drain();
  assert.equal(stopped.length, 1);
  const closeCount = closes.length;
  await owner.drain();
  assert.equal(closes.length, closeCount);
  assert.deepEqual(order, ['prepare-0', 'prepare-1', 'ledger', 'open-0', 'open-1'],
    'cleanup retries do not reselect, reopen or recredit acquisition');
});

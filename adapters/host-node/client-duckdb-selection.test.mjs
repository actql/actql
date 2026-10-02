import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {capturedDuckDBNativeConfiguration, openCapturedDuckDBSource,
  prepareCapturedDuckDBSource} from './captured-duckdb-source.mjs';

const nativeCapability = 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8';
const broadCapability = 'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89';
const text = path => readFile(new URL(path, import.meta.url), 'utf8');
const contracts = await Promise.all(['actql-query-acquisition.json',
  'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
  .map(name => text(`../../spec/contracts/${name}`)));
const aoa = JSON.parse(await text('../../spec/contracts/actql-aoa.json'));
const registry = await text('../../spec/dependencies/aoa-pipeline-registry.json');
const program = await text('../connectors/duckdb/node/examples/program.json');
const parameters = await text('../connectors/duckdb/node/examples/parameters.json');
const preparedOwners = new WeakMap();

async function requirement(capabilities = [nativeCapability, broadCapability], document = program) {
  const environmentBody = JSON.parse(await text('./fixtures/query-amount-environment.json'));
  environmentBody.connector_capabilities[0].capability_contract_cids = [...capabilities].sort();
  delete environmentBody.evidence_bundle_cid;
  environmentBody.evidence_bundle_cid = contentCid(environmentBody);
  const environment = moon.clientProgramCheckEnvironment(canonicalJson(environmentBody),
    environmentBody.evidence_bundle_cid, false, false, true, false, false, false, false);
  assert.ok(environment);
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
    document, 'json', environment, parameters);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.ok(prepared, String(moon.clientProgramPreparationIssueCode(outcome)));
  const required = checked(moon.clientProgramPrepareLocalQueryRequirement(prepared, 0, 0,
    registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  preparedOwners.set(required, prepared);
  return required;
}

function estimate(slots, duration, quantities = [137n, 103n, undefined]) {
  return checked(moon.clientProgramDuckDBAcquisitionEstimate(
    [Array.from({length: slots}, (_, index) => index)], [duration], quantities));
}

function choose(required, native, broad) {
  const selected = checked(moon.clientProgramSelectDuckDBAcquisition(required,
    'main', 'records', ...contracts, native, broad, []));
  return {selected, report: JSON.parse(moon.clientProgramDuckDBSelectionDocument(selected)),
    native: moon.clientProgramDuckDBSelectionNative(selected),
    broad: moon.clientProgramDuckDBSelectionBroad(selected)};
}

test('one real requirement compares Native and Broad and keeps the exact selected payload', async () => {
  const required = await requirement();
  const broad = estimate(8, 20n, [421n, 303n, undefined]);
  const nativeWins = choose(required, estimate(11, 10n), broad);
  assert.equal(nativeWins.report.reason, 'EstimatedFastest');
  assert.equal(nativeWins.report.selectedCandidate, 'nativeQuery');
  assert.equal(nativeWins.report.selectedIndex, 0);
  assert.ok(nativeWins.native);
  assert.equal(nativeWins.broad, undefined);
  assert.equal(nativeWins.report.candidates.length, 2);
  assert.deepEqual(nativeWins.report.candidates.map(({candidate, milliseconds,
    transferBytes, retainedBytes, moneyUnits}) => ({candidate, milliseconds,
    transferBytes, retainedBytes, moneyUnits})), [
    {candidate: 'nativeQuery', milliseconds: '10', transferBytes: '137',
      retainedBytes: '103', moneyUnits: null},
    {candidate: 'broadQuery', milliseconds: '20', transferBytes: '421',
      retainedBytes: '303', moneyUnits: null},
  ]);
  // Only one complete duration changes; the requirement and Broad estimate stay identical.
  const broadWins = choose(required, estimate(11, 30n), broad);
  assert.equal(broadWins.report.selectedCandidate, 'broadQuery');
  assert.equal(broadWins.report.selectedIndex, 1);
  assert.equal(broadWins.native, undefined);
  assert.ok(broadWins.broad);
  assert.equal(broadWins.report.requirementCid, nativeWins.report.requirementCid);
  assert.deepEqual(broadWins.report.candidates[1], nativeWins.report.candidates[1]);
  const tied = choose(required, estimate(11, 20n), broad);
  assert.equal(tied.report.selectedCandidate, 'nativeQuery');
  assert.equal(tied.report.reason, 'EstimatedFastest');
});

test('unknown complete duration or missing physical work defers without an executable payload', async () => {
  const required = await requirement();
  for (const native of [estimate(11, undefined), estimate(10, 1n)]) {
    const deferred = choose(required, native, estimate(8, 20n));
    assert.equal(deferred.report.status, 'deferred');
    assert.equal(deferred.report.reason, 'Deferred');
    assert.equal(deferred.report.selectedCandidate, null);
    assert.equal(deferred.report.candidates[0].milliseconds, null);
    assert.equal(deferred.native, undefined);
    assert.equal(deferred.broad, undefined);
  }
});

test('capability evidence filters a cheaper candidate before the common cost comparison', async () => {
  const required = await requirement([broadCapability]);
  const choice = choose(required, estimate(11, 1n), estimate(8, 20n));
  assert.equal(choice.report.nativeSupported, false);
  assert.equal(choice.report.broadSupported, true);
  assert.equal(choice.report.candidates.length, 1);
  assert.equal(choice.report.selectedCandidate, 'broadQuery');
  assert.equal(choice.report.selectedIndex, 0);
  assert.equal(choice.native, undefined);
  assert.ok(choice.broad);
  assert.equal(choice.report.estimates.nativeQuery.estimates[0].milliseconds, '1');
});

test('an empty eligible inventory has no executable payload or cheapest-candidate claim', async () => {
  const choice = choose(await requirement([]), estimate(11, 0n), estimate(8, 0n));
  assert.equal(choice.report.status, 'no_candidates');
  assert.equal(choice.report.reason, 'NoCandidates');
  assert.deepEqual(choice.report.candidates, []);
  assert.equal(choice.report.selectedCandidate, null);
  assert.equal(choice.native, undefined);
  assert.equal(choice.broad, undefined);
});

test('unsupported native compilation cannot win a cheap estimate with both capabilities advertised', async () => {
  const document = JSON.parse(program);
  document.stages[0].steps[0].filter = 'id + 1 > $minimum';
  const required = await requirement(undefined, JSON.stringify(document));
  const choice = choose(required, estimate(11, 1n), estimate(8, 20n));
  assert.equal(choice.report.nativeSupported, false);
  assert.equal(choice.report.selectedCandidate, 'broadQuery');
  assert.equal(choice.report.candidates.length, 1);
  assert.equal(choice.native, undefined);
  assert.ok(choice.broad);
  assert.throws(() => choose(required, estimate(11, -1n), estimate(8, 20n)));
});

test('malformed estimates do not silently remove a valid physical capability', async () => {
  const required = await requirement();
  const duplicate = checked(moon.clientProgramDuckDBAcquisitionEstimate(
    [Array.from({length: 11}, (_, index) => index), [0]], [10n, 1n],
    [undefined, undefined, undefined]));
  for (const invalid of [duplicate, estimate(11, -1n),
    estimate(11, 1n, [-1n, undefined, undefined])]) {
    assert.throws(() => choose(required, invalid, estimate(8, 20n)));
  }
  assert.throws(() => choose(required, estimate(11, 10n), estimate(8, -1n)));
  const broadOnly = await requirement([broadCapability]);
  assert.throws(() => choose(broadOnly, duplicate, estimate(8, 20n)));
  assert.throws(() => checked(moon.clientProgramDuckDBAcquisitionEstimate(
    [[0]], [], [undefined, undefined, undefined])));
});

const sourceLimits = {maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1};

async function sourceOptions(required, observedMoon, outcome) {
  const authorization = await createNodeAuthorizationGate({
    configuration: canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: 'planner-ordering', entries: [{entry_id: 'read', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
    context: {principal: 'planner-ordering', contextCid: 'sha256:' + 'c'.repeat(64)},
  });
  return {moon: observedMoon, preparedProgram: preparedOwners.get(required), registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered']),
    database: '/unopened-fixture.duckdb', schema: 'main', table: 'records',
    sourceAccess: {authorization, sourceRef: 'connector://crm/main/r#v'},
    transportLimits: sourceLimits,
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']}};
}

test('mandatory resource information and current authorization precede any priority or cost comparison', async () => {
  let comparisons = 0;
  const observedMoon = {...moon, clientProgramSelectDuckDBAcquisition(...args) {
    comparisons++;
    return moon.clientProgramSelectDuckDBAcquisition(...args);
  }};
  for (const capabilities of [[nativeCapability, broadCapability], [broadCapability]]) {
    const required = await requirement(capabilities);
    const options = await sourceOptions(required, observedMoon, 'allow');
    const incomplete = {...sourceLimits}; delete incomplete.memoryBytes;
    await assert.rejects(prepareCapturedDuckDBSource({...options, transportLimits: incomplete}),
      {code: 'InvalidLimits'});
    await assert.rejects(prepareCapturedDuckDBSource({...options, transportLimits: undefined}),
      {code: 'InvalidLimits'});
    assert.equal(comparisons, 0);
    const denied = await sourceOptions(required, observedMoon, 'deny');
    await assert.rejects(prepareCapturedDuckDBSource(denied),
      {runtimeCode: 'ACTQL_E_ACCOUNT_DENIED'});
    assert.equal(comparisons, 0);
  }
});

test('selection postponed by authorization can defer without starting source acquisition', async () => {
  const options = await sourceOptions(await requirement(), moon, 'allow');
  const current = options.sourceAccess.authorization;
  let permitted = false;
  options.sourceAccess = {...options.sourceAccess, authorization: {
    authorize: (...args) => permitted ? current.authorize(...args)
      : Promise.resolve({action: 'unsupported', reason: 'read_approval_required'}),
  }};
  options.acquisitionPlanning = {policy: 'estimatedLatency', candidates: {}};
  const preparedSource = await prepareCapturedDuckDBSource(options);
  assert.equal(preparedSource.selection, undefined);
  assert.throws(() => capturedDuckDBNativeConfiguration(preparedSource),
    {message: 'InstalledMultiSourceNativeAcquisitionRequired'});
  // Revising the original mutable object cannot change the prepared policy.
  options.acquisitionPlanning.policy = 'priority';
  delete options.acquisitionPlanning.candidates;
  options.acquisitionPlanning.priority = ['nativeQuery', 'broadQuery'];
  permitted = true;
  let ended;
  // The fixture database does not exist. Selection must defer before even the
  // technical file-grant lookup, and retain a definitive not_started outcome.
  await assert.rejects(openCapturedDuckDBSource({...options, preparedSource,
    reportAcquisitionFailure: failure => { ended = failure; }}),
  {code: 'InstalledSourceSelectionDeferred'});
  assert.equal(ended.outcome, 'not_started');
});

test('a prepared source binds its immutable mandatory transport policy', async () => {
  const options = await sourceOptions(await requirement(), moon, 'allow');
  options.transportLimits = {...sourceLimits};
  const preparedSource = await prepareCapturedDuckDBSource(options);
  assert.equal(preparedSource.selection.reason, 'HostPreferred');
  options.transportLimits.memoryBytes *= 2;
  let ended;
  await assert.rejects(openCapturedDuckDBSource({...options, preparedSource,
    reportAcquisitionFailure: failure => { ended = failure; }}),
  {message: 'InstalledSourceResourcePolicyMismatch'});
  assert.equal(ended.outcome, 'not_started');
});

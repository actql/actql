// Test-only trusted installation and original request Owner. All checking,
// compilation, authorization, selection, execution and cleanup are product code.
import {instantiate} from '../../_build/workers/modules/fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {bindWorkersFiniteHost} from './finite.mjs';

// Pinned public run-materials sample. Its CID is independently fixed in
// run_publication_host/client_values_run_materials_wbtest.mbt.
const environmentWire = '{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}';
const environmentCid = 'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904';

export function finiteDocument(rows = [{id: 1}, {id: 2}], nullable = false) {
  return JSON.stringify({version: 'actql/0.1', id: 'workers-finite',
    stages: [{id: 'source', inputs: {}, steps: [{values: {
      schema: {id: {type: 'number', nullable}}, rows}, as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}});
}

function configuration(moon, maxRows) {
  const [registry, values, grammar, barriers] = checked(moon.workersFiniteFixtureContracts());
  return {
    environment: {wire: environmentWire, cid: environmentCid,
      expressions: {text_time: false, veca: false},
      operations: {rela: true, sga: false, tea: false, calendar: false, text_rank: false}},
    contracts: {registry, values, grammar, barriers},
    sequence: {max_steps: 10, max_rows: 100, max_cells: 100,
      max_bindings: 10, max_name_bytes: 1000,
      expressions: {max_nodes: 100, max_work: 1000, max_depth: 10,
        max_literal_nodes: 100, max_literal_text_bytes: 1000}},
    execution: moon.workersFiniteFixtureExecution(),
    measurement: {max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100},
    capacity: {contract_cid: 'sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f',
      max_rows: maxRows, max_value_bytes: 10000},
    search: {max_offers: 10, max_strategies: 10, max_work: 10000, max_revisions: 3},
    ledger: {planning_work: 10000, attempts: 10, holdings: 10, transfer_bytes: 300000n,
      retained_bytes: 32000000n, execution_bytes: 134217728n},
    milliseconds: 1n, max_work: 10000, max_entries: 100,
  };
}

function gate(moon, outcome) {
  return createAuthorizationGate({runtime: moon,
    configuration: outcome === 'missing' ? undefined : JSON.stringify({
      version: 'actql-execution-account-config/0.1', account_id: 'workers-test-account',
      entries: [{entry_id: 'finite-activation', outcome,
        principal: {any_of: ['workers-tester']},
        connection: {any_of: ['in-process-default']}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    context: {principal: 'workers-tester', contextCid: 'sha256:' + 'a'.repeat(64)},
    protectedSites: ['in-process-default'],
  });
}

function failureCodes(error) {
  const codes = [], seen = new Set();
  const visit = value => {
    if (value == null || seen.has(value)) return;
    seen.add(value);
    if (typeof value.code === 'string') codes.push(value.code);
    if (typeof value.runtimeCode === 'string') codes.push(value.runtimeCode);
    if (typeof value.message === 'string' && !codes.includes(value.message)) codes.push(value.message);
    visit(value.cause);
    for (const nested of value.errors ?? []) visit(nested);
  };
  visit(error);
  return codes;
}

const refusal = action => {
  try { action(); return null; } catch (error) { return error.message; }
};

export function finiteOriginalMaterials({hashSeed = 0, rows = [{id: 1}, {id: 2}], nullable = false} = {}) {
  const moon = instantiate(hashSeed), selected = configuration(moon, 100);
  const host = bindWorkersFiniteHost(moon, selected);
  const document = finiteDocument(rows, nullable);
  const preparation = host.prepare(document);
  const original = moon.workersFiniteFixtureOriginal(preparation.program, preparation.compilation);
  const admission = moon.workersFiniteFixtureAdmission(original);
  const definition = moon.workersFiniteFixtureDefinition(original);
  return Object.freeze({configuration: selected,
    wire: moon.workersFiniteFixtureMaterials(preparation.program, preparation.compilation,
      admission, definition, environmentWire, environmentCid, document),
    runDefinitionCid: moon.strategyPublicationContractIdentity(definition)});
}

function durableRecordCase(moon) {
  const core = runtimeCore(moon), control = core.remoteSiteControl;
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const site = core.siteControl.create({key: 'worker-durable', generation: 1,
    runtimeRevision: cid('a'), maxConcurrentOperations: 1, maxConcurrentTransfers: 1,
    maxRetainedBytes: 1024n, maxExecutionBytes: 1024n});
  const request = control.prepare({coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'), taskKey: 'task-a', taskAttempt: 1,
    dispatchId: 'dispatch-a', siteKey: 'worker-durable', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'local',
    connectorRevision: 'local/1', strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'), obligationsCid: cid('2'), budgetCid: cid('3'),
    evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4')});
  const outputIntentInput = {storeAuthorityCid: cid('c'), publicationAttemptCid: cid('d'),
    resultDefinitionCid: cid('e'), orderingEvidenceCid: cid('f'),
    coordinatorAuthority: 'coordinator-a', transferAttemptId: 'transfer-a', transferRoute: 'direct',
    destinationSite: 'destination', destinationSiteGeneration: 2, transferMaxBytes: 1024n,
    transferExpiresAtMilliseconds: 1000n, sourceGrantCid: cid('1'),
    destinationGrantCid: cid('2'), routeCapabilityCid: cid('3'), transferOrigin: 'https://site.test'};
  const intent = control.prepareOutputIntent(request, outputIntentInput);
  const polled = control.admitPollOutput(control.pollOutputJson(request, intent));
  const outputProjection = control.outputIntentProjection(control.pollOutputIntent(polled));
  const outputRequestMatches = control.identity(control.pollOutputRequest(polled)) === control.identity(request);
  const journal = control.createJournal(site);
  const admission = control.prepareAdmission(journal, request);
  const initial = control.admissionDurableJson(admission);
  const refusedAdmission = refusal(() => control.commitAdmission(admission, false));
  const record = control.commitAdmission(admission, true);
  const initialMatch = control.recordDurableJson(record) === initial;
  const durable = control.admitDurableRecordJson(initial);
  const custody = control.createRuntimeCustody();
  const actions = [control.runtimeSuccessAction(record, custody)];
  control.runtimeCustodyAcquireBundle(custody);
  actions.push(control.runtimeSuccessAction(record, custody));
  const capability = control.registerExecutionCapability({site,
    runtimeBundleCid: cid('a'), connectorRegistration: 'local',
    connectorRevision: 'local/1', strategyRevision: 'strategy/1',
    operationCapabilityCid: cid('4')});
  const transition = control.prepareProvisioning(record, capability);
  const staleTransition = control.prepareProvisioning(record, capability);
  const planned = control.transitionDurableJson(transition);
  const expectedRevision = control.transitionExpectedRevision(transition);
  const refusedCommit = refusal(() => control.commitTransition(transition, false));
  const unchangedAfterRefusal = control.recordDurableJson(record) === initial;
  control.commitTransition(transition, true);
  const plannedMatch = control.recordDurableJson(record) === planned;
  const refusedStaleCommit = refusal(() => control.commitTransition(staleTransition, true));
  const refusedConsumedCommit = refusal(() => control.commitTransition(transition, true));
  const unchangedAfterStaleCommit = control.recordDurableJson(record) === planned;
  actions.push(control.runtimeSuccessAction(record, custody));
  control.runtimeCustodyAcquireOperation(custody);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.commitTransition(control.prepareExecution(record), true);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.runtimeCustodyAcquireOutput(custody);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.runtimeCustodyAcquireHolding(custody);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.runtimeCustodySettleOperation(custody);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.commitTransition(control.prepareSettled(record), true);
  actions.push(control.runtimeSuccessAction(record, custody));
  control.commitTransition(control.prepareRetained(record, 'material-generation', cid('c')), true);
  actions.push(control.runtimeSuccessAction(record, custody));
  const issuer = control.registerEvidenceIssuer({site, runtimeBundleCid: cid('a'),
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', evidenceKind: 'actql.remote.physical-output/0.1',
    issuerCapabilityCid: cid('b')});
  const evidence = control.issueExecutionEvidence(issuer, record, cid('d'));
  control.commitTransition(control.prepareEvidence(record, evidence), true);
  actions.push(control.runtimeSuccessAction(record, custody));
  const finishedWire = control.recordDurableJson(record);
  const saved = control.admitDurableRecordJson(finishedWire);
  const restored = control.restoreDurableRecord(control.createJournal(site), saved);
  const collision = refusal(() => control.restoreDurableRecord(journal, durable));
  control.runtimeCustodyReleaseOutput(custody);
  const releasedCustody = refusal(() => control.runtimeSuccessAction(record, custody));
  return {initialMatch, plannedMatch, expectedRevision, refusedCommit, refusedAdmission,
    refusedStaleCommit, refusedConsumedCommit, unchangedAfterStaleCommit,
    outputRequestMatches, outputProjection, outputIntentInput,
    managedExecutionProfileCid: core.managedExecutionProfileCid(),
    unchangedAfterRefusal, actions, collision, releasedCustody,
    initialRevision: control.durableRecordRevision(durable),
    initialIdentityMatches: control.durableRecordIdentity(durable) === control.identity(request),
    initialKey: control.durableRecordKey(durable),
    originalWireMatches: control.durableRecordJson(durable) === initial,
    restoredWireMatches: control.recordDurableJson(restored) === finishedWire,
    restoredRevision: control.revision(restored),
    malformed: refusal(() => control.admitDurableRecordJson(initial + ' ')),
    unknownField: refusal(() => control.admitDurableRecordJson(`${initial.slice(0, -1)},"extra":true}`))};
}

export async function runFiniteCase({rows = [{id: 1}, {id: 2}], nullable = false,
  outcome = 'allow', maxRows = 100, cancel = false, consumeFailure = false,
  directClose = false, hashSeed = 0, durableRecords = false, restoreMaterials = false, exportMeasurement = false} = {}) {
  const moon = instantiate(hashSeed);
  if (durableRecords) return durableRecordCase(moon);
  const host = bindWorkersFiniteHost(moon, configuration(moon, maxRows));
  const authorization = gate(moon, outcome);
  let preparation = host.prepare(finiteDocument(rows, nullable));
  const original = moon.workersFiniteFixtureOriginal(preparation.program, preparation.compilation);
  let owner = {admission: moon.workersFiniteFixtureAdmission(original),
    definition: moon.workersFiniteFixtureDefinition(original), ledger: host.createLedger()};
  let materialsChecks, duplicateMaterials;
  if (restoreMaterials) {
    const wire = moon.workersFiniteFixtureMaterials(preparation.program, preparation.compilation,
      owner.admission, owner.definition, environmentWire, environmentCid, finiteDocument(rows, nullable));
    const expected = moon.strategyPublicationContractIdentity(owner.definition);
    const restored = host.admitMaterials(wire, expected);
    duplicateMaterials = host.admitMaterials(wire, expected);
    materialsChecks = {originalIdentity: expected, restoredIdentity:
      moon.strategyPublicationContractIdentity(restored.definition),
      malformed: refusal(() => host.admitMaterials(
        `${wire.slice(0, -1)},"unexpected":true}`, expected)),
      wrongIdentity: refusal(() => host.admitMaterials(wire, "sha256:" + "f".repeat(64))),
      foreignPreparation: refusal(() => host.open({...restored.preparation},
        {...restored, ledger: owner.ledger}, authorization))};
    preparation = restored.preparation;
    owner = {...restored, ledger: owner.ledger};
    // Retain this original locally even when open fails. Public diagnostics
    // contain observations only, never an opaque preparation/Run graph.
  }
  const usage = () => moon.workersFiniteFixtureUsage(owner.ledger);
  const initialUsage = usage();
  let setup, saved, consumed = 0, phase = 'open', duplicateOpen, duplicateExecution, openedFinished;
  let result;
  try {
    setup = host.open(preparation, owner, authorization);
    openedFinished = moon.strategyHostFinished(setup);
    const openedUsage = usage();
    duplicateOpen = refusal(() => host.open(preparation, owner, authorization));
    if (materialsChecks) {
      const duplicate = duplicateMaterials;
      materialsChecks.duplicateAdmission = refusal(() => host.open(duplicate.preparation,
        {...duplicate, ledger: owner.ledger}, authorization));
      duplicateMaterials = undefined;
    }
    const duplicateOpenUsage = usage();
    phase = 'execution';
    const abort = new AbortController();
    if (cancel === 'preaborted') abort.abort(new Error('finite cancellation'));
    const pending = host.withExecution(setup, authorization, async report => {
      consumed++;
      saved = report;
      const output = report.output(0);
      if (!output) throw new Error('MissingFiniteTaskZeroOutput');
      const [rowsWire, schemaWire] = moon.workersFiniteFixtureOutput(output);
      const observation = {rows: JSON.parse(rowsWire), schema: JSON.parse(schemaWire),
        finishedAtConsumption: moon.strategyHostFinished(setup),
        completedTasks: report.completed.map(item => item.task),
        sites: report.completed.map(item => item.executionSite),
        consumedUsage: report.usage()};
      if (exportMeasurement) {
        const control = host.core.outputExportControl;
        const exported = await control.beginResult(setup, 0, {
          maxResultFields: 10, maxResultMappingWork: 10000,
          maxResultOrderWork: 10000, maxResultWorkspaceEntries: 1000,
          maxRows: 100, maxValueNodes: 10000, maxValueTextBytes: 100000,
          maxValueDepth: 100, maxValueWork: 100000, maxWireBytes: 100000,
          maxWireNodes: 10000, maxWireDepth: 100, maxColumns: 100,
          maxOrderWork: 10000, maxLogicalWireBytes: 100000,
          maxLogicalWireNodes: 10000, maxLogicalWireDepth: 100,
          maxSchemaFields: 100, maxSchemaBytes: 10000, maxSchemaNodes: 1000,
          maxSchemaDepth: 100, maxBatchBytes: 32,
        });
        try {
          observation.measurementBeforeFinish = refusal(() => control.measurement(exported));
          let wire = '';
          while (true) {
            const progress = control.advance(exported, 8);
            if (progress.issue !== undefined) throw new Error(progress.issue);
            if (progress.batch !== undefined) wire += progress.batch;
            if (progress.complete) break;
          }
          wire += control.finish(exported);
          observation.exportRows = JSON.parse(wire);
          observation.exportIdentity = control.identity(exported);
          observation.measurement = control.measurement(exported);
          observation.measurementFrozen = Object.isFrozen(observation.measurement) &&
            Object.isFrozen(observation.measurement.columnRows);
        } finally { control.cancel(exported); }
        observation.measurementAfterCancel = refusal(() => control.measurement(exported));
      }
      if (directClose) {
        // Call the canonical bridge while the task-0 output is still retained.
        // Scoped cleanup alone could hide a task-index-zero close regression.
        observation.beforeClose = usage();
        moon.strategyHostCloseOutputs(setup);
        observation.afterClose = usage();
        observation.outputAfterClose = moon.strategyHostOutput(setup, 0) !== undefined;
      }
      await Promise.resolve();
      if (consumeFailure) throw new Error('finite consumer failure');
      return observation;
    }, abort.signal);
    if (cancel === true || cancel === 'immediate') abort.abort(new Error('finite cancellation'));
    const observation = await pending;
    duplicateExecution = refusal(() => host.withExecution(setup, authorization, () => {}));
    result = {status: 'completed', ...observation, openedUsage, duplicateOpenUsage,
      finishedAfterExecution: moon.strategyHostFinished(setup), scopedUsage: usage()};
  } catch (error) {
    result = {status: 'failed', phase, codes: failureCodes(error),
      cleanupPending: !!error.cleanupHandle?.status().pending, scopedUsage: usage(),
      outputAfterFailure: setup ? moon.strategyHostOutput(setup, 0) !== undefined : false,
      finishedAfterFailure: setup ? moon.strategyHostFinished(setup) : false};
    if (!setup) duplicateOpen = refusal(() => host.open(preparation, owner, authorization));
  } finally {
    if (setup) {
      moon.strategyHostStop(setup);
      moon.strategyHostCloseOutputs(setup);
    }
    authorization.close();
  }
  let released = saved === undefined;
  if (saved) released = refusal(() => saved.output(0)) === 'ReleasedStrategy';
  return {...result, initialUsage, finalUsage: usage(), consumed, released,
    duplicateOpen, duplicateExecution, openedFinished, materialsChecks, counters: authorization.counters(),
    authorizationResources: authorization.resourceUsage()};
}

export default {async fetch(request) {
  const input = await request.json();
  const value = Array.isArray(input) ? await Promise.all(input.map(runFiniteCase))
    : await runFiniteCase(input);
  return new Response(JSON.stringify(value, (_, item) => typeof item === 'bigint' ? String(item) : item),
    {headers: {'content-type': 'application/json'}});
}};

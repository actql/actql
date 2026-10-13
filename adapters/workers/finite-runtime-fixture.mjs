// Test-only trusted installation and original request Owner. All checking,
// compilation, authorization, selection, execution and cleanup are product code.
import {instantiate} from '../../_build/workers/modules/fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
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

export async function runFiniteCase({rows = [{id: 1}, {id: 2}], nullable = false,
  outcome = 'allow', maxRows = 100, cancel = false, consumeFailure = false,
  directClose = false, hashSeed = 0} = {}) {
  const moon = instantiate(hashSeed);
  const host = bindWorkersFiniteHost(moon, configuration(moon, maxRows));
  const authorization = gate(moon, outcome);
  const preparation = host.prepare(finiteDocument(rows, nullable));
  const original = moon.workersFiniteFixtureOriginal(preparation.program, preparation.compilation);
  const owner = {admission: moon.workersFiniteFixtureAdmission(original),
    definition: moon.workersFiniteFixtureDefinition(original), ledger: moon.workersFiniteFixtureLedger()};
  const usage = () => moon.workersFiniteFixtureUsage(owner.ledger);
  const initialUsage = usage();
  let setup, saved, consumed = 0, phase = 'open', duplicateOpen, duplicateExecution, openedFinished;
  let result;
  try {
    setup = host.open(preparation, owner, authorization);
    openedFinished = moon.strategyHostFinished(setup);
    const openedUsage = usage();
    duplicateOpen = refusal(() => host.open(preparation, owner, authorization));
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
      cleanupPending: !!error.cleanupHandle?.status().pending, scopedUsage: usage()};
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
    duplicateOpen, duplicateExecution, openedFinished, counters: authorization.counters(),
    authorizationResources: authorization.resourceUsage()};
}

export default {async fetch(request) {
  const input = await request.json();
  const value = Array.isArray(input) ? await Promise.all(input.map(runFiniteCase))
    : await runFiniteCase(input);
  return new Response(JSON.stringify(value, (_, item) => typeof item === 'bigint' ? String(item) : item),
    {headers: {'content-type': 'application/json'}});
}};

import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import test from 'node:test';
import './connector-node-bundles.test.mjs';
import './backend-semantic-boundary.test.mjs';
import './source-dependency-closure.test.mjs';
import './query-boundary-behavior.test.mjs';
import './query-dependency-policy.test.mjs';
import {productionPackageImports, scopedPackageImports} from './source-dependency-closure.mjs';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {assertCommonAdapterGraph, assertOpaqueHandles, assertProductionBoundary,
  assertProductionImports, assertPublicBoundary, concreteDependencies,
  conformanceDependencies, publicFunction} from './query-dependency-policy.mjs';

const manifest = name => readFileSync(`src/${name}/moon.pkg`, 'utf8');
const api = name => readFileSync(`src/${name}/pkg.generated.mbti`, 'utf8');
const imports = name => productionPackageImports(manifest(name));
const opaque = (name, handles) => assertOpaqueHandles(api(name), handles);
const noPublic = (name, forbidden) => assertPublicBoundary(name, api(name), forbidden);
const noDependency = (name, forbidden) => assertProductionBoundary(name, manifest, forbidden);

// Check architectural edges, not a complete list of today's neutral helpers.
// Test and whitebox composition never establish a production dependency.
for (const name of ['connector_sdk', 'execution_relation', 'execution_site',
  'physical_host', 'physical_host_dispatch', 'physical_strategy', 'physical_strategy_host', 'remote_site_completion',
  'remote_site_protocol', 'remote_transfer', 'run_publication']) {
  test(`common production closure is connector-free: ${name}`, () => {
    noDependency(name, concreteDependencies);
  });
}
for (const name of ['physical_strategy', 'physical_strategy_host', 'physical_host', 'physical_host_dispatch', 'execution_query']) {
  test(`common public surface owns no concrete execution payload: ${name}`, () => {
    noDependency(name, /^query_planning$/u);
    noPublic(name, /DuckDB|duckdb|query_planning|connectors\//u);
  });
}

test('captured DAG consumes obligations without operation-template dependencies', () => {
  assertProductionImports('physical_strategy_host', manifest('physical_strategy_host'),
    /^(?:relation_join_shape|capacity_graph_preflight)$/u);
});

test('common serial adapter closure permits helper extraction but no Connector or test authority', () => {
  assertCommonAdapterGraph(localModuleGraphInputs(process.cwd(), [
    'adapters/host-common/strategy.mjs',
    'adapters/host-common/execution-sites.mjs',
    'adapters/host-common/managed-site-transfer.mjs',
  ]));
});

test('reference Compute author cannot reserve the physical ledger or expose execution authority', () => {
  assertProductionImports('reference Compute author', manifest('connectors/reference_compute/driver'),
    /^physical_resources$/u);
  noPublic('connectors_builtin', /NumericAttempt|TaskExecution/u);
});

test('linear cost schedules and Site control have no strategy or implementation dependencies', () => {
  const forbidden = /^(?:connectors\/|duckdb_|physical_(?:host(?:_dispatch)?|strategy(?:_host)?|resources)$|execution_(?:query|relation)$|query_)/u;
  for (const name of ['physical_cost', 'execution_site']) noDependency(name, forbidden);
  opaque('physical_cost', ['RateSchedule']);
  noPublic('physical_cost', /DuckDB|LocalDispatch|connectors\//u);
});

test('portable runtime bundle signatures and activation expose common transaction operations', () => {
  for (const name of ['bundle_signature_preimage', 'admit_bundle_signature_envelope',
    'prepare_bundle_activation', 'commit_bundle_activation',
    'prepare_active_bundle_drain', 'prepare_active_bundle_retain',
    'prepare_inactive_bundle_reclaim']) publicFunction(api('remote_bundle'), name);
  noDependency('remote_bundle', concreteDependencies);
});

test('DuckDB acquisition and transport remain independent of Compute composition and Local', () => {
  for (const name of ['connectors/duckdb/host', 'connectors/duckdb/host_node']) {
    noDependency(name, name.endsWith('/host')
      ? /^(?:duckdb_host|connectors_builtin|physical_host(?:_dispatch)?)$|^connectors\/(?:local|reference_compute)(?:\/|$)/u
      : /^(?:duckdb_host|connectors_builtin)$|^connectors\/(?:local|reference_compute)(?:\/|$)/u);
  }
  assert.ok(imports('connectors/duckdb/host').includes('connectors/duckdb/acquisition'));
  opaque('connectors/duckdb/host', ['NativeHostRun', 'BroadHostRun']);
  noPublic('connectors/duckdb/host', /StrategyHostDispatch|ComputeHost|LocalDispatch/u);
  noPublic('connectors/duckdb/standard_host', /NativeHostRun|BroadHostRun|configure_native_host|configure_broad_host|compute_host_sql|resident_import_sql/u);
  const bridge = api('connectors/duckdb/host_node');
  publicFunction(bridge, 'compute_host_sql');
  publicFunction(bridge, 'resident_import_sql');
});

test('concrete SQL compilation belongs to the DuckDB adapter, not the composition API', () => {
  for (const name of ['connectors/duckdb/compute', 'connectors/duckdb/driver']) {
    assert.ok(imports(name).includes('connectors/duckdb/adapter'));
  }
  noPublic('connectors_builtin_node', /pub fn (?:compute_host_sql|resident_import_sql)\(/u);
  noPublic('physical_strategy_host', /pub fn (?:captured_resident_query|captured_resident_cleanup_sql|resident_read_view_sql|resident_inputs_view_sql)\b/u);
});

test('Connector SDK exposes opaque author contracts rather than concrete execution or planning', () => {
  noDependency('connector_sdk', /^(?:connectors\/|duckdb_|query_planning$|physical_strategy(?:_host)?$)/u);
  noPublic('connector_sdk', /DuckDB|NativeQueryIssue|query_planning/u);
  opaque('connector_sdk', ['CapabilityRegistry', 'CapabilityRegistration',
    'FixedComputeRequest', 'FixedComputeCandidate', 'CapabilityImplementations',
    'PreparedExecution', 'SynchronousCompute']);
  noPublic('connector_sdk', /^pub\(all\) struct ExecutionOperations\b|^pub fn[^\n]*\b(?:bind_prepared_execution|start_prepared_execution)\(/mu);
});

test('Salesforce semantic catalog does not own acquisition custody', () => {
  noDependency('connectors/salesforce/catalog', /^(?:connector_sdk|physical_cost|query_planning|execution_query|execution_relation|lowering_relation)$/u);
  const host = api('connectors/salesforce/host');
  publicFunction(host, 'prepare_installed_salesforce_row_acquisition');
  noPublic('connectors/salesforce/host', /SalesforceBroad|salesforce_broad/u);
  opaque('connectors/salesforce/host', ['ManagedQuery']);
  for (const name of ['accept_row_run_values', 'capture_row_run']) {
    publicFunction(api('client_row_source_host'), name);
  }
});

test('product manifests exclude conformance only from production scopes', () => {
  const visit = directory => readdirSync(directory, {withFileTypes: true})
    .flatMap(entry => entry.isDirectory() ? visit(`${directory}/${entry.name}`)
      : entry.name === 'moon.pkg' ? [`${directory}/${entry.name}`] : []);
  const testOwners = /^(?:src\/(?:connectors\/duckdb\/conformance|node_host_conformance|query_integration|workers_conformance))\/moon\.pkg$/u;
  for (const path of visit('src')) {
    if (!testOwners.test(path)) {
      assertProductionImports(path, readFileSync(path, 'utf8'), conformanceDependencies);
    }
  }
});

test('query comparison and canonical materials have no concrete acquisition owner', () => {
  noDependency('query_planning', concreteDependencies);
  noPublic('query_planning', /DuckDB|MockQuery|QueryRealization|connectors\//u);
  opaque('query_planning', ['QueryRecordArtifacts', 'QueryMaterialBudget']);
  for (const name of ['mock', 'duckdb']) {
    assert.ok(imports(`connectors/${name}/acquisition`).includes('query_planning'));
  }
});

test('physical ledger is opaque and independent of algebra, strategy and Connector owners', () => {
  const forbidden = /^(?:connectors\/|duckdb_|connector_sdk$|physical_(?:strategy(?:_host)?|host(?:_dispatch)?|cost)$|execution_|query_|pipeline_|lowering_|relation_|graph_|vector_|sourceview_)/u;
  noDependency('physical_resources', forbidden);
  assertProductionImports('physical_resources public API', api('physical_resources'), forbidden);
  assert.ok(imports('physical_strategy_host').includes('physical_resources'));
  opaque('physical_resources', ['Ledger', 'Reservation', 'Holding',
    'SharedCapacity', 'SharedAllocation', 'SharedBorrow']);
});

test('execution lifecycle uses opaque preparations and completions, not backend attempts or hooks', () => {
  const strategy = api('physical_strategy_host');
  opaque('physical_strategy_host', ['TaskExecution']);
  for (const name of ['charge_task_execution_transfer', 'settle_task_execution',
    'complete_materializing_task_execution', 'close_task_execution']) {
    assert.match(publicFunction(strategy, name), /TaskExecution/u);
  }
  const materializing = publicFunction(strategy, 'start_captured_materializing_execution');
  assert.match(materializing, /PreparedExecution/u);
  assert.doesNotMatch(materializing, /DuckDB|GeneratedSequence|Bool|-> Result.*->/u);
  const synchronous = publicFunction(strategy, 'execute_captured_synchronous_task');
  assert.match(synchronous, /SynchronousCompute/u);
  assert.doesNotMatch(synchronous, /GeneratedSequence|SequenceExecutionLimits|Local/u);
  noPublic('physical_strategy_host', /CapturedDuckDBTask|DuckDBComputeAttempt|TaskPublication|pub fn (?:start_captured_execution|complete_task_execution|publish_task_completion|execute_captured_local_task|charge_captured_duckdb_transfer|settle_captured_duckdb_native|complete_captured_duckdb_task|close_captured_duckdb_task)\b/u);
});

test('prepared dispatch is opaque and provider-neutral', () => {
  opaque('physical_host_dispatch', ['DispatchDriver', 'DispatchTicket', 'DispatchWork', 'PreparedTaskDispatch']);
  noPublic('physical_host_dispatch', /DuckDB|Native|SQL|connectors\//u);
  noPublic('connectors/duckdb/standard_host', /pub fn execute_local_dispatch\b/u);
});

test('Local candidate construction and bounded sequence configuration remain Connector-owned', () => {
  opaque('connectors/local', ['LocalComputeModule']);
  for (const name of ['physical_host', 'physical_host_dispatch', 'connector_sdk', 'connectors/duckdb/compute',
    'connectors/duckdb/driver', 'connectors/reference_compute', 'connectors/reference_compute/driver']) {
    noPublic(name, /\bGeneratedSequence\b/u);
  }
});

test('concrete capacity, configuration, compiled requests and resident payloads stay opaque and Connector-owned', () => {
  const compute = api('connectors/duckdb/compute');
  for (const name of ['duckdb_task_retention_capacity', 'duckdb_task_scratch_capacity']) {
    publicFunction(compute, name);
    noPublic('physical_strategy_host', new RegExp(`pub fn ${name}\\b`, 'u'));
  }
  opaque('connectors/duckdb/compute', ['DuckDBDispatchPreparation', 'DuckDBSelectedCompute',
    'DuckDBResidentOutput', 'DuckDBResidentRead']);
  assert.doesNotMatch(publicFunction(compute, 'bind_duckdb_dispatch_candidate'), /FixedComputeRequest|ProducerRead/u);
  noPublic('connectors/duckdb/compute', /DuckDBJoinPreparation|pub fn (?:compile_duckdb_join_candidate|bind_duckdb_join_candidate|check_duckdb_compute_static)\b/u);
  opaque('connectors/duckdb/driver', ['ComputeHostConfiguration', 'StrategyComputeHostConfiguration']);
  noPublic('connectors/duckdb/standard_host', /^type (?:Strategy)?ComputeHostConfiguration$|pub fn (?:configure_compute_host|start_configured_compute_host|start_configured_strategy_compute_host|borrow_configured_resident_inputs)\(/mu);
});

test('fixed-input engine excludes acquisition and query integration even from its test composition', () => {
  // Deliberately stronger than a production policy: this existing package must
  // remain independently testable without importing its downstream facade.
  const forbidden = new Set(['execution_query', 'query_planning', 'query_integration',
    'sourceview_resolution', 'program_check', 'pipeline_check_context']);
  for (const entry of scopedPackageImports(manifest('execution_relation'))) {
    assert.ok(!forbidden.has(entry.path.replace(/^actql\/actql\//u, '')),
      `Engine composition dependency: ${entry.scope} ${entry.path}`);
  }
  assert.ok(imports('execution_query').includes('execution_relation'));
  assert.ok(imports('execution_query').includes('sourceview_resolution'));
  assert.ok(imports('query_planning').includes('execution_query'));
  const integration = scopedPackageImports(manifest('query_integration'))
    .filter(entry => entry.scope === 'wbtest').map(entry => entry.path);
  assert.ok(integration.includes('actql/actql/query_planning'));
  assert.ok(integration.includes('actql/actql/program_check'));
  noPublic('execution_relation', /\b(?:QuerySequence|QueryReceipt|QueryGuardIssue)\b|sourceview_resolution/u);
  noPublic('execution_query', /\b(?:TableStore|FragmentRuntimeContext|ExpressionFrame|RowBackend)\b/u);
});

test('adopted filesystem-free contract fixtures match the ordinary authoritative generator', async () => {
  // Its read-only mode verifies complete generated artifacts against normative
  // inputs. Do not hand-parse private function bodies or invent another oracle.
  await import('./lowering-registry-vectors.mjs');
});


test('portable checked graph and estimates never acquire live Host custody', () => {
  const forbidden = /^(?:physical_resources|physical_strategy_host|physical_host_dispatch)$/u;
  for (const name of ['physical_strategy', 'physical_host']) {
    noDependency(name, forbidden);
    assertProductionImports(name + ' public API', api(name), forbidden);
  }
  for (const name of ['physical_strategy_host', 'physical_host_dispatch']) {
    noDependency(name, concreteDependencies);
  }
});

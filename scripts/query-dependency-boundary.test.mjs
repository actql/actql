import assert from 'node:assert/strict';
import {readFileSync, readdirSync, existsSync} from 'node:fs';
import test from 'node:test';

const manifest = name => readFileSync(`src/${name}/moon.pkg`, 'utf8');
const imports = name => [...manifest(name).matchAll(/"actql\/actql\/([^"]+)"/g)].map(m => m[1]);

test('DuckDB SQL and physical values belong to the connector package group', () => {
  assert.ok(!existsSync('src/duckdb_adapter/moon.pkg'));
  for (const file of ['count_group_query.mbt', 'inner_join_query.mbt',
    'native_query.mbt', 'physical_values.mbt', 'resident_query.mbt']) {
    assert.ok(existsSync(`src/connectors/duckdb/adapter/${file}`), file);
  }
  for (const pkg of ['connectors/duckdb/compute', 'connectors/duckdb/driver']) {
    assert.ok(imports(pkg).includes('connectors/duckdb/adapter'));
    assert.ok(!imports(pkg).includes('duckdb_adapter'));
  }
});

const dependencies = name => {
  const seen = new Set();
  const pending = imports(name);
  while (pending.length) {
    const dependency = pending.pop();
    if (seen.has(dependency)) continue;
    seen.add(dependency);
    pending.push(...imports(dependency));
  }
  return [...seen];
};

test('connector SDK has no concrete implementation dependency or public error type', () => {
  for (const dependency of dependencies('connector_sdk')) {
    assert.doesNotMatch(dependency, /^(?:connectors\/|duckdb_|query_planning$|physical_strategy$)/);
  }
  const api = readFileSync('src/connector_sdk/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /(?:DuckDB|NativeQueryIssue|query_planning)/);
  for (const type of ['CapabilityRegistry', 'CapabilityRegistration', 'FixedComputeRequest', 'FixedComputeCandidate']) {
    assert.match(api, new RegExp(`^type ${type}$`, 'm'));
  }
  assert.match(api, /^type CapabilityImplementations\[T\]$/m);
});

test('physical resource ledger is independent of strategy and connector implementations', () => {
  assert.deepEqual(imports('physical_resources'), []);
  assert.ok(imports('physical_strategy').includes('physical_resources'));
  const api = readFileSync('src/physical_resources/pkg.generated.mbti', 'utf8');
  for (const handle of ['Ledger', 'Reservation', 'Holding', 'SharedCapacity', 'SharedAllocation', 'SharedBorrow']) {
    assert.match(api, new RegExp(`^type ${handle}$`, 'm'));
    assert.doesNotMatch(api, new RegExp(`(?:struct|enum) ${handle}\\b`));
  }
  const dependencies = [...api.matchAll(/^import \{([\s\S]*?)^\}/gm)];
  for (const [, block] of dependencies) assert.doesNotMatch(block, /actql\/actql\//);
});

test('DAG execution storage does not maintain a backend attempt lookup table', () => {
  const source = readFileSync('src/physical_strategy/captured_dag.mbt', 'utf8');
  const state = source.match(/struct CapturedDAG \{([\s\S]*?)\n\}/)?.[1];
  assert.ok(state);
  assert.doesNotMatch(state, /DuckDBComputeAttempt|NativeTaskResources|native_resources/);
  assert.match(state, /executions : Array\[TaskExecution\?\]/);
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.match(api, /^type TaskExecution$/m);
  assert.doesNotMatch(api, /(?:struct|enum) TaskExecution\b/);
  for (const name of ['charge_task_execution_transfer', 'settle_task_execution',
    'complete_task_execution', 'close_task_execution']) {
    const signature = api.split('\n').find(line => line.startsWith(`pub fn ${name}(`));
    assert.ok(signature, name);
    assert.match(signature, /TaskExecution/);
    assert.doesNotMatch(signature, /CapturedDuckDBTask|DuckDBComputeAttempt/);
  }
  assert.doesNotMatch(api, /pub fn (?:charge_captured_duckdb_transfer|settle_captured_duckdb_native|complete_captured_duckdb_task|close_captured_duckdb_task)\b/);
});

test('synchronous and asynchronous completion share private retained-output installation', () => {
  for (const file of ['captured_dag.mbt', 'task_execution.mbt']) {
    const source = readFileSync(`src/physical_strategy/${file}`, 'utf8');
    assert.match(source, /publish_task_completion\(/);
    assert.doesNotMatch(source, /run\.completed\[task\] = Some\(output\)/);
  }
  const completion = readFileSync('src/physical_strategy/task_completion.mbt', 'utf8');
  assert.doesNotMatch(completion, /@(?:duckdb|duckdb_compute|local_connector)\b/);
  assert.match(completion, /completed_output_matches_port\(/);
  assert.match(completion, /captured_output_inputs_match\(/);
  assert.match(completion, /holding_available\(run\.ledger, holding\)/);
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /pub fn publish_task_completion\b/);
});

test('common synchronous dispatch has no Local connector or generated-sequence execution API', () => {
  assert.ok(!imports('physical_strategy').includes('connectors/local'));
  const source = readFileSync('src/physical_strategy/captured_dag.mbt', 'utf8');
  assert.doesNotMatch(source, /@local_connector\b|generated_sequence_capacity\(/);
  assert.match(source, /@connector\.execute_synchronous_compute\(compute\)/);
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /pub fn execute_captured_local_task\b/);
  const signature = api.split('\n').find(line => line.startsWith('pub fn execute_captured_synchronous_task('));
  assert.ok(signature);
  assert.match(signature, /SynchronousCompute/);
  assert.doesNotMatch(signature, /GeneratedSequence|SequenceExecutionLimits|Local/);
  const sdk = readFileSync('src/connector_sdk/pkg.generated.mbti', 'utf8');
  assert.match(sdk, /^type SynchronousCompute$/m);
  assert.doesNotMatch(sdk, /(?:struct|enum) SynchronousCompute\b/);
});

test('asynchronous common start takes an owned preparation rather than transport callbacks', () => {
  const source = readFileSync('src/physical_strategy/task_execution.mbt', 'utf8');
  assert.doesNotMatch(source, /@(?:duckdb|duckdb_compute|local_connector)\b/);
  assert.match(source, /@connector\.start_prepared_execution\(prepared\)/);
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  const signature = api.split('\n').find(line => line.startsWith('pub fn[T] start_captured_execution('));
  assert.ok(signature);
  assert.match(signature, /PreparedExecution/);
  assert.doesNotMatch(signature, /DuckDB|GeneratedSequence|Bool|-> Result.*->/);
  assert.match(api, /^type TaskPublication$/m);
  assert.doesNotMatch(api, /pub fn (?:claim_task_publication|publish_task_completion)\b/);
  const sdk = readFileSync('src/connector_sdk/pkg.generated.mbti', 'utf8');
  assert.match(sdk, /^type PreparedExecution\[T, E, P\]$/m);
  assert.doesNotMatch(sdk, /(?:struct|enum) PreparedExecution\b/);
});

test('concrete DuckDB task construction and lifecycle stay in the connector driver', () => {
  for (const file of readdirSync('src/physical_strategy')) {
    if (!file.endsWith('.mbt') || file.endsWith('test.mbt')) continue;
    const source = readFileSync(`src/physical_strategy/${file}`, 'utf8');
    assert.doesNotMatch(source, /CapturedDuckDBTask|DuckDBComputeAttempt|(?:start|abort|close|complete)_duckdb_compute_attempt/, file);
  }
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /CapturedDuckDBTask|DuckDBComputeAttempt|start_captured_duckdb_task|captured_duckdb_(?:attempt|execution)/);
  assert.ok(!dependencies('physical_strategy').includes('connectors/duckdb/driver'));
  const driver = readFileSync('src/connectors/duckdb/driver/execution.mbt', 'utf8');
  assert.match(driver, /@strategy\.start_captured_execution\(/);
  assert.doesNotMatch(driver, /reserve_attempt|retain_allocation|settle_reservation/);
});

test('common cleanup selects allocations but does not compile physical removal SQL', () => {
  const source = readFileSync('src/physical_strategy/resident_output.mbt', 'utf8');
  const preparation = source.match(/pub fn\[T\] prepare_captured_cleanup\([\s\S]*?\n\}/)?.[0];
  assert.ok(preparation);
  assert.doesNotMatch(preparation, /@duckdb|Array\[String\]|drop_sql|cleanup_sql/);
  assert.match(preparation, /prepare\(tables\.copy\(\)\)/);
  const api = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /pub fn captured_resident_cleanup_sql/);
  const driver = readFileSync('src/connectors/duckdb/driver/execution.mbt', 'utf8');
  assert.match(driver, /@strategy\.prepare_captured_cleanup\(/);
  assert.match(driver, /@duckdb\.resident_import_drop_sql\(/);
});

test('prepared dispatch ownership has one common state machine and no connector payload', () => {
  assert.deepEqual(imports('physical_host'), [
    'physical_strategy', 'physical_resources', 'connector_sdk',
    'lowering_relation', 'pipeline_typing',
  ]);
  const api = readFileSync('src/physical_host/pkg.generated.mbti', 'utf8');
  for (const handle of ['DispatchDriver', 'DispatchTicket']) {
    assert.match(api, new RegExp(`^type ${handle}$`, 'm'));
    assert.doesNotMatch(api, new RegExp(`(?:struct|enum) ${handle}\\b`));
  }
  assert.doesNotMatch(api, /DuckDB|Native|SQL|connectors\//);
  const bridge = readFileSync('src/duckdb_host/dispatch.mbt', 'utf8');
  assert.doesNotMatch(bridge, /mut (?:pending|consumed)\s*:/);
  assert.match(bridge, /@host_driver\.consume_dispatch_ticket\(/);
  assert.match(bridge, /@host_driver\.prepare_installed_dispatch\(/);
  const installed = readFileSync('src/physical_host/installed_dispatch.mbt', 'utf8');
  assert.match(installed, /prepare_dispatch_inputs\(/);
  assert.match(installed, /capability_implementation\(/);
  assert.match(installed, /prepare_dispatch_ticket\(/);
  assert.doesNotMatch(installed, /@duckdb|@local_connector|DispatchWork|Native\(/);
  const inputs = readFileSync('src/physical_host/inputs.mbt', 'utf8');
  assert.doesNotMatch(inputs, /GeneratedSequence|@duckdb|@local_connector/);
  const synchronous = bridge.match(/pub fn execute_synchronous_dispatch\([\s\S]*?\n\}/)?.[0];
  assert.ok(synchronous);
  assert.doesNotMatch(synchronous, /@local_connector|local_execution|\.guards/);
  const bridgeApi = readFileSync('src/duckdb_host/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(bridgeApi, /pub fn execute_local_dispatch\b/);
});

test('Local installed preparation owns candidate construction and bounded sequence configuration', () => {
  const api = readFileSync('src/connectors/local/pkg.generated.mbti', 'utf8');
  assert.match(api, /^type LocalComputeModule$/m);
  assert.doesNotMatch(api, /(?:struct|enum) LocalComputeModule\b/);
  const source = readFileSync('src/duckdb_host/dispatch_implementations.mbt', 'utf8');
  const local = source.match(/fn prepare_local_dispatch_work\([\s\S]*?\n\}/)?.[0];
  assert.ok(local);
  assert.match(local, /prepare_local_module_compute\(/);
  assert.doesNotMatch(local, /local_fixed_compute_candidate\(|choose_fixed_compute_candidate\(|prepare_local_compute_execution\(|host\.generated|host\.limits/);
});

test('concrete Compute capacity formula is owned and exported by its connector', () => {
  const core = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  const connector = readFileSync('src/connectors/duckdb/compute/pkg.generated.mbti', 'utf8');
  for (const name of ['duckdb_task_retention_capacity', 'duckdb_task_scratch_capacity']) {
    assert.doesNotMatch(core, new RegExp(`pub fn ${name}\\b`));
    assert.match(connector, new RegExp(`pub fn ${name}\\b`));
  }
});

test('Host join dispatch cannot build SQL or exchange a compiled preparation request', () => {
  const dispatch = readFileSync('src/duckdb_host/dispatch_implementations.mbt', 'utf8');
  assert.doesNotMatch(dispatch, /@duckdb\.(?:compile_fixed_inner_join|prepare_fixed_join_inputs|prepare_fixed_join_compute)\b/);
  assert.doesNotMatch(dispatch, /"owned_input"|compile_duckdb_join_candidate\(|bind_duckdb_join_candidate\(|choose_fixed_compute_candidate\(/);
  assert.match(dispatch, /duckdb_dispatch_preflight_work\(preparation\)/);
  assert.match(dispatch, /@resources\.charge_planning\(/);
  const api = readFileSync('src/connectors/duckdb/compute/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(api, /DuckDBJoinPreparation|pub fn (?:compile_duckdb_join_candidate|bind_duckdb_join_candidate|check_duckdb_compute_static)\b/);
  assert.match(api, /^type DuckDBDispatchPreparation$/m);
  assert.match(api, /^type DuckDBSelectedCompute$/m);
  assert.doesNotMatch(api, /(?:struct|enum) (?:DuckDBDispatchPreparation|DuckDBSelectedCompute)\b/);
  const binding = api.split('\n').find(line => line.startsWith('pub fn bind_duckdb_dispatch_candidate('));
  assert.ok(binding);
  assert.doesNotMatch(binding, /FixedComputeRequest|ProducerRead/);
});

test('resident output lifecycle does not own table names or materialization SQL', () => {
  const source = readFileSync('src/physical_strategy/resident_output.mbt', 'utf8');
  const state = source.match(/struct ResidentPendingOutput \{([\s\S]*?)\n\}/)?.[1];
  assert.ok(state);
  assert.doesNotMatch(state, /table_name|query :|max_sql_bytes|limits :/);
  assert.doesNotMatch(source, /DuckDBResidentOutput|@duckdb_compute|ResidentQuery|FixedQuery/);
  assert.match(source, /resident_import_matches_output\(imported, output\)/);
  const preparation = readFileSync('src/physical_strategy/resident_execution.mbt', 'utf8');
  assert.doesNotMatch(preparation, /DuckDBComputeLimits|TransportColumnLimits|@duckdb_compute|fixed_compute_query/);
  const commonApi = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(commonApi, /pub fn captured_resident_query\b/);
  assert.doesNotMatch(source, /@duckdb\.(?:prepare_resident_query|prepare_resident_import|resident_import_drop_sql)\b/);
  const api = readFileSync('src/connectors/duckdb/compute/pkg.generated.mbti', 'utf8');
  assert.match(api, /^type DuckDBResidentOutput$/m);
  assert.doesNotMatch(api, /(?:struct|enum) DuckDBResidentOutput\b/);
});

test('resident borrowers do not store or export concrete view SQL', () => {
  const source = readFileSync('src/physical_strategy/resident_table.mbt', 'utf8');
  const state = source.match(/struct ResidentRead \{([\s\S]*?)\n\}/)?.[1];
  assert.ok(state);
  assert.doesNotMatch(state, /view_sql|String/);
  assert.doesNotMatch(source, /@duckdb\.resident_import_receiver_sql/);
  const core = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(core, /pub fn resident_(?:read_view_sql|inputs_view_sql)\b/);
  const connector = readFileSync('src/connectors/duckdb/compute/pkg.generated.mbti', 'utf8');
  assert.match(connector, /^type DuckDBResidentRead$/m);
});

test('fixed-input engine has no acquisition or query-integration dependency, including tests', () => {
  const forbidden = ['execution_query', 'query_planning', 'query_integration',
    'sourceview_resolution', 'program_check', 'pipeline_check_context'];
  for (const name of forbidden) assert.ok(!imports('execution_relation').includes(name), name);
  assert.ok(imports('execution_query').includes('execution_relation'));
  assert.ok(imports('execution_query').includes('sourceview_resolution'));
  assert.ok(imports('query_planning').includes('execution_query'));
  assert.ok(imports('query_integration').includes('query_planning'));
  assert.ok(imports('query_integration').includes('program_check'));
});

test('query adapter has no engine internals or compatibility authority facade', () => {
  const files = readdirSync('src/execution_query').filter(f => f.endsWith('.mbt'));
  const code = files.map(f => readFileSync(`src/execution_query/${f}`, 'utf8')).join('\n');
  assert.doesNotMatch(code, /\b(?:TableStore|FragmentRuntimeContext|ExpressionFrame|RowBackend)\b/);
  const engine = readFileSync('src/execution_relation/pkg.generated.mbti', 'utf8');
  assert.doesNotMatch(engine, /\b(?:QuerySequence|QueryReceipt|QueryGuardIssue)\b/);
  assert.doesNotMatch(engine, /sourceview_resolution/);
});

test('filesystem-free integration fixtures use the same adopted engine contract bodies', () => {
  const bodies = path => new Map(readFileSync(path, 'utf8').split('///|\n')
    .map(chunk => [chunk.match(/^fn (registered_\w+)\(/)?.[1], chunk.trim()])
    .filter(([name]) => name));
  const engine = bodies('src/execution_relation/registry_vectors.generated_wbtest.mbt');
  const integration = bodies('src/query_integration/pinned_engine_contracts_wbtest.mbt');
  assert.deepEqual([...integration.keys()], ['registered_body', 'registered_values', 'registered_fragment']);
  for (const [name, body] of integration) assert.equal(body, engine.get(name), name);
});

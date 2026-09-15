import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import test from 'node:test';

const manifest = name => readFileSync(`src/${name}/moon.pkg`, 'utf8');
const imports = name => [...manifest(name).matchAll(/"actql\/actql\/([^"]+)"/g)].map(m => m[1]);

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
  for (const handle of ['Ledger', 'Reservation', 'Holding']) {
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
});

test('concrete Compute capacity formula is owned and exported by its connector', () => {
  const core = readFileSync('src/physical_strategy/pkg.generated.mbti', 'utf8');
  const connector = readFileSync('src/connectors/duckdb/compute/pkg.generated.mbti', 'utf8');
  for (const name of ['duckdb_task_retention_capacity', 'duckdb_task_scratch_capacity']) {
    assert.doesNotMatch(core, new RegExp(`pub fn ${name}\\b`));
    assert.match(connector, new RegExp(`pub fn ${name}\\b`));
  }
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

import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import test from 'node:test';

const manifest = name => readFileSync(`src/${name}/moon.pkg`, 'utf8');
const imports = name => [...manifest(name).matchAll(/"actql\/actql\/([^"/]+)"/g)].map(m => m[1]);

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

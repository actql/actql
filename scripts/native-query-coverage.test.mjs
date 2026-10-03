import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {assertNativeQueryExecution, nativeQueryCoverage,
  readNativeQuerySources, selectNativeQueryTests} from './native-query-coverage.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const repositorySources = readNativeQuerySources(root);
// Unit fixtures include the reviewed ownership surface. Unreviewed new source
// readers are covered by the repository check below and must permit fallback.
const sources = {
  ...Object.fromEntries(Object.entries(repositorySources).filter(([path]) =>
    Object.keys(nativeQueryCoverage.files).some(file => path === `src/query_integration/${file}`))),
  'src/platform_native/remote_journal/inspection_stub.c': 'getenv("TMPDIR")',
  'src/platform_native/executor_slot/executor_slot_stub.c':
    'extern char **environ;\nposix_spawn(&pid, path, &actions, NULL, argv, environ)',
};
const environment = owner => Object.fromEntries(
  nativeQueryCoverage.requiredEnvironment[owner].map(name => [name, '1']));
const select = (owner = 'http-client', input = sources, env = environment(owner),
  manifest = nativeQueryCoverage) => selectNativeQueryTests(owner, input, env, manifest);
const query = 'src/query_integration/';
const summary = count => ({status: 0, signal: null,
  stdout: `Total tests: ${count}, passed: ${count}, failed: 0.\n`, stderr: ''});

test('HTTP owns every current HTTP, SQLite, DuckDB and remote-transfer file', () => {
  const selection = select();
  assert.equal(selection.mode, 'subset');
  assert.equal(selection.expected, 33);
  assert.deepEqual(selection.paths.map(path => path.slice(query.length)), [
    'duckdb_native_compute_wbtest.mbt', 'duckdb_native_runtime_wbtest.mbt',
    'native_publication_output_wbtest.mbt', 'native_remote_transfer_input_wbtest.mbt',
    'native_resident_standard_wbtest.mbt', 'physical_adaptive_dispatch_wbtest.mbt',
    'resident_native_source_wbtest.mbt',
  ]);
});

test('remote owns signed standard runtime and Values cases', () => {
  const selection = select('remote-runtime');
  assert.equal(selection.mode, 'subset');
  assert.equal(selection.expected, 12);
  assert.deepEqual(selection.paths, [query + 'client_source_free_root_wbtest.mbt',
    query + 'native_publication_output_wbtest.mbt']);
});

test('all current required cases exist, and core remains unfiltered', () => {
  assert.equal(Object.values(nativeQueryCoverage.files)
    .reduce((sum, entry) => sum + entry.tests.length, 0), 35);
  const core = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert.match(core, /\['test', '--target', 'native',/u);
  assert.doesNotMatch(core, /native-query-coverage/u);
});

test('repository inventory either selects owned cases or explicitly retains full coverage', () => {
  for (const owner of ['http-client', 'remote-runtime']) {
    const selection = select(owner, repositorySources);
    if (selection.mode === 'full-fallback') {
      assert.ok(selection.reasons.length > 0);
      assert.deepEqual(selection.paths, ['src/query_integration']);
    } else {
      assert.equal(selection.expected, owner === 'http-client' ? 33 : 12);
    }
  }
});

for (const owner of ['http-client', 'remote-runtime']) {
  test(`${owner} rejects each missing/empty fixture prerequisite`, () => {
    for (const name of nativeQueryCoverage.requiredEnvironment[owner]) {
      const env = environment(owner);
      delete env[name];
      assert.throws(() => select(owner, sources, env), /prerequisite missing/u);
      env[name] = '';
      assert.throws(() => select(owner, sources, env), /prerequisite missing/u);
    }
  });
}

test('HTTP requires fail-on-missing DuckDB mode', () => {
  assert.throws(() => select('http-client', sources,
    {...environment('http-client'), ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS: '0'}), /must be required/u);
});

test('unknown harness and malformed ownership cannot run', () => {
  assert.throws(() => selectNativeQueryTests('unknown', sources, {}), /Unknown native harness/u);
  for (const owners of [[], ['unknown'], ['http-client', 'http-client']]) {
    const manifest = structuredClone(nativeQueryCoverage);
    manifest.files['duckdb_native_runtime_wbtest.mbt'].owners = owners;
    assert.throws(() => select('http-client', sources, environment('http-client'), manifest), /Malformed/u);
  }
});

test('missing known file or renamed required case fails, never silently skips', () => {
  const path = query + 'native_resident_standard_wbtest.mbt';
  for (const source of ['', sources[path].replace('test "native resident Host',
    'test "renamed native resident Host')]) {
    assert.throws(() => select('http-client', {...sources, [path]: source}), /Missing required/u);
  }
});

test('new direct environment consumer falls back to full current suite', () => {
  const selection = select('http-client', {...sources,
    [query + 'new_wbtest.mbt']: 'test "new" { @env.get_env_var("NEW") }'});
  assert.equal(selection.mode, 'full-fallback');
  assert.deepEqual(selection.paths, ['src/query_integration']);
  assert.equal(selection.expected, 36);
});

test('new query package C environment reads and reader function values reject subset', () => {
  for (const source of ['getenv("ACTQL_TEST_NEW");',
    'char *(*reader)(const char *) = getenv; reader("NEW");',
    'char *(*reader)(const char *) = secure_getenv; reader("NEW");']) {
    assert.equal(select('http-client', {...sources,
      [query + 'new_stub.c']: source}).mode, 'full-fallback');
  }
});

test('new indirect helper consumer also rejects the subset', () => {
  const selection = select('remote-runtime', {...sources,
    [query + 'helpers_wbtest.mbt']: 'fn wrapper() { native_duckdb_test_library() }',
    [query + 'new_wbtest.mbt']: 'test "new" { wrapper() }'});
  assert.equal(selection.mode, 'full-fallback');
  assert.ok(selection.reasons.some(reason => reason.includes('new_wbtest')));
});

test('environment helper function values and aliases reject subset selection', () => {
  for (const source of [
    'test "new" { let reader = native_values_coordinator_authority; let value = reader() }',
    'fn wrapper() { let reader = native_values_coordinator_authority; reader() }\n' +
      'test "new" { let alias = wrapper; alias() }',
    'test "new" { let reader = @env.get_env_var; let alias = reader; alias("NEW") }',
  ]) {
    const selection = select('remote-runtime', {...sources, [query + 'new_wbtest.mbt']: source});
    assert.equal(selection.mode, 'full-fallback');
    assert.ok(selection.reasons.some(reason => reason.includes('new_wbtest')));
  }
});

test('unknown production reader preserves full harness coverage', () => {
  for (const source of ['fn helper() { @env.get_env_var("NEW") }',
    'const char *value = getenv("NEW");', 'extern char **environ;',
    'fn helper() { let reader = @env.get_env_var; reader("NEW") }',
    'char *(*reader)(const char *) = getenv; reader("NEW");',
    'char *(*reader)(const char *) = secure_getenv; reader("NEW");']) {
    const selection = select('http-client', {...sources, 'src/provider/helper.mbt': source});
    assert.equal(selection.mode, 'full-fallback');
    assert.equal(selection.expected, 35);
  }
});

test('new environment reads beside reviewed C reads are not allowlisted', () => {
  const path = 'src/platform_native/remote_journal/inspection_stub.c';
  assert.equal(select('http-client', {...sources,
    [path]: sources[path] + '\ngetenv("NEW");'}).mode, 'full-fallback');
});

test('unknown file ownership falls back, and empty inventory fails', () => {
  const manifest = structuredClone(nativeQueryCoverage);
  delete manifest.files['resident_native_source_wbtest.mbt'];
  assert.equal(select('http-client', sources, environment('http-client'), manifest).mode, 'full-fallback');
  assert.throws(() => select('http-client', sources, environment('http-client'), {files: {}}), /Missing/u);
});

test('changed known environment or extra test rejects the subset', () => {
  const path = query + 'duckdb_native_runtime_wbtest.mbt';
  for (const extra of ['\nfn extra() { @env.get_env_var("ACTQL_TEST_NEW") }',
    '\ntest "extra" {}']) {
    assert.equal(select('http-client', {...sources,
      [path]: sources[path] + extra}).mode, 'full-fallback');
  }
});

test('exact successful execution summaries are required', () => {
  const selection = select();
  assert.equal(assertNativeQueryExecution(selection, summary(33)).passed, 33);
  for (const result of [summary(0), summary(32), summary(34),
    {...summary(33), status: 1}, {...summary(33), signal: 'SIGTERM'},
    {...summary(33), stdout: ''}, {...summary(33), stdout: 'Total tests: invalid\n'},
    {...summary(33), stdout: 'Total tests: 33, passed: 32, failed: 1.\n'}]) {
    assert.throws(() => assertNativeQueryExecution(selection, result));
  }
});

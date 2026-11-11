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
    Object.hasOwn(nativeQueryCoverage.files, path))),
  'src/query_integration/moon.pkg': 'supported_targets = "+js+wasm+native"\n' +
    'import { "actql/actql/provider", "actql/actql/platform_native/remote_journal" }',
  'src/native_values_integration/moon.pkg': 'supported_targets = "+js+wasm+native"',
  'src/provider/moon.pkg': '',
  'src/platform_native/remote_journal/moon.pkg': 'options("native-stub": ["inspection_stub.c"])',
  'src/platform_native/remote_journal/inspection_stub.c': 'getenv("TMPDIR")',
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
  assert.deepEqual(selection.paths, ['src/native_values_integration/values_fixture_wbtest.mbt',
    query + 'client_source_free_root_wbtest.mbt',
    query + 'native_publication_output_wbtest.mbt']);
});

test('a missing relocated Values capture is refused before execution', () => {
  const path = 'src/native_values_integration/values_fixture_wbtest.mbt';
  assert.throws(() => select('remote-runtime', {...sources, [path]: ''}),
    /Missing required native query case/u);
});

test('an unowned reader in the relocated package retains both complete suites', () => {
  const selection = select('remote-runtime', {...sources,
    'src/native_values_integration/new_wbtest.mbt':
      'test "new" { @env.get_env_var("ACTQL_TEST_NEW") }'});
  assert.equal(selection.mode, 'full-fallback');
  assert.deepEqual(selection.paths, ['src/query_integration', 'src/native_values_integration']);
  assert.equal(selection.expected, 36);
});

test('all current required cases exist, and core remains unfiltered', () => {
  assert.equal(Object.values(nativeQueryCoverage.files)
    .reduce((sum, entry) => sum + entry.tests.length, 0), 35);
  const core = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert.match(core, /\['test', '--target', 'native',/u);
  assert.doesNotMatch(core, /native-query-coverage/u);
});

test('the current repository selects each owned Native query subset', () => {
  for (const owner of ['http-client', 'remote-runtime']) {
    const selection = select(owner, repositorySources);
    assert.equal(selection.mode, 'subset', selection.reasons.join('\n'));
    assert.equal(selection.expected, owner === 'http-client' ? 33 : 12);
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
    manifest.files['src/query_integration/duckdb_native_runtime_wbtest.mbt'].owners = owners;
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

test('new environment inputs inside an already owned file cannot inherit its registration', () => {
  const path = query + 'duckdb_native_runtime_wbtest.mbt';
  for (const extra of [
    '\nfn new_input() { "ACTQL_TEST_NEW_2" }',
    '\nextern "C" fn new_reader() -> Int = "getenv"',
    '\nextern "C" fn new_reader() -> Int = "secure_getenv"',
    '\nextern "C" fn new_reader() -> Int = "actql_native_sqlite_test_unclosed_coordinator"',
  ]) {
    const selection = select('http-client', {...sources, [path]: sources[path] + extra});
    assert.equal(selection.mode, 'full-fallback', extra);
  }
});

test('new direct environment consumer falls back to full current suite', () => {
  const selection = select('http-client', {...sources,
    [query + 'new_wbtest.mbt']: 'test "new" { @env.get_env_var("NEW") }'});
  assert.equal(selection.mode, 'full-fallback');
  assert.deepEqual(selection.paths, ['src/query_integration', 'src/native_values_integration']);
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

test('generic environment helpers cannot hide a new consumer behind an owned fixture', () => {
  const path = query + 'physical_adaptive_dispatch_wbtest.mbt';
  for (const generic of ['[T]', '[\nT\n]']) {
    const input = {...sources,
      [path]: sources[path] + '\nfn' + generic + ' fixture_environment(original : T) -> String { ' +
        '@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap() }',
      [query + 'new_generic_wbtest.mbt']:
        'test "new inferred helper" { let callback = fixture_environment; callback([1]) }',
    };
    const selection = select('http-client', input);
    assert.equal(selection.mode, 'full-fallback', generic);
    assert(selection.reasons.some(reason => reason.includes('new_generic_wbtest.mbt')));
  }
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

test('a same-named helper in another package cannot hide an environment dependency', () => {
  const fixture = query + 'client_source_free_root_wbtest.mbt';
  const selection = select('remote-runtime', {...sources,
    [fixture]: sources[fixture] +
      '\nfn native_values_coordinator_authority() { "pure fixture" }',
    ['src/native_values_integration/new_wbtest.mbt']:
      'test "new" { native_values_coordinator_authority() }'});
  assert.equal(selection.mode, 'full-fallback');
  assert.ok(selection.reasons.some(reason => reason.includes('new_wbtest')));
});

test('unknown imported production reader preserves full harness coverage', () => {
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

test('unrelated commands and conformance programs cannot force Query fallback', () => {
  for (const path of ['src/cmd/other/main.mbt', 'src/conformance/fixture.c']) {
    assert.equal(select('http-client', {...sources,
      [path]: 'getenv("ACTQL_TEST_OTHER");'}).mode, 'subset');
  }
});

test('transitive imports and literal FFI includes retain unknown environment dependencies', () => {
  const input = {...sources,
    'src/provider/moon.pkg': 'import { "actql/actql/second" }',
    'src/second/moon.pkg': 'options("native-stub": ["fixture.c"])',
    'src/second/fixture.c': '#include "../../ffi/reader.inc"',
    'ffi/reader.inc': 'const char *(*reader)(const char *) = secure_getenv;',
  };
  assert.equal(select('http-client', input).mode, 'full-fallback');
  assert.ok(select('http-client', {...input, 'src/second/fixture.c': '#include SELECTED_HEADER'})
    .reasons.some(reason => reason.includes('include expression')));
  delete input['ffi/reader.inc'];
  assert.ok(select('http-client', input).reasons.some(reason => reason.includes('missing query FFI')));
  delete input['src/second/moon.pkg'];
  assert.ok(select('http-client', input).reasons.some(reason => reason.includes('missing query dependency')));
  assert.equal(select('http-client', {...sources,
    'src/provider/moon.pkg': 'import { "unknown/environment" }'}).mode, 'full-fallback');
});

test('new reads beside the reviewed WAL fixture and new fixture callers fall back', () => {
  const path = 'src/platform_native/sqlite/sqlite_stub.c';
  const input = {...sources,
    'src/provider/moon.pkg': 'import { "actql/actql/platform_native/sqlite" }',
    'src/platform_native/sqlite/moon.pkg': 'options("native-stub": ["sqlite_stub.c"])',
    [path]: repositorySources[path],
  };
  // Its literal includes are already part of the actual source inventory.
  const withFixture = {...repositorySources, ...input};
  assert.equal(select('http-client', withFixture).mode, 'subset');
  assert.equal(select('http-client', {...withFixture,
    [path]: withFixture[path] + '\ngetenv("NEW");'}).mode, 'full-fallback');
  assert.equal(select('http-client', {...withFixture,
    [path]: withFixture[path].replace('getenv("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")', 'getenv("NEW")')}).mode,
  'full-fallback');
  for (const code of [
    'extern "C" fn reader() -> Int = "actql_native_sqlite_test_unclosed_coordinator"\n' +
      'fn alias() { let callback = reader; callback() }\ntest "new" { alias() }',
    'test "new" { actql_native_sqlite_test_unclosed_coordinator() }',
  ]) assert.equal(select('http-client', {...withFixture,
    [query + 'new_wbtest.mbt']: code}).mode, 'full-fallback');
});

test('new environment reads beside reviewed C reads are not allowlisted', () => {
  const path = 'src/platform_native/remote_journal/inspection_stub.c';
  assert.equal(select('http-client', {...sources,
    [path]: sources[path] + '\ngetenv("NEW");'}).mode, 'full-fallback');
});

test('reviewed diagnostics do not allow duplicate or unknown environment reads', () => {
  const path = 'src/platform_native/filesystem/native_timings.inc';
  for (const owner of ['http-client', 'remote-runtime']) {
    for (const extra of [
      'getenv("ACTQL_NATIVE_TIMINGS");',
      'getenv("ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS");',
      'getenv("NEW_DIAGNOSTIC");',
      'secure_getenv("ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS");',
      'extern char **environ;',
      'char *(*reader)(const char *) = getenv; reader("ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS");',
    ]) {
      const selection = select(owner, {...repositorySources,
        [path]: repositorySources[path] + '\n' + extra});
      assert.equal(selection.mode, 'full-fallback', extra);
      assert.ok(selection.reasons.includes(`production environment reader: ${path}`));
      assert.deepEqual(selection.paths, ['src/query_integration', 'src/native_values_integration']);
    }
  }
});

test('diagnostic exemptions require the exact getenv reader', () => {
  const path = 'src/platform_native/filesystem/native_timings.inc';
  for (const name of ['ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS']) {
    const source = repositorySources[path].replace(`getenv("${name}")`, `secure_getenv("${name}")`);
    assert.notEqual(source, repositorySources[path]);
    const selection = select('http-client', {...repositorySources, [path]: source});
    assert.equal(selection.mode, 'full-fallback', name);
    assert.ok(selection.reasons.includes(`production environment reader: ${path}`));
  }
});

test('diagnostic exemptions cannot transfer to another FFI source', () => {
  const path = 'src/platform_native/filesystem/native_timings.inc';
  const foreign = 'src/platform_native/filesystem/other_diagnostic.inc';
  for (const name of ['ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS']) {
    const selection = select('http-client', {...repositorySources,
      [path]: repositorySources[path] + '\n#include "other_diagnostic.inc"\n',
      [foreign]: `const char *value = getenv("${name}");`});
    assert.equal(selection.mode, 'full-fallback', name);
    assert.ok(selection.reasons.includes(`production environment reader: ${foreign}`));
    assert.deepEqual(selection.paths, ['src/query_integration', 'src/native_values_integration']);
  }
});

test('unknown file ownership falls back, and empty inventory fails', () => {
  const manifest = structuredClone(nativeQueryCoverage);
  delete manifest.files['src/query_integration/resident_native_source_wbtest.mbt'];
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

test('fallback counts Native declarations while retaining compiler-excluded JS cases', () => {
  const js = query + 'only_js_wbtest.mbt';
  const native = query + 'new_native_wbtest.mbt';
  const input = {...sources,
    [query + 'moon.pkg']: 'supported_targets = "+js+wasm+native"\n' +
      'options(targets: {"only_js_wbtest.mbt": ["js"]}, link: {"native": {"cc": "cc"}})',
    [js]: 'test "JS one" {}\ntest "JS two" {}',
    [native]: 'test "new Native" { @env.get_env_var("ACTQL_TEST_NEW") }',
  };
  const selection = select('http-client', input);
  assert.equal(selection.mode, 'full-fallback');
  assert.deepEqual(selection.paths, ['src/query_integration', 'src/native_values_integration']);
  assert.equal(selection.expected, 36);
  assert.doesNotThrow(() => assertNativeQueryExecution(selection, summary(36)));
  assert.throws(() => assertNativeQueryExecution(selection, summary(35)), /coverage mismatch/u);
  assert.throws(() => assertNativeQueryExecution(selection, summary(38)), /coverage mismatch/u);
});

test('required Native ownership cannot be hidden through package or file targets', () => {
  for (const metadata of ['supported_targets = "js"',
    'options(targets: {"duckdb_native_compute_wbtest.mbt": ["js"]})']) {
    assert.throws(() => select('http-client', {...sources,
      [query + 'moon.pkg']: metadata}), /Required native query target is excluded/u);
  }
});

test('unfamiliar and ambiguous target metadata never lower the required count', () => {
  for (const list of ['[]', '["not js"]', '["native", "native"]']) {
    assert.throws(() => select('http-client', {...sources,
      [query + 'moon.pkg']: `options(targets: {"only_js_wbtest.mbt": ${list}})`}),
    /Unsupported native file target expression/u);
  }
  assert.throws(() => select('http-client', {...sources,
    [query + 'moon.pkg']: 'options(targets: {})\noptions(targets: {})'}),
  /duplicate native file targets/u);
  const missing = {...sources};
  delete missing[query + 'moon.pkg'];
  assert.throws(() => select('http-client', missing), /Missing native package metadata/u);
});

test('the actual fallback retains Native Values and excludes exactly both declared JS-only files', () => {
  // Independently authored file/count inventory, not the selector's output.
  const jsOnly = {'strategy_cleanup_current_js_wbtest.mbt': 2, 'row_stream_current_js_wbtest.mbt': 2};
  const pkg = repositorySources[query + 'moon.pkg'];
  const clause = `  targets: {
    "strategy_cleanup_current_js_wbtest.mbt": [ "js" ],
    "row_stream_current_js_wbtest.mbt": [ "js" ],
  },`;
  assert.equal(pkg.split(clause).length, 2);
  for (const [file, expected] of Object.entries(jsOnly)) {
    assert.equal([...repositorySources[query + file].matchAll(/^test "/gmu)].length, expected, file);
  }
  const declarations = Object.entries(repositorySources)
    .filter(([path]) => path.startsWith(query) || path.startsWith('src/native_values_integration/'))
    .reduce((sum, [, source]) => sum + [...source.matchAll(/^test "/gmu)].length, 0);
  const forced = {...repositorySources, [query + 'force_full_stub.c']: 'getenv("ACTQL_TEST_FORCE_FULL");'};
  const selection = select('http-client', forced);
  assert.equal(selection.mode, 'full-fallback');
  assert.equal(selection.expected, declarations - Object.values(jsOnly).reduce((sum, count) => sum + count, 0));
  assert.ok(selection.paths.includes('src/native_values_integration'));
  // Re-admitting either file adds its two cases; it cannot hide another file.
  for (const [file, expected] of Object.entries(jsOnly)) {
    const changed = pkg.replace(`"${file}": [ "js" ]`, `"${file}": [ "js", "native" ]`);
    assert.notEqual(changed, pkg);
    assert.equal(select('http-client', {...forced, [query + 'moon.pkg']: changed}).expected,
      selection.expected + expected);
  }
});

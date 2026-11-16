// Bounded source DATA for selector/process-control tests. These bodies are not
// compiled Native fixtures and confer no execution or environment authority.
import {nativeQueryCoverage} from '../native-query-coverage.mjs';

export const declaredQueryCases = sources => Object.entries(sources)
  .filter(([path]) => path.startsWith('src/query_integration/') ||
    path.startsWith('src/native_values_integration/'))
  .reduce((sum, [, source]) => sum + [...source.matchAll(/^test "([^"]+)"/gmu)].length, 0);

export const ownedQueryCases = owner => Object.values(nativeQueryCoverage.files)
  .filter(entry => entry.owners.includes(owner))
  .reduce((sum, entry) => sum + entry.tests.length, 0);

export function nativeQuerySourceFixture() {
  const sources = Object.fromEntries(Object.entries(nativeQueryCoverage.files).map(([path, entry]) =>
    [path, entry.tests.map(name => `test ${JSON.stringify(name)} {}`).join('\n') +
      '\nfn fixture_variable_literals() { [' + entry.variables.map(value => JSON.stringify(value)).join(',') + '] }\n']));
  sources['src/query_integration/native_resident_standard_wbtest.mbt'] +=
    'fn native_duckdb_test_variable(name : String) { @env.get_env_var(name) }\n' +
    'fn native_duckdb_test_library() { native_duckdb_test_variable("ACTQL_TEST_DUCKDB_LIBRARY") }\n' +
    'fn native_resident_test_prerequisites() { native_duckdb_test_library() }\n';
  sources['src/native_values_integration/values_fixture_wbtest.mbt'] +=
    'fn native_values_coordinator_authority() { @env.get_env_var("ACTQL_TEST_NATIVE_VALUES_COORDINATOR_AUTHORITY") }\n';
  // This owned reader inherits its prerequisite through the package helper,
  // so removing its registration must retain the full harness too.
  const resident = 'src/query_integration/resident_native_source_wbtest.mbt';
  sources[resident] = sources[resident].replace('{}', '{ native_duckdb_test_library() }');
  return {...sources,
    'src/query_integration/moon.pkg': 'supported_targets = "+js+wasm+native"\n' +
      'import { "actql/actql/provider", "actql/actql/platform_native/remote_journal" }',
    'src/native_values_integration/moon.pkg': 'supported_targets = "+js+wasm+native"',
    'src/provider/moon.pkg': '',
    'src/platform_native/remote_journal/moon.pkg': 'options("native-stub": ["inspection_stub.c"])',
    'src/platform_native/remote_journal/inspection_stub.c': 'getenv("TMPDIR")',
  };
}

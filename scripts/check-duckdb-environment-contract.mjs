import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const contractUrl = new URL(
  '../adapters/connectors/duckdb/environment-contract.json',
  import.meta.url,
);
const headerUrl = new URL(
  '../src/connectors/duckdb/adapters/native/' +
    'duckdb_environment_settings.generated.h',
  import.meta.url,
);
const readbackUrl = new URL(
  '../src/connectors/duckdb/adapters/native/' +
    'duckdb_environment_readback.generated_wbtest.mbt',
  import.meta.url,
);
const contract = JSON.parse(await readFile(contractUrl, 'utf8'));
assert.equal(contract.version, 'actql-duckdb-environment/0.1');
assert.equal(typeof contract.settings, 'object');
assert.ok(!Array.isArray(contract.settings));

const entries = Object.entries(contract.settings);
assert.deepEqual(entries, [...entries].sort(([left], [right]) =>
  left.localeCompare(right),
));
for (const [name, value] of entries) {
  assert.match(name, /^[a-z][a-z0-9_]*$/);
  assert.equal(typeof value, 'string');
}

const generated = [
  '/* Generated from adapters/connectors/duckdb/environment-contract.json. */',
  'static const char *actql_duckdb_environment_settings[][2] = {',
  ...entries.map(([name, value]) => `  {"${name}", "${value}"},`),
  '};',
  '',
  'static const size_t actql_duckdb_environment_setting_count =',
  '  sizeof(actql_duckdb_environment_settings) /',
  '  sizeof(actql_duckdb_environment_settings[0]);',
  '',
].join('\n');
assert.equal(await readFile(headerUrl, 'utf8'), generated);

const readback = [
  '///|',
  '// Generated from adapters/connectors/duckdb/environment-contract.json.',
  'fn canonical_environment_readback() -> Array[(String, String)] {',
  '  [',
  ...entries.map(([name, value]) =>
    `    ("${name}", "${name === 'max_temp_directory_size' && value === '0B'
      ? '0 bytes' : value}"),`),
  '  ]',
  '}',
  '',
].join('\n');
assert.equal(await readFile(readbackUrl, 'utf8'), readback);

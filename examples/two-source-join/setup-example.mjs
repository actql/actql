// Create the two small, independently bound sources used by the public example.
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {DuckDBInstance} from '@duckdb/node-api';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const fixture = name => new URL(name, import.meta.url);
const rows = JSON.parse(await readFile(fixture('database-rows.json'), 'utf8'));
const root = resolve('two-source-example-data');
await mkdir(root, {recursive: true});
const sourceProfilePaths = [];
for (const name of ['left', 'right']) {
  const database = resolve(root, `${name}.duckdb`);
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    for (const row of rows[name]) {
      await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
    }
  } finally { connection.closeSync(); instance.closeSync(); }
  const environment = JSON.parse(await readFile(fixture(`${name}.environment.json`), 'utf8'));
  const profile = resolve(root, `${name}.profile.json`);
  await writeFile(profile, canonical({version: 'actql-installed-duckdb-source/0.1',
    database, schema: 'main', table: 'records',
    sourceRef: environment.schema_snapshots[0].source_ref,
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    checkEnvironmentWire: canonical(environment),
    accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
      account_id: `example-${name}`, entries: [{entry_id: 'read-example-database',
        outcome: 'allow', principal: {all: true},
        connection: {any_of: ['local-database']}, resource: {any_of: [database]},
        operation: {any_of: ['read']}, exclusions: []}]}),
  }) + '\n');
  sourceProfilePaths.push(profile);
}
await writeFile(resolve(root, 'connection.json'), JSON.stringify({
  mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve(root, 'actql-state'), sourceProfilePaths},
}, null, 2) + '\n');
console.log('Created two independently bound DuckDB sources');

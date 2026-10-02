// Execute the checked-in public example in the existing external installation.
// This is a small example check, not another source/restart/fault matrix.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import * as duckdb from '@duckdb/node-api';
import {observeTwoSourceProvider, readTwoSourceJournal} from './two-source-public-query.mjs';

const execute = promisify(execFile);
const example = resolve('two-source-example');
const expected = JSON.parse(await readFile(resolve(example, 'two-source-join.expected.json'), 'utf8'));
const readme = await readFile(resolve(example, 'README.md'), 'utf8');
const commands = [...readme.matchAll(/```bash\n([\s\S]*?)\n```/gu)].map(match => match[1]);
assert.equal(commands.length, 2);
assert.equal(commands[1], 'node two-source-example/setup-example.mjs\nnode two-source-example/run-example.mjs\ncat joined.jsonl');
const report = {status: 'running', entryPoint: '@actql/node', cases: [], commands: []};
const persist = () => writeFile('two-source-example-report.json', JSON.stringify(report, null, 2) + '\n');
async function run(command, args) {
  report.commands.push({command, args});
  await persist();
  const result = await execute(command, args, {timeout: 120_000, maxBuffer: 1024 * 1024});
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
}
async function verify(mode, options, directory) {
  const rows = (await readFile('joined.jsonl', 'utf8')).trimEnd().split('\n').map(JSON.parse);
  const description = JSON.parse(await readFile('joined.schema.json', 'utf8'));
  const ref = JSON.parse(await readFile('joined.run.json', 'utf8'));
  assert.deepEqual(rows, expected.rows);
  assert.deepEqual(description.columns, expected.columns);
  const before = readTwoSourceJournal(directory);
  assert.equal(before.length, 1);
  assert.equal(before[0].physical_start_reserved, 1);
  const inventory = JSON.parse(JSON.parse(before[0].run_admission_evidence_json).sourceInventory);
  assert.equal(inventory.acquisitions.length, 2);
  assert.notEqual(inventory.acquisitions[0].checkedSource.sourceRef,
    inventory.acquisitions[1].checkedSource.sourceRef);
  assert.notEqual(inventory.acquisitions[0].physicalBinding.database,
    inventory.acquisitions[1].physicalBinding.database);
  const client = await connect(options);
  try {
    assert.deepEqual((await client.lookupRequest('two-source-join-example')).ref, ref);
    const execution = await client.attach(ref);
    assert.equal((await execution.status()).status, 'succeeded');
    assert.deepEqual(await execution.result('joined').all(), expected.rows);
    const reader = execution.result('joined').rows();
    assert.deepEqual(await Array.fromAsync(reader), expected.rows);
    assert.equal(reader.state(), 'complete');
    const repeated = await client.aql(await readFile(resolve(example, 'two-source-join.program.json'), 'utf8'),
      {format: 'json', requestId: 'two-source-join-example'});
    assert.deepEqual(repeated.ref, ref);
  } finally { client.close(); }
  assert.deepEqual(readTwoSourceJournal(directory), before);
  report.cases.push({mode, rows, columns: description.columns, ref,
    acceptedRuns: before.length, sourceInventory: inventory});
  await persist();
  console.log(`Packed two-source documented example passed: ${mode}`);
}
await persist();
try {
  await run('bash', ['-eu', '-c', commands[1]]);
  const localOptions = JSON.parse(await readFile('two-source-example-data/connection.json', 'utf8'));
  const firstRef = JSON.parse(await readFile('joined.run.json', 'utf8'));
  // Reexecute the exact public script without running setup twice.
  await run(process.execPath, ['two-source-example/run-example.mjs']);
  assert.deepEqual((await readFile('joined.jsonl', 'utf8')).trimEnd().split('\n').map(JSON.parse), expected.rows);
  assert.deepEqual(JSON.parse(await readFile('joined.run.json', 'utf8')), firstRef);
  await verify('local', localOptions, localOptions.installation.directory);
  const directory = resolve('two-source-example-http-state');
  const provider = observeTwoSourceProvider(duckdb, {
    left: resolve('two-source-example-data/left.duckdb'),
    right: resolve('two-source-example-data/right.duckdb'),
  });
  let host, server;
  try {
    host = await openInstalledRemoteHttpHost({directory,
      sourceProfilePaths: localOptions.installation.sourceProfilePaths,
      authenticate: header => header === 'Bearer example-fixture' ? userInfo().username : undefined});
    server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const options = {mode: 'remote', durability: 'durable', token: 'example-fixture',
      endpoint: `https://127.0.0.1:${server.address().port}/`};
    await writeFile('example-http-connection.json', JSON.stringify(options) + '\n');
    await run(process.execPath, ['two-source-example/run-example.mjs', 'example-http-connection.json']);
    const afterExecution = provider.snapshot();
    assert.equal(afterExecution.sourceReadSessions, 2);
    assert.deepEqual([...new Set(afterExecution.sourceReadCommands.map(item => item.database))].sort(),
      [resolve('two-source-example-data/left.duckdb'), resolve('two-source-example-data/right.duckdb')].sort());
    await verify('https', options, directory);
    assert.deepEqual(provider.snapshot(), afterExecution, 'retained access and resubmission do not reopen sources');
    report.provider = afterExecution;
  } finally {
    if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
    await host?.close();
    provider.restore();
  }
  report.status = 'passed';
} catch (error) { report.status = 'failed'; throw error; }
finally { await persist(); }

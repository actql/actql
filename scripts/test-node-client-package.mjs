import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'node-client-package-'));
const cache = join(root, 'npm-cache');
const environment = {...process.env, npm_config_cache: cache};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

for (const name of ['sdk', 'node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
}
const sdk = join(root, 'actql-sdk-0.0.0-development.tgz');
const node = join(root, 'actql-node-0.0.0-development.tgz');
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--offline', '--ignore-scripts', '--no-save', sdk, node],
  root);
assert.deepEqual((await readdir(join(root, 'node_modules', '@actql'))).sort(),
  ['node', 'sdk']);

await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {connect, ClientError} from '@actql/node';

const calls = [];
globalThis.fetch = async (_url, init) => {
  const body = JSON.parse(init.body);
  calls.push(body.connection);
  return Response.json({version: 'actql-client-host/0.1',
    mode: body.connection.mode, owner: body.connection.owner,
    durability: 'volatile', scopeRef: 'scope-a', capabilities: [],
    limits: {maxReadWireBytes: 1024, maxRowWireBytes: 512,
      maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
      maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 1024}});
};
const connected = [
  {mode: 'remote', endpoint: 'https://remote.example/', token: 'token'},
  {mode: 'local', owner: 'local', endpoint: 'https://local.example/',
    token: 'token'},
  {mode: 'hybrid', owner: 'cloud', endpoint: 'https://cloud.example/',
    token: 'token', runners: ['runner-a'], movementPolicyRef: 'movement-a'},
  {mode: 'hybrid', owner: 'local', endpoint: 'https://local.example/',
    token: 'token', cloudConnectionRef: 'registered-cloud-a',
    movementPolicyRef: 'movement-a'},
];
for (const selected of connected) {
  const client = await connect(selected);
  assert.equal(client.profile.mode, selected.mode);
  assert.equal(client.profile.owner, selected.owner ?? 'remote');
  client.close();
}
await assert.rejects(connect({mode: 'local', owner: 'local'}),
  error => error instanceof ClientError &&
    error.code === 'LocalProviderNotInstalled');
await assert.rejects(connect({mode: 'hybrid', owner: 'local',
  cloudConnectionRef: 'registered-cloud-a',
  movementPolicyRef: 'movement-a'}),
  error => error instanceof ClientError &&
    error.code === 'LocalProviderNotInstalled');
assert.equal(calls.length, connected.length);
`);
run(process.execPath, ['smoke.mjs'], root);
console.log('packed Node assembly smoke passed');

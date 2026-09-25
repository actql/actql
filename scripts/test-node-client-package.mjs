import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'node-client-package-'));
const cache = join(root, 'npm-cache');
const environment = {...process.env, npm_config_cache: cache,
  ACTQL_LOCAL_STATE_DIR: join(root, 'local-state')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

function runAsync(command, args, cwd, extraEnvironment = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd,
      env: {...environment, ...extraEnvironment}});
    let output = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(output) :
      reject(new Error(`${command} ${args.join(' ')} failed:\n${output}`)));
  });
}

for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node',
  'node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
}
const sdk = join(root, 'actql-sdk-0.0.0-development.tgz');
const node = join(root, 'actql-node-0.0.0-development.tgz');
const wire = join(root, 'actql-client-wire-0.0.0-development.tgz');
const runHost = join(root, 'actql-run-host-core-0.0.0-development.tgz');
const local = join(root, 'actql-local-node-0.0.0-development.tgz');
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save',
  wire, sdk, runHost, local, node],
  root);
assert.deepEqual((await readdir(join(root, 'node_modules', '@actql'))).sort(),
  ['client-wire', 'local-node', 'node', 'run-host-core', 'sdk']);
for (const name of ['client-host.generated.js',
  'client-host.generated.d.ts']) {
  assert((await readFile(join(root, 'node_modules', '@actql',
    'client-wire', name), 'utf8')).length > 0);
}
for (const name of ['host-port.mjs', 'host-port.d.ts']) {
  assert((await readFile(join(root, 'node_modules', '@actql',
    'sdk', name), 'utf8')).length > 0);
}
await writeFile(join(root, 'values.json'), await readFile(join(repository,
  'packages/sdk/fixtures/values.json')));

await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {connect, ClientError} from '@actql/node';
import {connectInProcess} from '@actql/sdk/host-port';

const calls = [];
const originalFetch = globalThis.fetch;
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
const document = readFileSync('values.json', 'utf8');
async function runApplication(options, requestId) {
  const client = await connect(options);
  const execution = await client.aql(document, {format: 'json', requestId});
  const rows = await execution.result('answer').all();
  return {client, execution, rows};
}
const {client: installedLocal, execution, rows} = await runApplication(
  {mode: 'local', owner: 'local', durability: 'durable'},
  'packed-standard-values');
assert.equal(execution.profile.durability, 'durable');
assert.equal((await execution.status()).status, 'succeeded');
assert.deepEqual(rows, [{id: 1}, {id: 2}]);
await assert.rejects(execution.result('answer').all({maxRows: 1}),
  {code: 'ResultRetainedLimit'});
const reader = execution.result('answer').rows();
assert.deepEqual(await Array.fromAsync(reader), [{id: 1}, {id: 2}]);
assert.equal(reader.state(), 'complete');
assert.equal((await execution.result('answer')
  .deliveryAttempt(reader.attemptId)).kind, 'found');
assert.deepEqual((await installedLocal.lookupRequest(
  'packed-standard-values')).ref, execution.ref);
assert.deepEqual((await installedLocal.attach(execution.ref)).ref,
  execution.ref);
writeFileSync('run-ref.json', JSON.stringify(execution.ref));
const nullable = JSON.parse(document);
nullable.id = 'client-nullable-values';
nullable.stages[0].steps[0].values.schema.id.nullable = true;
nullable.stages[0].steps[0].values.rows = [{id: null}, {id: 3}];
const nullableRun = await installedLocal.aql(JSON.stringify(nullable),
  {format: 'json', requestId: 'packed-nullable-values'});
assert.deepEqual(await nullableRun.result('answer').all(),
  [{id: null}, {id: 3}]);
const empty = JSON.parse(document);
empty.id = 'client-empty-values';
empty.stages[0].steps[0].values.rows = [];
const emptyRun = await installedLocal.aql(JSON.stringify(empty),
  {format: 'json', requestId: 'packed-empty-values'});
assert.deepEqual(await emptyRun.result('answer').all(), []);
assert.deepEqual((await installedLocal.aql(document, {format: 'json',
  requestId: 'packed-standard-values'})).ref, execution.ref);
await assert.rejects(installedLocal.aql(document.replace('"id": 2',
  '"id": 3'), {format: 'json', requestId: 'packed-standard-values'}),
  {code: 'ClientRequestIntentConflict'});
installedLocal.close();
assert.equal(calls.length, connected.length);
globalThis.fetch = originalFetch;
const {client: installedRemote, execution: remoteExecution,
  rows: remoteRows} = await runApplication({mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT, token: 'packed-test-token',
  durability: 'durable'}, 'packed-remote-values');
assert.deepEqual(remoteRows, rows);
assert.equal((await remoteExecution.status()).status, 'succeeded');
assert.deepEqual((await installedRemote.attach(remoteExecution.ref)).ref,
  remoteExecution.ref);
assert.deepEqual((await installedRemote.lookupRequest(
  'packed-remote-values')).ref, remoteExecution.ref);
await assert.rejects(remoteExecution.result('answer').all({maxRows: 1}),
  {code: 'ResultRetainedLimit'});
let remoteReplyLost = false;
globalThis.fetch = async (url, options) => {
  const reply = await originalFetch(url, options);
  if (!remoteReplyLost && new URL(url).pathname.endsWith('/submit')) {
    remoteReplyLost = true;
    await reply.arrayBuffer();
    throw new Error('RemoteAcceptanceReplyLost');
  }
  return reply;
};
try {
  await assert.rejects(installedRemote.aql(document, {format: 'json',
    requestId: 'packed-remote-lost-ack'}), error =>
    error.code === 'SubmissionUnknown' &&
    error.requestId === 'packed-remote-lost-ack');
} finally { globalThis.fetch = originalFetch; }
assert.equal(remoteReplyLost, true);
const recoveredRemote = await installedRemote.lookupRequest(
  'packed-remote-lost-ack');
assert.equal(recoveredRemote.kind, 'found');
const resumedRemote = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-lost-ack'});
assert.deepEqual(resumedRemote.ref, recoveredRemote.ref);
assert.deepEqual(await resumedRemote.result('answer').all(), rows);
installedRemote.close();
const local = await connectInProcess({mode: 'local', owner: 'local'}, {
  async perform(operation) {
    assert.equal(operation, 'connect');
    return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'embedded-scope',
      capabilities: [], limits: {maxReadWireBytes: 1024,
        maxRowWireBytes: 512, maxRowRetainedValueBytes: 512,
        maxRetainedValueBytes: 1024, maxRows: 10, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 1024}};
  },
});
assert.equal(local.profile.owner, 'local');
assert.equal(calls.length, connected.length);
local.close();
`);
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], root);
const remoteModule = pathToFileURL(join(root, 'node_modules', '@actql',
  'local-node', 'adapters', 'host-node', 'embedded-local.mjs')).href;
const {openInstalledRemoteHttpHost} = await import(remoteModule);
const remoteHost = await openInstalledRemoteHttpHost({
  directory: join(root, 'remote-state'),
  authenticate: header => header === 'Bearer packed-test-token'
    ? userInfo().username : undefined,
});
const remoteServer = createServer({
  key: await readFile(join(root, 'remote.key')),
  cert: await readFile(join(root, 'remote.crt')),
}, remoteHost.handler);
await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
try {
  const endpoint = `https://127.0.0.1:${remoteServer.address().port}/`;
  await runAsync(process.execPath, ['smoke.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: endpoint,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally {
  await new Promise(resolve => remoteServer.close(resolve));
}
await writeFile(join(root, 'restart.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/node';
globalThis.fetch = () => { throw new Error('NetworkOnLocalRestart'); };
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable'});
const ref = JSON.parse(readFileSync('run-ref.json', 'utf8'));
const attached = await client.attach(ref);
assert.equal((await attached.status()).status, 'succeeded');
assert.deepEqual(await attached.result('answer').all(),
  [{id: 1}, {id: 2}]);
assert.deepEqual((await client.lookupRequest('packed-standard-values')).ref,
  ref);
const repeated = await client.aql(readFileSync('values.json', 'utf8'),
  {format: 'json', requestId: 'packed-standard-values'});
assert.deepEqual(repeated.ref, ref);
client.close();
`);
run(process.execPath, ['restart.mjs'], root);
const browser = join(root, 'actql-sdk-browser.mjs');
const browserMetadata = join(root, 'actql-sdk-browser-meta.json');
run(join(repository, 'node_modules/.bin/esbuild'), [
  join(root, 'node_modules/@actql/sdk/index.mjs'),
  '--bundle', '--platform=browser', '--format=esm', '--target=es2022',
  `--outfile=${browser}`, `--metafile=${browserMetadata}`,
], root);
const metadata = JSON.parse(await readFile(browserMetadata, 'utf8'));
assert.deepEqual(Object.keys(metadata.inputs).sort(), [
  'node_modules/@actql/client-wire/client-host.generated.js',
  'node_modules/@actql/client-wire/index.mjs',
  'node_modules/@actql/client-wire/publication.generated.js',
  'node_modules/@actql/sdk/index.mjs',
]);
assert(Object.values(metadata.outputs).every(output =>
  output.imports.length === 0));
await writeFile(join(root, 'browser-smoke.mjs'), `
import assert from 'node:assert/strict';
globalThis.fetch = async () => { throw new Error('NetworkOnImport'); };
const {connect} = await import('./actql-sdk-browser.mjs');
let calls = 0;
globalThis.fetch = async () => {
  calls++;
  return Response.json({version: 'actql-client-host/0.1', mode: 'remote',
    owner: 'remote', durability: 'volatile', scopeRef: 'browser-scope',
    capabilities: [], limits: {maxReadWireBytes: 1024,
      maxRowWireBytes: 512, maxRowRetainedValueBytes: 512,
      maxRetainedValueBytes: 1024, maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 1024}});
};
const client = await connect({mode: 'remote',
  endpoint: 'https://remote.example/', token: 'fixture-token'});
assert.equal(client.profile.mode, 'remote');
assert.equal(calls, 1);
client.close();
`);
run(process.execPath, ['browser-smoke.mjs'], root);
console.log('packed Node and browser Client smoke passed');

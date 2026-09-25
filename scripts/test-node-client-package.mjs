import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {once} from 'node:events';
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
  const settled = await execution.wait();
  assert.equal(settled.status, 'succeeded');
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
assert.equal((await nullableRun.wait()).status, 'succeeded');
assert.deepEqual(await nullableRun.result('answer').all(),
  [{id: null}, {id: 3}]);
const empty = JSON.parse(document);
empty.id = 'client-empty-values';
empty.stages[0].steps[0].values.rows = [];
const emptyRun = await installedLocal.aql(JSON.stringify(empty),
  {format: 'json', requestId: 'packed-empty-values'});
assert.equal((await emptyRun.wait()).status, 'succeeded');
assert.deepEqual(await emptyRun.result('answer').all(), []);
const computed = JSON.parse(document);
computed.id = 'client-values-filtered';
computed.stages[0].steps.push({filter: 'id > 1', as: 'filtered'});
computed.stages[0].results.rows.from = 'filtered';
const computedDocument = JSON.stringify(computed);
const computedLocal = await installedLocal.aql(computedDocument,
  {format: 'json', requestId: 'packed-computed-local'});
const computedLocalState = await computedLocal.wait();
assert.equal(computedLocalState.status, 'succeeded',
  JSON.stringify(computedLocalState));
assert.deepEqual(await computedLocal.result('answer').all(), [{id: 2}]);
assert.deepEqual((await installedLocal.aql(document, {format: 'json',
  requestId: 'packed-standard-values'})).ref, execution.ref);
await assert.rejects(installedLocal.aql(document.replace('"id": 2',
  '"id": 3'), {format: 'json', requestId: 'packed-standard-values'}),
  {code: 'ClientRequestIntentConflict'});
installedLocal.close();
assert.equal(calls.length, connected.length);
globalThis.fetch = originalFetch;
const remoteOptions = {mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT, token: 'packed-test-token',
  durability: 'durable'};
const timingClient = await connect(remoteOptions);
let acceptanceTimer;
const timingRun = await Promise.race([
  timingClient.aql(document, {format: 'json',
    requestId: 'packed-acceptance-before-dispatch'}),
  new Promise((_, reject) => {
    acceptanceTimer = setTimeout(() => reject(
      new Error('SubmitWaitedForPhysicalDispatch')), 5000);
  }),
]).finally(() => clearTimeout(acceptanceTimer));
const pendingState = await timingRun.status();
assert.equal(pendingState.status, 'running');
assert.equal(pendingState.result_availability.answer.reason,
  'not_published');
const abortedWait = new AbortController();
const waitAttempt = timingRun.wait({signal: abortedWait.signal});
abortedWait.abort();
await assert.rejects(waitAttempt);
assert.equal((await timingRun.status()).status, 'running');
const release = await originalFetch(new URL('/__test/release-dispatch',
  remoteOptions.endpoint), {method: 'POST'});
assert.equal(release.status, 200);
assert.equal((await timingRun.wait()).status, 'succeeded');
assert.deepEqual(await timingRun.result('answer').all(), rows);
timingClient.close();
const {client: installedRemote, execution: remoteExecution,
  rows: remoteRows} = await runApplication(remoteOptions,
  'packed-remote-values');
assert.deepEqual(remoteRows, rows);
const computedRemote = await installedRemote.aql(computedDocument,
  {format: 'json', requestId: 'packed-computed-remote'});
assert.equal((await computedRemote.wait()).status, 'succeeded');
assert.deepEqual(await computedRemote.result('answer').all(), [{id: 2}]);
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
assert.equal((await resumedRemote.wait()).status, 'succeeded');
assert.deepEqual(await resumedRemote.result('answer').all(), rows);
const failDispatch = await originalFetch(new URL(
  '/__test/fail-next-dispatch', remoteOptions.endpoint), {method: 'POST'});
assert.equal(failDispatch.status, 200);
const failedRemote = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-dispatch-failure'});
const failedState = await failedRemote.wait();
assert.equal(failedState.status, 'failed');
assert.equal(failedState.terminal_error.code,
  'ACTQL_E_UNPUBLISHED_RUN');
const repeatedFailure = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-dispatch-failure'});
assert.deepEqual(repeatedFailure.ref, failedRemote.ref);
assert.equal((await repeatedFailure.status()).status, 'failed');
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
let releaseDispatch;
const heldDispatch = new Promise(resolve => { releaseDispatch = resolve; });
let failNextDispatch = false;
const remoteHost = await openInstalledRemoteHttpHost({
  directory: join(root, 'remote-state'),
  authenticate: header => header === 'Bearer packed-test-token'
    ? userInfo().username : undefined,
  beforeDispatch: async () => {
    if (failNextDispatch) {
      failNextDispatch = false;
      throw new Error('TestPhysicalDispatchFailure');
    }
    await heldDispatch;
  },
});
const remoteServer = createServer({
  key: await readFile(join(root, 'remote.key')),
  cert: await readFile(join(root, 'remote.crt')),
}, (request, response) => {
  if (request.method === 'POST' &&
      request.url === '/__test/release-dispatch') {
    releaseDispatch();
    response.writeHead(200);
    response.end();
    return;
  }
  if (request.method === 'POST' &&
      request.url === '/__test/fail-next-dispatch') {
    failNextDispatch = true;
    response.writeHead(200);
    response.end();
    return;
  }
  return remoteHost.handler(request, response);
});
await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
try {
  const endpoint = `https://127.0.0.1:${remoteServer.address().port}/`;
  await runAsync(process.execPath, ['smoke.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: endpoint,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally {
  releaseDispatch();
  await new Promise(resolve => remoteServer.close(resolve));
}
await writeFile(join(root, 'restart-remote-host.mjs'), `
import {readFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';
const host = await openInstalledRemoteHttpHost({
  directory: join(process.cwd(), 'restart-remote-state'),
  authenticate: header => header === 'Bearer packed-test-token'
    ? userInfo().username : undefined,
  beforeDispatch: process.env.ACTQL_HOLD_DISPATCH === '1'
    ? async () => new Promise(() => {}) : undefined,
});
const server = createServer({key: readFileSync('remote.key'),
  cert: readFileSync('remote.crt')}, host.handler);
server.listen(0, '127.0.0.1', () => {
  console.log('READY:' + server.address().port);
});
`);
await writeFile(join(root, 'reserve-remote.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {connect} from '@actql/node';
const client = await connect({mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT,
  token: 'packed-test-token', durability: 'durable'});
const document = readFileSync('values.json', 'utf8');
const execution = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
for (let attempt = 0; attempt < 100; attempt++) {
  if ((await execution.status()).status === 'running') break;
  await new Promise(resolve => setTimeout(resolve, 20));
}
assert.equal((await execution.status()).status, 'running');
writeFileSync('restart-remote-ref.json', JSON.stringify(execution.ref));
client.close();
`);
await writeFile(join(root, 'resume-remote.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/node';
const client = await connect({mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT,
  token: 'packed-test-token', durability: 'durable'});
const document = readFileSync('values.json', 'utf8');
const ref = JSON.parse(readFileSync('restart-remote-ref.json', 'utf8'));
const attached = await client.attach(ref);
assert.equal((await attached.status()).status, 'running');
const execution = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
assert.deepEqual(execution.ref, ref);
assert.equal((await execution.wait()).status, 'succeeded');
assert.deepEqual(await execution.result('answer').all(),
  [{id: 1}, {id: 2}]);
const repeated = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
assert.deepEqual(repeated.ref, ref);
assert.equal((await repeated.status()).status, 'succeeded');
assert.deepEqual((await client.lookupRequest(
  'packed-restart-before-physical-start')).ref, ref);
client.close();
`);
async function startRestartHost(hold) {
  const child = spawn(process.execPath, ['restart-remote-host.mjs'], {
    cwd: root, env: {...environment, ACTQL_HOLD_DISPATCH: hold ? '1' : '0'},
  });
  let output = '';
  return new Promise((resolve, reject) => {
    child.stdout.setEncoding('utf8').on('data', chunk => {
      output += chunk;
      const ready = output.match(/READY:(\d+)/u);
      if (ready) resolve({child, port: Number(ready[1])});
    });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('exit', code => reject(new Error(
      `Packed restart Host exited before ready (${code}): ${output}`)));
  });
}
async function stopRestartHost(host) {
  if (host.child.exitCode !== null) return;
  const stopped = once(host.child, 'exit');
  host.child.kill('SIGTERM');
  await stopped;
}
const heldHost = await startRestartHost(true);
try {
  await runAsync(process.execPath, ['reserve-remote.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${heldHost.port}/`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally { await stopRestartHost(heldHost); }
const resumedHost = await startRestartHost(false);
try {
  await runAsync(process.execPath, ['resume-remote.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${resumedHost.port}/`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally { await stopRestartHost(resumedHost); }
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

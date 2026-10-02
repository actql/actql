import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {appendFileSync, readFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {canonical, configuration} from './installed-infer-fixture.mjs';
import {source, expectedRows, expectedColumns} from './infer-source-expectation.mjs';

const [transport, phase] = process.argv.slice(2);
assert.ok(['local', 'remote'].includes(transport));
assert.ok(['success', 'capture', 'replay'].includes(phase));
const root = join(process.cwd(), `${transport}-${phase === 'replay' ? 'capture' : phase}`);
const requestId = `packed-infer-source-${transport}-${phase === 'success' ? 'success' : 'capture'}`;
const {installation, taskCid} = configuration(
  JSON.parse(readFileSync('base-environment.json', 'utf8')));
const keys = generateKeyPairSync('ed25519');
let calls = 0;
const authorization = {
  hostKey: {keyId: 'packed-host', privateKey: keys.privateKey.export({
    type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'packed-reviewer', reviewerId: 'packed-reviewer',
    principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  accountConfiguration: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-owner',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {all: true},
      exclusions: []}],
  }),
  faultInjection(name) {
    if (phase === 'capture' && name === 'infer_capture_committed') {
      assert.equal(calls, 1);
      // This is the existing owner's committed-capture boundary. Exit before
      // publication so a new process must consume that exact retained capture.
      process.stdout.write(JSON.stringify({transport, phase, calls, boundary: name}) +
        '\n', () => process.exit(0));
      return new Promise(() => {});
    }
  },
};
const checked = result => {
  assert.equal(result.$tag, 1, 'physical request must pass common admission');
  return result._0;
};
const registerModelProviders = moon => [{providerId: 'models/packed',
  invoke() { throw new Error('UnpreparedModelCall'); },
  validatePrompt(actual, selector, wire) {
    return actual === taskCid && selector === 'packed-risk-model' &&
      JSON.parse(wire).format === 'packed-risk/0.1';
  },
  quantityCapacity: {
    limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
  observeEgress: () => ({_0: 'public', _1: 'fixture-region', _2: false, _3: false}),
  physicalPreflight: request => moon.clientProgramModelRequestPreflight(
    () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
      request, 1000n, 33n, 0n, 500n, () => {
        calls++;
        appendFileSync('source-provider-calls.jsonl',
          JSON.stringify({transport, phase, taskCid}) + '\n');
        assert.notEqual(phase, 'replay', 'retained capture must not redispatch');
        assert.equal(moon.clientProgramModelRequestInput(request, 'text'), '"urgent"');
        return moon.clientProgramModelResponse(request,
          '{"reason":null,"risk":"high"}', 'packed-risk-model',
          'packed-source-request', 1n, 2n, new Date().toISOString());
      }))}), () => true),
}];
let host;
let server;
let client;
try {
  if (transport === 'remote') {
    host = await openInstalledRemoteHttpHost({directory: root,
      authenticate: () => userInfo().username, authorization,
      modelInstallation: installation, registerModelProviders});
    server = createServer({cert: readFileSync('remote.crt'),
      key: readFileSync('remote.key')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-owner'});
  } else {
    client = await connect({mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: root, authorization,
        modelInstallation: installation, registerModelProviders}});
  }
  const run = await client.aql(source, {format: 'aql-text', requestId});
  const signal = AbortSignal.timeout(60_000);
  const terminal = await run.wait({signal});
  assert.equal(terminal.status, 'succeeded');
  assert.notEqual(phase, 'capture', 'capture exit boundary was not reached');
  const result = run.result('answer');
  const description = await result.describe({signal});
  assert.deepEqual(description.ref, run.ref);
  assert.equal(description.resultName, 'answer');
  assert.equal(description.serialization.version, 'actql-jsonl/0.1');
  assert.equal(description.serialization.format, 'jsonl');
  assert.deepEqual(description.columns, expectedColumns);
  assert.deepEqual(await result.all({signal}), expectedRows);
  assert.deepEqual(await result.all({signal}), expectedRows);
  const attached = await client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').describe({signal}), description);
  assert.deepEqual(await attached.result('answer').all({signal}), expectedRows);
  const resent = await client.aql(source, {format: 'aql-text', requestId});
  assert.deepEqual(resent.ref, run.ref);
  assert.deepEqual(await resent.result('answer').all({signal}), expectedRows);
  assert.equal(calls, phase === 'replay' ? 0 : 1);
  const journal = new DatabaseSync(join(root, 'requests', 'client-requests.sqlite3'),
    {readOnly: true});
  try {
    assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
      .get().count, 1, 'reread, attach and resend must not create another Run');
  } finally { journal.close(); }
  console.log(JSON.stringify({transport, phase, status: terminal.status,
    calls, ref: run.ref, columns: description.columns, rows: expectedRows}));
} finally {
  await client?.close();
  if (server) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
}

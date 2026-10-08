// Public Model/Checkpoint acceptance in fresh processes. Reuse the existing
// execution fixture; only the independent OTLP collector is added here.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn, execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';

const url = path => new URL(path, import.meta.url).href;
const runtime = {
  client: url('../node/index.mjs'), httpHost: url('../local-node/http-host.mjs'),
  observation: url('./index.mjs'),
  contextApi: url('./node_modules/@opentelemetry/api/build/src/index.js'),
  contextManager: url('./node_modules/@opentelemetry/context-async-hooks/build/src/index.js'),
  inferFixture: url('../../scripts/fixtures/installed-infer-fixture.mjs'),
  providerFixture: url('../../scripts/fixtures/model-provider-binding-fixture.mjs'),
  environment: fileURLToPath(new URL('../../spec/local-check-environment.json', import.meta.url)),
};
const processFixture = fileURLToPath(new URL('../../scripts/fixtures/model-resume-public-process.mjs', import.meta.url));
const parent = {traceId: '5'.repeat(32), spanId: '6'.repeat(16), traceFlags: 1};
const recoveredParent = {traceId: '7'.repeat(32), spanId: '8'.repeat(16), traceFlags: 1};
const expectedRows = [{id: '1', outcome: 'ok', value: {reason: null, risk: 'high'}}];
async function phase(root, transport, endpoint, name, changes = {}) {
  const env = {...process.env};
  for (const key of ['ACTQL_LOCAL_STATE_DIR', 'ACTQL_LOCAL_SOURCE_PROFILE',
    'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[key];
  const child = spawn(process.execPath, [processFixture], {stdio: ['pipe', 'ignore', 'pipe'],
    env});
  const timeout = setTimeout(() => child.kill('SIGKILL'), 45000);
  let error = '';
  child.stderr.on('data', bytes => { if (error.length < 65536) error += bytes.toString(); });
  const caller = name === 'wait' ? parent : recoveredParent;
  child.stdin.end(JSON.stringify({root, transport, phase: name, runtime,
    observation: {endpoint, parent: {...caller,
      traceFlags: changes.unsampled ? 0 : caller.traceFlags}}, ...changes}));
  try { assert.equal((await once(child, 'exit'))[0], 0, error); }
  finally { clearTimeout(timeout); }
  const report = JSON.parse(await readFile(join(root, `${name}-result.json`), 'utf8'));
  assert.equal(report.error, undefined);
  const status = JSON.parse(await readFile(join(root, `${name}-telemetry.json`), 'utf8'));
  if (changes.expectBudgetLoss) assert.ok(status.projection.budgetUnavailable > 0);
  else assert.equal(status.projection.budgetUnavailable, 0);
  return report;
}
function custody(root, action) {
  const database = new DatabaseSync(join(root, 'host/requests/client-requests.sqlite3'));
  try { return action(database); } finally { database.close(); }
}
for (const [transport, sampled] of [['local', true], ['https', true], ['local', false]]) {
test(`public ${transport}: ${sampled ? 'sampled' : 'unsampled'} approval restart retains capture and consumption`, async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-otel-recovery-'));
  const packets = [];
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    packets.push({path: request.url, body: Buffer.concat(chunks)});
    response.end();
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    if (transport === 'https') execFileSync('openssl', ['req', '-x509', '-nodes',
      '-newkey', 'rsa:2048', '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
    const endpoint = `http://127.0.0.1:${server.address().port}`;
    const flags = {unsampled: !sampled};
    const waiting = await phase(root, transport, endpoint, 'wait', flags);
    assert.equal(waiting.status, 'waiting_checkpoint');
    assert.equal(waiting.calls, 0);
    const waitingPackets = packets.splice(0);
    const waitingBudget = custody(root, db => db.prepare('SELECT records, bytes FROM client_observation_runs').get());
    assert.ok(waitingPackets.some(packet => packet.body.includes(Buffer.from('waiting_checkpoint'))));
    const approved = await phase(root, transport, endpoint, 'approve', flags);
    assert.deepEqual(approved.ref, waiting.ref);
    assert.equal(approved.calls, 1);
    assert.equal(approved.status, 'succeeded');
    assert.deepEqual(approved.rows, expectedRows);
    assert.ok(packets.some(packet => packet.body.includes(Buffer.from('actql.model.attempt_cid'))),
      'the physical Model attempt uses its Owner-issued identity');
    const approvedBudget = custody(root, db => db.prepare('SELECT records, bytes FROM client_observation_runs').get());
    assert.ok(approvedBudget.records > waitingBudget.records);
    assert.ok(approvedBudget.bytes > waitingBudget.bytes);
    assert.ok(packets.some(packet => packet.body.includes(Buffer.from('checkpoint_resolved'))));
    if (sampled) {
      assert.ok(packets.some(packet => packet.path === '/v1/traces' &&
        packet.body.includes(Buffer.from(parent.traceId, 'hex')) &&
        packet.body.includes(Buffer.from(recoveredParent.traceId, 'hex'))), 'recovery links the saved caller');
    } else assert.equal(packets.some(packet => packet.path === '/v1/traces'), false);
    const replayed = await phase(root, transport, endpoint, 'resume-again', flags);
    assert.deepEqual(replayed.rows, expectedRows);
    assert.equal(replayed.calls, 1, 'observation/recovery never resends the Model call');
    if (transport === 'local') {
      custody(root, db => db.exec('DELETE FROM client_observation_runs'));
      const withoutBudget = await phase(root, transport, endpoint, 'resume-again',
        {...flags, expectBudgetLoss: true});
      assert.deepEqual(withoutBudget.rows, expectedRows);
      assert.equal(withoutBudget.calls, 1);
      assert.equal(custody(root, db => db.prepare('SELECT count(*) AS n FROM client_observation_runs').get().n), 0,
        'lost consumption never mints a fresh observation budget');
    }
    if (!sampled) assert.equal([...waitingPackets, ...packets]
      .some(packet => packet.path === '/v1/traces'), false,
    'capture and replay never require sampled telemetry');
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  }
});
}
test('public Local: cancellation while waiting preserves Owner-confirmed outcome without dispatch', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-otel-cancel-'));
  const packets = [];
  const server = createServer(async (request, response) => {
    for await (const chunk of request) packets.push(Buffer.from(chunk));
    response.end();
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const endpoint = `http://127.0.0.1:${server.address().port}`;
    await phase(root, 'local', endpoint, 'wait');
    const cancelled = await phase(root, 'local', endpoint, 'cancel');
    assert.equal(cancelled.status, 'cancelled');
    assert.equal(cancelled.calls, 0);
    assert.equal(cancelled.rows, undefined);
    assert.ok(Buffer.concat(packets).includes(Buffer.from('cancellation_requested')));
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  }
});

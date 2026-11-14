import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createServer as httpsServer} from 'node:https';
import {createServer as httpServer} from 'node:http';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {generateKeyPairSync} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {context, trace, ROOT_CONTEXT, propagation} from '@opentelemetry/api';
import {AsyncLocalStorageContextManager} from '@opentelemetry/context-async-hooks';
import {createNodeHostObservability} from './index.mjs';
import {connect as localConnect} from '../local-node/index.mjs';
import {openInstalledRemoteHttpHost} from '../local-node/http-host.mjs';
import {connect as remoteConnect, getSubmissionCheckObservation, getSubmissionOutcome,
  getCheckInput, resolveCheckLocation} from '../sdk/index.mjs';
import {records, attributes, field, assertNoMetricExemplars} from './test/otlp-fixture.mjs';

const sentinel = 'SECRET_SENTINEL';
const parent = {traceId: '3'.repeat(32), spanId: '4'.repeat(16), traceFlags: 1};
const program = JSON.stringify({version: 'actql/0.1', id: 'private-program', stages: [{
  id: 'source', inputs: {}, steps: [{as: 'selected', values: {
    schema: {id: {type: 'number', nullable: false}, secret: {type: 'string', nullable: false}},
    rows: [{id: 1, secret: sentinel}, {id: 2, secret: sentinel}],
  }}], results: {rows: {from: 'selected', fields: ['id', 'secret']}},
}], results: {answer: {from: {stage: 'source', result: 'rows'}}}});

async function collect(t, failure = false) {
  const packets = [];
  const server = httpServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    packets.push({path: request.url, body: Buffer.concat(chunks)});
    if (failure && request.url === '/v1/traces') response.statusCode = 503;
    response.end();
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  return {packets, endpoint: `http://127.0.0.1:${server.address().port}`};
}
function requestRows(path) {
  const database = new DatabaseSync(path, {readOnly: true});
  try { return database.prepare('SELECT count(*) AS n FROM client_requests').get().n; }
  finally { database.close(); }
}

for (const [transport, mode] of [['local', 'normal'], ['https', 'normal'],
  ['local', 'export-failure'], ['local', 'overflow'], ['local', 'disabled'],
  ['https', 'unsampled-parent'], ['local', 'denied-run-read']]) {
test(`public ${transport} Host: ${mode} observations preserve execution`, async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-otel-public-'));
  const sink = await collect(t, mode === 'export-failure');
  const adapter = createNodeHostObservability(mode === 'disabled' ? {} : {endpoint: sink.endpoint,
    metrics: {endpoint: `${sink.endpoint}/v1/metrics`},
    logs: {endpoint: `${sink.endpoint}/v1/logs`},
    ...(mode === 'overflow' ? {projectionLimits: {queueRecords: 1}} : {})});
  const keys = generateKeyPairSync('ed25519');
  const owner = userInfo().username;
  const installation = {directory: join(root, 'host'), observation: adapter.connection,
    authorization: {accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'otel-acceptance', entries: [{entry_id: 'read-original', outcome: 'allow',
        principal: {any_of: [owner]}, connection: {all: true},
        resource: {any_of: mode === 'denied-run-read' ? ['result/answer'] : ['result/answer', 'run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: owner,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}]},
  };
  let client, host, server;
  const manager = new AsyncLocalStorageContextManager().enable();
  assert.equal(context.setGlobalContextManager(manager), true);
  t.after(() => { context.disable(); manager.disable(); });
  t.after(async () => {
    await client?.close();
    if (server) await new Promise(resolve => server.close(resolve));
    await host?.close(); await adapter.close();
    await rm(root, {recursive: true, force: true});
  });
  const caller = {...parent, traceFlags: mode === 'unsampled-parent' ? 0 : 1};
  let current = trace.setSpanContext(ROOT_CONTEXT, caller);
  current = propagation.setBaggage(current, propagation.createBaggage({secret: {value: sentinel}}));
  await context.with(current, async () => {
    if (transport === 'https') {
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
      const trusted = getCACertificates('default');
      setDefaultCACertificates([...trusted, await readFile(join(root, 'host.crt'), 'utf8')]);
      t.after(() => setDefaultCACertificates(trusted));
      host = await openInstalledRemoteHttpHost({...installation,
        authenticate: header => header === `Bearer ${sentinel}` ? owner : undefined});
      server = httpsServer({key: await readFile(join(root, 'host.key')),
        cert: await readFile(join(root, 'host.crt'))}, host.handler).listen(0, '127.0.0.1');
      await once(server, 'listening');
      client = await remoteConnect({mode: 'remote', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`, token: sentinel,
        traceContext: adapter.currentContext});
    } else client = await localConnect({mode: 'local', owner: 'local',
      durability: 'durable', installation});
    const journal = join(installation.directory, 'requests/client-requests.sqlite3');
    const check = await client.check(`SELECT ${sentinel} FROM`, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(check.report.verdict, 'invalid');
    assert.equal(requestRows(journal), 0, 'checking creates no Run');
    if (mode === 'normal') {
      const typed = await client.check('SELECT @id AS id', {kind: 'text', scope: 'bound_input', format: 'sql',
        parameterDeclarations: {id: {type: 'number'}},
        parameters: {id: 'not-a-number'}});
      assert.equal(typed.report.verdict, 'invalid');
      assert.equal(requestRows(journal), 0, 'a value/schema mismatch creates no Run');
      const original = {version: 'actql/0.1', id: sentinel};
      let rejected;
      try { await client.start(original); }
      catch (error) { rejected = error; }
      const checked = getSubmissionCheckObservation(rejected);
      assert.equal(checked?.report.verdict, 'invalid',
        `structured submission diagnostics survive observation wiring (${rejected?.code}; ${getSubmissionOutcome(rejected)?.problem?.code}; ${rejected?.cause?.code})`);
      const reason = checked.report.reasons.find(reason =>
        reason.code === 'program_structure_invalid');
      assert.equal(reason?.facts.issue, 'missing_field');
      assert.equal(reason.location.kind, 'structured');
      assert.equal(reason.location.pointer, '');
      assert.deepEqual(getCheckInput(checked, 'program').value, original);
      assert.equal(resolveCheckLocation(checked, reason.location).pointer, '');
      assert.equal(requestRows(journal), 0,
        'a rejected structured submission creates no Run');
    }
    const run = await client.startSource(program, {format: 'json',
      submissionRef: client.newSubmission({nonce: 'first-observed-run'})});
    if (mode === 'denied-run-read') {
      await assert.rejects(run.wait(), {code: 'ClientConnectionDenied'},
        'observation never supplies the missing original Run read permission');
    } else {
      assert.equal((await run.wait()).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(),
        [{id: 1, secret: sentinel}, {id: 2, secret: sentinel}]);
      assert.equal(requestRows(journal), 1);
      if (mode === 'normal') {
        assert.equal((await run.status()).status, 'succeeded');
        const before = adapter.status().projection.repeated;
        for (let n = 0; n < 2; n++) assert.equal((await run.status()).status, 'succeeded');
        assert.equal(adapter.status().projection.repeated, before + 2,
          'each unchanged public status suppresses the same Owner fact');
      }
    }
    await client.close();
    if (server) { await new Promise(resolve => server.close(resolve)); server = undefined; }
    await host?.close(); host = undefined;
  });
  const logs = Buffer.concat(sink.packets.filter(packet => packet.path === '/v1/logs').map(packet => packet.body));
  for (const packet of sink.packets) assert.equal(packet.body.includes(Buffer.from(sentinel)), false);
  if (mode === 'denied-run-read') return;
  if (mode === 'disabled') {
    assert.equal(sink.packets.length, 0);
    assert.equal(adapter.status().projection.dropped, 0);
    const database = new DatabaseSync(join(installation.directory,
      'requests/client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(database.prepare("SELECT name FROM sqlite_master WHERE name = 'client_observation_runs'")
        .get(), undefined, 'disabled observation does not allocate custody');
    } finally { database.close(); }
    return;
  }
  if (mode === 'overflow') {
    assert.ok(adapter.status().projection.queueOverflow > 0);
    return;
  }
  if (mode === 'export-failure') assert.ok(adapter.status().signals.traces.failed > 0);
  for (const event of ['check_completed', 'task_started', 'task_completed',
    'result_committed', 'cleanup_completed', 'owner_observed']) {
    assert.equal(logs.includes(Buffer.from(event)), true, event);
  }
  const logRecords = records(sink.packets, 'logs');
  const checks = logRecords.filter(record =>
    field(field(record, 5), 1).toString() === 'check_completed');
  assert.ok(checks.length > 0);
  for (const record of checks) {
    const values = attributes(record, 6);
    assert.equal(values['actql.check.verdict'], 'invalid');
    assert.equal(Object.keys(values).some(key => /run|program/iu.test(key)), false,
      'actual pre-Run checker records have no invented Run or Program identity');
  }
  const ownerRecords = logRecords.map(record => attributes(record, 6))
    .filter(values => values['actql.event'] === 'owner_observed');
  assert.ok(ownerRecords.some(values => values['actql.outcome'] === 'succeeded' &&
    /^sha256:[a-f0-9]{64}$/u.test(values['actql.run.definition_cid'])));
  assertNoMetricExemplars(sink.packets);
  assert.equal(logs.includes(Buffer.from('actql.check.verdict')), true);
  assert.equal(logs.includes(Buffer.from('invalid')), true);
  assert.equal(sink.packets.some(packet => packet.path === '/v1/traces' &&
    packet.body.includes(Buffer.from(parent.traceId, 'hex'))), mode !== 'unsampled-parent',
    'caller sampling decision reaches Host without affecting execution');
  for (const packet of sink.packets) {
    assert.equal(packet.body.includes(Buffer.from(sentinel)), false, packet.path);
    if (packet.path === '/v1/metrics') assert.equal(packet.body.includes(Buffer.from('actql.run.id')), false);
  }
  assert.equal(adapter.status().projection.budgetUnavailable, 0);
});
}

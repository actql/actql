// Use the installed Gateway, Client and original Host cancellation owners.
// The second HTTP delivery models a transport replay of the exact request.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {realpath} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join, sep} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as delay} from 'node:timers/promises';
import {connect} from '@actql/node';
import {createHostObservationConnection} from '@actql/local-node/observation';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import {startExplorer} from '@actql/explorer/launcher';
import type {CancellationObservation, OriginalCancellation} from '@actql/explorer-ui/cancellation';

const require = createRequire(import.meta.url);
const modules = await realpath('node_modules');
for (const name of ['@actql/node', '@actql/local-node/observation', '@actql/explorer/launcher', '@actql/explorer/browser-source']) {
  assert((await realpath(require.resolve(name))).startsWith(modules + sep));
}

const principal = userInfo().username;
const {privateKey, publicKey} = generateKeyPairSync('ed25519');
const held = Promise.withResolvers<void>();
const release = Promise.withResolvers<void>();
let physicalStarts = 0, computed = 0;
const observation = createHostObservationConnection({deliver(record) {
  if (record.operation === 'compute' && record.event === 'task_started') computed++;
}});
const directory = join(process.cwd(), 'stop-host');
const authorization = {
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'explorer-stop-fixture', entries: [
      {entry_id: 'owner-read', outcome: 'allow', principal: {any_of: [principal]},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['result/main', 'run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'write', outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}, exclusions: []},
    ]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
    publicKey: publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: privateKey.export({type: 'pkcs8', format: 'pem'})},
  async faultInjection(name: string) {
    if (name === 'physical_start_reserved') {
      physicalStarts++;
      held.resolve();
      await release.promise;
    }
  },
};
const client = await connect({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory, observation, authorization}});
let gateway: Awaited<ReturnType<typeof startExplorer>> | undefined;
let database: DatabaseSync | undefined;
let report: unknown;
try {
  database = new DatabaseSync(join(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  const journal = database;
  const submissionRef = client.newSubmission({nonce: 'explorer-original-stop-run'});
  const run = await client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef});
  await Promise.race([held.promise, delay(10000, undefined, {ref: false}).then(() => {
    throw new Error('Original physical start was not observed');
  })]);
  const before = await run.status();
  assert.equal(before.status, 'running');
  assert.equal(before.control?.physical_stop, 'unknown');
  assert(before.control);
  const snapshot = () => ({
    run: journal.prepare(`SELECT revision, physical_start_reserved, physical_close_confirmed,
      cancellation_requested FROM client_requests WHERE run_definition_cid = ?`).get(run.ref.runDefinitionCid),
    operations: journal.prepare(`SELECT cancel_id, expected_revision, outcome_cid FROM
      client_cancellation_operations WHERE run_definition_cid = ? ORDER BY cancel_id`).all(run.ref.runDefinitionCid),
    issued: journal.prepare('SELECT issued_count FROM client_cancellation_custody').get()?.issued_count,
  });
  const initial = snapshot();
  assert.equal(initial.run?.physical_start_reserved, 1);
  assert.equal(initial.run?.physical_close_confirmed, 0);
  const original: OriginalCancellation = {
    cancelRef: {...run.ref, cancelId: 'explorer-original-stop', expectedRevision: before.control.revision},
    attemptRef: {operation: 'cancel', attemptId: 'explorer-original-stop-attempt'},
  };
  gateway = await startExplorer({client, allowCancellation: true});
  const activeGateway = gateway;
  let cookie: string | undefined, appRequests = 0, transports = 0, lookups = 0;
  let first: CancellationObservation | undefined;
  let transportCheckError: unknown;
  const source = createExplorerBrowserSource({origin: activeGateway.origin, async fetch(input, init) {
    const headers = new Headers(init?.headers);
    headers.set('origin', activeGateway.origin);
    if (cookie) headers.set('cookie', cookie);
    const pathname = new URL(String(input)).pathname;
    const send = async () => {
      if (pathname === '/api/control/cancel') transports++;
      return fetch(input, {...init, headers});
    };
    const response = await send();
    const entered = response.headers.get('set-cookie');
    if (entered) cookie = entered.split(';', 1)[0];
    if (pathname === '/api/control/lookup-cancellation') lookups++;
    if (pathname !== '/api/control/cancel') return response;

    appRequests++;
    try {
      assert.deepEqual(JSON.parse(String(init?.body)), original);
      assert.equal(response.status, 200);
      first = (await response.json() as {data: typeof first}).data;
      assert(first?.state === 'observed' && first.outcome.kind === 'accepted');
      const afterAcceptance = snapshot();
      assert.equal(afterAcceptance.run?.cancellation_requested, 1);
      assert.equal(afterAcceptance.run?.revision, before.control!.revision + 1);
      assert.equal(afterAcceptance.run?.physical_close_confirmed, 0);
      assert.equal(afterAcceptance.operations.length, 1);
      assert.equal(afterAcceptance.issued, Number(initial.issued) + 1);

      const replay = await send();
      assert.equal(replay.status, 200);
      const repeated = (await replay.json() as {data: typeof first}).data;
      assert(repeated?.state === 'observed' && (repeated.outcome.kind === 'accepted' ||
        repeated.outcome.kind === 'already_satisfied'));
      assert.deepEqual(repeated.original, original);
      assert.deepEqual(repeated.outcome.attemptRef, original.attemptRef);
      assert.deepEqual(repeated.outcome.cancellation, first.outcome.cancellation);
      assert.deepEqual(snapshot(), afterAcceptance);
    } catch (error) {
      transportCheckError = error;
      throw error;
    }
    throw new Error('Test adapter discarded the accepted Gateway reply');
  }});
  assert.equal((await source.connect(activeGateway.issueBootstrap().bootstrap)).cancellation, true);
  assert.deepEqual(await source.cancel(original), {state: 'unknown', original});
  assert.ifError(transportCheckError);
  assert(first?.state === 'observed' && first.outcome.kind === 'accepted');
  activeGateway.invalidateScope();
  source.close();
  await source.connect(activeGateway.issueBootstrap().bootstrap);
  assert.deepEqual(await source.lookupCancellation(original.cancelRef),
    {kind: 'found', cancellation: first.outcome.cancellation});
  assert.equal(snapshot().run?.physical_close_confirmed, 0);

  release.resolve();
  const stopDeadline = AbortSignal.timeout(12000);
  let stopped = await run.status();
  while (stopped.control?.physical_stop !== 'confirmed') {
    await delay(10, undefined, {signal: stopDeadline});
    stopped = await run.status({signal: stopDeadline});
  }
  assert.equal(stopped.status, 'cancelled');
  assert.equal(stopped.result_available, false);
  assert.equal(snapshot().run?.physical_close_confirmed, 1);
  const terminal = snapshot();
  assert.equal(terminal.run?.revision, first.outcome.cancellation.revision + 1);
  assert.equal(terminal.run?.cancellation_requested, 1);
  assert.equal(terminal.operations.length, 1);
  assert.deepEqual(await source.lookupCancellation(original.cancelRef),
    {kind: 'found', cancellation: first.outcome.cancellation});
  assert.deepEqual(snapshot(), terminal);
  assert.deepEqual({appRequests, transports, lookups, physicalStarts},
    {appRequests: 1, transports: 2, lookups: 2, physicalStarts: 1});
  source.close();
  report = {appRequests, transports, lookups, physicalStarts,
    acceptedRevision: first.outcome.cancellation.revision, physicalRevision: terminal.run?.revision, physicalStop: stopped.control.physical_stop,
    persistentOperations: terminal.operations.length, issued: terminal.issued};
} finally {
  release.resolve();
  database?.close();
  try {await gateway?.close();} finally {await client.close();}
}
const observationStatus = observation.status();
assert(observationStatus?.closed);
assert.equal(observationStatus.dropped, 0);
assert.equal(observationStatus.queued, 0);
assert.equal(observationStatus.active, 0);
assert.equal(observationStatus.activeSegments, 0);
assert.deepEqual(observationStatus.loss, {});
assert.equal(computed, 0);
console.log('INSTALLED_EXPLORER_STOP:', JSON.stringify({report, computed, firstGatewayClose: true, firstHostClose: true}));

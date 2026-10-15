import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {connectRealRouteTransport, closeRealRouteTransport} from './fixtures/real-cross-connector-transport.mjs';

const closed = () => ({storeCleanupPending: false, authorizationCleanupPending: false,
  diagnosticDeliveryPending: false, pendingRetention: []});
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'real-route-transport-control-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const https = {keyPath: join(root, 'key'), certPath: join(root, 'cert'), token: 'x'.repeat(43)};
  await writeFile(https.keyPath, 'synthetic non-key fixture', {mode: 0o600});
  await writeFile(https.certPath, 'synthetic non-certificate fixture');
  const calls = [], held = {}, state = {report: closed(), address: '127.0.0.1'};
  const error = new Error('independent cleanup control');
  const client = {async close() { calls.push('client.close'); if (state.fail === 'client') throw error; }};
  const host = {handler() {}, async close() { calls.push('host.close'); if (state.fail === 'host') throw error; return state.report; }};
  const server = {once() {}, removeListener() {},
    listen(port, address, callback) { assert.equal(port, 0); assert.equal(address, '127.0.0.1'); calls.push('listen'); queueMicrotask(callback); },
    address: () => ({address: state.address, port: 12345}),
    closeAllConnections() { calls.push('server.connections'); },
    close(callback) { calls.push('server.close'); callback(state.fail === 'server' ? error : undefined); }};
  const options = {mode: 'local', owner: 'local', durability: 'durable', installation: {
    directory: '/synthetic/original', sourceProfilePaths: ['/synthetic/one', '/synthetic/two'],
    effectProfilePath: '/synthetic/effect', authorization: {original: true}}};
  const resolveSourceSecret = () => { throw new Error('not a Source control'); };
  const args = {options, transport: 'https', https, principalId: 'original-principal', resolveSourceSecret,
    async openInstalledRemoteHttpHost(value) { calls.push('host.open'); state.hostOptions = value; if (state.openFailure) throw state.openFailure; return host; },
    createServer(tls, handler) { calls.push('server.create'); assert.equal(handler, host.handler); assert.equal(tls.key.toString(), 'synthetic non-key fixture'); return server; },
    async connect(value) { calls.push('client.open'); state.clientOptions = value; return client; }};
  return {held, args, calls, state, error, host, server, client};
}

test('real route Local keeps the same installed connection without an HTTP Host', async t => {
  const f = await fixture(t);
  assert.equal(await connectRealRouteTransport(f.held, {...f.args, transport: 'local'}), f.client);
  assert.deepEqual(f.state.clientOptions, {...f.args.options,
    installation: {...f.args.options.installation, resolveSourceSecret: f.args.resolveSourceSecret}});
  assert.deepEqual(await closeRealRouteTransport(f.held), {transport: 'local', clientCloseResolved: true});
  await closeRealRouteTransport(f.held);
  assert.deepEqual(f.calls, ['client.open', 'client.close']);
});

test('real route HTTPS preserves the original installation and uses only the public Remote Client', async t => {
  const f = await fixture(t);
  await connectRealRouteTransport(f.held, f.args);
  for (const key of ['directory', 'sourceProfilePaths', 'effectProfilePath', 'authorization']) {
    assert.equal(f.state.hostOptions[key], f.args.options.installation[key]);
  }
  assert.equal(f.state.hostOptions.resolveSourceSecret, f.args.resolveSourceSecret);
  assert.equal(f.state.hostOptions.authenticate(`Bearer ${f.args.https.token}`), 'original-principal');
  assert.equal(f.state.hostOptions.authenticate('Bearer wrong'), undefined);
  assert.deepEqual(f.state.clientOptions, {mode: 'remote', durability: 'durable',
    endpoint: 'https://127.0.0.1:12345/', token: f.args.https.token});
  const report = await closeRealRouteTransport(f.held);
  assert.deepEqual(report, {transport: 'https', clientCloseResolved: true, serverClosed: true, hostClose: closed()});
  await closeRealRouteTransport(f.held);
  assert.deepEqual(f.calls, ['host.open', 'server.create', 'listen', 'client.open',
    'client.close', 'server.connections', 'server.close', 'host.close']);
});

test('real route never promotes absent false or pending Host close observations to release', async t => {
  for (const report of [undefined, null, false, {}, {...closed(), storeCleanupPending: true},
    {...closed(), authorizationCleanupPending: true}, {...closed(), diagnosticDeliveryPending: true},
    {...closed(), pendingRetention: ['original']}]) {
    const f = await fixture(t); f.state.report = report;
    await connectRealRouteTransport(f.held, f.args);
    await assert.rejects(closeRealRouteTransport(f.held), /retains cleanup responsibility/u);
    assert.equal(f.held.host, f.host); assert.equal(f.held.hostClose, report);
    assert.equal(f.held.client, undefined); assert.equal(f.held.server, undefined);
    f.state.report = closed(); await closeRealRouteTransport(f.held);
    assert.equal(f.calls.filter(x => x === 'host.open').length, 1);
    assert.equal(f.calls.filter(x => x === 'client.open').length, 1);
  }
});

test('real route retains only the failed original close handle and closes independent components', async t => {
  for (const failed of ['client', 'server', 'host']) {
    const f = await fixture(t); await connectRealRouteTransport(f.held, f.args); f.state.fail = failed;
    await assert.rejects(closeRealRouteTransport(f.held), error => error === f.error);
    assert.equal(f.held[failed], f[failed]);
    for (const other of ['client', 'server', 'host'].filter(x => x !== failed)) assert.equal(f.held[other], undefined);
    f.state.fail = undefined; await closeRealRouteTransport(f.held);
    for (const component of ['client', 'server', 'host']) {
      assert.equal(f.calls.filter(x => x === `${component}.close`).length, component === failed ? 2 : 1);
    }
  }
});

test('real route preserves an initialization cleanup handle and refuses reopening that generation', async t => {
  const f = await fixture(t), handle = {status: () => ({pending: true})};
  const failure = Object.assign(new Error('original initialization control'), {cleanupPending: true, cleanupHandle: handle});
  f.state.openFailure = failure;
  await assert.rejects(connectRealRouteTransport(f.held, f.args), error => error === failure);
  assert.equal(f.held.initializationFailure.cleanupHandle, handle);
  await assert.rejects(closeRealRouteTransport(f.held), error => error === failure);
  await assert.rejects(connectRealRouteTransport(f.held, f.args), /retains cleanup/u);
  assert.deepEqual(f.calls, ['host.open']);
});

test('real route refuses a non-loopback listener without claiming an unopened Client closed', async t => {
  const f = await fixture(t); f.state.address = '0.0.0.0';
  await assert.rejects(connectRealRouteTransport(f.held, f.args));
  const report = await closeRealRouteTransport(f.held);
  assert.equal(report.clientCloseResolved, null); assert.equal(report.serverClosed, true);
  assert.deepEqual(report.hostClose, closed());
  assert(!f.calls.includes('client.open'));
});

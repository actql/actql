// A fresh process uses the persisted public Run and original Checkpoint.
// Optional approval uses only synthetic fixture keys and the real signer API;
// it never manufactures a checkpoint or receipt. Packed tests load the product.
import assert from 'node:assert/strict';
import {sign} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {dirname, join} from 'node:path';
import {userInfo} from 'node:os';
import {setTimeout as delay} from 'node:timers/promises';
import {tableTestModule} from './table-test-modules.mjs';

const local = await tableTestModule(
  new URL('../embedded-local.mjs', import.meta.url), '@actql/local-node');
const open = local.connectEmbeddedLocal ?? local.connect;
const {options, ref, approval, retainedResult, transport} = JSON.parse(await readFile(process.argv[2], 'utf8'));
let host, server, client;
async function openClient() {
  if (transport !== 'HTTPS') return open(options);
  const {openInstalledRemoteHttpHost} = await tableTestModule(
    new URL('../embedded-local.mjs', import.meta.url), '@actql/local-node/http-host');
  const {connect} = await tableTestModule(
    new URL('../../../packages/sdk/index.mjs', import.meta.url), '@actql/sdk');
  const directory = dirname(process.argv[2]);
  host = await openInstalledRemoteHttpHost({...options.installation,
    authenticate: header => header === 'Bearer table-fixture' ? userInfo().username : undefined});
  server = createServer({key: await readFile(join(directory, 'host.key')),
    cert: await readFile(join(directory, 'host.crt'))}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return connect({mode: 'remote', durability: 'durable', token: 'table-fixture',
    endpoint: `https://127.0.0.1:${server.address().port}/`});
}
try {
  client = await openClient();
  const run = await client.attach(ref);
  let state = await run.status();
  assert.equal(state.status, 'waiting_checkpoint');
  if (retainedResult === undefined) assert.deepEqual(state.result_availability, {});
  const checkpoints = (await client.checkpoints()).items;
  assert.equal(checkpoints.length, 1);
  if (approval !== undefined) {
    assert.equal(checkpoints[0].checkpointCid, approval.checkpointCid);
    const answer = await client.resolveCheckpoints([
      {checkpoint: checkpoints[0], decision: 'approved'},
    ], {signer: {
      keyId: approval.keyId, reviewerId: approval.reviewerId,
      authorityScopeCid: ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, approval.privateKey),
    }});
    assert.deepEqual(answer.results.map(result => result.status), ['committed']);
    const signal = AbortSignal.timeout(30000);
    for (;;) {
      signal.throwIfAborted();
      state = await run.wait({signal});
      if (!['running', 'resuming'].includes(state.status)) break;
      await delay(20, undefined, {signal});
    }
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    if (retainedResult === undefined) assert.deepEqual(state.result_availability, {});
  }
  let observedResult;
  if (retainedResult !== undefined && approval !== undefined) {
    assert.deepEqual(Object.keys(state.result_availability), [retainedResult.name]);
    assert.equal(state.result_availability[retainedResult.name].state, 'available');
    const result = run.result(retainedResult.name);
    observedResult = {name: retainedResult.name, rows: await result.all(),
      columns: (await result.describe()).columns};
    assert.deepEqual(observedResult, retainedResult);
  }
  process.stdout.write(JSON.stringify({status: state.status,
    result_availability: state.result_availability,
    ...(observedResult === undefined ? {} : {observedResult})}) + '\n');
} finally {
  try { if (client) await client.close(); }
  finally {
    try {
      if (server?.listening) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
    } finally {
      if (host) {
        const closed = await host.close();
        assert.equal(closed.storeCleanupPending, false);
        assert.equal(closed.authorizationCleanupPending, false);
        assert.deepEqual(closed.pendingRetention, []);
      }
    }
  }
}

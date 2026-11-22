import assert from 'node:assert/strict';
import {once} from 'node:events';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';

const [input] = await once(process, 'message');
const {directory, effectProfilePath, authorization, key, cert, owner, ref, readResult} = input;
setDefaultCACertificates([...getCACertificates('default'), cert]);
const host = await openInstalledRemoteHttpHost({directory, effectProfilePath,
  authenticate: header => header === 'Bearer owner-token' ? owner : undefined,
  resolveEffectSecret: async () => 'test-only-token', authorization});
const server = createServer({key, cert}, host.handler);
let client;
let outcome;
let primary;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'owner-token', durability: 'durable'});
  const original = await client.attach(ref);
  assert.deepEqual(original.ref, ref);
  const state = await original.status();
  const rows = readResult ? await original.result('answer').all() : undefined;
  outcome = {pid: process.pid, runId: state.run_id, status: state.status, rows};
} catch (error) {
  primary = error;
} finally {
  for (const close of [
    () => client?.close(),
    () => {
      server.closeAllConnections();
      if (server.listening) {
        return new Promise((resolve, reject) => server.close(error =>
          error ? reject(error) : resolve()));
      }
    },
    () => host.close(),
  ]) {
    try { await close(); } catch (error) { primary ??= error; }
  }
}
if (primary) throw primary;
await new Promise((resolve, reject) => process.send({...outcome, firstClose: true},
  error => error ? reject(error) : resolve()));
process.disconnect();

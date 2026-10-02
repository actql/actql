// Fresh process, installed packages only: restore published Results, without
// submitting source or invoking a compiler to recreate missing data.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';

const retained = JSON.parse(await readFile('retained-string-results.json', 'utf8'));
const sourceProfilePath = resolve('source-profile.json');
function accepted(directory) {
  const db = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'),
    {readOnly: true});
  try { return db.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count; }
  finally { db.close(); }
}
async function readRetained(mode, options, directory) {
  const before = accepted(directory);
  const client = await connect(options);
  try {
    const item = retained[mode];
    const execution = await client.attach(item.ref);
    assert.equal((await execution.status()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), item.expected);
    assert.deepEqual((await execution.result('answer').describe()).columns, item.columns);
    assert.equal(accepted(directory), before, 'restoring Results creates no Run');
    console.log(`Exact strings retained after fresh ${mode} Host process`);
  } finally { client.close(); }
}
await readRetained('local', {mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('local-state'), sourceProfilePath}}, 'local-state');
const host = await openInstalledRemoteHttpHost({directory: resolve('remote-state'),
  sourceProfilePath, authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await readRetained('remote', {mode: 'remote', durability: 'durable',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'}, 'remote-state');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}

import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {exercisePublicQueryInput} from './public-query-input.mjs';

// Authored independently of both the Program and the README's displayed rows.
const rows = [{customer_id: 'c1', order_count: 1, total_amount: 120},
  {customer_id: 'c2', order_count: 1, total_amount: 80}];
assert.deepEqual((await readFile('answer.jsonl', 'utf8')).trimEnd()
  .split('\n').map(line => JSON.parse(line)), rows);
const ref = JSON.parse(await readFile('run.json', 'utf8'));
const local = await connect({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('actql-state')}});
try {
  assert.deepEqual((await local.lookupRequest('customer-open-orders')).ref, ref);
  const attached = await local.attach(ref);
  assert.equal((await attached.wait()).status, 'succeeded');
  assert.deepEqual(await attached.result('main').all(), rows);
} finally { local.close(); }

const host = await openInstalledRemoteHttpHost({directory: resolve('readme-http-state'),
  authenticate: header => header === 'Bearer readme-fixture' ? userInfo().username : undefined});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
try {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  await exercisePublicQueryInput(connect, {mode: 'remote', durability: 'durable',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'readme-fixture'},
  {requestPrefix: 'readme-http', observe: () => {
    const journal = new DatabaseSync(resolve('readme-http-state/requests/client-requests.sqlite3'),
      {readOnly: true});
    try { return {acceptedRuns: journal.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n,
      sourceIo: 0}; } finally { journal.close(); }
  },
    successes: [{name: 'open-orders', format: 'yaml',
      text: await readFile('query.aql', 'utf8'), results: {main: {rows}}}], refusals: []});
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
console.log('README quickstart: independent Local/HTTPS named rows, order and termination passed');

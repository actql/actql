// Installed public APIs only. SDK transport replies are independent fixture
// DATA; Local alone opens the actual installed Host and executes a query.
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {createServer} from 'node:http';
import {join, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';

const [profile, expectedVersion] = process.argv.slice(2);
assert.equal(process.versions.node, expectedVersion);
assert(['sdk', 'local'].includes(profile));
const name = profile === 'sdk' ? '@actql/sdk' : '@actql/node';
const entry = realpathSync(fileURLToPath(import.meta.resolve(name)));
const suffix = relative(realpathSync(join(process.cwd(), 'node_modules')), entry);
assert(suffix && suffix !== '..' && !suffix.startsWith('../') && !isAbsolute(suffix),
  'Version consumer resolved outside its installed packages');
const api = await import(name);
if (profile === 'local') {
  const client = await api.open({stateDir: join(process.cwd(), 'state')});
  try { assert.deepEqual(await client.sql('SELECT 42 AS n').all(), [{n: 42}]); }
  finally { await client.close(); }
} else {
  const calls = [], failures = [];
  const ref = {namespaceId: 'version-smoke', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
    runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  const profileReply = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
    durability: 'durable', workspaceId: 'versions', scopeRef: 'version-smoke', capabilities: [],
    submissionEpoch: {version: 'actql-submission-epoch/0.1', authorityScopeCid: ref.authorityScopeCid,
      epochNonce: 'b'.repeat(64), authenticator: 'c'.repeat(64), notBefore: 1800000000000, expiresAt: 1800000001000},
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
      maxRetainedValueBytes: 4096, maxRows: 2, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
  const server = createServer(async (request, response) => {
    try {
      let text = ''; for await (const chunk of request) text += chunk;
      const body = JSON.parse(text), operation = request.url.split('/').at(-1); calls.push(operation);
      assert.equal(request.headers.authorization, 'Bearer version-fixture');
      assert.equal(body.connection.workspaceId, 'versions');
      if (operation === 'read') {
        response.writeHead(200, {'content-type': 'application/x-ndjson'});
        response.end('{"n":42}\n\x1e'); return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      assert(['connect', 'attach'].includes(operation));
      response.end(JSON.stringify(operation === 'connect' ? profileReply : {ref, durability: 'durable', revision: 1}));
    } catch (error) { failures.push(error); response.writeHead(500); response.end('{}'); }
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  let client;
  try {
    client = await api.connect(`actql://localhost:${server.address().port}/versions?transport=http`, {token: 'version-fixture'});
    assert.deepEqual(await (await client.attach(ref)).result('answer').all(), [{n: 42}]);
  } finally {
    try { await client?.close(); }
    finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  }
  assert.deepEqual(failures, []); assert.deepEqual(calls, ['connect', 'attach', 'read']);
}
console.log(JSON.stringify({profile, node: process.versions.node, installed: true,
  publicApiRoundtrip: true, closed: true, localHost: profile === 'local'}));

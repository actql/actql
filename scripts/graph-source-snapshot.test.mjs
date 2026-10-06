import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';

const packed = process.env.ACTQL_GRAPH_PACKED === '1';
const {connect} = await import(packed ? '@actql/sdk' : '../packages/sdk/index.mjs');
const {connectEmbeddedLocal, openInstalledRemoteHttpHost} = await import(packed
  ? new URL('./adapters/host-node/embedded-local.mjs', import.meta.resolve('@actql/local-node'))
  : '../adapters/host-node/embedded-local.mjs');
const scratch = new URL(packed ? './source-snapshot-state/'
  : '../_build/graph-source-snapshot/', import.meta.url);
await mkdir(scratch, {recursive: true});

// Authored source and oracle: two independently keyed self-loops allow exactly
// two ordered TRAIL paths of length two. Neither parser output nor a product
// snapshot encoder is used to construct this expectation.
const source = `
DATA n = SELECT 1 AS id;
DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst
  UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES)
  EDGE TABLES (e AS E KEY (key)
    SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N
    LABEL R NO PROPERTIES)
);
FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->(:Node)-[:R]->(:Node)
  |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths
`;
const expectedRows = [{depth: 2}, {depth: 2}];
const expectedColumns = [{name: 'depth', contract: {type: 'number', nullable: false}}];

for (const mode of ['local', 'remote']) {
  test(`authored Graph source preserves parallel edges through snapshot and ${mode} Result`,
    {timeout: 60_000}, async t => {
      const directory = await mkdtemp(new URL(`${mode}-`, scratch));
      const events = [];
      const completed = new Map();
      const waiters = new Map();
      const keys = generateKeyPairSync('ed25519');
      const authorization = {
        accountConfiguration: canonicalText({
          version: 'actql-execution-account-config/0.1', account_id: 'source-snapshot-owner',
          entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
            connection: {all: true}, resource: {all: true}, operation: {all: true}, exclusions: []}],
        }),
        hostKey: {keyId: 'source-snapshot-host',
          privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        reviewers: [{keyId: 'source-snapshot-reviewer', reviewerId: 'source-snapshot-reviewer',
          principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        faultInjection(name, detail) {
          events.push(name);
          if (name === 'computed') {
            completed.set(detail.ref.runDefinitionCid, detail.carrierSnapshots);
            waiters.get(detail.ref.runDefinitionCid)?.();
          }
        },
      };
      let client;
      if (mode === 'local') {
        client = await connectEmbeddedLocal({mode, owner: 'local', installation: {directory, authorization}});
      } else {
        const host = await openInstalledRemoteHttpHost({directory, authorization,
          authenticate: header => header === 'Bearer source-snapshot-token' ? userInfo().username : undefined});
        t.after(() => host.close());
        let material;
        if (packed) {
          const read = name => readFile(new URL(`./tls/${name}`, import.meta.url));
          material = {ca: await read('ca.crt'), siteKey: await read('site.key'),
            siteCertificate: await read('site.crt')};
        } else {
          const {certificates} = await import('../adapters/site-node/https-agent-harness.mjs');
          material = await certificates(await mkdtemp(new URL('tls-', scratch)));
        }
        const previousCAs = getCACertificates('default');
        setDefaultCACertificates([...previousCAs, material.ca.toString('utf8')]);
        t.after(() => setDefaultCACertificates(previousCAs));
        const server = createServer({key: material.siteKey, cert: material.siteCertificate}, host.handler);
        await new Promise((resolve, reject) => {
          server.once('error', reject);
          server.listen(0, '127.0.0.1', resolve);
        });
        t.after(async () => {
          server.closeAllConnections();
          await new Promise(resolve => server.close(resolve));
        });
        client = await connect({mode, endpoint: `https://127.0.0.1:${server.address().port}/`,
          token: 'source-snapshot-token'});
      }
      t.after(() => client.close());
      const requestId = `source-snapshot-${mode}`;
      const run = await client.aql(source, {format: 'aql-text', requestId});
      assert.equal((await run.wait()).status, 'succeeded');
      assert.deepEqual(await run.result('paths').all(), expectedRows);
      assert.deepEqual((await run.result('paths').describe()).columns, expectedColumns);
      if (!completed.has(run.ref.runDefinitionCid)) {
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => {
            waiters.delete(run.ref.runDefinitionCid);
            reject(new Error('SourceSnapshotCompletionNotObserved'));
          }, 15_000);
          waiters.set(run.ref.runDefinitionCid, () => {clearTimeout(timer); resolve();});
        });
      }
      const snapshots = completed.get(run.ref.runDefinitionCid);
      assert.equal(snapshots.length, 1, 'one constructed Graph is saved and restored by the existing owner');
      const [snapshot] = snapshots;
      assert.match(snapshot.cid, /^sha256:[0-9a-f]{64}$/u);
      assert.ok(snapshot.bytes > 0);
      assert.equal(snapshot.verifiedReadBytes, snapshot.bytes);
      assert.equal(snapshot.sourceReleased, true);
      assert.equal(snapshot.restored, true);
      assert.equal(snapshot.temporaryBodyReclaimed, true);
      assert.deepEqual(await readdir(`${directory}/carrier-snapshots`), []);
      const beforeReuse = events.length;
      assert.deepEqual(await (await client.attach(run.ref)).result('paths').all(), expectedRows);
      assert.deepEqual((await client.aql(source, {format: 'aql-text', requestId})).ref, run.ref);
      assert.equal(events.length, beforeReuse, 'read/attach/request reuse dispatches no new work');
      assert.equal(completed.size, 1);
      t.diagnostic('Authored source → ordinary Host → saved/restored Graph → TRAIL Named Result; no independent exact snapshot CID claim');
    });
}

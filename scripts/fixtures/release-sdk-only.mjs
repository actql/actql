// Run from an installation containing only sdk and client-wire. The actual
// HTTPS Host runs separately in the standard Node consumer.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {connect, getSubmissionInput} from '@actql/sdk';
const readme = await readFile(new URL('./node_modules/@actql/sdk/README.md', import.meta.url), 'utf8');
const example = /## Remote quickstart[\s\S]*?```js\n([\s\S]*?)```/u.exec(readme)?.[1];
assert(example, 'Missing standalone SDK README example');
const path = new URL('./readme-example.mjs', import.meta.url);
await writeFile(path, example);
const result = spawnSync(process.execPath, [path.pathname], {encoding: 'utf8', timeout: 60_000,
  env: {...process.env, ACTQL_ENDPOINT: process.env.ACTQL_RELEASE_TEST_ENDPOINT, ACTQL_TOKEN: 'short-token'}});
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stdout.trim(), '[ { id: 1 } ]', 'Independent SDK README result');
const client = await connect({mode: 'remote', endpoint: process.env.ACTQL_RELEASE_TEST_ENDPOINT,
  token: 'short-token'});
try {
  const query = client.sql('SELECT 17 AS id', undefined,
    {submissionRef: client.newSubmission({nonce: 'release-sdk-only'})});
  const requestId = query.requestId;
  const result = await query;
  assert.equal(getSubmissionInput(result).requestId, requestId);
  assert.deepEqual(await result.all(), [{id: 17}]);
  const recovery = client.recoverRequest(result), observed = await recovery.lookup();
  assert.equal(observed.kind, 'ready');
  assert.deepEqual((await recovery.attach(observed)).ref, result.execution.ref);
  assert.deepEqual(await result.all(), [{id: 17}]);
  console.log('SDK-only registry consumer: real HTTPS, independent Result and original request lookup passed');
} finally {await client.close();}

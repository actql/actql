import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {resolve} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {selectReleaseSourcefreeQueryCases} from '../release-sourcefree-query-cases.mjs';
import {exercisePublicQueryInput} from './public-query-input.mjs';
import {guardReleaseSourcefreeIo} from './release-sourcefree-io.mjs';

const mode = process.argv[2];
assert.ok(['local', 'https'].includes(mode), 'Select one installed transport');
const directory = resolve(`sourcefree-${mode}`);
const reviewer = generateKeyPairSync('ed25519'), hostKey = generateKeyPairSync('ed25519');
const authorization = {
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: `release-sourcefree-${mode}`, entries: [{entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: hostKey.privateKey.export({type: 'pkcs8', format: 'pem'})},
};
const cases = selectReleaseSourcefreeQueryCases(), completed = [];
let host, server;
const io = guardReleaseSourcefreeIo();
try {
  // No Source/Effect/Model installation or external Provider is added. These
  // public factories and their bundled Owners are the execution implementation.
  const {open} = await import('@actql/node');
  const {connect} = await import('@actql/sdk');
  let connectClient, options;
  if (mode === 'local') {
    connectClient = open;
    options = {stateDir: directory, durability: 'durable', installation: {
      sourceProfilePaths: [], authorization, resolveSourceSecret: io.resolveSourceSecret}};
  } else {
    const {openInstalledRemoteHttpHost} = await import('@actql/local-node/http-host');
    host = await openInstalledRemoteHttpHost({directory, sourceProfilePaths: [], authorization,
      resolveSourceSecret() {return io.resolveSourceSecret();},
      authenticate: header => header === 'Bearer sourcefree-test' ? userInfo().username : undefined});
    server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    const endpoint = `https://127.0.0.1:${server.address().port}/`;
    io.allowTransportOrigin(new URL(endpoint).origin);
    connectClient = connect;
    options = {mode: 'remote', endpoint, token: 'sourcefree-test'};
  }
  const observe = () => {
    io.assertQuiet();
    const journal = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
    try {
      // Same durable admission fact as the existing public query harness.
      // Row/session zero is scoped to no installed Source readers and quiet
      // process/fetch/secret guards, not arbitrary filesystem I/O or Providers.
      return {acceptedRuns: journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count,
        sourceIo: io.attemptedProviderIo(), sourceReads: 0, sourceReadSessions: 0};
    } finally {journal.close();}
  };
  await exercisePublicQueryInput(connectClient, options, {
    requestPrefix: `release-${mode}`, observe, ...cases,
    completedCase({name, ref, submissionRef, observedResults, beforeSubmit, beforeRead}) {
      completed.push({name, ref, submissionRef, observedResults, beforeSubmit, beforeRead});
    },
  });
  assert.equal(completed.length, 4);
  assert.equal(observe().acceptedRuns, 4);
  io.assertQuiet();
  await writeFile(`sourcefree-${mode}.json`, JSON.stringify({mode,
    successNames: completed.map(value => value.name), refusalNames: cases.refusals.map(value => value.name),
    completed, providerObservation: io.snapshot(),
    observationScope: 'Empty Source inventory; process/fetch/secret guards and read-only durable Run admission. Store filesystem I/O is not Source I/O.'}, null, 2) + '\n', {flag: 'wx'});
} finally {
  try {if (server) await new Promise(resolve => server.close(resolve));}
  finally {try {await host?.close();} finally {io?.close();}}
}

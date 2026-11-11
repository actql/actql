// Exercise the installed Host configuration entry, not a post-lowering edit.
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const {directory, entrance, output, ref, submissionRef: originalSubmission,
  interruptAfterRows, originalAttemptId} = JSON.parse(process.argv[2]);
// Observe the Store's actual durable issuance records independently of SDK
// calls. New START commits keep these originals in the native index, without
// legacy deliveries/*/attempt.json or contracts/*.json locator copies. This
// read-only, single-statement snapshot never claims or reopens an attempt.
// Three rows are enough to expose an unexpected third issue in this fixture.
function savedAdmissions() {
  const database = new DatabaseSync(join(directory, 'host/publication/delivery-attempts.sqlite3'),
    {readOnly: true, allowExtension: false});
  try {
    return database.prepare(`SELECT a.attempt_cid, a.run_cid, a.grant_cid,
      a.attempt_wire, a.grant_wire, a.ready, i.initial_cid, u.uses
      FROM attempts AS a LEFT JOIN initial_records AS i USING(attempt_cid)
      LEFT JOIN grant_uses AS u USING(grant_cid)
      ORDER BY a.attempt_cid LIMIT 3`).all();
  } finally {database.close();}
}
const keys = generateKeyPairSync('ed25519');
let computes = 0;
const authorization = {
  accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'read-row-capacity', entries: [{entry_id: 'owner-read', outcome: 'allow',
      principal: {any_of: [userInfo().username]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  observe(name, detail) {
    if (name === 'computed') computes++;
    console.log('INSTALLED_READ_121_OWNER', name, detail?.code ?? '', detail?.cause?.constructor?.name ?? '');
  },
};
const installation = {directory: join(directory, 'host'), authorization,
  ...(ref === undefined ? {valuesMaxRows: 121} : {})};
let client, host, server;
const originalCAs = getCACertificates('default');
try {
  if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation});
  else {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(directory, name))));
    setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => userInfo().username});
    server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'fixture-token', endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  console.log('INSTALLED_READ_121_PHASE', 'connected');
  const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
  const submissionRef = originalSubmission ?? client.newSubmission({nonce: 'installed-read-121'});
  if (originalSubmission === undefined) await writeFile(join(directory, 'submission-ref.json'),
    JSON.stringify(submissionRef), {flag: 'wx', mode: 0o600});
  const run = ref === undefined ? await client.start(program, {submissionRef}) : await client.attach(ref);
  console.log('INSTALLED_READ_121_PHASE', 'submitted');
  const status = await run.wait({signal: AbortSignal.timeout(15000)});
  console.log('INSTALLED_READ_121_PHASE', 'terminal', status.status);
  const request = await client.lookupSubmission(submissionRef);
  console.log('INSTALLED_READ_121_PHASE', 'request-found');
  const result = run.result('answer');
  let originalFirst, originalSecond, lookupBefore, lookupAfter;
  if (originalAttemptId !== undefined) {
    lookupBefore = savedAdmissions();
    originalFirst = await result.deliveryAttempt(originalAttemptId);
    originalSecond = await result.deliveryAttempt(originalAttemptId);
    lookupAfter = savedAdmissions();
  }
  const description = await result.describe();
  console.log('INSTALLED_READ_121_PHASE', 'described');
  const reader = result.rows();
  const rows = [];
  for await (const row of reader) {
    rows.push(row);
    if (rows.length === interruptAfterRows) break;
  }
  console.log('INSTALLED_READ_121_PHASE', 'read', rows.length);
  const attempt = await result.deliveryAttempt(reader.attemptId);
  const originalAfterRead = originalAttemptId === undefined ? undefined :
    await result.deliveryAttempt(originalAttemptId);
  const admissions = savedAdmissions();
  const attempts = admissions.map(row => row.attempt_wire);
  const grants = admissions.map(row => JSON.parse(row.grant_wire));
  console.log('INSTALLED_READ_121_PHASE', 'receipt', attempt.record?.state);
  await writeFile(output, JSON.stringify({pid: process.pid, ref: run.ref, submissionRef, status, request,
    description, rows, attempt, readState: reader.state(), rowsYielded: reader.rowsYielded(), computes,
    originalFirst, originalSecond, originalAfterRead, lookupBefore, lookupAfter, admissions, attempts, grants}));
} catch (error) {
  console.log('INSTALLED_READ_121_FAILURE', error.code ?? error.name, error.message);
  throw error;
} finally {
  await client?.close();
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  await host?.close();
  setDefaultCACertificates(originalCAs);
}

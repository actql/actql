import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual Common/Account/Credential/SQLite-use/TLS boundary. The original-Job
// callback is an explicit assembly double, not a durable Run Journal supplier.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {moon, originalBigQueryRowOwner, jobBody, resultBody} from './bigquery-read.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {readBigQuerySqlApi, BIGQUERY_SQL_READ_OPERATION} from '../site/bigquery-sql-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const cid = digit => `sha256:${digit.repeat(64)}`;
export const selectedFields = Object.freeze([
  {name: 'ACCOUNT_ID', type: 'STRING', mode: 'REQUIRED'},
  {name: 'ACTIVE_USERS', type: 'INT64', mode: 'REQUIRED'},
  {name: 'TREND', type: 'STRING', mode: 'NULLABLE'},
]);
export const exactRows = Object.freeze([
  ['a1', '-9223372036854775808', 'down'], ['a2', '9223372036854775807', null],
]);
export const bounds = Object.freeze({maxBytes: 4096, maxNodes: 1000, maxDepth: 16,
  maxFields: 16, maxNameBytes: 4096, maxSchemaBytes: 4096, maxRows: 2, maxTotalRows: 2n,
  maxValueNodes: 1000, maxValueTextBytes: 4096, maxJobBytes: 1024, maxPageTokenBytes: 256,
  maxPages: 4, maxResults: 2, timeoutMs: 0, maxRequests: 8, maxRequestBytes: 8192,
  maxSecretBytes: 1024, pollDelayMs: 0, maximumBytesBilled: 1000000n});
export {jobBody};

export function rowsBody(jobId, options = {}) {
  return resultBody(jobId, {rows: exactRows, selectedFields, ...options});
}

export async function bigqueryHttpsFixture(t, {accountOutcome = 'allow'} = {}) {
  const parent = join(repo, '_build/bigquery-https-fixtures');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'original-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', 'server.key', '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
  const [key, ca] = await Promise.all([readFile(join(root, 'server.key')),
    readFile(join(root, 'server.crt'))]);
  const state = {requests: [], sockets: new Set(), resolutions: 0, currentCalls: 0,
    originals: [], onRequest: undefined, beforeCurrent: undefined, resolve: undefined};
  const server = createServer({key, cert: ca}, async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const entry = {method: request.method, path: request.url,
      headers: {...request.headers}, body: Buffer.concat(chunks).toString('utf8')};
    state.requests.push(entry);
    try {
      const answer = state.onRequest ? await state.onRequest(entry, request, response)
        : {body: entry.method === 'POST' ? jobBody(row.requestId) : rowsBody(row.requestId)};
      if (answer === undefined) return;
      response.writeHead(answer.status ?? 200, {'content-type': 'application/json', ...answer.headers});
      response.end(Buffer.from(answer.body));
    } catch (error) { response.destroy(error); }
  });
  server.on('connection', socket => {
    state.sockets.add(socket); socket.once('close', () => state.sockets.delete(socket));
  });
  let row, journal;
  t.after(async () => {
    row?.close();
    if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    journal?.close();
    const stopped = Promise.all([...state.sockets].map(socket =>
      new Promise(resolve => socket.once('close', resolve))));
    await new Promise(resolve => server.close(resolve));
    await stopped;
    assert.equal(state.sockets.size, 0);
    t.diagnostic(`Retained BigQuery physical fixture: ${root}`);
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  row = await originalBigQueryRowOwner({selectedFields});
  const control = runtimeCore(moon).remoteCredentialControl;
  const authority = generateKeyPairSync('ed25519');
  journal = openSqliteCredentialJournal(join(root, 'credential-journal'), {
    credentialAuthorities: new Map([['bigquery-fixture', new Map([['key', authority.publicKey]])]])});
  const frame = Object.freeze({acquisition: row.acquisition, run: row.run,
    requestId: row.requestId, runInvocationCid: cid('b'), dispatchRequestCid: cid('c')});
  const scope = Object.freeze({issuerAuthority: 'bigquery-fixture', principal: 'operator',
    namespaceId: 'fixture', environment: 'test', siteKey: 'site', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'bigquery', connectorRevision: 'bigquery/0.1',
    resourceOrigin: `https://127.0.0.1:${server.address().port}`, operation: BIGQUERY_SQL_READ_OPERATION,
    runInvocationCid: frame.runInvocationCid, taskAttempt: 1, dispatchRequestCid: frame.dispatchRequestCid,
    expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 8});
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key', privateKey: authority.privateKey}), control);
  const accountPath = join(root, 'account.json');
  const writeAccount = outcome => writeFile(accountPath, canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'fixture', entries: [{
      entry_id: 'table-read', outcome, principal: {all: true}, connection: {any_of: ['bigquery:fixture']},
      resource: {any_of: ['usage_30d']}, operation: {any_of: ['read']}, exclusions: []}]}));
  await writeAccount(accountOutcome);
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath,
    principal: 'operator', context: {principal: 'operator', contextCid: cid('d')}});
  const verifyRead = async () => {
    state.currentCalls++;
    await state.beforeCurrent?.(state.currentCalls);
    const decision = await gate.authorize('acquisition',
      {connection: 'bigquery:fixture', resource: 'usage_30d', operation: 'read'},
      {subjectCid: scope.runInvocationCid});
    if (decision.action !== 'dispatch') throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied', decision});
  };
  const job = checked(moon.clientProgramBigQueryOriginalJob('acme-project', row.requestId, 'EU', 1024));
  const withOriginalJob = async (original, sendOriginal) => {
    assert.equal(original.frame.run, row.run);
    assert.equal(original.frame.acquisition, row.acquisition);
    assert.equal(original.frame.requestId, row.requestId);
    assert.equal(moon.clientProgramBigQueryJobOriginalRecordMatchesRequest(
      original.jobRead, original.request, original.record), true);
    assert.equal(original.wire, moon.clientProgramBigQueryJobOriginalRecordWire(original.record));
    // Explicit test assembly callback. This supplies no production durable CAS.
    state.originals.push(original);
    return sendOriginal();
  };
  const options = {moon, prepared: row.prepared, rowRun: frame, job, limits: bounds,
    authorizationFor: async sequence => ({grant, scope, useId: `bq-${row.requestId}-${sequence}`}),
    credential: {control, journal, ca, resolveSecret: async () => {
      state.resolutions++; await state.resolve?.(); return 'bigquery-fixture-secret';
    }}, verifyRead, withOriginalJob};
  return {root, moon, state, row, frame, scope, grant, control, journal, options,
    writeAccount, read: overrides => readBigQuerySqlApi({...options, ...overrides})};
}

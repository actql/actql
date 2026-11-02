import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Controlled physical boundary: genuine Common contracts, Account authority,
// credential control, SQLite use journal and loopback TLS. No live Snowflake,
// installed release, normal funding profile or Python runtime is claimed.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {readSnowflakeSqlApi, SNOWFLAKE_SQL_READ_OPERATION} from '../site/snowflake-sql-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const read = name => readFile(join(repo, name), 'utf8');
const cid = digit => `sha256:${digit.repeat(64)}`;
import {decimal38, readLimits, pending, resultBody, metadataBody} from './snowflake-response.fixture.mjs';
export {decimal38, readLimits, pending, resultBody, metadataBody};

async function originalRowOwner(descriptionBody) {
  const responseLimits = moon.clientProgramSnowflakeResponseLimits(4096, 1000,
    16, 16, 256, 128, 4, 3, 3n);
  const descriptionLimits = moon.clientProgramSnowflakeDescriptionLimits(16,
    4096, 4096, 1000, 16);
  const declarationLimits = moon.clientProgramSnowflakeDeclarationLimits(200000,
    20000, 32, 1, 3);
  const description = checked(moon.clientProgramSnowflakeDescribeTable('PRODUCT',
    'USAGE', 'USAGE_30D', [descriptionBody], responseLimits, descriptionLimits));
  const declaration = checked(moon.clientProgramSnowflakeGenerateReadDeclaration(
    description, 'usage_30d', 'snowflake', 'snowflake/0.1', descriptionLimits, declarationLimits));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(check);
  const view = declared.views[0];
  const publication = JSON.stringify({environmentCid: environment.evidenceCid,
    aliases: [{name: 'snowflake.usage_30d', sourceRef: view.source_ref,
      sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]});
  const outcome = moon.clientProgramPrepareSourceWithParameters(
    'SELECT ACCOUNT_ID, ACTIVE_USERS, TREND FROM snowflake.usage_30d',
    'sql', check, publication, undefined, undefined);
  const program = moon.clientProgramPreparationReady(outcome);
  assert.ok(program, `ordinary SQL must prepare the original declared input: ${
    moon.clientProgramPreparationIssueCode(outcome)}`);
  const [registryWire, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const values=JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const registry=checked(moon.clientPrepareInstalledSequenceContracts(registryWire,values,fragment,ordered));
  const requirement=checked(moon.clientProgramPrepareLocalQueryRequirement(program,0,0,registry,values,fragment,ordered));
  const prepared = checked(moon.clientProgramSnowflakePrepareRead(description,
    declaration, requirement, query, evidence, descriptionLimits, declarationLimits));
  const acquisition = moon.clientProgramSnowflakeReadAcquisition(prepared);
  // Explicit test units, not normal product prices. This is the same ledger
  // and original run consumed by the physical driver, never a second root.
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 8192n,
    100000000n, 100000000n, 0));
  const requestId = randomUUID();
  const run = checked(moon.clientProgramRowSourceStartAccounted(acquisition,
    requestId, () => true, ledger, 8192n, 4096n));
  checked(moon.clientProgramRowSourceBegin(run, 4096, 2, 2, undefined));
  return {prepared, acquisition, run, ledger, requestId, requirement,
    originals: {description, declaration, declared, environment, program,
      descriptionLimits, declarationLimits, registry,
      values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])},
    usage: () => moon.clientProgramMultiCapturedLedgerUsage(ledger),
    assertNoCapture: () => assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)),
      {code: 'MoonBitHostFailure'}),
    captureRows() {
      checked(moon.clientProgramRowSourceFinish(run));
      const captured = checked(moon.clientProgramRowSourceCapture(run));
      const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
      const exported = checked(moon.clientProgramExportSourceCapture(source,
        requirement, 'snowflake-original-row-test'));
      return moon.clientProgramSourceCaptureExportRows(exported);
    },
    close: () => checked(moon.clientProgramRowSourceCloseAccounted(run))};
}

export async function snowflakeFixture(t, {accountOutcome = 'allow',
  descriptionBody = metadataBody()} = {}) {
  const originalDescription = Buffer.from(descriptionBody);
  const parent = join(repo, '_build/snowflake-read-fixtures');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'original-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', 'server.key', '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
  const [key, ca] = await Promise.all([readFile(join(root, 'server.key')),
    readFile(join(root, 'server.crt'))]);
  const state = {requests: [], sockets: new Set(), secret: 'snowflake-fixture-secret',
    resolutions: 0, currentCalls: 0, responseBytes: 0, onRequest: undefined,
    resolve: undefined, beforeCurrent: undefined};
  const server = createServer({key, cert: ca}, async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const entry = {method: request.method, path: request.url,
      headers: {...request.headers}, body: Buffer.concat(chunks).toString('utf8')};
    state.requests.push(entry);
    try {
      const answer = state.onRequest ? await state.onRequest(entry, request, response)
        : {body: resultBody()};
      if (answer === undefined) return;
      const body = Buffer.from(answer.body);
      state.responseBytes += body.byteLength;
      response.writeHead(answer.status ?? 200, {'content-type': 'application/json',
        ...(answer.headers ?? {})});
      response.end(body);
    } catch (error) { response.destroy(error); }
  });
  server.on('connection', socket => {
    state.sockets.add(socket); socket.once('close', () => state.sockets.delete(socket));
  });
  let row, journal;
  t.after(async () => {
    // Retained SQLite/certificates are new owned fixtures; never old Run/DBs.
    row?.close();
    if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    journal?.close();
    // The peer server's close callback can precede its sockets' close events.
    // Observe those exact events too; do not erase the set or infer peer stop
    // from the client's independently confirmed binding retirement.
    const peerStops = Promise.all([...state.sockets].map(socket =>
      new Promise(resolve => socket.once('close', resolve))));
    await new Promise(resolve => server.close(resolve));
    await peerStops;
    assert.equal(state.sockets.size, 0);
    t.diagnostic(`Retained Snowflake physical fixture: ${root}`);
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  row = await originalRowOwner(originalDescription);
  const control = runtimeCore(moon).remoteCredentialControl;
  const authority = generateKeyPairSync('ed25519');
  journal = openSqliteCredentialJournal(join(root, 'credential-journal'), {
    credentialAuthorities: new Map([['snowflake-fixture', new Map([['key', authority.publicKey]])]])});
  const frame = Object.freeze({acquisition: row.acquisition, run: row.run,
    requestId: row.requestId, runInvocationCid: cid('b'), dispatchRequestCid: cid('c')});
  const scope = Object.freeze({issuerAuthority: 'snowflake-fixture', principal: 'operator',
    namespaceId: 'fixture', environment: 'test', siteKey: 'site', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'snowflake',
    connectorRevision: 'snowflake/0.1', resourceOrigin: `https://127.0.0.1:${server.address().port}`,
    operation: SNOWFLAKE_SQL_READ_OPERATION, runInvocationCid: frame.runInvocationCid,
    taskAttempt: 1, dispatchRequestCid: frame.dispatchRequestCid,
    expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 8});
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key', privateKey: authority.privateKey}), control);
  const accountPath = join(root, 'account.json');
  const writeAccount = outcome => writeFile(accountPath, canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'fixture', entries: [{
      entry_id: 'table-read', outcome, principal: {all: true},
      connection: {any_of: ['snowflake:fixture']}, resource: {any_of: ['usage_30d']},
      operation: {any_of: ['read']}, exclusions: []}]}));
  await writeAccount(accountOutcome);
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath,
    principal: 'operator', context: {principal: 'operator', contextCid: cid('d')}});
  const verifyRead = async () => {
    state.currentCalls++;
    await state.beforeCurrent?.(state.currentCalls);
    const decision = await gate.authorize('acquisition',
      {connection: 'snowflake:fixture', resource: 'usage_30d', operation: 'read'},
      {subjectCid: scope.runInvocationCid});
    if (decision.action !== 'dispatch') throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied', decision});
  };
  const resolveSecret = async () => {
    state.resolutions++;
    await state.resolve?.();
    return state.secret;
  };
  const options = {moon, prepared: row.prepared, rowRun: frame, limits: readLimits,
    warehouse: 'ANALYTICS', role: 'READER', authenticationType: 'OAUTH',
    authorizationFor: async sequence => ({grant, scope, useId: `statement-${sequence}`}),
    credential: {control, journal, resolveSecret, ca}, verifyRead};
  return {root, moon, state, row, frame, scope, grant, control, journal, options,
    writeAccount, read: overrides => readSnowflakeSqlApi({...options, ...overrides})};
}

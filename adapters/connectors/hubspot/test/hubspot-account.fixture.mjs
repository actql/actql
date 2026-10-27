import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Owned component fixture: real Common permission/credential owners, SQLite
// and loopback TLS. No normal installed artifact, live service or numeric price.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import * as common from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from
  '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson, createLocalAuthorizationGate} from
  '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from
  '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from
  '../site/hubspot-account-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const control = runtimeCore(common).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const read = name => readFile(join(repo, name), 'utf8');

async function rowOwner(rowSchema, verifyOriginalTransport = () => false) {
  const schemaWire = rowSchema === undefined ? undefined : canonicalJson(rowSchema);
  const restore = rowSchema === undefined ? common.clientProgramRowSourceRestoreDeclaration
    : common.clientProgramRowSourceRestoreRelationDeclaration;
  const declaration = checked(restore(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{
      resource: 'records', resource_kind: 'record', ...(schemaWire === undefined ? {fields: [{
        name: 'id', type: 'string', nullable: false}]} : {schema_wire: schemaWire,
        schema_cid: `sha256:${createHash('sha256').update(schemaWire).digest('hex')}`})}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(
    (await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(check);
  const outcome = common.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: 'hubspot-identity-accounting', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'records'}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: ['id'], as: 'output'}],
      results: {r: {from: 'output', fields: ['id']}}}],
    results: {r: {from: {stage: 'scan', result: 'r'}}}}), 'json', check, undefined);
  const program = common.clientProgramPreparationReady(outcome);
  assert.ok(program);
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement = checked(common.clientProgramPrepareLocalQueryRequirement(
    program, 0, 0, registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const acquisition = checked(common.clientProgramRowSourcePrepareAcquisition(
    declaration, requirement, query, evidence));
  // Independent test units. This is not a normal Host retained/workspace price.
  const ledger = checked(common.clientProgramAcquisitionLedger(
    1, 1, rowSchema === undefined ? 8192n : 24576n, 100000000n, 100000000n, 0));
  const run = checked(common.clientProgramRowSourceStartAccounted(
    acquisition, randomUUID(), verifyOriginalTransport, ledger, rowSchema === undefined ? 8192n : 24576n, rowSchema === undefined ? 4096n : 8192n));
  checked(common.clientProgramRowSourceBegin(run, 4096, 2, 2, undefined));
  return {
    charge: bytes => checked(common.clientProgramRowSourceChargePage(run, bytes)),
    page: (rows, charge) => checked(common.clientProgramRowSourceAcceptChargedPage(
      run, charge, Buffer.from(JSON.stringify(rows)))),
    finish: () => checked(common.clientProgramRowSourceFinish(run)),
    captureCount: () => {
      const capture = checked(common.clientProgramRowSourceCapture(run));
      const source = checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(
        common.clientProgramIdentifyCapturedSourceRelation(source)));
    },
    consume: charge => checked(common.clientProgramRowSourceConsumeObservationCharge(run, charge)),
    usage: () => common.clientProgramMultiCapturedLedgerUsage(ledger),
    assertNoCapture: () => assert.throws(() => checked(
      common.clientProgramRowSourceCapture(run)), {code: 'MoonBitHostFailure'}),
    close: () => checked(common.clientProgramRowSourceCloseAccounted(run)),
  };
}

export async function accountFixture(t, {accounted = true, accountOutcome = 'allow',
  rowSchema, resources = ['account'], accountOperations = ['read']} = {}) {
  const parent = join(repo, '_build', 'hubspot-account-fixtures');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'identity-'));
  const openssl = args => execFileSync('openssl', args, {cwd: root, stdio: 'ignore'});
  openssl(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
    '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
  const [key, cert] = await Promise.all([
    readFile(join(root, 'server.key')), readFile(join(root, 'server.crt'))]);
  const state = {body: '{"portalId":7,"accountType":"STANDARD"}', status: 200,
    secret: 'provider-secret', requests: [], resolutions: 0, charges: 0, consumed: 0,
    currentCalls: 0, onRequest: undefined, resolve: undefined};
  const server = createServer({key, cert}, async (request, response) => {
    state.requests.push({method: request.method, path: request.url,
      authorization: request.headers.authorization});
    try {
      if (state.onRequest && await state.onRequest(request, response)) return;
      response.writeHead(state.status, {'content-type': 'application/json'});
      response.end(state.body);
    } catch (error) { response.destroy(error); }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  let journal, binding, row;
  // Register custody before later fallible fixture construction. A failed
  // declaration must not leave its already listening test server alive.
  t.after(async () => {
    const failures = [];
    try { if (binding) assert.equal(closeHttpsCredentialBinding(binding), 'closed'); }
    catch (cause) { failures.push(cause); }
    try {
      row?.close();
      if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    } catch (cause) { failures.push(cause); }
    try { journal?.close(); } catch (cause) { failures.push(cause); }
    try { await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
    catch (cause) { failures.push(cause); }
    t.diagnostic(`Retained owned HubSpot fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'HubSpotFixtureCleanupUnconfirmed');
  });
  const authority = generateKeyPairSync('ed25519');
  await Promise.all([
    writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({
      format: 'pem', type: 'pkcs8'}), {mode: 0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({
      format: 'pem', type: 'spki'})),
  ]);
  journal = openSqliteCredentialJournal(join(root, 'credential-journal'), {
    credentialAuthorities: new Map([['hubspot-fixture',
      new Map([['key', authority.publicKey]])]])});
  const scope = Object.freeze({issuerAuthority: 'hubspot-fixture', principal: 'operator',
    namespaceId: 'fixture', environment: 'test', siteKey: 'site', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'hubspot',
    connectorRevision: 'hubspot/0.1', resourceOrigin: `https://127.0.0.1:${server.address().port}`,
    operation: HUBSPOT_ACCOUNT_DETAILS_OPERATION, runInvocationCid: cid('b'),
    taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 1});
  const grant = control.prepare(scope);
  const sign = value => signRemoteCredentialGrant(value, control,
    {keyId: 'key', privateKey: authority.privateKey});
  journal.acceptGrant(sign(grant), control);
  const accountPath = join(root, 'account.json');
  const writeAccount = outcome => writeFile(accountPath, canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'fixture', entries: [{
      entry_id: 'identity-read', outcome, principal: {all: true},
      connection: {any_of: ['hubspot:fixture']}, resource: {any_of: resources},
      operation: {any_of: accountOperations}, exclusions: []}]}));
  await writeAccount(accountOutcome);
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath,
    principal: 'operator', context: {principal: 'operator', contextCid: cid('d')}});
  const current = async (resource = 'account', operation = 'read', boundary = 'acquisition') => {
    state.currentCalls++;
    const decision = await gate.authorize(boundary,
      {connection: 'hubspot:fixture', resource, operation},
      {subjectCid: scope.runInvocationCid});
    if (decision.action !== 'dispatch') throw Object.assign(
      new Error('ExecutionAuthorizationDenied'), {code: 'ExecutionAuthorizationDenied', decision});
  };
  const resolveSecret = async () => {
    state.resolutions++;
    if (state.resolve) await state.resolve();
    return state.secret;
  };
  const credential = {control, journal, resolveSecret, ca: cert};
  binding = openHttpsCredentialBinding({...credential, scope, maxSecretBytes: 128});
  const ownedCredential = Object.freeze({...credential, binding});
  row = accounted ? await rowOwner(rowSchema, rowSchema === undefined ? undefined
    : () => closeHttpsCredentialBinding(binding) === 'closed') : undefined;
  const authorization = Object.freeze({grant, scope, useId: 'original-identity'});
  const options = {moon: provider, originalPortalId: '7', authorization,
    credential: ownedCredential,
    limits: {maxResponseBytes: 4096, maxNodes: 100, maxDepth: 10}, current,
    chargeResponse: body => { state.charges++; return row?.charge(body) ?? body.byteLength; },
    consumeObservation: charge => { state.consumed++; row?.consume(charge); }};

  return {root, state, scope, grant, control, journal, binding, row, options,
    current, sign, writeAccount, observe: overrides => observeHubSpotAccount({...options, ...overrides})};
}

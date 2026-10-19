// Thread Source component fixture: actual SQL/AQL Common, legacy accounted canonical
// RowRun, Account, signed Credential, SQLite and TLS. Its existing reservations
// do not fund the new reader raw/alias inventory or establish normal physical
// retirement. No packed/live Google, normal numeric or same-Host Run claim.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gmail/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {readGmailThreads, GMAIL_THREAD_LIST_OPERATION, GMAIL_THREAD_GET_OPERATION} from '../site/gmail-thread-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const control = runtimeCore(common).remoteCredentialControl;
const cid = c => `sha256:${c.repeat(64)}`;
const read = name => readFile(join(repo, name), 'utf8');
const vectors = JSON.parse(await readFile(new URL('../../../../spec/fixtures/gmail-thread-projection.json',import.meta.url),'utf8'));
export const threadRowSchema = Object.freeze(vectors.schema);
export const threadReadLimits = Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,
  maxNodes:2048,maxDepth:16,pageSize:100,maxPages:3,maxThreads:10,
  maxMailboxBytes:256,maxTargetBytes:2048,maxIdBytes:128,maxTokenBytes:128,
  maxMessages:20,maxLabels:100,maxHeaders:100,maxHeaderUnits:1024,maxCommentDepth:8,
  maxValueNodes:100,maxValueTextBytes:8192,maxRowsWireBytes:16384,maxRowsWireNodes:100,maxRowsWireDepth:8});
export const threadReadResponses = () => [
  {threads:[{id:'t/+'}]},
  {id:'t/+',messages:[{id:'m',threadId:'t/+',internalDate:'-1',payload:{}}]},
];

export async function threadRowOwner(verifyOriginalTransport, factsWire, format, selection) {
  const wire = vectors.schema_preimage;
  assert.deepEqual(JSON.parse(wire),threadRowSchema);
  assert.equal(checked(provider.gmailThreadSchemaWire(4096,100,8)),wire);
  assert.equal(`sha256:${createHash('sha256').update(wire).digest('hex')}`,vectors.schema_cid);
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    'gmail', 'gmail', 'gmail/0.1', JSON.stringify({views: [{resource: 'threads',
      resource_kind: 'gmail_threads', schema_wire: wire,
      schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire: factsWire}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(check);
  const view = declared.views[0];
  const publication = JSON.stringify({environmentCid: environment.evidenceCid,
    aliases: [{name:'gmail.threads',sourceRef:view.source_ref,
      sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}]});
  // Text must enter the original Source binder; the canonical JSON-only
  // preparation API deliberately refuses SQL and AQL format names.
  const source = format === 'sql' ? `SELECT ${selection} FROM gmail.threads`
    : `FROM gmail.threads |> SELECT ${selection}`;
  const preparation = common.clientProgramPrepareSourceWithParameters(
    source, format, check, publication, undefined, undefined);
  const program = common.clientProgramPreparationReady(preparation);
  assert.ok(program,common.clientProgramPreparationIssueCode(preparation));
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'), read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'), read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement = checked(common.clientProgramPrepareLocalQueryRequirement(program, 0, 0, registry,
    JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const acquisition = checked(common.clientProgramRowSourcePrepareAcquisition(declaration, requirement, query, evidence));
  // Explicit independent component bounds, not normal Host funding.
  const ledger = checked(common.clientProgramAcquisitionLedger(1, 1, 262144n, 100000000n, 100000000n, 0));
  const requestId = randomUUID();
  const run = checked(common.clientProgramRowSourceStartAccounted(acquisition, requestId, verifyOriginalTransport,
    ledger, 262144n, 131072n));
  checked(common.clientProgramRowSourceBegin(run, 16384, 1, 10, undefined));
  return {originals: Object.freeze({acquisition, run, requestId}),
    charge: bytes => checked(common.clientProgramRowSourceChargePage(run, bytes)),
    observation: charge => checked(common.clientProgramRowSourceConsumeObservationCharge(run, charge)),
    page: (rows, charge) => checked(common.clientProgramRowSourceAcceptChargedPage(run, charge, Buffer.from(JSON.stringify(rows)))),
    finish: () => checked(common.clientProgramRowSourceFinish(run)),
    captureCount: () => {const capture=checked(common.clientProgramRowSourceCapture(run));
      const source=checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(common.clientProgramIdentifyCapturedSourceRelation(source)));},
    assertNoCapture: () => assert.throws(() => checked(common.clientProgramRowSourceCapture(run)), {code:'MoonBitHostFailure'}),
    usage: () => common.clientProgramMultiCapturedLedgerUsage(ledger),
    close: () => checked(common.clientProgramRowSourceCloseAccounted(run))};
}

export async function threadReadFixture(t, {account = 'allow', factsWire = '{"relation_keys":{"candidate_keys":[["id"]]}}', format='sql', selection='id, labels, last_message_date, message_count, subject', accounted=true} = {}) {
  const parent = join(repo, '_build', 'gmail-thread-read-fixtures'); await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'query-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
    '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'server.key')), readFile(join(root, 'server.crt'))]);
  const state = {pages: threadReadResponses().map(value=>JSON.stringify(value)),
    requests: [], charges: 0, resolutions: 0, rows: [], status: 200, secret:'gmail-fixture-secret', beforeResponse: undefined, resolved: undefined};
  const server = createServer({key, cert}, async (request, response) => {
    const chunks=[];for await(const chunk of request)chunks.push(chunk);
    state.requests.push({path:request.url,authorization:request.headers.authorization,method:request.method,
      contentType:request.headers['content-type'],body:Buffer.concat(chunks)});
    try {
      await state.beforeResponse?.(request, response);
      if (response.writableEnded || response.destroyed) return;
      const body = state.pages[state.requests.length - 1]; assert.equal(typeof body, 'string');
      response.writeHead(state.status, {'content-type': 'application/json'}); response.end(body);
    } catch (error) {response.destroy(error);}
  });
  await new Promise((resolve, reject) => {server.once('error', reject);server.listen(0, '127.0.0.1', resolve);});
  let binding, journal, row;
  t.after(async () => {
    const failures = [];
    try {if (binding) assert.equal(closeHttpsCredentialBinding(binding), 'closed');} catch (cause) {failures.push(cause);}
    try {row?.close();if (row) assert.deepEqual(row.usage().slice(4,8), [0n,0n,0n,0n]);} catch (cause) {failures.push(cause);}
    try {journal?.close();} catch (cause) {failures.push(cause);}
    try {await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));} catch (cause) {failures.push(cause);}
    t.diagnostic(`Retained original Gmail thread-read fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'GmailThreadReadFixtureCleanupUnconfirmed');
  });
  const authority = generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal = openSqliteCredentialJournal(join(root,'credential-journal'), {credentialAuthorities: new Map([
    ['gmail-fixture',new Map([['key',authority.publicKey]])]])});
  const scope = Object.freeze({issuerAuthority:'gmail-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'gmail',connectorRevision:'gmail/0.1',
    resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:GMAIL_THREAD_LIST_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:3});
  const grant = control.prepare(scope);
  const sign = value => signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  const getScope=Object.freeze({...scope,operation:GMAIL_THREAD_GET_OPERATION,maxUses:10});
  const getGrant=control.prepare(getScope);journal.acceptGrant(sign(getGrant),control);
  const accountPath=join(root,'account.json');
  const writeAccount = outcome => writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',account_id:'fixture',entries:[{
    entry_id:'gmail-read',outcome,principal:{all:true},connection:{any_of:['gmail:fixture']},resource:{any_of:['threads']},
    operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context:{principal:'operator',contextCid:cid('d')}});
  const current=async () => {const decision=await gate.authorize('acquisition',{connection:'gmail:fixture',resource:'threads',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('GmailReadDenied'),{code:'GmailReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async () => {state.resolutions++;await state.resolved?.();return state.secret;}};
  binding=openHttpsCredentialBinding({...credential,scope,maxSecretBytes:128});
  if(accounted)row=await threadRowOwner(() => closeHttpsCredentialBinding(binding)==='closed', factsWire, format, selection);
  const initialAuthorization={grant,scope,useId:'initial'};
  const options={moon:provider,mailbox:'support+box@example.test',names:Object.keys(threadRowSchema),initialAuthorization,
    credential:{...credential,binding},limits:threadReadLimits,current,
    authorizationFor:({operation,index}) => operation===GMAIL_THREAD_LIST_OPERATION
      ? {grant,scope,useId:`list-${index}`} : {grant:getGrant,scope:getScope,useId:`get-${index}`},
    chargeResponse:body => {state.charges++;return row.charge(body);},
    consumeObservation:charge=>row.observation(charge),
    consumePage:(rows,{charge}) => {row.page(rows,charge);state.rows.push(...rows);}};
  return {root,state,row,journal,binding,scope,grant,getScope,getGrant,control,sign,current,writeAccount,options,
    read:overrides=>{assert.ok(row,'the direct reader fixture requires its original RowRun');
      return readGmailThreads({...options,...overrides});}};
}

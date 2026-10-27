import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Source component fixture: actual SQL/AQL Common, legacy accounted canonical
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
import {readGmailLabelList, GMAIL_LABEL_LIST_OPERATION} from '../site/gmail-label-list-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const control = runtimeCore(common).remoteCredentialControl;
const cid = c => `sha256:${c.repeat(64)}`;
const read = name => readFile(join(repo, name), 'utf8');
export const labelListRowSchema = Object.freeze({id:{type:'string',nullable:false},
  name:{type:'string',nullable:false},type:{type:'string',nullable:false}});
export const labelListReadLimits = Object.freeze({maxResponseBytes:4096,maxNodes:512,maxDepth:16,
  maxRows:10,maxMailboxBytes:256,maxTargetBytes:1024,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:4096,maxRowsWireNodes:100,maxRowsWireDepth:8});
export const labelListResponse = () => ({labels:[{id:'INBOX',name:'Inbox',type:'system'},
  {id:'Label_1',name:'顧客 / é 📩',type:'user'}]});

export async function labelListRowOwner(verifyOriginalTransport, factsWire, format, selection) {
  const wire = '{"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"type":{"nullable":false,"type":"string"}}';
  assert.deepEqual(JSON.parse(wire),labelListRowSchema);
  assert.equal(checked(provider.gmailLabelListSchemaWire(2048,100,8)),wire);
  assert.equal(provider.gmailLabelListRelationFactsWire(),'{"relation_keys":{"candidate_keys":[["id"]]}}');
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    'gmail', 'gmail', 'gmail/0.1', JSON.stringify({views: [{resource: 'labels',
      resource_kind: 'gmail_labels', schema_wire: wire,
      schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire: factsWire}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(check);
  const view = declared.views[0];
  const publication = JSON.stringify({environmentCid: environment.evidenceCid,
    aliases: [{name:'gmail.labels',sourceRef:view.source_ref,
      sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}]});
  // Text must enter the original Source binder; the canonical JSON-only
  // preparation API deliberately refuses SQL and AQL format names.
  const source = format === 'sql' ? `SELECT ${selection} FROM gmail.labels`
    : `FROM gmail.labels |> SELECT ${selection}`;
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
  const ledger = checked(common.clientProgramAcquisitionLedger(1, 1, 24576n, 100000000n, 100000000n, 0));
  const run = checked(common.clientProgramRowSourceStartAccounted(acquisition, randomUUID(), verifyOriginalTransport,
    ledger, 24576n, 8192n));
  checked(common.clientProgramRowSourceBegin(run, 4096, 2, 10, undefined));
  return {charge: bytes => checked(common.clientProgramRowSourceChargePage(run, bytes)),
    page: (rows, charge) => checked(common.clientProgramRowSourceAcceptChargedPage(run, charge, Buffer.from(JSON.stringify(rows)))),
    finish: () => checked(common.clientProgramRowSourceFinish(run)),
    captureCount: () => {const capture=checked(common.clientProgramRowSourceCapture(run));
      const source=checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(common.clientProgramIdentifyCapturedSourceRelation(source)));},
    assertNoCapture: () => assert.throws(() => checked(common.clientProgramRowSourceCapture(run)), {code:'MoonBitHostFailure'}),
    usage: () => common.clientProgramMultiCapturedLedgerUsage(ledger),
    close: () => checked(common.clientProgramRowSourceCloseAccounted(run))};
}

export async function labelListFixture(t, {account = 'allow', factsWire = '{"relation_keys":{"candidate_keys":[["id"]]}}', format='sql', selection='id, name, type', accounted=true} = {}) {
  const parent = join(repo, '_build', 'gmail-label-list-fixtures'); await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'query-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
    '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'server.key')), readFile(join(root, 'server.crt'))]);
  const state = {pages: [JSON.stringify(labelListResponse())],
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
    try {row?.close();if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n,0n,0n,0n]);} catch (cause) {failures.push(cause);}
    try {journal?.close();} catch (cause) {failures.push(cause);}
    try {await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));} catch (cause) {failures.push(cause);}
    t.diagnostic(`Retained original Gmail label-list fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'GmailLabelListFixtureCleanupUnconfirmed');
  });
  const authority = generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal = openSqliteCredentialJournal(join(root,'credential-journal'), {credentialAuthorities: new Map([
    ['gmail-fixture',new Map([['key',authority.publicKey]])]])});
  const scope = Object.freeze({issuerAuthority:'gmail-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'gmail',connectorRevision:'gmail/0.1',
    resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:GMAIL_LABEL_LIST_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:1});
  const grant = control.prepare(scope);
  const sign = value => signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  const accountPath=join(root,'account.json');
  const writeAccount = outcome => writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',account_id:'fixture',entries:[{
    entry_id:'gmail-read',outcome,principal:{all:true},connection:{any_of:['gmail:fixture']},resource:{any_of:['labels']},
    operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context:{principal:'operator',contextCid:cid('d')}});
  const current=async () => {const decision=await gate.authorize('acquisition',{connection:'gmail:fixture',resource:'labels',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('GmailReadDenied'),{code:'GmailReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async () => {state.resolutions++;await state.resolved?.();return state.secret;}};
  binding=openHttpsCredentialBinding({...credential,scope,maxSecretBytes:128});
  if(accounted)row=await labelListRowOwner(() => closeHttpsCredentialBinding(binding)==='closed', factsWire, format, selection);
  const initialAuthorization={grant,scope,useId:'initial'};
  const options={moon:provider,mailbox:'support+box@example.test',names:['name'],initialAuthorization,
    credential:{...credential,binding},limits:labelListReadLimits,current,
    authorizationFor:({index}) => ({grant,scope,useId:`query-${index}`}),
    chargeResponse:body => {state.charges++;return row.charge(body);},
    consumePage:(rows,{charge}) => {row.page(rows,charge);state.rows.push(...rows);}};
  return {root,state,row,journal,binding,scope,grant,control,sign,current,writeAccount,options,
    read:overrides=>{assert.ok(row,'the direct reader fixture requires its original RowRun');
      return readGmailLabelList({...options,...overrides});}};
}

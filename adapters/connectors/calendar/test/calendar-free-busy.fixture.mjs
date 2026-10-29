import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Source component fixture: actual Common RowRun, Account, signed Credential,
// SQLite and TLS. No normal packed/live Google or numeric-profile qualification.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
const common = await import(process.env.ACTQL_TEST_COMMON_URL ?? new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const provider = await import(process.env.ACTQL_TEST_CALENDAR_URL ?? new URL('../../../../_build/js/release/build/connectors/calendar/host_node/host_node.js',import.meta.url).href);
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {prepareCalendarFreeBusyPages, CALENDAR_FREE_BUSY_OPERATION} from '../site/calendar-free-busy-read.mjs';

const repo = new URL('../../../../', import.meta.url).pathname;
const control = runtimeCore(common).remoteCredentialControl;
const cid = c => `sha256:${c.repeat(64)}`;
const read = name => readFile(join(repo, name), 'utf8');
export const freeBusyRowSchema = Object.freeze({calendar_id:{type:'string',nullable:false},
  start:{type:'timestamp',nullable:false},end:{type:'timestamp',nullable:false}});
export const freeBusyReadLimits = Object.freeze({maxResponseBytes:4096,maxNodes:512,maxDepth:16,
  maxCalendars:4,maxRows:10,maxRequestBytes:16384,maxBodyBytes:4096,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:4096,maxRowsWireNodes:100,maxRowsWireDepth:8});
export const freeBusyResponse = () => ({kind:'calendar#freeBusy',
  timeMin:'2026-10-17T00:00:00Z',timeMax:'2026-10-18T00:00:00Z',
  calendars:{'sales@example.test':{busy:[{start:'2026-10-17T10:00:00+09:00',end:'2026-10-17T10:30:00+09:00'}]},
    private:{busy:[{start:'2026-10-17T02:00:00Z',end:'2026-10-17T02:15:00Z'}]}}});

async function rowOwner(verifyOriginalTransport, factsWire) {
  const wire = canonicalJson(freeBusyRowSchema);
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    'fixture', 'calendar', 'calendar/0.1', JSON.stringify({views: [{resource: 'free_busy',
      resource_kind: 'calendar_free_busy', schema_wire: wire,
      schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire: factsWire}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(check);
  const preparation = common.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify({version: 'actql/0.1', id: 'calendar-free-busy-accounting', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'free_busy'}},
      steps: [{filter: 'true', as: 'all'}, {select: ['calendar_id','start','end'], as: 'out'}],
      results: {r: {from: 'out', fields: ['calendar_id','start','end']}}}], results: {r: {from: {stage: 'scan', result: 'r'}}}}),
    'json', check, undefined);
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

export async function freeBusyFixture(t, {account = 'allow', factsWire = '{}'} = {}) {
  const parent = join(repo, '_build', 'calendar-free-busy-fixtures'); await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'query-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
    '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'server.key')), readFile(join(root, 'server.crt'))]);
  const state = {pages: [JSON.stringify(freeBusyResponse())],
    requests: [], responses: [], charges: 0, resolutions: 0, rows: [], status: 200, secret:'calendar-fixture-secret', beforeResponse: undefined, resolved: undefined};
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
  let journal, row;const readers=[],factories=[];
  t.after(async () => {
    const failures = [];
    try {for(const reader of readers){reader.requestStop();reader.retry();assert.equal(reader.observe().cleanupConfirmed,true);}for(const factory of factories)assert.equal(factory.retire(),true);} catch (cause) {failures.push(cause);}
    try {row?.close();if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n,0n,0n,0n]);} catch (cause) {failures.push(cause);}
    try {journal?.close();} catch (cause) {failures.push(cause);}
    try {await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));} catch (cause) {failures.push(cause);}
    t.diagnostic(`Retained original Calendar free/busy fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'CalendarFreeBusyFixtureCleanupUnconfirmed');
  });
  const authority = generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal = openSqliteCredentialJournal(join(root,'credential-journal'), {credentialAuthorities: new Map([
    ['calendar-fixture',new Map([['key',authority.publicKey]])]])});
  const scope = Object.freeze({issuerAuthority:'calendar-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'calendar',connectorRevision:'calendar/0.1',
    resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:CALENDAR_FREE_BUSY_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:1});
  const grant = control.prepare(scope);
  const sign = value => signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  const accountPath=join(root,'account.json');
  const writeAccount = outcome => writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',account_id:'fixture',entries:[{
    entry_id:'calendar-read',outcome,principal:{all:true},connection:{any_of:['calendar:fixture']},resource:{any_of:['free_busy']},
    operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context:{principal:'operator',contextCid:cid('d')}});
  const current=async () => {const decision=await gate.authorize('acquisition',{connection:'calendar:fixture',resource:'free_busy',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('CalendarReadDenied'),{code:'CalendarReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async () => {state.resolutions++;await state.resolved?.();return state.secret;}};
  row=await rowOwner(() => readers.every(reader=>reader.observe().transportClosed), factsWire);
  const initialAuthorization={grant,scope,useId:'initial'};
  const query=checked(provider.calendarPrepareFreeBusyQuery(['sales@example.test','private'],
    '2026-10-17T00:00:00.000Z','2026-10-18T00:00:00.000Z',4096,512,16,4,10,4096,100,4096));
  const options={moon:provider,query,names:['start'],initialAuthorization,
    credential,limits:freeBusyReadLimits,current,
    authorizationFor:({index}) => ({grant,scope,useId:`query-${index}`}),
    chargeResponse:body => {state.charges++;return row.charge(body);},
    consumePage:(rows,{charge}) => {row.page(rows,charge);state.rows.push(...rows);}};
  const create=(overrides={})=>{
    const selected={...options,...overrides},bound=Object.freeze({...selected.limits});
    const physical=selected.callResource??callHttpsCredentialResource;
    const site={credential:selected.credential,referenceCurrent:()=>true,async callResource(input){
      const response=await physical(input);state.responses.push(response);return response;
    }};
    const factory=createInstalledCredentialSourceReader({capacity:{},site,operation:CALENDAR_FREE_BUSY_OPERATION,
      maxResponses:1,maxRequestBytes:bound.maxRequestBytes,maxResponseBytes:bound.maxResponseBytes,maxSecretBytes:128,
      preparePageReader({columns},applySynchronousProjection){return prepareCalendarFreeBusyPages(
        {moon:selected.moon,query:selected.query,names:columns,limits:bound},applySynchronousProjection);}});
    factories.push(factory);
    const reader=factory.prepare({resource:'free_busy',columns:selected.names,signal:selected.signal,
      verifyRead:typeof selected.current==='function'?()=>selected.current(CALENDAR_FREE_BUSY_OPERATION):selected.current,
      authorizationFor:typeof selected.authorizationFor==='function'?index=>selected.authorizationFor({operation:CALENDAR_FREE_BUSY_OPERATION,index}):selected.authorizationFor,
      chargePage:selected.chargeResponse,consumePage:selected.consumePage});
    readers.push(reader);return reader;
  };
  return {root,state,row,journal,scope,grant,control,sign,current,writeAccount,options,readers,create,
    read:overrides=>create(overrides).read()};
}

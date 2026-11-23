// @ts-expect-error TS7016: the shared test ledger projection is still authored JavaScript.
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Source component fixture: actual Common RowRun, Account, signed Credential,
// SQLite and TLS. No normal packed/live Google or numeric-profile qualification.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import type {AddressInfo} from 'node:net';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
const common: CalendarRowRuntime = await import(process.env.ACTQL_TEST_COMMON_URL ?? new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
const provider: CalendarListBindings = await import(process.env.ACTQL_TEST_CALENDAR_URL ?? new URL('../../../../_build/js/release/build/connectors/calendar/host_node/host_node.js', import.meta.url).href);
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson,readAccountConfiguration} from '../../../host-node/local-account-config.mjs';
import {createAuthorizationGate} from '../../../host-common/authorization-gate.mjs';
import {readFileSync} from 'node:fs';
// A bounded component may use an unchanged original adapter together with its
// own canonical Common namespace; normal CI prepares this same checkout.
const {rowSourceCheckEnvironment}: Pick<typeof import('../../../host-node/installed-row-source.mjs'), 'rowSourceCheckEnvironment'>=await import(process.env.ACTQL_TEST_SOURCE_ADAPTER_MODULE ??
  new URL('../../../host-node/installed-row-source.mjs',import.meta.url).href);
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {callHttpsCredentialResource,openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {prepareCalendarListPages, CALENDAR_LIST_OPERATION} from '../site/calendar-list-read.mjs';

import type {IncomingMessage, ServerResponse} from 'node:http';
import type {CalendarListBindings, CalendarListLimits, CalendarListProjection} from '../site/calendar-list-read.mjs';
import type {remoteCredentialControl} from '../../../host-common/remote-credential-control.mjs';

type AccountRuntime = NonNullable<NonNullable<Parameters<typeof createAuthorizationGate>[0]>['runtime']>;
type CalendarCredentialControl = ReturnType<typeof remoteCredentialControl>;

// Only the existing Common methods used by the Calendar RowRun fixture.
// Nominal results go back through the original Common checks.
export type CalendarRowRuntime = AccountRuntime & Readonly<{
  clientProgramRowSourceRestoreRelationDeclaration(connectorId: string, registration: string,
    revision: string, declaration: string, mappings: undefined): unknown;
  clientProgramRowSourceDeclarationJson(original: unknown): string;
  clientProgramCheckEnvironment(wire: string, evidenceCid: string, sourceMap: boolean,
    graph: boolean, rel: boolean, worker: boolean, partial: boolean, model: boolean, effects: boolean): unknown;
  clientProgramPrepareEffectFreeWithParameters(wire: string, format: string, environment: unknown, parameters: undefined): unknown;
  clientProgramPreparationReady(original: unknown): unknown;
  clientProgramPreparationIssueCode(original: unknown): string;
  clientPrepareInstalledSequenceContracts(registry: string, values: string, fragment: string, ordered: string): unknown;
  clientProgramPrepareLocalQueryRequirement(program: unknown, stage: number, input: number,
    contracts: unknown, values: string, fragment: string, ordered: string): unknown;
  clientProgramRowSourcePrepareAcquisition(declaration: unknown, requirement: unknown, query: string, evidence: string): unknown;
  clientProgramAcquisitionLedger(sources: number, tasks: number, transfer: bigint,
    retention: bigint, execution: bigint, attempts: number): unknown;
  clientProgramRowSourceStartAccounted(acquisition: unknown, id: string, verify: () => boolean,
    ledger: unknown, transfer: bigint, execution: bigint): unknown;
  clientProgramRowSourceBegin(run: unknown, bytes: number, pageRows: number, rows: number, cursor: undefined): unknown;
  clientProgramRowSourceChargePage(run: unknown, body: ArrayBufferView): unknown;
  clientProgramRowSourceAcceptChargedPage(run: unknown, charge: unknown, wire: Uint8Array): unknown;
  clientProgramRowSourceFinish(run: unknown): unknown;
  clientProgramRowSourceCaptureBegin(run: unknown): unknown;
  clientProgramRowSourceCaptureAdvance(run: unknown, work: number): unknown;
  clientProgramRowSourceCapture(run: unknown): unknown;
  clientProgramRowSourceCaptureSource(capture: unknown): unknown;
  clientProgramIdentifyCapturedSourceRelation(source: unknown): unknown;
  clientProgramCapturedSourceRowCount(source: unknown): number;
  clientProgramMultiCapturedLedgerUsage(ledger: unknown): unknown;
  clientProgramRowSourceCloseAccounted(run: unknown): unknown;
}>;

export type CalendarTestContext = Readonly<{
  after(close: () => Promise<void>): unknown;
  diagnostic(message: string): unknown;
}>;
export type CalendarTestRequest = {
  path: string | undefined; authorization: string | undefined; method: string | undefined;
};
export type CalendarTestState<Row, Request extends CalendarTestRequest = CalendarTestRequest> = {
  pages: string[]; requests: Request[]; charges: number; resolutions: number; rows: Row[];
  status: number; secret: string;
  beforeResponse?: (request: IncomingMessage, response: ServerResponse) => unknown;
  resolved?: () => unknown;
};
type ProjectedRow = ReturnType<ReturnType<typeof prepareCalendarListPages>['decodePage']>['rows'][number];
type Reader = ReturnType<ReturnType<typeof createInstalledCredentialSourceReader>['prepare']>;
type Factory = ReturnType<typeof createInstalledCredentialSourceReader>;
type AcquisitionCallbacks = Readonly<{assertCurrent(): void; observeCurrent(): unknown}>;

const repo = new URL('../../../../', import.meta.url).pathname;
const control = (runtimeCore as (moon: CalendarRowRuntime) => {remoteCredentialControl: CalendarCredentialControl})
  (common).remoteCredentialControl;
const cid = (c: string) => `sha256:${c.repeat(64)}`;
const read = (name: string) => readFile(join(process.env.ACTQL_TEST_CONTRACT_ROOT ?? repo, name), 'utf8');
export const calendarRowSchema = Object.freeze(Object.fromEntries(
  ['access_role', 'id', 'summary', 'time_zone'].map(name => [name, {type: 'string', nullable: false}])));
export const calendarReadLimits: CalendarListLimits = Object.freeze({maxResponseBytes: 4096, maxNodes: 512,
  maxDepth: 16, maxPages: 4, maxRows: 10, maxRequests: 4, perPage: 2,
  maxCursorUnits: 128, maxValueNodes: 100, maxValueTextBytes: 4096,
  maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 8});
export const calendarRecord = (id: string, summary = id) => ({id, summary, timeZone: 'UTC', accessRole: 'reader'});

async function rowOwner(verifyOriginalTransport: () => boolean) {
  const wire = canonicalJson(calendarRowSchema);
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    'fixture', 'calendar', 'calendar/0.1', JSON.stringify({views: [{resource: 'calendars',
      resource_kind: 'calendar_list', schema_wire: wire,
      schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire: '{"relation_keys":{"candidate_keys":[["id"]]}}'}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration)) as Parameters<typeof rowSourceCheckEnvironment>[1];
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(check);
  const program = common.clientProgramPreparationReady(common.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify({version: 'actql/0.1', id: 'calendar-list-accounting', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'calendars'}},
      steps: [{filter: 'true', as: 'all'}, {select: ['id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}}}], results: {r: {from: {stage: 'scan', result: 'r'}}}}),
    'json', check, undefined));
  assert.ok(program);
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'), read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'), read('spec/contracts/actql-query-process-evidence.json')]);
  const values=JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const contracts=checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
  const requirement=checked(common.clientProgramPrepareLocalQueryRequirement(program,0,0,contracts,
    values,fragment,ordered));
  const acquisition = checked(common.clientProgramRowSourcePrepareAcquisition(declaration, requirement, query, evidence));
  // Explicit independent component bounds, not normal Host funding.
  const ledger = checked(common.clientProgramAcquisitionLedger(1, 1, 24576n, 100000000n, 100000000n, 0));
  const run = checked(common.clientProgramRowSourceStartAccounted(acquisition, randomUUID(), verifyOriginalTransport,
    ledger, 24576n, 8192n));
  checked(common.clientProgramRowSourceBegin(run, 4096, 2, 10, undefined));
  return {charge: (bytes: ArrayBufferView) => checked(common.clientProgramRowSourceChargePage(run, bytes)),
    page: (rows: readonly ProjectedRow[], charge: unknown) => checked(common.clientProgramRowSourceAcceptChargedPage(run, charge, Buffer.from(JSON.stringify(rows)))),
    finish: () => checked(common.clientProgramRowSourceFinish(run)),
    captureCount:()=>{
      checked(common.clientProgramRowSourceCaptureBegin(run));
      while(!runtimeField(checked(common.clientProgramRowSourceCaptureAdvance(run,64)),0)) {}
      const capture=checked(common.clientProgramRowSourceCapture(run));
      const source=checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(common.clientProgramIdentifyCapturedSourceRelation(source)));},
    assertNoCapture: () => assert.throws(() => checked(common.clientProgramRowSourceCapture(run)), {code:'MoonBitHostFailure'}),
    usage: () => common.clientProgramMultiCapturedLedgerUsage(ledger),
    close: () => checked(common.clientProgramRowSourceCloseAccounted(run))};
}

export async function calendarFixture(t: CalendarTestContext, {account = 'allow', accounted = true} = {}) {
  const parent = join(repo, '_build', 'calendar-source-fixtures'); await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'list-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
    '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'server.key')), readFile(join(root, 'server.crt'))]);
  const state: CalendarTestState<ProjectedRow> = {pages: [JSON.stringify({kind: 'calendar#calendarList', items: [calendarRecord('one')], nextPageToken: 'opaque /+é'}),
    JSON.stringify({kind: 'calendar#calendarList', items: [calendarRecord('two')]})],
    requests: [], charges: 0, resolutions: 0, rows: [], status: 200, secret:'calendar-fixture-secret', beforeResponse: undefined, resolved: undefined};
  const server = createServer({key, cert}, async (request, response) => {
    state.requests.push({path: request.url, authorization: request.headers.authorization, method: request.method});
    try {
      await state.beforeResponse?.(request, response);
      if (response.writableEnded || response.destroyed) return;
      const body = state.pages[state.requests.length - 1]; assert.equal(typeof body, 'string');
      response.writeHead(state.status, {'content-type': 'application/json'}); response.end(body);
    } catch (error) {response.destroy(error as Error);}
  });
  await new Promise<void>((resolve, reject) => {server.once('error', reject);server.listen(0, '127.0.0.1', resolve);});
  let journal: ReturnType<typeof openSqliteCredentialJournal> | undefined,row: Awaited<ReturnType<typeof rowOwner>> | undefined;
  const readers: Reader[]=[],factories: Factory[]=[];
  t.after(async () => {
    const failures = [];
    let readersRetired = false;
    try {
      for(const reader of readers){reader.requestStop();reader.retry();assert.equal(reader.observe().cleanupConfirmed,true);}
      for(const factory of factories)assert.equal(factory.retire(),true);
      readersRetired = true;
    } catch (cause) {failures.push(cause);}
    if (readersRetired) {
      let rowClosed = false;
      try {row?.close();if (row) assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n,0n,0n,0n]);rowClosed = true;} catch (cause) {failures.push(cause);}
      if (rowClosed) try {journal?.close();} catch (cause) {failures.push(cause);}
    }
    try {await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));} catch (cause) {failures.push(cause);}
    t.diagnostic(`Retained original Calendar fixture: ${root}`);
    if (failures.length) throw new AggregateError(failures, 'CalendarFixtureCleanupUnconfirmed');
  });
  const authority = generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal = openSqliteCredentialJournal(join(root,'credential-journal'), {credentialAuthorities: new Map([
    ['calendar-fixture',new Map([['key',authority.publicKey]])]])});
  const scope = Object.freeze({issuerAuthority:'calendar-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'calendar',connectorRevision:'calendar/0.1',
    resourceOrigin:`https://127.0.0.1:${(server.address() as AddressInfo).port}`,operation:CALENDAR_LIST_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:4});
  const grant = control.prepare(scope);
  const sign = (value: unknown) => signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  const accountPath=join(root,'account.json');
  const writeAccount = (outcome: string) => writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',account_id:'fixture',entries:[{
    entry_id:'calendar-read',outcome,principal:{all:true},connection:{any_of:['calendar:fixture']},resource:{any_of:['calendars']},
    operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const configuration=await readAccountConfiguration(accountPath);
  const gate=createAuthorizationGate({runtime:common,configuration:configuration.text,
    readConfiguration:()=>readFileSync(accountPath,'utf8'),
    context:{principal:'operator',contextCid:cid('d')}});
  const current: (operation?: string) => Promise<void>=async () => {const decision=await gate.authorize('acquisition',{connection:'calendar:fixture',resource:'calendars',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('CalendarReadDenied'),{code:'CalendarReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async () => {state.resolutions++;await state.resolved?.();return state.secret;}};
  if(accounted)row=await rowOwner(() => readers.every(reader=>reader.observe().transportClosed));
  const initialAuthorization={grant,scope,useId:'initial'};
  const options={moon:provider,names:['summary','time_zone','access_role'],initialAuthorization,
    credential,limits:calendarReadLimits,current,
    authorizationFor:({index}: {index: number; operation?: string}) => ({grant,scope,useId:`page-${index}`}),
    chargeResponse:(body: ArrayBufferView) => {state.charges++;return row!.charge(body);},
    consumePage:(rows: readonly ProjectedRow[],{charge}: {charge: unknown}) => {row!.page(rows,charge);state.rows.push(...rows);}};
  type Overrides = Partial<Omit<typeof options, 'moon' | 'authorizationFor'>> & Readonly<{
    moon?: Partial<CalendarListBindings>; signal?: AbortSignal;
    authorizationFor?(selection: {operation?: string; index: number}): unknown;
  }>;
  const create=(overrides: Overrides={})=>{
    const selected={...options,...overrides};
    const bound=Object.freeze({...selected.limits});
    const site={credential:selected.credential,referenceCurrent:()=>true,callResource:callHttpsCredentialResource};
    const originalSite=Object.freeze({site,referenceCurrent:()=>true,callResource:callHttpsCredentialResource,
      authorizationPurpose(original: unknown) {assert.equal(original,selected.initialAuthorization);return {kind:'read'};},
      bindRunAcquisition(original: typeof initialAuthorization,callbacks: AcquisitionCallbacks) {
        assert.equal(original,selected.initialAuthorization);callbacks.assertCurrent();
        const binding=openHttpsCredentialBinding({...selected.credential,scope:original.scope,
          maxSecretBytes:128,assertCurrent:callbacks.assertCurrent});
        return Object.freeze({credential:Object.freeze({...selected.credential,binding,
          currentBeforeSend:callbacks.observeCurrent}),close:()=>closeHttpsCredentialBinding(binding)});
      }
    });
    const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},operation:CALENDAR_LIST_OPERATION,
      maxResponses:bound.maxPages,maxResponseBytes:bound.maxResponseBytes,maxSecretBytes:128,
      preparePageReader:({columns}: {columns: readonly string[]},applySynchronousProjection: CalendarListProjection)=>prepareCalendarListPages({moon:selected.moon,names:columns,limits:bound},applySynchronousProjection)});
    factories.push(factory);
    const reader=factory.prepare({originalAuthorization:selected.initialAuthorization,resource:'calendars',columns:selected.names,signal:selected.signal,
      verifyRead:typeof selected.current==='function'?()=>selected.current!(CALENDAR_LIST_OPERATION):selected.current,
      authorizationFor:typeof selected.authorizationFor==='function'?(index: number)=>selected.authorizationFor!({operation:CALENDAR_LIST_OPERATION,index}):selected.authorizationFor,
      chargePage:typeof selected.chargeResponse==='function'?(body: ArrayBufferView)=>selected.chargeResponse!(body):selected.chargeResponse,
      consumePage:typeof selected.consumePage==='function'?(rows: readonly ProjectedRow[],ticket: {charge: unknown})=>selected.consumePage!(rows,ticket):selected.consumePage} as Parameters<Factory['prepare']>[0]);
    readers.push(reader);return reader;
  };
  return {root,state,row,journal,scope,grant,control,sign,current,writeAccount,options,create,readers,
    read:async (overrides?: Overrides)=>{const reader=create(overrides);const result=await reader.read();reader.requestStop();return result;}};
}

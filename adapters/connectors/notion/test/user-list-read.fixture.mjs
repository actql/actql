import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual Common/Credential/SQLite/TLS and legacy accounted canonical RowRun.
// Explicit component bounds do not fund the retained reader graph, establish
// normal physical retirement, or qualify a pristine installed Notion product.
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,randomUUID} from 'node:crypto';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
const common = await import(process.env.ACTQL_TEST_COMMON_URL ?? new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
const provider = await import(process.env.ACTQL_TEST_NOTION_URL ?? new URL('../../../../_build/js/release/build/connectors/notion/host_node/host_node.js', import.meta.url).href);
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson,readAccountConfiguration} from '../../../host-node/local-account-config.mjs';
import {createAuthorizationGate} from '../../../host-common/authorization-gate.mjs';
import {readFileSync} from 'node:fs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {callHttpsCredentialResource,openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {prepareNotionUserListPages,NOTION_USER_LIST_OPERATION} from '../site/user-list-read.mjs';

const repo=new URL('../../../../',import.meta.url).pathname;
const control=runtimeCore(common).remoteCredentialControl;
const cid=c=>`sha256:${c.repeat(64)}`;
const read = name => readFile(join(process.env.ACTQL_TEST_CONTRACT_ROOT ?? repo, name), 'utf8');
export const userListReadLimits=Object.freeze({maxResponseBytes:8192,maxTotalResponseBytes:24576,
  maxNodes:512,maxDepth:16,maxRows:10,maxTotalRows:20,maxPages:4,pageSize:10,
  maxCursorBytes:128,maxIdentityBytes:128,maxTargetBytes:1024,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8});
export const userPage=(results,nextCursor)=>({object:'list',type:'user',user:{},results,has_more:nextCursor!==null,next_cursor:nextCursor});

async function rowOwner(verifyTransport,format) {
  const wire=checked(provider.notionUserListSchemaWire(4096,100,8));
  assert.deepEqual(JSON.parse(wire),{email:{nullable:true,type:'string'},id:{nullable:false,type:'string'},
    name:{nullable:true,type:'string'},type:{nullable:true,type:'string'}});
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('notion','notion','notion/0.1',
    JSON.stringify({views:[{resource:'users',resource_kind:'notion_users',schema_wire:wire,
      schema_cid:`sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire:'{"relation_keys":{"candidate_keys":[["id"]]}}'}]}),undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(),declared);
  const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);
  const view=declared.views[0];
  const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:[{name:'notion.users',
    sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}]});
  const preparation=common.clientProgramPrepareSourceWithParameters(
    format==='sql'?'SELECT id, name FROM notion.users':'FROM notion.users |> SELECT id, name',
    format,check,publication,undefined,undefined);
  const program=common.clientProgramPreparationReady(preparation);
  assert.ok(program,common.clientProgramPreparationIssueCode(preparation));
  const [registry,aoa,query,evidence]=await Promise.all([read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const values=JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const contracts=checked(common.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
  const requirement=checked(common.clientProgramPrepareLocalQueryRequirement(program,0,0,contracts,
    values,fragment,ordered));
  const acquisition=checked(common.clientProgramRowSourcePrepareAcquisition(declaration,requirement,query,evidence));
  // Independent component reservations, not a normal installed reader supplier.
  const ledger=checked(common.clientProgramAcquisitionLedger(1,1,65536n,100000000n,100000000n,0));
  const run=checked(common.clientProgramRowSourceStartAccounted(acquisition,randomUUID(),verifyTransport,ledger,65536n,8192n));
  checked(common.clientProgramRowSourceBegin(run,8192,5,20,undefined));
  return {charge:body=>checked(common.clientProgramRowSourceChargePage(run,body)),
    observe:charge=>checked(common.clientProgramRowSourceConsumeObservationCharge(run,charge)),
    page:(rows,charge)=>checked(common.clientProgramRowSourceAcceptChargedPage(run,charge,Buffer.from(JSON.stringify(rows)))),
    finish:()=>checked(common.clientProgramRowSourceFinish(run)),
    captureCount:()=>{
      checked(common.clientProgramRowSourceCaptureBegin(run));
      while(!runtimeField(checked(common.clientProgramRowSourceCaptureAdvance(run,64)),0)) {}
      const capture=checked(common.clientProgramRowSourceCapture(run));
      const source=checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(common.clientProgramIdentifyCapturedSourceRelation(source)));},
    assertNoCapture:()=>assert.throws(()=>checked(common.clientProgramRowSourceCapture(run)),{code:'MoonBitHostFailure'}),
    usage:()=>common.clientProgramMultiCapturedLedgerUsage(ledger),
    close:()=>checked(common.clientProgramRowSourceCloseAccounted(run))};
}

export async function userListFixture(t,{account='allow',format='sql',accounted=true}={}) {
  const parent=join(repo,'_build','notion-user-list-fixtures');await mkdir(parent,{recursive:true});
  const root=await mkdtemp(join(parent,'query-'));
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout','server.key',
    '-out','server.crt','-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd:root,stdio:'ignore'});
  const [key,cert]=await Promise.all([readFile(join(root,'server.key')),readFile(join(root,'server.crt'))]);
  const state={pages:[userPage([{object:'user',id:'U1',type:'person',name:'one',person:{email:'one@example.test'}}],'opaque+/= cursor'),
      userPage([{object:'user',id:'U2',type:'bot',name:'two',bot:{}}],null)],
    requests:[],resolutions:0,charges:0,observationCharges:0,rows:[],status:200,
    secret:'notion-fixture-token',beforeResponse:undefined,resolved:undefined};
  const server=createServer({key,cert},async(request,response)=>{
    const chunks=[];for await(const chunk of request)chunks.push(chunk);
    state.requests.push({path:request.url,method:request.method,authorization:request.headers.authorization,
      contentType:request.headers['content-type'],notionVersion:request.headers['notion-version'],body:Buffer.concat(chunks)});
    try {
      await state.beforeResponse?.(request,response);
      if(response.destroyed||response.writableEnded)return;
      const body=state.pages[state.requests.length-1];
      assert.notEqual(body,undefined);
      response.writeHead(state.status,{'content-type':'application/json'});
      response.end(typeof body==='string'?body:JSON.stringify(body));
    } catch(cause){response.destroy(cause);}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  let journal,row;const readers=[],factories=[];
  t.after(async()=>{
    const errors=[];
    let readersRetired=false;
    try{
      for(const reader of readers){reader.requestStop();reader.retry();assert.equal(reader.observe().cleanupConfirmed,true);}
      for(const factory of factories)assert.equal(factory.retire(),true);
      readersRetired=true;
    }catch(cause){errors.push(cause);}
    if(readersRetired){
      let rowClosed=false;
      try{if(row){row.close();assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),[0n,0n,0n,0n]);}rowClosed=true;}catch(cause){errors.push(cause);}
      if(rowClosed)try{journal?.close();}catch(cause){errors.push(cause);}
    }
    try{await new Promise((resolve,reject)=>server.close(cause=>cause?reject(cause):resolve()));}catch(cause){errors.push(cause);}
    t.diagnostic(`Retained original Notion fixture: ${root}`);
    if(errors.length){t.diagnostic(JSON.stringify(errors.map(error=>({name:error.name,code:error.code,message:error.message}))));throw new AggregateError(errors,'NotionUserListFixtureCleanupUnconfirmed');}
  });
  const authority=generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root,'credential-authority.key'),authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root,'credential-authority.pub'),authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal=openSqliteCredentialJournal(join(root,'credential-journal'),{credentialAuthorities:new Map([
    ['notion-fixture',new Map([['key',authority.publicKey]])]])});
  const scope=Object.freeze({issuerAuthority:'notion-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'notion',connectorRevision:'notion/0.1',
    resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:NOTION_USER_LIST_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),
    expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:5});
  const grant=control.prepare(scope);
  const sign=value=>signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  const accountPath=join(root,'account.json');
  const writeAccount=outcome=>writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',
    account_id:'fixture',entries:[{entry_id:'notion-read',outcome,principal:{all:true},connection:{any_of:['notion:fixture']},
      resource:{any_of:['users']},operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const configuration=await readAccountConfiguration(accountPath);
  const gate=createAuthorizationGate({runtime:common,configuration:configuration.text,
    configurationCid:configuration.configurationCid,readConfiguration:()=>readFileSync(accountPath,'utf8'),
    context:{principal:'operator',contextCid:cid('d')}});
  const current=async()=>{const decision=await gate.authorize('acquisition',{connection:'notion:fixture',resource:'users',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('NotionReadDenied'),{code:'NotionReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async()=>{state.resolutions++;await state.resolved?.();return state.secret;}};
  row=accounted?await rowOwner(()=>readers.every(reader=>reader.observe().transportClosed),format):undefined;
  const authorizationFor=({operation,index})=>{assert.equal(operation,NOTION_USER_LIST_OPERATION);
    return{grant,scope,useId:`users-${index}`};};
  const options={moon:provider,names:provider.notionUserListColumnNames(),
    initialAuthorization:{grant,scope,useId:'initial'},credential,
    authorizationFor,limits:userListReadLimits,current,
    chargeResponse:body=>{state.charges++;return row.charge(body);},
    consumeObservation:charge=>{state.observationCharges++;row.observe(charge);},
    consumePage:(rows,{charge})=>{row.page(rows,charge);state.rows.push(...rows);}};
  const create=(overrides={})=>{
    const selected={...options,...overrides};
    const bound=Object.freeze({...selected.limits});
    const site={credential:selected.credential,referenceCurrent:()=>true,callResource:callHttpsCredentialResource};
    const originalSite=Object.freeze({site,referenceCurrent:()=>true,callResource:callHttpsCredentialResource,
      authorizationPurpose(original) {assert.equal(original,selected.initialAuthorization);return {kind:'read'};},
      bindRunAcquisition(original,callbacks) {
        assert.equal(original,selected.initialAuthorization);callbacks.assertCurrent();
        const binding=openHttpsCredentialBinding({...selected.credential,scope:original.scope,
          maxSecretBytes:128,assertCurrent:callbacks.assertCurrent});
        return Object.freeze({credential:Object.freeze({...selected.credential,binding,
          currentBeforeSend:callbacks.observeCurrent}),close:()=>closeHttpsCredentialBinding(binding)});
      }
    });
    const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},operation:NOTION_USER_LIST_OPERATION,
      maxResponses:bound.maxPages,maxResponseBytes:bound.maxResponseBytes,maxSecretBytes:128,
      preparePageReader:({columns},applySynchronousProjection)=>prepareNotionUserListPages({moon:selected.moon,names:columns,limits:bound},applySynchronousProjection)});
    factories.push(factory);
    const reader=factory.prepare({originalAuthorization:selected.initialAuthorization,resource:'users',columns:selected.names,signal:selected.signal,
      verifyRead:typeof selected.current==='function'?()=>selected.current(NOTION_USER_LIST_OPERATION):selected.current,
      authorizationFor:typeof selected.authorizationFor==='function'?index=>selected.authorizationFor({operation:NOTION_USER_LIST_OPERATION,index}):selected.authorizationFor,
      chargePage:typeof selected.chargeResponse==='function'?body=>selected.chargeResponse(body):selected.chargeResponse,
      consumePage:typeof selected.consumePage==='function'?(rows,ticket)=>selected.consumePage(rows,ticket):selected.consumePage});
    readers.push(reader);return reader;
  };
  return {root,state,row,journal,scope,grant,control,sign,options,current,writeAccount,create,readers};
}

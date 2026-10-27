import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual Common/Credential/SQLite/TLS and legacy accounted canonical RowRun.
// Explicit component bounds do not fund the retained reader graph, establish
// normal physical retirement, or qualify a pristine installed Slack product.
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,randomUUID} from 'node:crypto';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson,createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {createSlackUserListReader,SLACK_USER_LIST_OPERATION,
  SLACK_WORKSPACE_IDENTITY_OPERATION} from '../site/user-list-read.mjs';

const repo=new URL('../../../../',import.meta.url).pathname;
const control=runtimeCore(common).remoteCredentialControl;
const cid=c=>`sha256:${c.repeat(64)}`;
const read=name=>readFile(join(repo,name),'utf8');
export const userListReadLimits=Object.freeze({maxResponseBytes:8192,maxTotalResponseBytes:24576,
  maxNodes:512,maxDepth:16,maxRows:10,maxTotalRows:20,maxPages:4,pageSize:10,
  maxCursorBytes:128,maxIdentityBytes:128,maxTargetBytes:1024,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8});
export const userPage=(members,nextCursor)=>({ok:true,members,response_metadata:{next_cursor:nextCursor}});

async function rowOwner(verifyTransport,format) {
  const wire=checked(provider.slackUserListSchemaWire(4096,100,8));
  assert.deepEqual(JSON.parse(wire),{deleted:{nullable:true,type:'boolean'},display_name:{nullable:true,type:'string'},
    email:{nullable:true,type:'string'},id:{nullable:false,type:'string'},is_bot:{nullable:true,type:'boolean'},
    name:{nullable:true,type:'string'},real_name:{nullable:true,type:'string'},tz:{nullable:true,type:'string'}});
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('slack','slack','slack/0.1',
    JSON.stringify({views:[{resource:'users',resource_kind:'slack_users',schema_wire:wire,
      schema_cid:`sha256:${createHash('sha256').update(wire).digest('hex')}`,
      facts_wire:'{"relation_keys":{"candidate_keys":[["id"]]}}'}]}),undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(),declared);
  const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);
  const view=declared.views[0];
  const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:[{name:'slack.users',
    sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}]});
  const preparation=common.clientProgramPrepareSourceWithParameters(
    format==='sql'?'SELECT id, name FROM slack.users':'FROM slack.users |> SELECT id, name',
    format,check,publication,undefined,undefined);
  const program=common.clientProgramPreparationReady(preparation);
  assert.ok(program,common.clientProgramPreparationIssueCode(preparation));
  const [registry,aoa,query,evidence]=await Promise.all([read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement=checked(common.clientProgramPrepareLocalQueryRequirement(program,0,0,registry,
    JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const acquisition=checked(common.clientProgramRowSourcePrepareAcquisition(declaration,requirement,query,evidence));
  // Independent component reservations, not a normal installed reader supplier.
  const ledger=checked(common.clientProgramAcquisitionLedger(1,1,65536n,100000000n,100000000n,0));
  const run=checked(common.clientProgramRowSourceStartAccounted(acquisition,randomUUID(),verifyTransport,ledger,65536n,8192n));
  checked(common.clientProgramRowSourceBegin(run,8192,5,20,undefined));
  return {charge:body=>checked(common.clientProgramRowSourceChargePage(run,body)),
    observe:charge=>checked(common.clientProgramRowSourceConsumeObservationCharge(run,charge)),
    page:(rows,charge)=>checked(common.clientProgramRowSourceAcceptChargedPage(run,charge,Buffer.from(JSON.stringify(rows)))),
    finish:()=>checked(common.clientProgramRowSourceFinish(run)),
    captureCount:()=>{const capture=checked(common.clientProgramRowSourceCapture(run));
      const source=checked(common.clientProgramRowSourceCaptureSource(capture));
      return common.clientProgramCapturedSourceRowCount(checked(common.clientProgramIdentifyCapturedSourceRelation(source)));},
    assertNoCapture:()=>assert.throws(()=>checked(common.clientProgramRowSourceCapture(run)),{code:'MoonBitHostFailure'}),
    usage:()=>common.clientProgramMultiCapturedLedgerUsage(ledger),
    close:()=>checked(common.clientProgramRowSourceCloseAccounted(run))};
}

export async function userListFixture(t,{account='allow',format='sql',accounted=true}={}) {
  const parent=join(repo,'_build','slack-user-list-fixtures');await mkdir(parent,{recursive:true});
  const root=await mkdtemp(join(parent,'query-'));
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout','server.key',
    '-out','server.crt','-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd:root,stdio:'ignore'});
  const [key,cert]=await Promise.all([readFile(join(root,'server.key')),readFile(join(root,'server.crt'))]);
  const state={identity:{ok:true,team_id:'T-original',user_id:'U-bot',bot_id:'B-original'},
    pages:[userPage([{id:'U1',name:'one'}],'opaque+/= cursor'),userPage([{id:'U2',name:'two'}],null)],
    requests:[],resolutions:0,charges:0,observationCharges:0,rows:[],status:200,
    secret:'slack-fixture-token',beforeResponse:undefined,resolved:undefined};
  const server=createServer({key,cert},async(request,response)=>{
    const chunks=[];for await(const chunk of request)chunks.push(chunk);
    state.requests.push({path:request.url,method:request.method,authorization:request.headers.authorization,
      contentType:request.headers['content-type'],body:Buffer.concat(chunks)});
    try {
      await state.beforeResponse?.(request,response);
      if(response.destroyed||response.writableEnded)return;
      const body=request.url==='/api/auth.test'?state.identity:state.pages[state.requests.length-2];
      assert.notEqual(body,undefined);
      response.writeHead(state.status,{'content-type':'application/json'});
      response.end(typeof body==='string'?body:JSON.stringify(body));
    } catch(cause){response.destroy(cause);}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  let journal,binding,row;
  t.after(async()=>{
    const errors=[];
    try{if(binding)assert.equal(closeHttpsCredentialBinding(binding),'closed');}catch(cause){errors.push(cause);}
    try{if(row){row.close();assert.deepEqual(ledgerUsageFieldsFor(row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),[0n,0n,0n,0n]);}}catch(cause){errors.push(cause);}
    try{journal?.close();}catch(cause){errors.push(cause);}
    try{await new Promise((resolve,reject)=>server.close(cause=>cause?reject(cause):resolve()));}catch(cause){errors.push(cause);}
    t.diagnostic(`Retained original Slack fixture: ${root}`);
    if(errors.length)throw new AggregateError(errors,'SlackUserListFixtureCleanupUnconfirmed');
  });
  const authority=generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root,'credential-authority.key'),authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),
    writeFile(join(root,'credential-authority.pub'),authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal=openSqliteCredentialJournal(join(root,'credential-journal'),{credentialAuthorities:new Map([
    ['slack-fixture',new Map([['key',authority.publicKey]])]])});
  const scope=Object.freeze({issuerAuthority:'slack-fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'slack',connectorRevision:'slack/0.1',
    resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:SLACK_USER_LIST_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),
    expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:5});
  const grant=control.prepare(scope),authScope=Object.freeze({...scope,operation:SLACK_WORKSPACE_IDENTITY_OPERATION,maxUses:1});
  const authGrant=control.prepare(authScope);
  const sign=value=>signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  for(const original of [grant,authGrant])journal.acceptGrant(sign(original),control);
  const accountPath=join(root,'account.json');
  const writeAccount=outcome=>writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',
    account_id:'fixture',entries:[{entry_id:'slack-read',outcome,principal:{all:true},connection:{any_of:['slack:fixture']},
      resource:{any_of:['users']},operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context:{principal:'operator',contextCid:cid('d')}});
  const current=async()=>{const decision=await gate.authorize('acquisition',{connection:'slack:fixture',resource:'users',operation:'read'},
    {subjectCid:scope.runInvocationCid});if(decision.action!=='dispatch')throw Object.assign(new Error('SlackReadDenied'),{code:'SlackReadDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async()=>{state.resolutions++;await state.resolved?.();return state.secret;}};
  binding=openHttpsCredentialBinding({...credential,scope,maxSecretBytes:128});
  if(accounted)row=await rowOwner(()=>closeHttpsCredentialBinding(binding)==='closed',format);
  const authorizationFor=({operation,index})=>operation===SLACK_WORKSPACE_IDENTITY_OPERATION
    ?{grant:authGrant,scope:authScope,useId:'identity-0'}:{grant,scope,useId:`users-${index}`};
  const options={moon:provider,workspaceId:'T-original',names:provider.slackUserListColumnNames(),
    initialAuthorization:{grant,scope,useId:'initial'},credential:{...credential,binding},
    authorizationFor,limits:userListReadLimits,current,
    chargeResponse:body=>{state.charges++;return row.charge(body);},
    consumeObservation:charge=>{state.observationCharges++;row.observe(charge);},
    consumePage:(rows,{charge})=>{row.page(rows,charge);state.rows.push(...rows);}};
  return {root,state,row,journal,binding,scope,grant,authScope,authGrant,control,sign,options,current,writeAccount,
    create:overrides=>createSlackUserListReader({...options,...overrides})};
}

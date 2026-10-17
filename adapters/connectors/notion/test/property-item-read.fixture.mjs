// Actual Common Credential/SQLite/Account/TLS, with explicit observation-ticket
// doubles. No numerical RowRun/capture/retirement or installed Source claim.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson,createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {createNotionPropertyReader,NOTION_PROPERTY_READ_OPERATION} from '../site/property-item-read.mjs';

const repo=new URL('../../../../',import.meta.url).pathname;
const control=runtimeCore(common).remoteCredentialControl;
const cid=x=>'sha256:'+x.repeat(64);
const metadata=[16384,1024,20,8,8,128,128];
const declarationBounds=[...metadata,256,16,4096,16,100000];
export const propertyReadLimits=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:65536,
  maxTargetBytes:1024,maxPages:8,pageSize:10,maxValueNodes:128,maxValueDepth:16,
  maxValueTextBytes:4096,maxWireBytes:8192,maxWireNodes:256,maxWireDepth:16});
export function propertyItemPage(text,cursor=null){return{object:'list',type:'property_item',results:text.map(plain=>({
  object:'property_item',id:'t%3Ax',type:'rich_text',rich_text:{type:'text',text:{content:plain},plain_text:plain},
})),has_more:cursor!==null,next_cursor:cursor,property_item:{id:'t%3Ax',type:'rich_text',rich_text:{},
  next_url:cursor===null?null:'https://foreign.example.test/do-not-follow'}};}

export function propertyOriginals({enumeration,propertyLimits={}}={}){
  const database=checked(provider.notionProjectDatabase(Buffer.from('{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}'),...metadata));
  const source=checked(provider.notionProjectDataSource(database,0,Buffer.from('{"object":"data_source","id":"s","parent":{"type":"database_id","database_id":"db"},"properties":{"text":{"id":"t%3Ax","name":"text","type":"rich_text","rich_text":{}}}}'),...metadata));
  const contract={type:'string',nullable:false,...(enumeration===undefined?{}:{enum:enumeration})};
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{'t%3Ax':[{column:'text',projection:'value',contract}]}})),...declarationBounds));
  const binding=checked(provider.notionBindDataSourceReadContracts(declaration,source,...declarationBounds));
  const page=checked(provider.notionProjectQueryPage(source,Buffer.from('{"object":"list","type":"page_or_data_source","page_or_data_source":{},"results":[{"object":"page","id":"page","parent":{"type":"data_source_id","data_source_id":"s"},"properties":{"text":{"id":"t%3Ax","type":"rich_text","rich_text":[],"has_more":true}}}],"has_more":false,"next_cursor":null}'),...metadata,100,128));
  const limits={maxPages:8,maxItems:128,maxTotalBytes:65536,maxTotalNodes:4096,maxTotalTextBytes:32768,maxCursorBytes:128,maxWork:1000000,...propertyLimits};
  const request=checked(provider.notionStartColumnPropertyRequest(binding,page,0,0,...metadata,
    limits.maxPages,limits.maxItems,limits.maxTotalBytes,limits.maxTotalNodes,limits.maxTotalTextBytes,limits.maxCursorBytes,limits.maxWork));
  return{binding,request};
}

export async function propertyReadFixture(t,{account='allow',enumeration,propertyLimits,additionalOperations=[]}={}){
  const parent=join(repo,'_build','notion-property-fixtures');await mkdir(parent,{recursive:true});
  const root=await mkdtemp(join(parent,'read-'));
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout','server.key','-out','server.crt','-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],{cwd:root,stdio:'ignore'});
  const [key,cert]=await Promise.all([readFile(join(root,'server.key')),readFile(join(root,'server.crt'))]);
  const state={pages:[propertyItemPage(['é\r\n'],'opaque+/= cursor'),propertyItemPage(['😀'])],requests:[],resolutions:0,
    charges:[],observations:[],values:[],secret:'notion-fixture-token',beforeResponse:undefined,resolved:undefined,status:200};
  const server=createServer({key,cert},async(request,response)=>{
    state.requests.push({path:request.url,method:request.method,authorization:request.headers.authorization,version:request.headers['notion-version']});
    try{let body='';for await(const chunk of request){body+=chunk.toString();assert(Buffer.byteLength(body)<=16384);}
      state.requests.at(-1).body=body;
      await state.beforeResponse?.(request,response);if(response.destroyed||response.writableEnded)return;
      const page=state.respond===undefined?state.pages[state.requests.length-1]:await state.respond(request,body);assert.notEqual(page,undefined);
      response.writeHead(state.status,{'content-type':'application/json'});response.end(typeof page==='string'||Buffer.isBuffer(page)?page:JSON.stringify(page));
    }catch(cause){response.destroy(cause);}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  let journal,binding;
  t.after(async()=>{
    const failures=[];
    try{if(binding)assert.equal(closeHttpsCredentialBinding(binding),'closed');}catch(cause){failures.push(cause);}
    try{journal?.close();}catch(cause){failures.push(cause);}
    try{await new Promise((resolve,reject)=>server.close(cause=>cause?reject(cause):resolve()));}catch(cause){failures.push(cause);}
    t.diagnostic(`Retained original Notion property fixture: ${root}`);
    if(failures.length)throw new AggregateError(failures,'NotionPropertyFixtureCleanupUnconfirmed');
  });
  const authority=generateKeyPairSync('ed25519');
  await Promise.all([writeFile(join(root,'credential-authority.key'),authority.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600}),writeFile(join(root,'credential-authority.pub'),authority.publicKey.export({format:'pem',type:'spki'}))]);
  journal=openSqliteCredentialJournal(join(root,'credential-journal'),{credentialAuthorities:new Map([['notion-property-fixture',new Map([['key',authority.publicKey]])]])});
  const scope=Object.freeze({issuerAuthority:'notion-property-fixture',principal:'operator',namespaceId:'fixture',environment:'test',siteKey:'site',siteGeneration:1,
    runtimeBundleCid:cid('a'),connectorRegistration:'notion',connectorRevision:'notion/0.1',resourceOrigin:`https://127.0.0.1:${server.address().port}`,operation:NOTION_PROPERTY_READ_OPERATION,
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:16});
  const grant=control.prepare(scope),sign=value=>signRemoteCredentialGrant(value,control,{keyId:'key',privateKey:authority.privateKey});
  journal.acceptGrant(sign(grant),control);
  // Each operation has its own actual signed original grant. The test never
  // retargets a property grant/use to authorize a database-query operation.
  const authorizations=new Map([[NOTION_PROPERTY_READ_OPERATION,{grant,scope}]]);
  for(const operation of additionalOperations){
    assert.equal(typeof operation,'string');assert(!authorizations.has(operation));
    const selected=Object.freeze({...scope,operation}),original=control.prepare(selected);
    journal.acceptGrant(sign(original),control);authorizations.set(operation,{grant:original,scope:selected});
  }
  const authorize=(operation,useId)=>{const original=authorizations.get(operation);assert(original);return{...original,useId};};
  const accountPath=join(root,'account.json');
  const writeAccount=outcome=>writeFile(accountPath,canonicalJson({version:'actql-execution-account-config/0.1',account_id:'fixture',entries:[{entry_id:'notion-property-read',outcome,
    principal:{all:true},connection:{any_of:['notion:fixture']},resource:{any_of:['property-fixture']},operation:{any_of:['read']},exclusions:[]}]}));
  await writeAccount(account);
  const gate=await createLocalAuthorizationGate({accountConfig:accountPath,principal:'operator',context:{principal:'operator',contextCid:cid('d')}});
  const current=async()=>{const decision=await gate.authorize('acquisition',{connection:'notion:fixture',resource:'property-fixture',operation:'read'},{subjectCid:scope.runInvocationCid});
    if(decision.action!=='dispatch')throw Object.assign(new Error('NotionPropertyDenied'),{code:'NotionPropertyDenied'});};
  const credential={control,journal,ca:cert,resolveSecret:async()=>{state.resolutions++;await state.resolved?.();return state.secret;}};
  binding=openHttpsCredentialBinding({...credential,scope,maxSecretBytes:128});
  const originals=propertyOriginals({enumeration,propertyLimits});
  const authorizationFor=({operation,index})=>{assert.equal(operation,NOTION_PROPERTY_READ_OPERATION);return{grant,scope,useId:`property-${index}`};};
  const consumed=new Set();
  const consume=charge=>{assert(state.charges.includes(charge));assert(!consumed.has(charge));consumed.add(charge);};
  const options={moon:provider,originalRequest:originals.request,readContracts:originals.binding,column:0,
    initialAuthorization:{grant,scope,useId:'initial'},credential:{...credential,binding},authorizationFor,current,limits:propertyReadLimits,
    chargeResponse:body=>{const charge=Object.freeze({originalBody:body});state.charges.push(charge);return charge;},
    consumeObservation:charge=>{consume(charge);state.observations.push(charge);},
    consumeValue:(wire,{charge})=>{consume(charge);state.values.push(wire);}};
  return{root,state,scope,grant,control,sign,journal,options,current,writeAccount,originals,authorize,
    create:overrides=>createNotionPropertyReader({...options,...overrides})};
}

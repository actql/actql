import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {parse} from 'acorn';
import {types as nodeTypes} from 'node:util';
import {pathToFileURL} from 'node:url';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {prepareSlackSourceReadSequence as currentSequence} from '../site/slack-source-read.mjs';

const root=new URL('../../../../',import.meta.url);
const baseline='dd149689ca05a4f570d4c2f9099a9f5b3fb02913';
const mode=process.env.ACTQL_TEST_SLACK_JOIN_SOURCE??'current';
const read=(path,original=false)=>original?execFileSync('git',['show',baseline+':'+path],{cwd:root,encoding:'utf8'})
  :readFileSync(new URL(path,root),'utf8');
const provider=await import(process.env.ACTQL_SLACK_PROVIDER_MODULE===undefined
  ?new URL('_build/js/release/build/connectors/slack/host_node/host_node.js',root)
  :pathToFileURL(process.env.ACTQL_SLACK_PROVIDER_MODULE));
let sequence=currentSequence;
if(mode!=='current'){
  // Exact frozen authored body, only relative import URLs resolved to this
  // same checkout. A component before-body, never a normal product overlay.
  const path='adapters/connectors/slack/site/slack-source-read.mjs';
  const source=read(path,true).replace(/from '([^']+)'/gu,(_match,name)=>'from '+JSON.stringify(new URL(name,new URL(path,root)).href));
  sequence=(await import('data:text/javascript,'+encodeURIComponent(source))).prepareSlackSourceReadSequence;
}
function property(source,name){
  let selected;
  const visit=node=>{
    if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name===name&&['FunctionExpression','ArrowFunctionExpression'].includes(node.value.type)){
      assert.equal(selected,undefined);selected=(node.method?'function':'')+source.slice(node.value.start,node.value.end);
    }
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  };
  visit(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(selected);return selected;
}
const limits=Object.freeze({maxResponseBytes:8192,maxTotalResponseBytes:24576,maxNodes:512,maxDepth:16,
  maxRows:10,maxTotalRows:20,maxPages:4,pageSize:10,maxCursorBytes:128,maxIdentityBytes:128,
  maxTargetBytes:1024,maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8});
const fail=code=>{throw Object.assign(new Error(code),{code});};

test('actual Slack service reader RowRun and Catalog join carries bounded POST and original requests',async()=>{
  // Actual three JS bodies and original Catalog; Account/Resource/charge/Host
  // capacity ports are explicit. No normal admission or physical ACK claim.
  const installation={},selection={},site={},capacity={},runtime='original-runtime',credential={};
  const physicalSite={},requests=[],rows=[],charged=new Set();let serial=0,consumed=0;
  const scope=operation=>Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,'original:'+name])),operation});
  const grant=Object.freeze({scope:scope('slack:users:list'),grant:{}});
  const currentRead=async()=>({action:'dispatch'});
  const rowSite={issueReadGrant(input){assert.equal(this,rowSite);assert.equal(input.resource,'users');
    assert.equal(input.operation,'slack:workspace:identity');assert.equal(input.maxUses,1);
    return Object.freeze({scope:scope(input.operation),grant:{}});}};
  const originalSite={site:physicalSite,referenceCurrent(){return true;},authorizationPurpose(){return{kind:'read'};},
    bindRunAcquisition(original,callbacks){assert.equal(original,grant);callbacks.assertCurrent();
      return Object.freeze({credential,close(){return'closed';},retire(){return true;}});},
    readChildCredential(original){assert.equal(original.credential,credential);return credential;},
    async callResource(input){assert.equal(this,physicalSite);await input.currentBeforeSend();
      const [operation,request]=[...input.operations][0];requests.push({operation,request});
      const body=request.path==='/api/auth.test'?{ok:true,team_id:'T-original',user_id:'U-bot',bot_id:'B-original'}
        :{ok:true,members:[{id:'U1',name:'one'}],response_metadata:{next_cursor:null}};
      const response=Object.freeze({accepted:true,statusCode:200,body:Buffer.from(JSON.stringify(body))});
      input.responseCustody.retain(response);return response;}};
  const implementation={runtimeBundleCid:runtime,value:{capacity,limits:{...limits,maxPages:5}},
    [mode==='original'?'slackLimits':'readSequenceConstruction']:{original:limits,originalLimits:limits,maxRequestBytes:2,
      sequences:{users:{operation:'slack:users:list',maxUses:4,
      children:[{operation:'slack:workspace:identity',maxUses:1}]}}}};
  const constructor={scope:{}};
  const sourceImplementations=new WeakMap([[selection,implementation]]),selected=new WeakMap([[installation,runtime]]),
    siteInstallations=new WeakMap([[site,selection]]),sourceContexts=new WeakMap([[selection,constructor]]);
  const serviceSource=read('adapters/host-node/installed-host-services.mjs',mode==='original');
  const ports={services:Object.freeze({}),current(){},publicationOnly:false,nodeTypes,fail,requireSourceConstructor:()=>selection,
    sourceImplementations,selected,siteInstallations,sourceContexts,
    installedRowCredentialOperationSite:()=>originalSite,createInstalledCredentialSourceReader};
  const create=Function(...Object.keys(ports),'return '+property(serviceSource,'createSourceReader')+';')(...Object.values(ports));
  const factory=create({installation,implementation:implementation.value,site,
    prepareReadSequence({resource,columns},apply){return sequence({moon:provider,workspaceId:'T-original',resource,names:columns,limits},apply);}});
  const readerDemand=constructor.scope.readerDemand;
  assert.equal(readerDemand.sequences,implementation[mode==='original'?'slackLimits':'readSequenceConstruction'].sequences);
  const rowPorts={readerDemand,operation:'slack:users:list',nodeTypes,fail,currentRead,prepared:{},access:{},signal:undefined,
    owner:{resource:'users'},site:rowSite,runInvocationCid:'run',dispatchRequestCid:'dispatch',grant,directReadIdentity:undefined,
    nonce:'request',text:value=>typeof value==='string'&&value.length>0};
  const authorizeReadChild=Function(...Object.keys(rowPorts),'let readChildIndex=0,rootReadUses=0,propertyOccurrences=0;'+
    'const readChildOriginals=new WeakMap(),readChildGrants=new Map(),readChildUses=new Map();return '+
    property(read('adapters/host-node/installed-row-source.mjs'),'authorizeReadChild')+';')(...Object.values(rowPorts));
  const reader=factory.prepare({resource:'users',columns:['id'],originalAuthorization:grant,
    verifyRead:currentRead,authorizationFor:async()=>({...grant,useId:'original-root'}),authorizeReadChild,
    chargePage(body){assert(Buffer.isBuffer(body));const charge=Object.freeze({serial:++serial});charged.add(charge);return charge;},
    consumeObservation(charge){assert(charged.delete(charge));consumed++;},
    consumePage(value,{charge}){assert(charged.delete(charge));consumed++;rows.push(...value);}});
  await reader.read();
  assert.deepEqual(rows.map(value=>[value.id,value.name]),[['U1','one']]);
  assert.deepEqual(requests.map(value=>[value.operation,value.request.method,value.request.path]),[
    ['slack:workspace:identity','POST','/api/auth.test'],['slack:users:list','GET','/api/users.list?limit=10']]);
  assert.equal(requests[0].request.body,'{}');assert.equal(consumed,2);assert.equal(charged.size,0);
  await reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

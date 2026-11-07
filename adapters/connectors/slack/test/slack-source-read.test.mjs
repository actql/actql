import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {loadInstalledSlackSource} from '../host/installed-slack-source.mjs';
import {prepareSlackSourceReadSequence} from '../site/slack-source-read.mjs';
import {createInstalledHostServices,retainInstalledHostServiceInstallation} from '../../../host-node/installed-host-services.mjs';
import {installedJsonSourceReaderProfileLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';

const provider=await import(process.env.ACTQL_SLACK_PROVIDER_MODULE===undefined
  ?new URL('../../../../_build/js/release/build/connectors/slack/host_node/host_node.js',import.meta.url)
  :pathToFileURL(process.env.ACTQL_SLACK_PROVIDER_MODULE));
const limits=Object.freeze({maxResponseBytes:8192,maxTotalResponseBytes:65536,maxNodes:512,maxDepth:16,
  maxRows:10,maxTotalRows:20,maxPages:8,pageSize:10,maxCursorBytes:128,maxIdentityBytes:128,
  maxTargetBytes:1024,maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,
  maxRowsWireNodes:200,maxRowsWireDepth:8});
const identity={ok:true,team_id:'T-original',user_id:'U-bot',bot_id:'B-original'};
const page=(field,rows,cursor=null)=>({ok:true,[field]:rows,has_more:false,response_metadata:{next_cursor:cursor}});
// Actual Catalog originals, explicit pure IO/charge/current ports only. This
// component does not claim Host, Account, Resource or physical retirement.
function fixture(resource,respond,overrides={}){
  const requests=[],rows=[];let charged=false,consumed=0;
  const apply=(fn,receiver,args)=>Reflect.apply(fn,receiver,args);
  const sequence=prepareSlackSourceReadSequence({moon:provider,workspaceId:'T-original',resource,
    names:['id'],limits:{...limits,...overrides}},apply);
  const context={project:apply,async readChild(original){
    assert.equal(charged,false,'each original charge must be consumed before another request');
    const selected=original.prepare();requests.push({operation:original.operation,...selected.request});
    const response=await respond(selected.request,requests.length);
    charged=true;
    return selected.project({accepted:true,statusCode:200,body:Buffer.from(JSON.stringify(response))});
  },async consumeObservation(){assert.equal(charged,true);charged=false;consumed++;},
  async consumePage(value){assert.equal(charged,true);charged=false;consumed++;rows.push(...value);}};
  return{sequence,context,requests,rows,consumed:()=>consumed};
}

test('managed Slack users authenticates the original workspace before paged complete rows',async()=>{
  const f=fixture('users',(request,index)=>index===1?identity:index===2
    ?page('members',[{id:'U1',name:'one'}],'opaque+/= cursor'):page('members',[{id:'U2',name:'two'}]));
  await f.sequence.read(f.context);
  assert.deepEqual(f.rows.map(row=>[row.id,row.name]),[['U1','one'],['U2','two']]);
  assert.equal(Object.keys(f.rows[0]).length,8,'the checked Program receives the complete original schema');
  assert.deepEqual(f.requests.map(value=>[value.operation,value.method,value.path]),[
    ['slack:workspace:identity','POST','/api/auth.test'],['slack:users:list','GET','/api/users.list'],
    ['slack:users:list','GET','/api/users.list']]);
  assert.deepEqual(f.requests[2].query,[['limit','10'],['cursor','opaque+/= cursor']]);
  assert.equal(f.consumed(),3);assert.equal(f.sequence.retire(),true);
  await assert.rejects(f.sequence.read(f.context),{code:'InstalledSlackReaderAlreadyStarted'});
});

test('managed Slack channels preserves the selected complete conversation schema',async()=>{
  const f=fixture('channels',request=>request.path==='/api/auth.test'?identity:
    page('channels',[{id:'C1',name:'general',is_private:false,is_archived:false}]));
  await f.sequence.read(f.context);
  assert.deepEqual(f.rows.map(row=>[row.id,row.name]),[['C1','general']]);
  assert.equal(Object.keys(f.rows[0]).length,8);
  assert.deepEqual(f.requests[1].query,[['types','public_channel,private_channel'],['exclude_archived','false'],['limit','10']]);
  assert.equal(f.sequence.retire(),true);
});

test('managed Slack messages keeps original channel history reply and nanosecond coalescence',async()=>{
  const f=fixture('messages',request=>{
    const query=Object.fromEntries(request.query);
    if(request.path==='/api/auth.test')return identity;
    if(request.path==='/api/conversations.list')return page('channels',[
      {id:'C1',is_im:false,is_mpim:false},{id:'D1',is_im:true,is_mpim:false}]);
    if(request.path==='/api/conversations.history')return page('messages',query.channel==='C1'
      ?[{type:'message',ts:'1.000001',text:'parent',reply_count:1}]
      :[{type:'message',ts:'3.000000001',text:'direct'}]);
    assert.equal(request.path,'/api/conversations.replies');
    return page('messages',query.channel==='C1'
      ?[{type:'message',ts:'1.000001',thread_ts:'1.000001',text:'parent',reply_count:1},
        {type:'message',ts:'2.000001',thread_ts:'1.000001',text:'child'}]
      :[{type:'message',ts:'3.000000001',text:'direct'}]);
  });
  await f.sequence.read(f.context);
  assert.deepEqual(f.rows.map(row=>[row.channel,row.ts,row.text]),[
    ['C1','1.000001','parent'],['C1','2.000001','child'],['D1','3.000000001','direct']]);
  assert.equal(f.requests.length,8);assert.equal(f.consumed(),8);
  assert.equal(f.requests[1].query[0][1],'public_channel,private_channel,mpim,im');
  assert.equal(f.sequence.retire(),true);
});

test('managed Slack refuses a foreign workspace and repeated cursor without another request',async()=>{
  const foreign=fixture('users',()=>({...identity,team_id:'T-foreign'}));
  await assert.rejects(foreign.sequence.read(foreign.context),{code:'ForeignSlackWorkspace'});
  assert.equal(foreign.requests.length,1);assert.equal(foreign.sequence.retire(),true);
  const repeat=fixture('users',(request,index)=>index===1?identity:page('members',[{id:'U'+index}],'repeat'));
  await assert.rejects(repeat.sequence.read(repeat.context),{code:'SlackUserListRepeatedCursor'});
  assert.equal(repeat.requests.length,3);assert.equal(repeat.sequence.retire(),true);
});

test('managed Slack keeps a pending response borrower and the original messages exchange bound',async()=>{
  let release,entered;
  const waiting=new Promise(resolve=>{entered=resolve;});
  const f=fixture('users',()=>new Promise(resolve=>{release=resolve;entered();}));
  const running=f.sequence.read(f.context);await waiting;
  assert.equal(f.sequence.retire(),false);release(identity);
  // Only the untouched data response is supplied after the pending identity.
  f.context.readChild=async original=>{
    const selected=original.prepare();return selected.project({accepted:true,statusCode:200,
      body:Buffer.from(JSON.stringify(page('members',[])))});
  };
  f.context.consumePage=async rows=>{assert.deepEqual(rows,[]);};
  await running;assert.equal(f.sequence.retire(),true);
  const bounded=fixture('messages',request=>request.path==='/api/auth.test'?identity:page('channels',[
    {id:'C1',is_im:false,is_mpim:false}]),{maxPages:2});
  await assert.rejects(bounded.sequence.read(bounded.context),{code:'InstalledSlackMessagesRequestLimit'});
  assert.equal(bounded.requests.length,2);assert.equal(bounded.sequence.retire(),true);
});

test('generic Source service retains the complete original Slack construction without dispatch or a second quote',async()=>{
  const f=await sourceConstruction(),installation=Object.freeze({registration:'not-a-dispatch-key'});
  const moon={clientProgramInstalledSourceReaderPolicy:()=>[65536,100000,100],
    clientProgramInstalledJsonSourceReaderProfile:()=>({$tag:1,_0:installedJsonSourceReaderProfileLimitNames.map(()=>100000)}),
    clientProgramInstalledJsonSourceReaderCapacity(){assert.fail('Generic pages must not replace the original complete recipe');}};
  const services=createInstalledHostServices({root:'/UNOPENED',principalId:'component',moon,assertCurrent(){}});
  retainInstalledHostServiceInstallation(services,installation,'sha256:'+'a'.repeat(64));
  services.sourceReaderImplementationProfile({installation,metadataResponses:1,originUnits:20});
  const selection={installation,columnCount:11,limits:f.input.limits,readSequenceConstruction:f.input.readSequenceConstruction};
  const selected=services.sourceReaderImplementation(selection);
  assert.equal(selected.capacity,f.capacity);assert.equal(f.quotes.length,1);
  assert.equal(services.sourceReaderImplementation({...selection,limits:{...f.input.limits}}),selected);
  assert.throws(()=>services.sourceReaderImplementation({...selection,
    readSequenceConstruction:Object.freeze({...f.input.readSequenceConstruction,
      originalLimits:Object.freeze({...f.selectedLimits,maxCaBytes:16385})})}),{code:'InstalledSourceReaderSelectionChanged'});
  assert.equal(f.quotes.length,1);
});

test('actual Slack RowRun grants keep identity channels history and replies separately bounded before reentry',async()=>{
  const source=readFileSync(new URL('../../../host-node/installed-row-source.mjs',import.meta.url),'utf8');
  let arrow;
  const visit=node=>{
    if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name==='authorizeReadChild'&&node.value.type==='ArrowFunctionExpression'){
      assert.equal(arrow,undefined);arrow=source.slice(node.value.start,node.value.end);
    }
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  };
  visit(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(arrow);
  const root={},decision={},grants=new Map(),events=[];let authorize,reenter;
  const selected={operation:'slack:messages:history',maxUses:2,children:[
    {operation:'slack:workspace:identity',maxUses:2},{operation:'slack:channels:list',maxUses:1},
    {operation:'slack:messages:replies',maxUses:2}]};
  const site={issueReadGrant(input){assert.equal(this,site);assert.equal(input.decision,decision);
    assert.equal(input.resource,'messages');events.push(input);const grant={};grants.set(input.operation,grant);return grant;}};
  const ports={readerDemand:{responses:7,sequences:{messages:selected}},operation:selected.operation,nodeTypes,
    fail:code=>{throw Object.assign(new Error(code),{code});},
    currentRead:async()=>{await reenter?.();return decision;},prepared:{},access:{},signal:undefined,
    owner:{resource:'messages'},site,runInvocationCid:'original-run',dispatchRequestCid:'original-dispatch',grant:root,
    directReadIdentity:undefined,nonce:'request',text:value=>typeof value==='string'&&value.length>0};
  authorize=Function(...Object.keys(ports),'let readChildIndex=0,rootReadUses=0,propertyOccurrences=0;'+
    'const readChildOriginals=new WeakMap(),readChildGrants=new Map(),readChildUses=new Map();return '+arrow+';')(...Object.values(ports));
  const first={};reenter=async()=>{reenter=undefined;
    await assert.rejects(authorize('slack:workspace:identity',0,first),{code:'InvalidInstalledSourceReadChild'});};
  assert.equal((await authorize('slack:workspace:identity',0,first)).originalAuthorization,grants.get('slack:workspace:identity'));
  await authorize('slack:channels:list',1,{});
  await assert.rejects(authorize('slack:channels:list',2,{}),{code:'InstalledSourceReadChildUseLimit'});
  assert.equal((await authorize('slack:messages:history',2,{})).originalAuthorization,root);
  await authorize('slack:messages:replies',3,{});
  await authorize('slack:workspace:identity',4,{});
  await assert.rejects(authorize('slack:workspace:identity',5,{}),{code:'InstalledSourceReadChildUseLimit'});
  await authorize('slack:messages:history',5,{});await authorize('slack:messages:replies',6,{});
  await assert.rejects(authorize('slack:messages:history',7,{}),{code:'InvalidInstalledSourceReadChild'});
  assert.deepEqual(events.map(value=>[value.operation,value.maxUses]),[
    ['slack:workspace:identity',2],['slack:channels:list',1],['slack:messages:replies',2]]);
});


async function sourceConstruction(){
  const capacity={},installation={},quotes=[],stop=new Error('Original implementation boundary');let input;
  const selectedLimits=Object.freeze({...limits,maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384});
  const profile={version:'actql-installed-slack-source/0.1',connectorId:'original-slack',workspaceId:'T-original',
    siteProfilePath:'/UNOPENED/site.json',accountConfigurationWire:'{}',limits:selectedLimits};
  const site={version:'actql-installed-slack-site/0.1',apiOrigin:'https://slack.invalid',
    credentialAuthorityId:'authority',credentialKeyId:'key',credentialPrivateKeyPath:'/UNOPENED/key',
    environment:'fixture',journalRoot:'/UNOPENED/journal',namespaceId:'fixture',siteGeneration:1,siteKey:'slack'};
  const sourceInitialization=Object.freeze({prepareDeclaration(){assert.fail('No declaration beyond implementation boundary');}});
  const moon={clientProgramInstalledSlackSourceReaderCapacity(...args){assert.equal(this,moon);quotes.push(args);return capacity;}};
  const services={sourceReaderImplementationProfile(){assert.equal(this,services);
    return Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(name=>[name,100000]));},
    sourceReaderImplementation(value){assert.equal(this,services);input=value;throw stop;},
    openRowSite(){assert.fail('No physical Site in this Source constructor scope');},
    createSourceReader(){assert.fail('No reader beyond implementation boundary');}};
  const declarationProvider=Object.fromEntries(['slackUserListSchemaWire','slackUserListRelationFactsWire',
    'slackChannelListSchemaWire','slackChannelListRelationFactsWire','slackMessageSchemaWire','slackMessageRelationFactsWire',
    'slackUserListColumnNames','slackChannelListColumnNames','slackMessageColumnNames'].map(name=>[name,function(){
    assert.equal(this,declarationProvider);assert(name.endsWith('ColumnNames'));
    return Array(name==='slackMessageColumnNames'?11:name==='slackUserListColumnNames'?8:10).fill('original');}]));
  const configurationReader={readJson(path){assert.equal(this,configurationReader);assert.equal(path,profile.siteProfilePath);return site;},
    readText(){assert.fail('No CA selected');}};
  await assert.rejects(loadInstalledSlackSource(profile,{moon,providerMoon:declarationProvider,installation,sourceInitialization,
    installationServices:services,configurationReader,resolveSecret(){assert.fail('No secret in constructor scope');}}),cause=>cause===stop);
  return{capacity,quotes,input,selectedLimits};
}

test('Slack Source hands its complete original capacity and all operation occurrences to the generic service',async()=>{
  const f=await sourceConstruction();
  assert.deepEqual(f.quotes,[[[8192,65536,512,16,10,20,9,10,128,128,1024,100,4096,8192,200,8],11,128,8]]);
  assert.equal(f.input.readSequenceConstruction.capacity,f.capacity);
  assert.deepEqual(f.input.readSequenceConstruction.originalLimits,f.selectedLimits);
  assert.equal(f.input.readSequenceConstruction.maxRequestBytes,2);
  assert.deepEqual(f.input.readSequenceConstruction.sequences,{
    users:{operation:'slack:users:list',maxUses:8,children:[{operation:'slack:workspace:identity',maxUses:1}]},
    channels:{operation:'slack:channels:list',maxUses:8,children:[{operation:'slack:workspace:identity',maxUses:1}]},
    messages:{operation:'slack:messages:history',maxUses:8,children:[
      {operation:'slack:workspace:identity',maxUses:8},{operation:'slack:channels:list',maxUses:8},{operation:'slack:messages:replies',maxUses:8}]},
  });
});

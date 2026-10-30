import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,invokeScopedCredentialOperation}
  from '../../../host-common/owned-invocation-context.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

// Execute the actual caller declarations with only HTTPS replaced by an
// explicit transport port. Common provider methods are the original compiled
// namespace; these cases are not normal Host/Account/RowRun acceptance.
const provider=await import(process.env.ACTQL_TEST_NOTION_URL??
  new URL('../../../../_build/js/release/build/connectors/notion/host_node/host_node.js',import.meta.url).href);
const usersOperation='notion:users:list',queryOperation='notion:data-sources:query';
function caller(file,name,transport){
  const text=readFileSync(new URL('../site/'+file,import.meta.url),'utf8');
  const declarations=parse(text,{ecmaVersion:'latest',sourceType:'module'}).body.flatMap(node=>{
    const value=node.declaration??node;
    return ['VariableDeclaration','FunctionDeclaration','ClassDeclaration'].includes(value.type)?[text.slice(value.start,value.end)]:[];
  }).join('\n');
  return Function('checked','ownInvocationContext','ownInvocationAuthorization','invocationBindingsMatch',
    'invokeScopedCredentialOperation','callHttpsCredentialResource','requestTarget',
    'createNotionPropertyReader','NOTION_PROPERTY_READ_OPERATION','NOTION_PROPERTY_READ_API_VERSION',
    declarations+'\nreturn '+name+';')(checked,ownInvocationContext,ownInvocationAuthorization,
      invocationBindingsMatch,invokeScopedCredentialOperation,transport,requestTarget,
      ()=>assert.fail('complete scalar rows require no property child'),'notion:pages:property:read','2026-03-11');
}
const bounds=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,maxRequestBytes:1024,maxTargetBytes:1024,
  maxPages:4,pageSize:2,maxTotalRows:3,maxRows:2,maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:8,
  maxIdentityBytes:128,maxNameBytes:128,maxCursorBytes:128,maxRowNodes:256,maxRowDepth:16,maxRowTextBytes:4096,
  maxColumns:16,maxRowWork:1000000,maxPageWork:1000000,maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20,
  maxPropertyPages:4,maxPropertyItems:128,maxPropertyBytes:65536,maxPropertyNodes:4096,maxPropertyTextBytes:32768,
  maxPropertyWork:1000000,maxValueNodes:100,maxValueTextBytes:4096});
const cursor='original /+é cursor';
const user=(id,name)=>({object:'user',id,name,type:'bot',bot:{}});
const userPage=(ids,next)=>({object:'list',type:'user',user:{},results:ids.map(id=>user(id,'name-'+id)),has_more:next!==null,next_cursor:next});
const queryPage=(ids,next)=>({object:'list',type:'page_or_data_source',page_or_data_source:{},results:ids.map(id=>({
  object:'page',id,parent:{type:'data_source_id',data_source_id:'s'},properties:{
    amount:{id:'n',type:'number',number:123.25},enabled:{id:'b',type:'checkbox',checkbox:true}}})),has_more:next!==null,next_cursor:next});
function queryOriginals(){
  const metadata=[16384,1024,20,8,8,128,128],declarationLimits=[...metadata,256,16,4096,16,100000];
  const database=checked(provider.notionProjectDatabase(Buffer.from('{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}'),...metadata));
  const source=checked(provider.notionProjectDataSource(database,0,Buffer.from('{"object":"data_source","id":"s","parent":{"type":"database_id","database_id":"db"},"properties":{"amount":{"id":"n","name":"amount","type":"number","number":{"format":"number"}},"enabled":{"id":"b","name":"enabled","type":"checkbox","checkbox":{}}}}'),...metadata));
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from('{"id":"db","read_contracts":{"n":[{"column":"amount","projection":"value","contract":{"type":"decimal","nullable":false,"precision":20,"scale":2}}]}}'),...declarationLimits));
  const readContracts=checked(provider.notionBindDataSourceReadContracts(declaration,source,...declarationLimits));
  return{declaration,source,readContracts};
}
function fixture(family,{maxTotalRows=3,pages,loseCurrentAfterPage=false}={}){
  const operation=family==='users'?usersOperation:queryOperation,requests=[],grants=[],charges=[],rows=[];
  const bodies=(pages??(family==='users'?[userPage(['one','two'],cursor),userPage(['three'],null)]:
    [queryPage(['one','two'],cursor),queryPage(['three'],null)])).map(page=>Buffer.from(JSON.stringify(page)));
  const scope=Object.freeze({operation}),cause=new Error('same original current refusal');let current=true;
  const verify=async selected=>{assert.equal(selected,operation);if(!current)throw cause;};
  const transport=async input=>{
    await input.currentBeforeSend();const request=input.operations.get(operation);assert(request);
    requests.push(request);assert(requests.length<=bodies.length);
    return{accepted:true,statusCode:200,body:bodies[requests.length-1]};
  };
  const create=caller(family==='users'?'user-list-read.mjs':'data-source-read.mjs',
    family==='users'?'createNotionUserListReader':'createNotionDataSourceReader',transport);
  const reader=create({moon:provider,...(family==='users'?{names:['id','name']}:queryOriginals()),
    initialAuthorization:{grant:{},scope,useId:'original'},credential:{binding:{}},limits:{...bounds,maxTotalRows},
    current:verify,authorizationFor(input){grants.push(input);return{grant:{},scope,useId:'page-'+input.index};},
    chargeResponse(body){assert.equal(body,bodies[requests.length-1]);const charge=Object.freeze({body});charges.push(charge);return charge;},
    consumeObservation(){assert.fail('no property response in scalar fixture');},
    consumePage(page,{charge}){assert.equal(charge,charges.at(-1));rows.push(...page);if(loseCurrentAfterPage)current=false;}});
  return{reader,requests,grants,charges,rows,cause,loseCurrent(){current=false;}};
}
for(const family of ['users','query']){
  test('Notion '+family+' requests only remaining rows on the unchanged original cursor',async()=>{
    const f=fixture(family),result=await f.reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,3);assert.equal(f.grants.length,2);assert.equal(f.charges.length,2);
    if(family==='users')assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://notion.invalid').searchParams.get('page_size')),['2','1']);
    else assert.deepEqual(f.requests.map(request=>JSON.parse(request.body)),[{page_size:2},{page_size:1,start_cursor:cursor}]);
    const final=f.requests[1];
    if(family==='users')assert.equal(new URL(final.path,'https://notion.invalid').searchParams.get('start_cursor'),cursor);
    assert.ok(f.requests.every(request=>request.method===(family==='users'?'GET':'POST')&&request.headers.some(([k,v])=>k==='notion-version'&&v==='2026-03-11')));
    assert.equal(f.rows.length,3);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
  test('Notion '+family+' exhausted remainder refuses before another indexed authorization or send',async()=>{
    const f=fixture(family,{maxTotalRows:2});
    await assert.rejects(f.reader.read(),error=>error.cause?.code===(family==='users'?'NotionUserListRowLimit':'NotionDataSourceRowLimit'));
    assert.equal(f.grants.length,1);assert.equal(f.requests.length,1);assert.equal(f.charges.length,1);
    assert.equal(f.rows.length,2,'the retained prefix is not a complete Source');
    assert.equal(f.reader.observe().phase,'failed');assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
}


for(const family of ['users','query']){
  test('Notion '+family+' over-return remains refused without truncating or delivering the last page',async()=>{
    const page=family==='users'?userPage:queryPage;
    const f=fixture(family,{pages:[page(['one','two'],cursor),page(['three','four'],null)]});
    await assert.rejects(f.reader.read(),error=>error.cause?.code===(family==='users'?'NotionUserListRowLimit':'NotionDataSourceRowLimit'));
    assert.equal(f.requests.length,2);assert.equal(f.grants.length,2);assert.equal(f.charges.length,2);
    assert.equal(f.rows.length,2,'only the earlier full page is retained');assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
  test('Notion '+family+' original current refusal prevents another authorization or remaining-row request',async()=>{
    const f=fixture(family,{loseCurrentAfterPage:true});
    await assert.rejects(f.reader.read(),error=>error.cause===f.cause);
    assert.equal(f.requests.length,1);assert.equal(f.grants.length,1);assert.equal(f.charges.length,1);
    assert.equal(f.rows.length,2);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
}

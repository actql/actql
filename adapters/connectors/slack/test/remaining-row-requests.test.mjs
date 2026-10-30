import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types} from 'node:util';
import {parse} from 'acorn';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,invokeScopedCredentialOperation}
  from '../../../host-common/owned-invocation-context.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

// Actual caller declarations and original compiled provider methods; only HTTPS
// is an explicit port. This does not qualify normal Host/Account/RowRun funding.
const provider=await import(process.env.ACTQL_TEST_SLACK_URL??
  new URL('../../../../_build/js/release/build/connectors/slack/host_node/host_node.js',import.meta.url).href);
const identityOperation='slack:workspace:identity';
const bounds=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,maxNodes:1024,maxDepth:20,
  maxRows:2,maxTotalRows:3,maxPages:4,pageSize:2,maxCursorBytes:128,maxIdentityBytes:128,
  maxTargetBytes:1024,maxValueNodes:128,maxValueTextBytes:4096,
  maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20});
const cursor='original /+é cursor';
function caller(family,transport){
  const source=readFileSync(new URL('../site/'+(family==='users'?'user-list-read.mjs':'channel-list-read.mjs'),import.meta.url),'utf8');
  const declarations=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body.flatMap(node=>{
    const value=node.declaration??node;
    return ['VariableDeclaration','FunctionDeclaration','ClassDeclaration'].includes(value.type)?[source.slice(value.start,value.end)]:[];
  }).join('\n');
  return Function('types','checked','ownInvocationContext','ownInvocationAuthorization','invocationBindingsMatch',
    'invokeScopedCredentialOperation','callHttpsCredentialResource','requestTarget',
    declarations+'\nreturn '+(family==='users'?'createSlackUserListReader':'createSlackChannelListReader')+';')(
      types,checked,ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
      invokeScopedCredentialOperation,transport,requestTarget);
}
function page(family,ids,next){
  return {ok:true,[family==='users'?'members':'channels']:ids.map(id=>({id,name:'name-'+id})),
    response_metadata:{next_cursor:next}};
}
function fixture(family,{maxTotalRows=3,pages,loseCurrentAfterPage=false,workspaceId='T-original'}={}){
  const operation=family==='users'?'slack:users:list':'slack:channels:list';
  const requests=[],grants=[],charges=[],rows=[],observationCharges=[];
  const bodies=[{ok:true,team_id:'T-original',user_id:'U-original'},
    ...(pages??[page(family,['one','two'],cursor),page(family,['three'],null)])].map(p=>Buffer.from(JSON.stringify(p)));
  const cause=new Error('same original current refusal');let current=true;
  const transport=async input=>{
    await input.currentBeforeSend();const selected=input.operations.get(input.scope.operation);assert(selected);
    requests.push(selected);assert(requests.length<=bodies.length);
    return {accepted:true,statusCode:200,body:bodies[requests.length-1]};
  };
  const reader=caller(family,transport)({moon:provider,workspaceId,names:['id','name'],
    initialAuthorization:{grant:{},scope:{operation},useId:'original'},credential:{binding:{}},
    limits:{...bounds,maxTotalRows},
    current:async()=>{if(!current)throw cause;},
    authorizationFor(input){grants.push(input);return{grant:{},scope:{operation:input.operation},useId:'original-'+input.operation+'-'+input.index};},
    chargeResponse(body){assert.equal(body,bodies[requests.length-1]);const charge=Object.freeze({body});charges.push(charge);return charge;},
    consumeObservation(charge){assert.equal(charge,charges[0]);observationCharges.push(charge);},
    consumePage(page,{charge}){assert.equal(charge,charges.at(-1));rows.push(...page);if(loseCurrentAfterPage)current=false;}});
  return{reader,requests,grants,charges,rows,observationCharges,cause,operation};
}
for(const family of ['users','channels']){
  test('Slack '+family+' requests remaining rows after the original workspace check',async()=>{
    const f=fixture(family),result=await f.reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,3);assert.equal(f.rows.length,3);
    assert.equal(f.requests[0].path,'/api/auth.test');assert.equal(f.requests[0].method,'POST');assert.equal(f.requests[0].body,'{}');
    assert.deepEqual(f.requests.slice(1).map(request=>new URL(request.path,'https://slack.invalid').searchParams.get('limit')),['2','1']);
    assert.equal(new URL(f.requests[2].path,'https://slack.invalid').searchParams.get('cursor'),cursor);
    assert.deepEqual(f.grants.map(x=>[x.operation,x.index]),[[identityOperation,0],[f.operation,0],[f.operation,1]]);
    assert.equal(f.observationCharges.length,1);assert.equal(f.charges.length,3);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
  test('Slack '+family+' zero remaining rows refuse before another grant or send',async()=>{
    const f=fixture(family,{maxTotalRows:2});
    await assert.rejects(f.reader.read(),e=>e.cause?.code===(family==='users'?'SlackUserListRowLimit':'SlackChannelListRowLimit'));
    assert.equal(f.requests.length,2);assert.equal(f.grants.length,2);assert.equal(f.charges.length,2);
    assert.equal(f.observationCharges.length,1);assert.equal(f.rows.length,2);assert.equal(f.reader.observe().phase,'failed');
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
}

for(const family of ['users','channels']){
  test('Slack '+family+' over-return refuses the last page without truncation or partial success',async()=>{
    const f=fixture(family,{pages:[page(family,['one','two'],cursor),page(family,['three','four'],null)]});
    await assert.rejects(f.reader.read(),e=>e.cause?.code===(family==='users'?'SlackUserListRowLimit':'SlackChannelListRowLimit'));
    assert.equal(f.requests.length,3);assert.equal(f.grants.length,3);assert.equal(f.charges.length,3);
    assert.deepEqual(f.rows.map(x=>x.id),['one','two']);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
  test('Slack '+family+' original current refusal prevents the next authorization and send',async()=>{
    const f=fixture(family,{loseCurrentAfterPage:true});
    await assert.rejects(f.reader.read(),e=>e.cause===f.cause);
    assert.equal(f.requests.length,2);assert.equal(f.grants.length,2);assert.equal(f.charges.length,2);
    assert.equal(f.rows.length,2);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
  test('Slack '+family+' foreign actual workspace observation refuses before a data grant',async()=>{
    const f=fixture(family,{workspaceId:'T-foreign'});
    await assert.rejects(f.reader.read(),e=>e.cause?.code==='ForeignSlackWorkspace');
    assert.equal(f.requests.length,1);assert.equal(f.grants.length,1);assert.equal(f.charges.length,1);
    assert.equal(f.observationCharges.length,0);assert.equal(f.rows.length,0);assert.equal(f.reader.observe().cleanupConfirmed,false);
  });
}

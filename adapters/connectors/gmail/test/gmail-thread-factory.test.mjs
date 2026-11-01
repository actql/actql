import assert from 'node:assert/strict';
import test from 'node:test';
import {GMAIL_THREAD_GET_OPERATION,GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';
import {threadFactoryFixture} from './gmail-thread-factory.fixture.mjs';

test('Gmail shared reader uses actual original Account Site and RowRun with separate get uses',async t=>{
  const f=await threadFactoryFixture(t);
  f.state.pages=[JSON.stringify({threads:[{id:'one'},{id:'two'}]}),JSON.stringify({id:'one',messages:[]}),JSON.stringify({id:'two',messages:[]})];
  const {reader,factory}=await f.makeReader(),result=await reader.read();
  assert.equal(result.rowCount,2);assert.equal(result.pages,3);
  assert.deepEqual(f.state.rows,['one','two'].map(id=>({id,labels:[],last_message_date:null,message_count:'0',subject:null})));
  assert.equal(f.grants.length,2);
  assert.deepEqual(f.grants.map(value=>value.options.operation),[GMAIL_THREAD_LIST_OPERATION,GMAIL_THREAD_GET_OPERATION]);
  assert.ok(f.grants.every(value=>f.authorization.issued(value.options.decision)));
  assert.notEqual(f.grants[0].original.grant,f.grants[1].original.grant);
  const uses=f.observations.map(response=>f.site.credential.journal.inspect(response.useCid));
  assert.notEqual(uses[0].grantCid,uses[1].grantCid);assert.equal(uses[1].grantCid,uses[2].grantCid);
  assert.notEqual(uses[1].useId,uses[2].useId);assert.equal(uses[1].useOrdinal,1);assert.equal(uses[2].useOrdinal,2);
  assert.equal(f.state.charges,3);f.row.finish();f.row.assertNoCapture();
  assert.equal(reader.observe().transportClosed,false);assert.equal(reader.observe().cleanupConfirmed,false);
  reader.requestStop();assert.equal(reader.observe().transportClosed,true);assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(factory.retire(),true);
  await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
});

test('Gmail shared reader captures original methods receivers and cannot bind its original authorization twice',async t=>{
  const f=await threadFactoryFixture(t),moon={...f.provider},prepare=moon.gmailPrepareThreadRead;
  moon.gmailPrepareThreadRead=function(...args){assert.equal(this,moon);return prepare(...args);};
  const {factory,reader,readerOptions}=await f.makeReader({moon});
  f.state.resolved=()=>{
    moon.gmailNextThreadRequest=()=>{throw Error('replacement provider');};
    f.suppliedSite.issueReadGrant=()=>{throw Error('replacement Site');};
    f.suppliedSite.callResource=()=>{throw Error('replacement physical caller');};
    f.options.verifyRead=()=>{throw Error('replacement current');};
  };
  assert.equal((await reader.read()).rowCount,1);
  const duplicate=factory.prepare(readerOptions);
  await assert.rejects(duplicate.read(),{code:'RowSourceCredentialAcquisitionAuthorizationConsumed'});
  duplicate.requestStop();reader.requestStop();assert.equal(factory.retire(),true);
  assert.equal(f.state.requests.length,2);
});

test('Gmail shared reader refuses copied Account decision before dependent get grant and send',async t=>{
  const f=await threadFactoryFixture(t),current=f.options.verifyRead;
  f.options.verifyRead=async function(){const original=await Reflect.apply(current,f.options,[]);
    return f.state.requests.length===0?original:{...original};};
  const {reader}=await f.makeReader();await assert.rejects(reader.read(),{code:'RowSourceGrantNotAuthorized'});
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.equal(f.grants.length,1);f.row.assertNoCapture();
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

test('Gmail shared reader keeps its captured original Run tuple across an unrelated caller container replacement',async t=>{
  const f=await threadFactoryFixture(t);
  f.hooks.afterCurrent=()=>{if(f.state.requests.length===1)f.options.rowRun={...f.rowRun,runInvocationCid:'foreign'};};
  const {reader}=await f.makeReader();assert.equal((await reader.read()).rowCount,1);
  assert(f.grants.every(({options})=>options.runInvocationCid===f.rowRun.runInvocationCid&&
    options.dispatchRequestCid===f.rowRun.dispatchRequestCid));
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

test('Gmail shared reader retains rejected get response charge and refuses another start',async t=>{
  const f=await threadFactoryFixture(t);f.state.beforeResponse=()=>{if(f.state.requests.length===2)f.state.status=403;};
  const {reader}=await f.makeReader();await assert.rejects(reader.read(),{code:'GmailThreadReadRejected'});
  assert.equal(reader.observe().responseCount,2);assert.equal(f.observations[1].statusCode,403);
  assert.equal(f.state.charges,2);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,2);reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

test('Gmail shared reader fails closed for denied Account and absent original capacity',async t=>{
  const f=await threadFactoryFixture(t,{account:'deny'});
  assert.throws(()=>f.makeFactory({capacity:undefined}),{code:'InvalidInstalledCredentialSourceReader'});
  await assert.rejects(f.makeReader(),{code:'GmailReadDenied'});
  assert.equal(f.state.requests.length,0);assert.equal(f.grants.length,0);f.row.assertNoCapture();
});

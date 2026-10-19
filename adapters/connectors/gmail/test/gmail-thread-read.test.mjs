import assert from 'node:assert/strict';
import test from 'node:test';
import {createGmailThreadReader, GmailThreadReadFailure, GMAIL_THREAD_GET_OPERATION,
  GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';
import {threadReadFixture, threadReadResponses} from './gmail-thread-read.fixture.mjs';

const expected = {id:'t/+',labels:[],last_message_date:'1969-12-31T23:59:59.999Z',message_count:'1',subject:null};
const json = value => JSON.stringify(value);

test('Gmail actual SQL and Pipe Source retain empty continued lists and dependent metadata get charges', async t => {
  for (const format of ['sql','aql']) {
    const f = await threadReadFixture(t,{format});
    f.state.pages = [json({nextPageToken:'opaque/+ ='}),json({threads:[{id:'t/+'}],nextPageToken:'last'}),
      json(threadReadResponses()[1]),json({})];
    const result = await f.read();
    assert.equal(result.pages,3);assert.equal(result.rowCount,1);assert.deepEqual(f.state.rows,[expected]);
    assert.equal(f.state.requests.length,4);assert.equal(f.state.charges,4);
    assert.equal(f.row.usage()[3],result.observations.reduce((sum,response)=>sum+BigInt(response.body.length),0n));
    const targets = f.state.requests.map(request=>new URL(request.path,'https://fixture.invalid'));
    assert.equal(targets[0].searchParams.get('pageToken'),null);
    assert.equal(targets[1].searchParams.get('pageToken'),'opaque/+ =');
    assert.equal(targets[2].pathname,'/gmail/v1/users/support%2Bbox%40example.test/threads/t%2F%2B');
    assert.equal(targets[2].searchParams.get('format'),'metadata');
    assert.deepEqual(targets[2].searchParams.getAll('metadataHeaders'),['Subject','Date']);
    assert.equal(targets[2].searchParams.get('fields'),'id,messages(id,threadId,labelIds,internalDate,payload(headers(name,value)))');
    assert.equal(targets[3].searchParams.get('pageToken'),'last');
    for(const request of f.state.requests){assert.equal(request.method,'GET');assert.equal(request.body.length,0);}
    f.row.finish();assert.equal(f.row.captureCount(),1);
  }
});

test('Gmail complete message projection preserves original subject labels exact count and maximum Date', async t => {
  const f=await threadReadFixture(t);
  f.state.pages[1]=json({id:'t/+',messages:[
    {id:'one',threadId:'t/+',labelIds:['INBOX','Label_1','INBOX'],internalDate:'0',payload:{headers:[
      {name:'Subject',value:'Original é'},{name:'Date',value:'1 Jan 2000 00:00 +0000'}]}},
    {id:'two',threadId:'t/+',labelIds:['Label_1','inbox'],internalDate:'9999999999999',payload:{headers:[
      {name:'Subject',value:'Later'},{name:'Date',value:'31 Dec 1999 23:59 +0000'}]}},
  ]});
  const result=await f.read();assert.equal(result.rowCount,1);
  assert.deepEqual(f.state.rows,[{id:'t/+',labels:['INBOX','Label_1','inbox'],
    last_message_date:'2000-01-01T00:00:00.000Z',message_count:'2',subject:'Original é'}]);
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

test('Gmail awaited observation consumers cannot construct a next Common request after revocation or stop', async t => {
  for(const mode of ['current','stop']){
    const f=await threadReadFixture(t), moon={...f.options.moon};let constructed=0,reader;
    const next=moon.gmailNextThreadRequest;
    moon.gmailNextThreadRequest=function(...args){assert.equal(this,moon);constructed++;return next(...args);};
    const reason=new Error('OriginalGmailObservationStop');
    reader=createGmailThreadReader({...f.options,moon,consumeObservation:async charge=>{
      await f.options.consumeObservation(charge);
      if(mode==='current')await f.writeAccount('deny');else reader.requestStop(reason);
    }});
    await assert.rejects(reader.read(),error=>error instanceof GmailThreadReadFailure&&
      (mode==='stop'?error.cause===reason:['AuthorizationCurrentAccountChanged','GmailReadDenied'].includes(error.cause.code)));
    assert.equal(constructed,1);assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);
    assert.equal(reader.observe().cleanupConfirmed,false);f.row.assertNoCapture();
    await assert.rejects(reader.read(),{code:'GmailThreadReaderAlreadyStarted'});
  }
});

test('Gmail malformed selected get retains raw response and charge without partial row or resend', async t => {
  const f=await threadReadFixture(t);
  f.state.pages[1]=json({id:'t/+',messages:[
    {id:'valid',threadId:'t/+',internalDate:'1',payload:{}},
    {id:'invalid',threadId:'t/+',internalDate:'01',payload:{}},
  ]});
  const reader=createGmailThreadReader(f.options);
  await assert.rejects(reader.read(),error=>error instanceof GmailThreadReadFailure&&
    error.observations.length===2&&error.observations[1].body.toString()===f.state.pages[1]&&
    error.exchanges[1].charge!==undefined);
  assert.equal(f.state.charges,2);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  await assert.rejects(reader.read(),{code:'GmailThreadReaderAlreadyStarted'});assert.equal(f.state.requests.length,2);
});

test('Gmail repeated continuation and cross-page duplicate IDs cannot complete or replace the retained prefix', async t => {
  for(const kind of ['token','id']){
    const f=await threadReadFixture(t);
    f.state.pages=kind==='token'?[json({nextPageToken:'repeat'}),json({nextPageToken:'repeat'})]
      :[json({threads:[{id:'t/+'}],nextPageToken:'next'}),json(threadReadResponses()[1]),json({threads:[{id:'t/+'}]})];
    await assert.rejects(f.read(),error=>error instanceof GmailThreadReadFailure&&error.observations.length===f.state.pages.length);
    assert.equal(f.state.requests.length,f.state.pages.length);assert.equal(f.state.charges,f.state.pages.length);
    assert.equal(f.state.rows.length,kind==='id'?1:0);f.row.assertNoCapture();
  }
});

test('Gmail actual Account and separate get operation cannot be supplied by the list grant or token visibility', async t => {
  const denied=await threadReadFixture(t,{account:'deny'});
  await assert.rejects(denied.read(),error=>error.cause.code==='GmailReadDenied');
  assert.equal(denied.state.requests.length,0);
  const f=await threadReadFixture(t),authorize=f.options.authorizationFor;
  await assert.rejects(f.read({authorizationFor:entry=>entry.operation===GMAIL_THREAD_GET_OPERATION
    ? authorize({...entry,operation:GMAIL_THREAD_LIST_OPERATION}):authorize(entry)}),
    error=>error.cause.code==='ForeignGmailThreadAuthorization');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);f.row.assertNoCapture();
});

test('Gmail known rejection retains original bytes and resource accounting without another exchange', async t => {
  const f=await threadReadFixture(t);f.state.status=403;
  await assert.rejects(f.read(),error=>error.cause.code==='GmailThreadReadRejected'&&
    error.observations.length===1&&error.observations[0].statusCode===403&&error.exchanges[0].charge!==undefined);
  assert.equal(f.state.charges,1);assert.equal(f.state.requests.length,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
});

test('Gmail receiver captures compiler methods callbacks receiver limits and selection before secret await', async t => {
  const f=await threadReadFixture(t),moon={...f.options.moon},limits={...f.options.limits};
  const options={...f.options,moon,limits,names:['subject','message_count']};let reads=0;
  const prepare=moon.gmailPrepareThreadRead;
  Object.defineProperty(moon,'gmailPrepareThreadRead',{get(){reads++;return function(...args){
    assert.equal(this,moon);return prepare(...args);
  };}});
  const current=options.current;options.current=function(...args){assert.equal(this,options);return current(...args);};
  f.state.resolved=()=>{limits.maxThreads=0;options.names[0]='foreign';
    options.current=()=>{throw Error('replacement current');};moon.gmailNextThreadRequest=()=>{throw Error('replacement compiler');};};
  const result=await createGmailThreadReader(options).read();assert.equal(result.rowCount,1);assert.equal(reads,1);
  assert.deepEqual(f.state.rows,[expected]);
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

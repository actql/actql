import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../host-common/runtime-result.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {prepareCalendarFreeBusyPages,CALENDAR_FREE_BUSY_OPERATION}
  from '../connectors/calendar/site/calendar-free-busy-read.mjs';
const provider = await import(process.env.ACTQL_TEST_CALENDAR_URL ??
  new URL('../../_build/js/release/build/connectors/calendar/host_node/host_node.js',import.meta.url).href);

// The real immutable Calendar query/projections and shared Reader; Credential,
// Account/current, accounting and transport are explicit component ports.
// No ordinary Source/RowRun, physical send or physical cleanup ACK is inferred.
const limits=Object.freeze({maxRequestBytes:512,maxBodyBytes:4096,maxResponseBytes:4096,
  maxNodes:512,maxDepth:16,maxCalendars:4,maxRows:4,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:4096,maxRowsWireNodes:100,maxRowsWireDepth:8});
const body=()=>({kind:'calendar#freeBusy',timeMin:'2026-10-17T00:00:00Z',timeMax:'2026-10-18T00:00:00Z',
  calendars:{work:{busy:[{start:'2026-10-17T10:00:00+09:00',end:'2026-10-17T10:30:00+09:00'}]},
    private:{busy:[{start:'2026-10-17T02:00:00Z',end:'2026-10-17T02:15:00Z'}]}}});
const expectedRows=[{calendar_id:'work',start:'2026-10-17T01:00:00.000Z',end:'2026-10-17T01:30:00.000Z'},
  {calendar_id:'private',start:'2026-10-17T02:00:00.000Z',end:'2026-10-17T02:15:00.000Z'}];
function fixture({response=body(),status=200,bounds={},charged}={}){
  const selected=Object.freeze({...limits,...bounds});
  const query=checked(provider.calendarPrepareFreeBusyQuery(['work','private'],
    '2026-10-17T00:00:00.000Z','2026-10-18T00:00:00.000Z',4096,512,16,4,4,512,100,4096));
  const scope=Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,name])),
    operation:CALENDAR_FREE_BUSY_OPERATION,resourceOrigin:'https://provider.invalid'});
  const credential={control:{identity:()=> 'explicit-grant'},journal:{
    claim(_cid,useId){return{use:{},record:{grantCid:'explicit-grant',useId},replayed:false};},
    authorize(){},finish(){}},resolveSecret:()=> 'explicit-secret'};
  const requests=[],charges=[],rows=[],raw=Buffer.from(JSON.stringify(response));
  const site={credential,referenceCurrent:()=>true,async callResource(input){
    assert.equal(this,site);requests.push(input);
    assert.equal(input.maxRequestBytes,selected.maxRequestBytes,'same original request bound');
    return{accepted:status===200,statusCode:status,body:raw};
  }};
  const factory=createInstalledCredentialSourceReader({capacity:{},site,operation:CALENDAR_FREE_BUSY_OPERATION,
    maxResponses:1,maxRequestBytes:selected.maxRequestBytes,maxResponseBytes:selected.maxResponseBytes,maxSecretBytes:64,
    preparePageReader({columns},applySynchronousProjection){return prepareCalendarFreeBusyPages(
      {moon:provider,query,names:columns,limits:selected},applySynchronousProjection);}});
  const reader=factory.prepare({resource:'free_busy',columns:['start'],async verifyRead(){},
    authorizationFor(index){assert.equal(index,0);return{grant:{},scope,useId:'same-query'};},
    chargePage(value){assert.equal(value,raw);charges.push(value);charged?.();return Object.freeze({body:value});},
    consumePage(value,{charge}){assert.equal(charge.body,raw);rows.push(...value);}});
  return{reader,requests,charges,rows,raw,close(){reader.requestStop();reader.retry();
    assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(factory.retire(),true);}};
}

test('actual Calendar FreeBusy query and complete rows use one bounded shared POST',async t=>{
  const f=fixture();
  try{
    const result=await f.reader.read().catch(error=>{
      for(let cause=error,depth=0;cause!==undefined&&depth<4;cause=cause.cause,depth++){
        t.diagnostic(JSON.stringify({depth,name:cause.name,code:cause.code,message:cause.message}));
      }
      throw error;
    });
    assert.deepEqual(result,{pages:1,rowCount:2});
    assert.deepEqual(f.rows,expectedRows);assert.equal(f.charges.length,1);assert.equal(f.requests.length,1);
    const request=f.requests[0].operations.get(CALENDAR_FREE_BUSY_OPERATION);
    assert.equal(request.method,'POST');assert.equal(request.path,'/calendar/v3/freeBusy');
    assert.deepEqual(JSON.parse(request.body),{timeMin:'2026-10-17T00:00:00.000Z',timeMax:'2026-10-18T00:00:00.000Z',
      timeZone:'UTC',calendarExpansionMax:2,items:[{id:'work'},{id:'private'}]});
    assert.deepEqual(request.headers,[['accept','application/json']]);
    assert.equal(f.reader.observe().receivedBodyBytes,BigInt(f.raw.length));
    assert.equal(f.reader.observe().cleanupConfirmed,false);
    await assert.rejects(f.reader.read());assert.equal(f.requests.length,1);
  }finally{f.close();}
});

test('Calendar FreeBusy failure and cancellation retain charges without partial rows or another send',async()=>{
  for(const mode of ['status','calendar','cancel']){
    const response=body(),reason=new Error('same original FreeBusy cancellation');let f;
    if(mode==='calendar')response.calendars.private.errors=[{domain:'calendar',reason:'notFound'}];
    f=fixture({response,status:mode==='status'?403:200,charged:()=>{if(mode==='cancel')f.reader.requestStop(reason);}});
    try{
      await assert.rejects(f.reader.read(),error=>mode==='cancel'?error.cause===reason:
        mode==='status'?error.cause?.code==='CalendarFreeBusyReadRejected':error.cause?.code==='MoonBitHostFailure');
      assert.equal(f.requests.length,1);assert.equal(f.charges.length,1);assert.deepEqual(f.rows,[]);
      await assert.rejects(f.reader.read());assert.equal(f.requests.length,1);
    }finally{f.close();}
  }
});

test('Calendar FreeBusy retains both independent original request body ceilings before any send',async()=>{
  for(const field of ['maxRequestBytes','maxBodyBytes']){
    const f=fixture({bounds:{[field]:1}});
    try{
      await assert.rejects(f.reader.read(),error=>error.cause?.code==='CalendarFreeBusyRequestLimit');
      assert.equal(f.requests.length,0);assert.equal(f.charges.length,0);assert.deepEqual(f.rows,[]);
    }finally{f.close();}
  }
});

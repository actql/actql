import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {prepareNotionUserListPages,NOTION_USER_LIST_OPERATION,NOTION_USER_LIST_API_VERSION}
  from '../connectors/notion/site/user-list-read.mjs';
import {prepareCalendarListPages,CALENDAR_LIST_OPERATION}
  from '../connectors/calendar/site/calendar-list-read.mjs';

const ok = value => ({$tag:1,_0:value});
const allLimits = {maxResponseBytes:8192,maxTotalResponseBytes:24576,maxNodes:512,maxDepth:16,
  maxRows:10,maxTotalRows:20,maxPages:4,maxRequests:4,pageSize:2,perPage:2,
  maxCursorBytes:128,maxCursorUnits:128,maxIdentityBytes:128,maxTargetBytes:1024,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8};
const columns = {notion:['email','id','name','type'],calendar:['access_role','id','summary','time_zone']};
const row = (family,id) => family === 'notion' ? {email:null,id,name:id,type:'bot'}
  : {access_role:'reader',id,summary:id,time_zone:'UTC'};
const page = (family,id,next=null) => ({rows:id === null ? [] : [row(family,id)],
  ids:id === null ? [] : [id],next});

// Actual provider adapters and Host owner, with explicit compiled-projection,
// Account/grant and physical response ports. No Common/SQLite/TLS or normal
// installer/Plan qualification is inferred from these callback-boundary cases.
function fixture(family,pages,{limits={},names=columns[family],status=200,consume,current,charge,projection}={}) {
  const events=[],requests=[],delivered=[],responses=[];
  const operation = family === 'notion' ? NOTION_USER_LIST_OPERATION : CALENDAR_LIST_OPERATION;
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(k=>[k,k])),
    operation,resourceOrigin:'https://provider.invalid'});
  const credential = {control:{identity:()=> 'same-grant'},journal:{
    claim(_cid,useId){return {use:{},record:{grantCid:'same-grant',useId},replayed:false};},
    authorize(){},finish(){}},resolveSecret:()=> 'fixture-secret'};
  const bodies=pages.map((_,i)=>Buffer.from(`original-page-${i}`));
  const selected = body => {assert.equal(events.at(-2),'charge');assert.equal(events.at(-1),'current');
    const index=bodies.indexOf(body);assert(index>=0);events.push('decode');return pages[index];};
  let live=true;
  const site={credential,referenceCurrent(){assert.equal(this,site);return live;},
    async callResource(input){assert.equal(this,site);requests.push(input.operations.get(operation));
      const response={accepted:true,statusCode:status,body:bodies[requests.length-1]};
      assert(response.body);responses.push(response);events.push('send');return response;}};
  const moon = family === 'notion' ? {
    notionProjectUserList(body){assert.equal(this,moon);const p=selected(body);return projection?projection(body,p):ok(p);},
    notionUserListIds(p){return p.ids;},
    notionUserListMetadataJson(p){return ok(JSON.stringify({rowCount:p.rows.length,nextCursor:p.next}));},
    notionUserListRowsWire(p,selected){assert.deepEqual(selected,names);return ok(JSON.stringify(p.rows));},
    notionUserListColumnNames(){return columns.notion;},
  } : {
    calendarProjectCalendarList(body){assert.equal(this,moon);const p=selected(body);return projection?projection(body,p):ok(p);},
    calendarListMetadataJson(p){return JSON.stringify({rowCount:p.rows.length,ids:p.ids,nextPageToken:p.next});},
    calendarListRowsWire(p,selected){assert.deepEqual(selected,columns.calendar);return ok(JSON.stringify(p.rows));},
    calendarListColumnNames(){return columns.calendar;},
  };
  const bounded={...allLimits,...limits};
  const callbacks={resource:family === 'notion' ? 'users':'calendars',columns:[...names],
    async verifyRead(){events.push('current');await current?.();},
    authorizationFor(index){events.push(`grant:${index}`);return {grant:{},scope,useId:`page-${index}`};},
    chargePage(body){assert.equal(body,responses.at(-1).body);events.push('charge');charge?.(body);
      return Object.freeze({body});},
    consumePage(rows,{charge:ticket}){assert.equal(ticket.body,responses.at(-1).body);
      delivered.push(...rows);consume?.(rows);}};
  const factory=createInstalledCredentialSourceReader({capacity:{},site,operation,
    maxResponses:bounded.maxPages,maxResponseBytes:bounded.maxResponseBytes,maxSecretBytes:64,
    preparePageReader({columns:selected},applySynchronousProjection){return (family === 'notion' ? prepareNotionUserListPages
      :prepareCalendarListPages)({moon,names:selected,limits:bounded},applySynchronousProjection);}});
  const reader=factory.prepare(callbacks);
  return {reader,requests,events,delivered,moon,bounded,callbacks,
    notCurrent(){live=false;},bytes:bodies.reduce((n,b)=>n+BigInt(b.length),0n)};
}

for(const family of ['notion','calendar']) test(`${family} page meaning uses the same Host owner for empty one and multiple pages`,async()=>{
  for(const pages of [[page(family,null)],[page(family,'one')],
    [page(family,'one','opaque /+é'),page(family,'two')]]){
    const f=fixture(family,pages,{names:family === 'calendar' ? ['summary']:columns.notion});
    const result=await f.reader.read();
    assert.deepEqual(result,{pages:pages.length,rowCount:pages.flatMap(p=>p.rows).length});
    assert.deepEqual(f.delivered,pages.flatMap(p=>p.rows));
    assert.equal(f.requests.length,pages.length);
    for(const [i,request] of f.requests.entries()){
      const url=new URL(request.path,'https://provider.invalid');assert.equal(request.method,'GET');
      if(family === 'notion'){
        assert.equal(url.pathname,'/v1/users');assert.equal(url.searchParams.get('page_size'),'2');
        assert.equal(url.searchParams.get('start_cursor'),i === 0 ? null:'opaque /+é');
        assert(request.headers.some(([k,v])=>k==='notion-version'&&v===NOTION_USER_LIST_API_VERSION));
      }else{
        assert.equal(url.pathname,'/calendar/v3/users/me/calendarList');
        assert.equal(url.searchParams.get('maxResults'),'2');assert.equal(url.searchParams.get('showHidden'),'true');
        assert.equal(url.searchParams.get('showDeleted'),'false');
        assert.equal(url.searchParams.get('pageToken'),i === 0 ? null:'opaque /+é');
      }
    }
    assert.equal(f.reader.observe().receivedBodyBytes,f.bytes);
    assert.equal(f.reader.observe().cleanupConfirmed,false);
    f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
    f.reader.retry();assert.equal(f.requests.length,pages.length);
  }
});

test('Notion still refuses duplicate identity cursor target page row and aggregate raw bounds',async()=>{
  for(const mode of ['id','cursor','target','pages','rows','bytes']){
    const limits=mode==='target'?{maxTargetBytes:1}:mode==='pages'?{maxPages:1}:
      mode==='rows'?{maxTotalRows:1}:mode==='bytes'?{maxTotalResponseBytes:15}:{};
    const pages=[page('notion','one','cursor'),page('notion',mode==='id'?'one':'two',mode==='cursor'?'cursor':null)];
    const f=fixture('notion',pages,{limits});
    const code={id:'NotionUserListDuplicateUser',cursor:'NotionUserListRepeatedCursor',target:'NotionUserListTargetLimit',
      pages:'NotionUserListPageLimit',rows:'NotionUserListRowLimit',bytes:'NotionUserListResponseLimit'}[mode];
    await assert.rejects(f.reader.read(),e=>e.cause?.code===code);
    assert.equal(f.requests.length,mode==='target'?0:mode==='pages'?1:2);
    f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  }
});

test('Calendar retains remaining-row requests full columns and duplicate or incomplete-page refusals',async()=>{
  const f=fixture('calendar',[page('calendar','one','next'),page('calendar','two')],{limits:{maxRows:2},names:['summary']});
  await f.reader.read();
  assert.equal(new URL(f.requests[0].path,'https://provider.invalid').searchParams.get('maxResults'),'2');
  assert.equal(new URL(f.requests[1].path,'https://provider.invalid').searchParams.get('maxResults'),'1');
  assert.deepEqual(f.delivered,[row('calendar','one'),row('calendar','two')]);f.reader.requestStop();
  for(const mode of ['id','cursor','pages','rows']){
    const limits=mode==='pages'?{maxPages:1}:mode==='rows'?{maxRows:1}:{};
    const pages=[page('calendar','one','next'),page('calendar',mode==='id'?'one':'two',mode==='cursor'?'next':null)];
    const g=fixture('calendar',pages,{limits});
    const code={id:'CalendarListDuplicateRecord',cursor:'CalendarListCursorCycle',pages:'CalendarListPageLimit',rows:'CalendarListRowLimit'}[mode];
    await assert.rejects(g.reader.read(),e=>e.cause?.code===code);
    assert.equal(g.requests.length,['pages','rows'].includes(mode)?1:2);
    g.reader.requestStop();assert.equal(g.reader.observe().cleanupConfirmed,true);
  }
});

test('both providers charge a rejected body without decoding or manufacturing empty completion',async()=>{
  for(const family of ['notion','calendar']){
    const f=fixture(family,[page(family,'one')],{status:403});
    await assert.rejects(f.reader.read(),e=>e.cause?.code===(family === 'notion'?'NotionUserListReadRejected':'CalendarListReadRejected')&&
      !Object.hasOwn(e,'observations'));
    assert.equal(f.events.filter(e=>e==='charge').length,1);assert(!f.events.includes('decode'));
    assert.deepEqual(f.delivered,[]);f.reader.requestStop();assert(f.reader.observe().cleanupConfirmed);
  }
});

test('both provider callbacks preserve original cancellation or current loss without another send',async()=>{
  for(const family of ['notion','calendar']) for(const mode of ['cancel','current']){
    let f;const cause=new Error('same original cancellation');
    f=fixture(family,[page(family,'one','next'),page(family,'two')],{consume(){
      if(mode==='cancel')f.reader.requestStop(cause);else f.notCurrent();}});
    await assert.rejects(f.reader.read(),e=>mode==='cancel'?e.cause===cause:e.cause?.code==='InstalledSourceReaderNotCurrent');
    assert.equal(f.requests.length,1);f.reader.requestStop();assert(f.reader.observe().cleanupConfirmed);
  }
});

test('both providers capture original projection methods columns and limits before the first Host await',async()=>{
  for(const family of ['notion','calendar']){
    const f=fixture(family,[page(family,'one','next'),page(family,'two')]);
    const name=family === 'notion'?'notionProjectUserList':'calendarProjectCalendarList';
    f.moon[name]=()=>assert.fail('replaced projection');f.callbacks.columns[0]='foreign';f.bounded.maxPages=1;
    assert.equal((await f.reader.read()).rowCount,2);f.reader.requestStop();
    assert(f.reader.observe().cleanupConfirmed);
  }
});


test('both provider adapters retain unexpected asynchronous compiled projections until their same borrow settles',async()=>{
  for(const family of ['notion','calendar']){
    let release,finished;
    const pending=new Promise(resolve=>{release=resolve;});
    const settled=new Promise(resolve=>{finished=resolve;});
    const f=fixture(family,[page(family,'one')],{projection:async(body,value)=>{
      await pending;assert.equal(body.toString(),'original-page-0');finished();return ok(value);
    }});
    await assert.rejects(f.reader.read());f.reader.requestStop();
    try{
      assert.equal(f.reader.observe().readPending,false);
      assert.equal(f.reader.observe().transportClosed,true);
      assert.equal(f.reader.observe().cleanupConfirmed,false);
    }finally{
      release();await settled;await new Promise(resolve=>setImmediate(resolve));
    }
    assert.equal(f.reader.observe().cleanupConfirmed,true);
    assert.equal(f.requests.length,1);assert.equal(f.delivered.length,0);
  }
});

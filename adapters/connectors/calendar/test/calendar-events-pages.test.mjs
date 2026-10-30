// Explicit provider ports exercise the actual pure hooks only. These are not
// original MoonBit query/page issuance, managed-reader or Source acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareCalendarEventsPages,CalendarEventsReadFailure} from '../site/calendar-events-pages.mjs';

const limits=Object.freeze({maxResponseBytes:16384,maxNodes:1024,maxDepth:20,maxPages:4,maxRows:3,maxRequests:4,
  perPage:2,maxIdentityBytes:128,maxCursorBytes:128,maxQueryBytes:4096,maxTargetBytes:4096,maxAttendees:100,
  maxValueNodes:1000,maxValueTextBytes:8192,maxResolutionWork:100,maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20});
const wire=JSON.stringify({calendar_id:'calendar/é@example.test',time_min:'2026-03-01T10:00:00.1234+09:00',
  time_max:'2026-03-02T10:00:00.1234+09:00',time_zone:'Fixture/Eastern'});
const cursor='original /+é cursor';
const ok=value=>({$tag:1,_0:value}); // Explicit pinned Result ABI port, no opaque issuer.
function fixture(options={}){
  const query=Object.freeze({port:'original query sentinel'}),calls=[],selected=[],originals=[];
  const columns=['id','start','attendees'];
  const rowsWire='[{"id":"one","start":"2026-03-01T00:00:00.123456789Z","attendees":[]}]';
  const pages=options.pages??[{ids:['one','two'],nextPageToken:cursor},{ids:['three'],nextPageToken:null}];
  const provider={
    calendarEventsColumnNames(){assert.equal(this,provider);return columns;},
    calendarEventsQueryWire(value,...bounds){assert.equal(this,provider);assert.equal(value,query);calls.push({query:value,bounds});return ok(options.wire??wire);},
    calendarProjectEvents(body,value,...bounds){assert.equal(this,provider);assert.equal(value,query);calls.push({body,query:value,bounds});const page={...pages[body[0]],query:value};originals.push(page);return ok(page);},
    calendarEventsMatchesQuery(page,value){assert.equal(this,provider);assert.equal(page.query,value);return options.matches??true;},
    calendarEventsMetadataWire(page,...bounds){assert.equal(this,provider);calls.push({metadata:page,bounds});return ok(JSON.stringify({calendarId:'calendar/é@example.test',rowCount:page.ids.length,...page,query:undefined}));},
    calendarEventsRowsWire(page,names,...bounds){assert.equal(this,provider);assert(originals.includes(page));selected.push(names);calls.push({rows:page,bounds});return ok(rowsWire);},
  };
  const getters=new Map();
  for(const name of Object.keys(provider)){
    const fn=provider[name];
    Object.defineProperty(provider,name,{configurable:true,get(){getters.set(name,(getters.get(name)??0)+1);return fn;}});
  }
  const invocations=[];
  const hooks=prepareCalendarEventsPages({moon:provider,query,names:options.names??['id'],limits:options.limits??limits},
    (method,receiver,args)=>{assert.equal(receiver,provider);invocations.push(method);return Reflect.apply(method,receiver,args);});
  return{hooks,provider,query,calls,columns,getters,selected,rowsWire,invocations};
}
const response=index=>({accepted:true,statusCode:200,body:Uint8Array.of(index)});

test('Calendar Events pure hooks retain original request and remaining-row cursor through explicit provider ports',()=>{
  const f=fixture(),first=f.hooks.fetchPage({pageIndex:0,rowCount:0});
  assert.equal(first.path,'/calendar/v3/calendars/calendar%2Fe%CC%81%40example.test/events');
  assert.equal(first.method,'GET');assert.equal(first.query.find(([k])=>k==='maxResults')[1],'2');
  assert.deepEqual(first.query.filter(([k])=>['timeMin','timeMax','timeZone'].includes(k)),[
    ['timeMin','2026-03-01T10:00:00.1234+09:00'],['timeMax','2026-03-02T10:00:00.1234+09:00'],['timeZone','Fixture/Eastern']]);
  assert.equal(first.query.some(([k])=>['fields','maxAttendees'].includes(k)),false);
  assert.deepEqual(f.hooks.decodePage(response(0),{pageIndex:0,rowCount:0}),{rowsWire:f.rowsWire,rowCount:2,done:false});
  assert.deepEqual(f.selected,[['id','start','attendees']]);
  const next=f.hooks.fetchPage({pageIndex:1,rowCount:2});
  assert.equal(next.query.find(([k])=>k==='maxResults')[1],'1');
  assert.equal(next.query.find(([k])=>k==='pageToken')[1],cursor);
  assert.deepEqual(f.hooks.decodePage(response(1),{pageIndex:1,rowCount:2}),{rowsWire:f.rowsWire,rowCount:1,done:true});
  assert.equal(f.calls.filter(x=>x.query&&!x.body).length,1,'one original query serialization');
  // The port wire/counts are DATA. Only the actual shared Common admission may
  // establish their correspondence; this test does not supply that admission.
});

test('Calendar Events pure hooks refuse duplicate cursor identity and exhausted bounds before returning wire',()=>{
  for(const mode of ['id','cursor','pages','requests','rows']){
    const chosen=mode==='pages'?{...limits,maxPages:1}:mode==='requests'?{...limits,maxRequests:1}:
      mode==='rows'?{...limits,maxRows:2}:limits;
    const f=fixture({limits:chosen,pages:[{ids:['one','two'],nextPageToken:cursor},
      {ids:[mode==='id'?'one':'three'],nextPageToken:mode==='cursor'?cursor:null}]});
    if(['pages','requests','rows'].includes(mode)){
      assert.throws(()=>f.hooks.decodePage(response(0),{pageIndex:0,rowCount:0}),
        {code:{pages:'CalendarEventsPageLimit',requests:'CalendarEventsRequestLimit',rows:'CalendarEventsRowLimit'}[mode]});
      assert.equal(f.calls.filter(x=>x.rows).length,0);
    }else{
      f.hooks.decodePage(response(0),{pageIndex:0,rowCount:0});
      assert.throws(()=>f.hooks.decodePage(response(1),{pageIndex:1,rowCount:2}),
        {code:mode==='id'?'CalendarEventsDuplicateRecord':'CalendarEventsCursorCycle'});
      assert.equal(f.calls.filter(x=>x.rows).length,1);
    }
  }
  const f=fixture();assert.throws(()=>f.hooks.fetchPage({pageIndex:1,rowCount:3}),{code:'CalendarEventsRowLimit'});
  assert.equal(f.calls.some(x=>x.body),false);
});

test('Calendar Events pure hooks capture original methods limits and declared columns before later mutation',()=>{
  const mutable={...limits},f=fixture({limits:mutable});
  for(const name of Object.keys(f.provider))Object.defineProperty(f.provider,name,{value:()=>assert.fail('replacement method'),configurable:true});
  mutable.perPage=2000;mutable.maxRows=2000;f.columns.push('replacement');
  assert.equal(f.hooks.fetchPage({pageIndex:0,rowCount:0}).query[0][1],'2');
  f.hooks.decodePage(response(0),{pageIndex:0,rowCount:0});
  assert.deepEqual(f.selected,[['id','start','attendees']]);
  assert(f.getters.size===6&&[...f.getters.values()].every(count=>count===1));
  assert.deepEqual(Object.keys(f.hooks),['fetchPage','decodePage','onError']);
  const cause=Object.assign(new Error('original managed read failure'),{cleanupPending:true});
  const wrapped=f.hooks.onError(cause);assert(wrapped instanceof CalendarEventsReadFailure);assert.equal(wrapped.cause,cause);
});

test('Calendar Events pure hooks keep foreign and incomplete metadata rejected without a terminal shortcut',()=>{
  const foreign=fixture({matches:false});
  assert.throws(()=>foreign.hooks.decodePage(response(0),{pageIndex:0,rowCount:0}),{code:'ForeignCalendarEventsQuery'});
  assert.equal(foreign.calls.some(x=>x.metadata||x.rows),false);
  const missing=fixture({pages:[{ids:[]}]});
  assert.throws(()=>missing.hooks.decodePage(response(0),{pageIndex:0,rowCount:0}),{code:'CalendarEventsRowLimit'});
  const target=fixture({limits:{...limits,maxTargetBytes:1}});
  assert.throws(()=>target.hooks.fetchPage({pageIndex:0,rowCount:0}),{code:'CalendarEventsTargetLimit'});
  const status=fixture();assert.throws(()=>status.hooks.decodePage({accepted:false,statusCode:429},{pageIndex:0,rowCount:0}),{code:'CalendarEventsReadRejected'});
  assert.equal(status.calls.some(x=>x.body),false);
  assert.throws(()=>fixture({wire:'{"calendar_id":"x"}'}),{code:'InvalidCalendarEventsRequest'});
});

// Explicit provider ports cover the actual pure callbacks, not original Core
// issuance, physical send/accounting/ACK, a RowRun or normal Host acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareCalendarFreeBusyRequestPages,CalendarFreeBusyPagesFailure} from '../site/calendar-free-busy-pages.mjs';

const limits=Object.freeze({maxResponseBytes:4096,maxNodes:512,maxDepth:16,maxCalendars:4,maxRows:3,
  maxRequestBytes:4096,maxBodyBytes:2048,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:8192,maxRowsWireNodes:512,maxRowsWireDepth:16});
const originalRequest='{"calendar_id":"calendar/é@example.test","time_min":"2026-10-17T00:00:00.0001Z","time_max":"2026-10-17T00:00:00.0002Z"}';
const body='{"timeMin":"2026-10-17T00:00:00.0001Z","timeMax":"2026-10-17T00:00:00.0002Z","timeZone":"UTC","calendarExpansionMax":1,"items":[{"id":"calendar/é@example.test"}]}';
const ok=value=>({$tag:1,_0:value}); // Explicit pinned ABI only, no opaque issuer.
function fixture(options={}){
  const query=Object.freeze({port:'original query'}),page=Object.freeze({port:'original page'}),calls=[];
  const columns=['calendar_id','start','end'],originalLimits={...limits},selected=[];
  const provider={
    calendarPrepareFreeBusyRequest(wire,...bounds){assert.equal(this,provider);assert.equal(wire,originalRequest);calls.push({bounds});return ok(query);},
    calendarFreeBusyRequestWire(value){assert.equal(this,provider);assert.equal(value,query);return options.body??body;},
    calendarFreeBusyColumnNames(){assert.equal(this,provider);return columns;},
    calendarProjectFreeBusy(value,original,...bounds){assert.equal(this,provider);assert.equal(original,query);calls.push({value,bounds});return ok(page);},
    calendarFreeBusyMatchesQuery(value,original){assert.equal(this,provider);assert.equal(value,page);assert.equal(original,query);return options.matches??true;},
    calendarFreeBusyMetadataJson(value){assert.equal(this,provider);assert.equal(value,page);return options.metadata??JSON.stringify({responseSha256:'a'.repeat(64),rowCount:options.rowCount??1});},
    calendarFreeBusyRowsWire(value,names,...bounds){assert.equal(this,provider);assert.equal(value,page);selected.push(names);calls.push({bounds});return ok(options.rows??'[{"calendar_id":"calendar/é@example.test","start":"2026-10-17T00:00:00.0001Z","end":"2026-10-17T00:00:00.0002Z"}]');},
  };
  const hooks=prepareCalendarFreeBusyRequestPages({moon:provider,requestWire:originalRequest,
    names:options.names??['start'],limits:originalLimits},(method,receiver,args)=>Reflect.apply(method,receiver,args));
  return{hooks,provider,columns,originalLimits,calls,selected};
}
const frame={pageIndex:0,rowCount:0},response={accepted:true,statusCode:200,body:new Uint8Array([1,2])};

test('Calendar free busy pure pages preserve original request receiver complete columns and one-page result',()=>{
  const f=fixture(),request=f.hooks.fetchPage(frame);
  assert.deepEqual(request,{method:'POST',path:'/calendar/v3/freeBusy',query:[],headers:[['accept','application/json']],responseHeaders:[],body});
  const result=f.hooks.decodePage(response,frame);assert.equal(result.done,true);assert.equal(result.rowCount,1);
  assert.deepEqual(Object.keys(JSON.parse(result.rowsWire)[0]).sort(),['calendar_id','end','start']);
  assert.deepEqual(f.selected[0],['calendar_id','start','end']);assert.equal(f.calls[1].value,response.body);
  assert.deepEqual(f.calls[0].bounds,[4096,512,16,4,3,2048,100,4096]);
});

test('Calendar free busy pure pages retain original methods limits and columns before later mutation',()=>{
  const f=fixture();f.originalLimits.maxRows=0;f.columns.length=0;
  for(const name of Object.keys(f.provider))f.provider[name]=()=>{throw new Error('replaced method');};
  assert.equal(f.hooks.fetchPage(frame).body,body);assert.equal(f.hooks.decodePage(response,frame).rowCount,1);
  assert.deepEqual(f.selected[0],['calendar_id','start','end']);
  const cause=new Error('original refusal'),wrapped=f.hooks.onError(cause);
  assert(wrapped instanceof CalendarFreeBusyPagesFailure);assert.equal(wrapped.cause,cause);
});

test('Calendar free busy pure pages refuse foreign incomplete status and exhausted original bounds',()=>{
  assert.throws(()=>fixture({matches:false}).hooks.decodePage(response,frame),{code:'ForeignCalendarFreeBusyQuery'});
  assert.throws(()=>fixture({metadata:'{}'}).hooks.decodePage(response,frame),{code:'InvalidCalendarFreeBusyMetadata'});
  assert.throws(()=>fixture({rowCount:4}).hooks.decodePage(response,frame),{code:'InvalidCalendarFreeBusyMetadata'});
  assert.throws(()=>fixture({body:'x'.repeat(2049)}),{code:'CalendarFreeBusyRequestLimit'});
  assert.throws(()=>fixture({rows:'x'.repeat(8193)}).hooks.decodePage(response,frame),{code:'CalendarFreeBusyRowsLimit'});
  assert.throws(()=>fixture().hooks.decodePage({...response,statusCode:429},frame),{code:'CalendarFreeBusyReadRejected'});
  for(const changed of [{pageIndex:1,rowCount:0},{pageIndex:0,rowCount:1},null]){
    assert.throws(()=>fixture().hooks.fetchPage(changed),{code:'InvalidCalendarFreeBusyFrame'});
    assert.throws(()=>fixture().hooks.decodePage(response,changed),{code:'InvalidCalendarFreeBusyFrame'});
  }
});

test('Calendar free busy pure request entrance rejects missing ports invalid wire limits and duplicate selections',()=>{
  const project=(method,receiver,args)=>Reflect.apply(method,receiver,args);
  for(const patch of [{requestWire:undefined},{requestWire:'\ud800'},{limits:{...limits,maxCalendars:51}},
    {limits:{...limits,maxBodyBytes:1}},{names:['start','start']},{moon:{}}]){
    assert.throws(()=>prepareCalendarFreeBusyRequestPages({moon:{},requestWire:originalRequest,names:['start'],limits,...patch},project));
  }
  assert.throws(()=>fixture({names:['foreign']}),{code:'InvalidCalendarFreeBusyPages'});
});

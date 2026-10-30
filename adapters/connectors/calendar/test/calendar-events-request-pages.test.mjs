// Real provider entry and hooks, explicit Core ports. Not a nominal Profile,
// RowAcquisition, Source, Account, physical exchange or normal Host fixture.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareCalendarEventsRequestPages} from '../site/calendar-events-pages.mjs';
const limits={maxResponseBytes:16384,maxNodes:1024,maxDepth:20,maxPages:4,maxRows:3,maxRequests:4,
  perPage:2,maxIdentityBytes:128,maxCursorBytes:128,maxQueryBytes:4096,maxTargetBytes:4096,
  maxAttendees:100,maxValueNodes:1000,maxValueTextBytes:8192,maxResolutionWork:100,
  maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20};
const requestWire='{"calendar_id":"calendar/é@example.test","time_min":"2026-03-01T10:00:00.1234+09:00","time_max":"2026-03-02T10:00:00.1234+09:00","time_zone":"Fixture/Eastern"}';
const ok=value=>({$tag:1,_0:value});
test('Calendar request page entry consumes one exact original request environment and retained Profile before original query hooks',()=>{
  const environment=Object.freeze({port:'original environment sentinel'}),profile=Object.freeze({port:'original Profile sentinel'}),query=Object.freeze({port:'issued query sentinel'}),calls=[];
  let getters=0,selectCalls=0;
  const prepare=function(wire,selected,...bounds){assert.equal(this,provider);assert.equal(wire,requestWire);assert.equal(selected,profile);
    calls.push({wire,selected,bounds});return ok(query);};
  const rowsWire='[{"id":"one","attendees":null}]';
  const provider={
    get calendarEventsQueryFromRequestWire(){getters++;return prepare;},
    calendarEventsProfileFromEnvironment(original){assert.equal(this,provider);assert.equal(original,environment);selectCalls++;return ok(profile);},
    calendarEventsQueryWire(original){assert.equal(this,provider);assert.equal(original,query);return ok(requestWire);},
    calendarEventsColumnNames(){assert.equal(this,provider);return['id','attendees'];},
    calendarProjectEvents(body,original){assert.equal(this,provider);assert.equal(original,query);assert.deepEqual(body,Uint8Array.of(1));return ok({query:original});},
    calendarEventsMatchesQuery(page,original){assert.equal(this,provider);return page.query===original;},
    calendarEventsMetadataWire(){return ok('{"calendarId":"calendar/é@example.test","ids":["one"],"rowCount":1,"nextPageToken":null}');},
    calendarEventsRowsWire(_page,names){assert.deepEqual(names,['id','attendees']);return ok(rowsWire);},
  };
  const selectedLimits={...limits};
  const hooks=prepareCalendarEventsRequestPages({moon:provider,environment,requestWire,names:['id'],limits:selectedLimits},
    (method,receiver,args)=>Reflect.apply(method,receiver,args));
  selectedLimits.maxRows=900;selectedLimits.maxQueryBytes=1;
  Object.defineProperty(provider,'calendarEventsQueryFromRequestWire',{value(){throw Error('late replacement');}});
  const frame={pageIndex:0,rowCount:0};
  assert.equal(hooks.fetchPage(frame).query.find(([name])=>name==='timeMin')[1],'2026-03-01T10:00:00.1234+09:00');
  assert.deepEqual(hooks.decodePage({accepted:true,statusCode:200,body:Uint8Array.of(1)},frame),{rowsWire,rowCount:1,done:true});
  assert.equal(calls.length,1);assert.equal(getters,1);assert.equal(selectCalls,1);
  assert.deepEqual(calls[0].bounds,[4096,1024,20,3,128,128,100,1000,8192,100]);
  assert.deepEqual(Object.keys(hooks).sort(),['decodePage','fetchPage','onError']);
});
test('Calendar request page entry refuses missing environment request and limits before Core or physical work',()=>{
  let calls=0;const projection=()=>{calls++;throw Error('unexpected projection');};
  for(const patch of [{environment:undefined},{environment:null},{environment:undefined,profile:{}},{requestWire:undefined},{requestWire:null},
    {requestWire:'\ud800'},{limits:{...limits,maxQueryBytes:1}},{limits:{...limits,maxNodes:0}}]){
    assert.throws(()=>prepareCalendarEventsRequestPages({moon:{},environment:{port:'original environment'},requestWire,names:['id'],limits,...patch},projection));
  }
  assert.equal(calls,0);
  const original=Error('original selected Profile/request refusal');
  assert.throws(()=>prepareCalendarEventsRequestPages({moon:{calendarEventsProfileFromEnvironment(){},calendarEventsQueryFromRequestWire(){}},environment:{},requestWire,names:['id'],limits},()=>{throw original;}),error=>error===original);
});

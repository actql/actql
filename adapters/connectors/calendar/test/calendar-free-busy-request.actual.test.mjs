// Actual standalone Calendar provider ABI and pure request/page callbacks.
// Request wire is explicit component DATA, not an original RowAcquisition,
// physical response/current/Account ACK, normal Host or Saved acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareCalendarFreeBusyRequestPages} from '../site/calendar-free-busy-pages.mjs';

const calendar=await import(process.env.ACTQL_TEST_CALENDAR_PROVIDER_MODULE??
  new URL('../../../../_build/js/release/build/connectors/calendar/host_node/host_node.js',import.meta.url).href);
const wire='{"calendar_id":"calendar/é@example.test","time_min":"2026-10-17T00:00:00.0001Z","time_max":"2026-10-17T00:00:00.0002Z"}';
const limits={maxResponseBytes:4096,maxNodes:512,maxDepth:16,maxCalendars:4,maxRows:3,
  maxRequestBytes:4096,maxBodyBytes:2048,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:8192,maxRowsWireNodes:512,maxRowsWireDepth:16};
const responseBody=new TextEncoder().encode('{"kind":"calendar#freeBusy","timeMin":"2026-10-17T00:00:00.0001Z","timeMax":"2026-10-17T00:00:00.0002Z","calendars":{"calendar/é@example.test":{"busy":[{"start":"2026-10-17T00:00:00.0001Z","end":"2026-10-17T00:00:00.0002Z"}]}}}');
const query=request=>checked(calendar.calendarPrepareFreeBusyRequest(request,4096,512,16,4,3,2048,100,4096));

test('actual Calendar free busy original Request ABI preserves exact Timestamp DATA through pure pages',()=>{
  const hooks=prepareCalendarFreeBusyRequestPages({moon:calendar,requestWire:wire,names:['start'],limits},
    (method,receiver,args)=>Reflect.apply(method,receiver,args));
  const frame={pageIndex:0,rowCount:0},request=hooks.fetchPage(frame);
  assert.equal(request.method,'POST');assert.equal(request.path,'/calendar/v3/freeBusy');
  assert.deepEqual(JSON.parse(request.body),{timeMin:'2026-10-17T00:00:00.0001Z',timeMax:'2026-10-17T00:00:00.0002Z',
    timeZone:'UTC',calendarExpansionMax:1,items:[{id:'calendar/é@example.test'}]});
  assert.deepEqual(request.headers,[['accept','application/json']]);
  const result=hooks.decodePage({accepted:true,statusCode:200,body:responseBody},frame);
  assert.equal(result.done,true);assert.equal(result.rowCount,1);
  assert.deepEqual(JSON.parse(result.rowsWire),[{calendar_id:'calendar/é@example.test',
    start:'2026-10-17T00:00:00.0001Z',end:'2026-10-17T00:00:00.0002Z'}]);
});

test('actual Calendar free busy Request contract and original page refuse copied selectors foreign query and changed response',()=>{
  assert.equal(checked(calendar.calendarFreeBusyRequestSchemaWire(4096,100,8)),
    '{"additional_properties":false,"fields":{"calendar_id":{"nullable":false,"type":"string"},"time_max":{"nullable":false,"type":"timestamp"},"time_min":{"nullable":false,"type":"timestamp"}},"nullable":false,"type":"object"}');
  for(const request of ['{}',wire.replace('"calendar/é@example.test"','null'),
    wire.replace('"calendar/é@example.test"','[]'),wire.replace('{','{"foreign":"x",'),
    wire.replace('.0001Z','.0002Z')])assert.throws(()=>query(request),{code:'MoonBitHostFailure'});
  const original=query(wire),repeated=query(wire);
  const page=checked(calendar.calendarProjectFreeBusy(responseBody,original,4096,512,16,4,3,2048,100,4096));
  assert.equal(calendar.calendarFreeBusyMatchesQuery(page,original),true);
  assert.equal(calendar.calendarFreeBusyMatchesQuery(page,repeated),false);
  const changed=new TextEncoder().encode(new TextDecoder().decode(responseBody).replace('calendar/é@example.test','foreign'));
  assert.throws(()=>checked(calendar.calendarProjectFreeBusy(changed,original,4096,512,16,4,3,2048,100,4096)),{code:'MoonBitHostFailure'});
});

// Pure actual compiled ABI component. The original Common constructs its own
// CheckEnvironment/selected Profile. No Source, Account, HTTP/DB/Run, physical
// ACK or normal execution authority is supplied by this synthetic fixture.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {inspect} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareCalendarEventsRequestPages} from '../site/calendar-events-pages.mjs';

// Normal CI's existing preparation builds both root modules. A bounded local
// component may explicitly select one new matching Common module. The
// environment issuer and ALL Profile/query/page methods must be its SAME
// namespace; a separately compiled provider cannot consume its retained Map.
const commonUrl=process.env.ACTQL_TEST_COMMON_MODULE??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href;
const common=await import(commonUrl),calendar=common;
const table='{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"test-fixture","version":"actql-tzdb-table/0.1","zones":{"UTC":{"initial_offset_seconds":0,"transitions":[]}}}';
const tableCid='sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca';
assert.equal('sha256:'+createHash('sha256').update(table).digest('hex'),tableCid);
// Original independently pinned CheckEnvironment fixture: same semantic table
// selection used by program_check/calendar_environment_wbtest.mbt. Capacities
// are fixture DATA, not a funded normal Source/Request allowance.
const wire='{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe","host_policy_profile":{"calendar":{"conversion_law":"actql-calendar-boundaries/0.1","table_bytes_cid":"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca","tzdb_version":"test-fixture","version":"actql-calendar-selection/0.1"},"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}';
function environment(enabled=true){
  const original=common.clientProgramCheckEnvironment(wire,
    'sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe',
    false,false,true,false,true,enabled,false);
  assert(original,'Actual original Common CheckEnvironment admission failed');
  return original;
}
function supplement(original,body=table){
  return common.clientProgramCheckEnvironmentWithCalendarArtifact(original,
    new TextEncoder().encode(body),1000,100,8,1,0,10000);
}
const limits=Object.freeze({maxResponseBytes:16384,maxNodes:1024,maxDepth:20,maxPages:4,maxRows:3,maxRequests:4,
  perPage:2,maxIdentityBytes:128,maxCursorBytes:128,maxQueryBytes:4096,maxTargetBytes:4096,
  maxAttendees:100,maxValueNodes:1000,maxValueTextBytes:8192,maxResolutionWork:100,
  maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20});
const requestWire='{"calendar_id":"original@example.test","time_min":"2026-03-01T00:00:00.1234Z","time_max":"2026-03-10T00:00:00.1234Z","time_zone":"UTC"}';

test('actual Calendar provider retains the Common environment original Profile through request and complete typed page',()=>{
  const original=environment(),selected=supplement(original);assert(selected);
  const profile=checked(calendar.calendarEventsProfileFromEnvironment(selected));
  assert(profile!==undefined&&profile!==null,'Actual getter must return the retained Profile, not an absent reference');
  assert.equal(profile,checked(calendar.calendarEventsProfileFromEnvironment(selected)),'same immutable original, not re-admitted Profile');
  let query;
  try{query=checked(calendar.calendarEventsQueryFromRequestWire(requestWire,profile,4096,1024,20,3,128,128,100,1000,8192,100));}
  catch(error){console.error('Actual original Calendar request refusal:',inspect(error.cause,{depth:4}));throw error;}
  const body=new TextEncoder().encode('{"kind":"calendar#events","timeZone":"UTC","items":[{"id":"event","start":{"date":"2026-03-08"},"end":{"date":"2026-03-09"},"attendees":[]}]}');
  const page=checked(calendar.calendarProjectEvents(body,query,16384,1024,20,2,128,128,100,1000,8192,100));
  assert.equal(calendar.calendarEventsMatchesQuery(page,query),true);
  const metadata=JSON.parse(checked(calendar.calendarEventsMetadataWire(page,16384,2048,20)));
  assert.equal(metadata.profileCid,tableCid);assert.equal(metadata.calendarId,'original@example.test');
  assert.deepEqual(metadata.ids,['event']);assert.equal(metadata.nextPageToken,null);
  assert.deepEqual(JSON.parse(checked(calendar.calendarEventsRowsWire(page,['start','end','all_day'],16384,2048,20))),
    [{start:'2026-03-08T00:00:00.000Z',end:'2026-03-09T00:00:00.000Z',all_day:true}]);
  // This is the actual new request-entry provider connection, still using an
  // explicit response DATA port and not a signed physical read or RowRun.
  const hooks=prepareCalendarEventsRequestPages({moon:calendar,environment:selected,requestWire,names:['id'],limits},
    (method,receiver,args)=>Reflect.apply(method,receiver,args));
  const frame={pageIndex:0,rowCount:0};
  assert.equal(hooks.fetchPage(frame).query.find(([name])=>name==='timeZone')[1],'UTC');
  const result=hooks.decodePage({accepted:true,statusCode:200,body},frame);
  assert.equal(result.rowCount,1);assert.equal(result.done,true);
  const rows=JSON.parse(result.rowsWire);assert.equal(rows[0].id,'event');
  assert.equal(Object.keys(rows[0]).length,16);assert.deepEqual(rows[0].attendees,[]);
  assert.equal(rows[0].calendar_id,'original@example.test');assert.equal(rows[0].status,null);
  assert.throws(()=>checked(calendar.calendarEventsProfileFromEnvironment(original)),{code:'MoonBitHostFailure'},'original unselected environment remains unmodified');
});

test('actual Calendar environment getter does not default absent disabled changed or query-foreign profile data',()=>{
  const absent=environment();
  assert.throws(()=>checked(calendar.calendarEventsProfileFromEnvironment(absent)),{code:'MoonBitHostFailure'});
  const disabled=environment(false);assert.equal(supplement(disabled),undefined);
  assert.throws(()=>checked(calendar.calendarEventsProfileFromEnvironment(disabled)),{code:'MoonBitHostFailure'});
  assert.equal(supplement(absent,' '+table),undefined,'actual original artifact pin refuses changed bytes');
  assert.throws(()=>checked(calendar.calendarEventsProfileFromEnvironment(absent)),{code:'MoonBitHostFailure'});
  const selected=supplement(absent);assert(selected);
  const profile=checked(calendar.calendarEventsProfileFromEnvironment(selected));
  assert.throws(()=>checked(calendar.calendarEventsQueryFromRequestWire(requestWire.replace('"UTC"','"Unknown/Zone"'),
    profile,4096,1024,20,3,128,128,100,1000,8192,100)),{code:'MoonBitHostFailure'});
  assert.equal(profile,checked(calendar.calendarEventsProfileFromEnvironment(selected)));
});

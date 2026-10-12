// Prepared inputs for the existing public-query consumer, not Host evidence.
// Boundaries, late decisions, rows and full column order are authored here.
const number = {type:'number',nullable:false};
const input = [{event_id:1,occurred_ms:0},{event_id:2,occurred_ms:10}];
const variants = [
  {name:'relation-fixed',event:false,kind:'fixed'},
  {name:'event-fixed',event:true,kind:'fixed'},
  {name:'event-sliding',event:true,kind:'sliding'},
  {name:'event-mark',event:true,kind:'fixed',policy:'mark'},
  {name:'event-drop',event:true,kind:'fixed',policy:'drop'},
  {name:'event-empty',event:true,kind:'fixed',empty:true},
];
const fixed = [{event_id:1,occurred_ms:0,start:-2,end:8},
  {event_id:2,occurred_ms:10,start:8,end:18}];
const sliding = [{event_id:1,occurred_ms:0,start:-8,end:2},
  {event_id:1,occurred_ms:0,start:-5,end:5},
  {event_id:1,occurred_ms:0,start:-2,end:8},
  {event_id:2,occurred_ms:10,start:1,end:11},
  {event_id:2,occurred_ms:10,start:4,end:14},
  {event_id:2,occurred_ms:10,start:7,end:17},
  {event_id:2,occurred_ms:10,start:10,end:20}];
function expected(v) {
  const start=v.event?'window_start_ms':'window_start';
  const end=v.event?'window_end_ms':'window_end';
  const fields=['event_id','occurred_ms',start,end];
  const columns=fields.map(name=>({name,contract:number}));
  if(v.policy) columns.push({name:'watermark_ms',contract:number},
    {name:'late',contract:{type:'boolean',nullable:false}},
    {name:'watermark_decision',contract:{type:'string',nullable:false}});
  const rows=(v.empty?[]:v.kind==='sliding'?sliding:fixed)
    .filter(row=>v.policy!=='drop'||row.event_id===2)
    .map(row=>({event_id:row.event_id,occurred_ms:row.occurred_ms,
      [start]:row.start,[end]:row.end,...(v.policy?{watermark_ms:10,
        late:row.event_id===1,watermark_decision:row.event_id===1?'mark':'keep'}:{})}));
  return {answer:{rows,columns}};
}
function control(v) {
  const fields=expected(v).answer.columns.map(c=>c.name);
  const steps=[{values:{schema:{event_id:number,occurred_ms:number},rows:v.empty?[]:input},as:'rows'}];
  if(v.event)steps.push({from:'rows',to_events:{id:'event_id',time:'occurred_ms'},as:'ev'});
  steps.push({from:v.event?'ev':'rows',[v.event?'window_events':'row_window']:{
    kind:v.kind,size:10,step:3,offset:-2,...(v.event?{}:{time:'occurred_ms'})},as:'windowed'});
  if(v.policy)steps.push({from:'windowed',watermark_events:{watermark_ms:10,policy:v.policy},as:'marked'});
  if(v.event)steps.push({from:v.policy?'marked':'windowed',events:true});
  steps.push({sort:[{field:'event_id',dir:'asc',nulls:'first'},
    {field:v.event?'window_start_ms':'window_start',dir:'asc',nulls:'first'}]},
  {select:fields,as:'out'});
  return {version:'actql/0.1',id:'fixture.window_'+v.name,
    stages:[{id:'main',inputs:{},steps,results:{rows:{from:'out',fields}}}],
    results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function source(v) {
  const rows='SELECT 1 AS event_id, 0 AS occurred_ms UNION ALL SELECT 2, 10';
  const fields=expected(v).answer.columns.map(c=>c.name).join(', ');
  return 'WITH rows AS ('+(v.empty?'WITH input AS ('+rows+') SELECT event_id, occurred_ms FROM input WHERE FALSE':rows)+'), '
    +(v.event?'ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)), ':'')
    +'windowed AS (FROM '+(v.event?'ev':'rows AS r')+' |> '+(v.event?'window_events':'row_window')
    +"(kind: '"+v.kind+"', size: 10, step: 3, offset: -2"+(v.event?'':', time: r.OCCURRED_MS')+')), '
    +(v.policy?"marked AS (FROM windowed |> watermark_events(watermark_ms: 10, policy: '"+v.policy+"')), ":'')
    +'result_rows AS (FROM '+(v.policy?'marked':'windowed')+(v.event?' |> events()':'')+') '
    +'SELECT '+fields+' FROM result_rows ORDER BY event_id, '+(v.event?'window_start_ms':'window_start');
}
export const eventWindowSourceSuccesses=variants.flatMap(v=>[
  {name:'window-json-'+v.name,format:'json',text:JSON.stringify(control(v)),results:expected(v),sourceReadCount:0},
  {name:'window-text-'+v.name,format:'aql-text',text:source(v),results:expected(v),sourceReadCount:0},
]);
const prefix='WITH rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)) ';
export const eventWindowSourceRefusals=[
  ['fixed-step-zero',"FROM rows |> row_window(time: occurred_ms, kind: 'fixed', size: 10, step: 0)"],
  ['offset-fractional',"FROM rows |> row_window(time: occurred_ms, kind: 'fixed', size: 10, offset: 0.5)"],
  ['sliding-missing-step',"FROM rows |> row_window(time: occurred_ms, kind: 'sliding', size: 10)"],
  ['exact-kind',"FROM rows |> row_window(time: occurred_ms, kind: 'FIXED', size: 10)"],
  ['window-needs-events',"FROM rows |> window_events(kind: 'fixed', size: 10)"],
  ['rows-needs-relation',"FROM ev |> row_window(time: occurred_ms, kind: 'fixed', size: 10)"],
  ['exact-policy',"FROM ev |> watermark_events(watermark_ms: 0, policy: 'MARK')"],
  ['watermark-needs-events',"FROM rows |> watermark_events(watermark_ms: 0, policy: 'mark')"],
].map(([name,text])=>({name:'window-'+name,format:'aql-text',text:prefix+text,expectedCode:'ClientProgramInvalidInput'}));

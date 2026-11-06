// Prepared controls use the existing public-query consumer. No Host execution
// is claimed here; winners and complete column contracts are independent data.
const number={type:'number',nullable:false};
const nullableNumber={type:'number',nullable:true};
const input=[{event_id:1,occurred_ms:20,bucket:null,score:null},
  {event_id:2,occurred_ms:10,bucket:null,score:7},
  {event_id:3,occurred_ms:30,bucket:2,score:5},
  {event_id:4,occurred_ms:5,bucket:2,score:null}];
const columns=[{name:'event_id',contract:number},{name:'occurred_ms',contract:number},
  {name:'bucket',contract:nullableNumber},{name:'score',contract:nullableNumber}];
const explicit=(nulls)=>[{field:'score',dir:'desc',nulls}];
const variants=[
  {name:'repeated-nullable-score',by:['bucket','bucket'],order:explicit('last'),
    sourceBy:'[bucket, BUCKET]',sourceOrder:"[{FIELD: SCORE, DIR: 'desc', NULLS: 'last'}]",ids:[2,3]},
  {name:'short-time',by:['bucket'],order:[{occurred_ms:'asc'}],
    sourceBy:'[bucket]',sourceOrder:"[{`OCCURRED_MS`: 'asc'}]",ids:[2,4]},
  {name:'global',by:[],order:[{occurred_ms:'asc'}],
    sourceBy:'[]',sourceOrder:"[{occurred_ms: 'asc'}]",ids:[4]},
  {name:'nulls-first',by:['bucket'],order:explicit('first'),
    sourceBy:'[bucket]',sourceOrder:"[{field: score, dir: 'desc', nulls: 'first'}]",ids:[1,4]},
  {name:'empty',by:['bucket','bucket'],order:explicit('last'),
    sourceBy:'[bucket, bucket]',sourceOrder:"[{field: score, dir: 'desc', nulls: 'last'}]",ids:[],empty:true},
];
const rowsText='SELECT 1 AS event_id, 20 AS occurred_ms, CAST(NULL AS FLOAT64) AS bucket, CAST(NULL AS FLOAT64) AS score UNION ALL SELECT 2, 10, CAST(NULL AS FLOAT64), 7 UNION ALL SELECT 3, 30, 2, 5 UNION ALL SELECT 4, 5, 2, CAST(NULL AS FLOAT64)';
function source(v,rows=rowsText){
  return 'WITH `rows` AS ('+(v.empty?'WITH all_rows AS ('+rows+') SELECT event_id, occurred_ms, bucket, score FROM all_rows WHERE FALSE':rows)+'), '
    +'ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)), '
    +'picked AS (FROM ev |> dedupe_events(by: '+v.sourceBy+', order_by: '+v.sourceOrder+')), '
    +'result_rows AS (FROM picked |> events()) '
    +'SELECT event_id, occurred_ms, bucket, score FROM result_rows ORDER BY event_id';
}
function control(v,rows=input){
  const fields=columns.map(c=>c.name);
  return {version:'actql/0.1',id:'fixture.event_dedupe_'+v.name,
    stages:[{id:'main',inputs:{},steps:[{values:{schema:Object.fromEntries(columns.map(c=>[c.name,c.contract])),rows:v.empty?[]:rows},as:'rows'},
      {from:'rows',to_events:{id:'event_id',time:'occurred_ms'},as:'ev'},
      {from:'ev',dedupe_events:{by:v.by,order_by:v.order},as:'picked'},
      {from:'picked',events:true},{sort:[{field:'event_id',dir:'asc',nulls:'first'}]},
      {select:fields,as:'out'}],results:{rows:{from:'out',fields}}}],
    results:{answer:{from:{stage:'main',result:'rows'}}}};
}
export const eventDedupeSourceSuccesses=variants.flatMap(v=>{
  const results={answer:{rows:v.ids.map(id=>input.find(row=>row.event_id===id)),columns}};
  return [{name:'event-dedupe-json-'+v.name,format:'json',text:JSON.stringify(control(v)),results,sourceReadCount:0},
    {name:'event-dedupe-text-'+v.name,format:'aql-text',text:source(v),results:{main:results.answer},sourceReadCount:0}];
});
const prefix='WITH rows AS ('+rowsText+'), ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)) ';
export const eventDedupeSourceRefusals=[
  ['empty-order',"FROM ev |> dedupe_events(by: [], order_by: [])"],
  ['unknown-order',"FROM ev |> dedupe_events(by: [], order_by: [{missing: 'asc'}])"],
  ['exact-direction',"FROM ev |> dedupe_events(by: [], order_by: [{score: 'ASC'}])"],
  ['missing-null-placement',"FROM ev |> dedupe_events(by: [], order_by: [{field: score, dir: 'asc'}])"],
  ['wrong-carrier',"FROM rows |> dedupe_events(by: [], order_by: [{score: 'asc'}])"],
  ['string-is-not-grouping-field',"FROM ev |> dedupe_events(by: ['bucket'], order_by: [{score: 'asc'}])"],
].map(([name,text])=>({name:'event-dedupe-'+name,format:'aql-text',text:prefix+text,expectedCode:'ClientProgramInvalidInput'}));
const tied={name:'top-tie',by:['bucket'],order:[{occurred_ms:'asc'}],sourceBy:'[bucket]',sourceOrder:"[{occurred_ms: 'asc'}]"};
const tiedRows=input.map(row=>({...row,occurred_ms:row.event_id===1?10:row.occurred_ms}));
export const eventDedupeSourceExecutionFailures=[
  {name:'event-dedupe-json-top-tie',format:'json',text:JSON.stringify(control(tied,tiedRows)),resultNames:['answer'],sourceReadCount:0},
  {name:'event-dedupe-text-top-tie',format:'aql-text',text:source(tied,rowsText.replace('20 AS occurred_ms','10 AS occurred_ms')),resultNames:['main'],sourceReadCount:0},
];

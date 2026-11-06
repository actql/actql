// Independent F01/F02 public inputs. They use the existing installed records
// Source and ordinary Client/Host. No Catalog override or test Driver is added.
const number={type:'number',nullable:false};
const columns=[{name:'node_key',contract:number},{name:'occurred_ms',contract:number}];
const expected=[{node_key:1,occurred_ms:0}];
const sourceRows=[{id:2,amount:20},{id:1,amount:null},{id:3,amount:30}];
const graph=', g AS (GRAPH (NODE TABLES (source_rows AS N KEY (node_key) PROPERTIES (occurred_ms)))) ';
const prefix=source=>'WITH source_rows AS ('+source+')'+graph;
const localPrefix=prefix('SELECT 1 AS node_key, 0 AS occurred_ms');
const sourcePrefix=prefix('SELECT id AS node_key, 0 AS occurred_ms FROM records WHERE id = 1');
const select=' |> SELECT node_key, occurred_ms |> ORDER BY node_key';
const eventTail=' |> to_events(id: node_key, time: occurred_ms) |> events()'+select;
const graphControl={version:'actql/0.1',id:'fixture.carrier_continuation_graph_events',
  stages:[{id:'main',inputs:{},steps:[
    {values:{schema:{node_key:number,occurred_ms:number},rows:expected},as:'rows'},
    {graph:{version:'actql-graph-constructor/0.1',nodes:[{name:'N',from:'rows',key:['node_key'],
      labels:[{name:'N',properties:{mode:'columns',columns:[{from:'occurred_ms',to:'occurred_ms'}]}}]}],edges:[]},as:'g'},
    {from:'g',node_rows:true,as:'nodes'},
    {from:'nodes',to_events:{id:'node_key',time:'occurred_ms'},as:'ev'},
    {from:'ev',events:true,as:'event_rows'},
    {from:'event_rows',sort:[{field:'node_key',dir:'asc',nulls:'first'}]},
    {select:['node_key','occurred_ms'],as:'out'},
  ],results:{rows:{from:'out',fields:['node_key','occurred_ms']}}}],
  results:{answer:{from:{stage:'main',result:'rows'}}}};
const result={answer:{rows:expected,columns}};
function success(name,text,source=false) {
  return ['sql','aql-text'].map(format=>({name:`carrier-continuation-${name}-${format}`,format,text,
    results:{main:structuredClone(result.answer)},sourceReadSessionCount:source?1:0,
    ...(source?{sourceRows}: {sourceReadCount:0})}));
}
export const carrierContinuationSuccesses=[
  {name:'carrier-continuation-json-events-control',format:'json',text:JSON.stringify(graphControl),
    results:structuredClone(result),sourceReadCount:0,sourceReadSessionCount:0},
  ...success('graph-marked',localPrefix+', picked AS (FROM GRAPH g) FROM picked |> node_rows()'+select),
  ...success('graph-unmarked',localPrefix+', picked AS (FROM g) FROM picked |> node_rows()'+select),
  ...success('events-flat',localPrefix+'FROM g |> node_rows()'+eventTail),
  ...success('events-with',localPrefix+', projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events()'+select),
  ...success('source-events-flat',sourcePrefix+'FROM g |> node_rows()'+eventTail,true),
  ...success('source-events-with',sourcePrefix+', projected AS (FROM g |> node_rows()), temporal AS (FROM projected |> to_events(id: node_key, time: occurred_ms)) FROM temporal |> events()'+select,true),
];
const eventsPrefix='WITH source_rows AS (SELECT 1 AS event_id, 0 AS occurred_ms), e AS (FROM source_rows |> to_events(id: event_id, time: occurred_ms))';
const invalidGraphCases=[
  ['demanded-events',eventsPrefix+', not_a_graph AS (FROM GRAPH e) FROM not_a_graph |> events() |> SELECT event_id'],
  ['unused-events',eventsPrefix+', unused AS (FROM GRAPH e) SELECT 1 AS answer'],
  ['root-events',eventsPrefix+' FROM GRAPH e |> events() |> SELECT event_id'],
  ['marked-relation','WITH source_rows AS (SELECT 1 AS event_id), unused AS (FROM GRAPH source_rows) SELECT 1 AS answer'],
  // The outer Graph itself is valid: the node key is not duplicated as a
  // property. Only the nearest inner Events binding must fail its Graph role.
  ['shadowed-events',localPrefix+'FROM (WITH g AS (FROM source_rows |> to_events(id: node_key, time: occurred_ms)), chosen AS (FROM GRAPH g) FROM chosen |> events() |> SELECT node_key)'],
  ['relation-tail-graph-call',localPrefix+'FROM g |> node_rows() |> edge_rows() |> SELECT node_key'],
  ['key-property-collision',localPrefix.replace('PROPERTIES (occurred_ms)','PROPERTIES (node_key, occurred_ms)')+'FROM g |> node_rows()'+eventTail],
];
export const carrierContinuationRefusals=invalidGraphCases.flatMap(([name,text])=>['sql','aql-text'].map(format=>({
  name:`carrier-continuation-refusal-${name}-${format}`,format,text,expectedCode:'ClientProgramInvalidInput',
})));
// Preserve the original rejected machine mapping separately from the valid
// acceptance control. Correcting the example does not relax output collisions.
const collision=structuredClone(graphControl);
collision.id+='.key_property_collision';
collision.stages[0].steps[1].graph.nodes[0].labels[0].properties.columns.unshift({from:'node_key',to:'node_key'});
carrierContinuationRefusals.push({name:'carrier-continuation-refusal-key-property-collision-json',
  format:'json',text:JSON.stringify(collision),expectedCode:'ClientProgramInvalidInput'});

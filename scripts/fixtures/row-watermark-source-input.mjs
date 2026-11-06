// Designed expectations distinguish a fixed threshold from a running prefix.
// No product compiler/checker/evaluator creates these rows or column contracts.
const number={type:'number',nullable:false};
const input=[{id:1,at:10},{id:2,at:3},{id:3,at:9}];
const columns=[{name:'id',contract:number},{name:'at',contract:number},
  {name:'watermark_ms',contract:number},{name:'watermark_late',contract:{type:'boolean',nullable:false}},
  {name:'watermark_decision',contract:{type:'string',nullable:false}}];
const variants=[
  {name:'fixed-mark',threshold:{watermark_ms:3},source:'watermark_ms: 3',policy:'mark',expected:[
    {id:1,at:10,watermark_ms:3,watermark_late:false,watermark_decision:'keep'},
    {id:2,at:3,watermark_ms:3,watermark_late:false,watermark_decision:'keep'},
    {id:3,at:9,watermark_ms:3,watermark_late:false,watermark_decision:'keep'}]},
  {name:'prefix-mark',threshold:{max_skew:1},source:'max_skew: 1',policy:'mark',expected:[
    {id:1,at:10,watermark_ms:9,watermark_late:false,watermark_decision:'keep'},
    {id:2,at:3,watermark_ms:9,watermark_late:true,watermark_decision:'mark'},
    {id:3,at:9,watermark_ms:9,watermark_late:false,watermark_decision:'keep'}]},
  {name:'prefix-drop',threshold:{max_skew:1},source:'max_skew: 1',policy:'drop',expected:[
    {id:1,at:10,watermark_ms:9,watermark_late:false,watermark_decision:'keep'},
    {id:3,at:9,watermark_ms:9,watermark_late:false,watermark_decision:'keep'}]},
  {name:'empty',threshold:{watermark_ms:-0.5},source:'watermark_ms: -0.5',policy:'mark',empty:true,expected:[]},
];
const rowsText='SELECT 1 AS id, 10 AS at UNION ALL SELECT 2, 3 UNION ALL SELECT 3, 9';
const sourceRowsText='SELECT 1 AS id, 10 AS `at` UNION ALL SELECT 2, 3 UNION ALL SELECT 3, 9';
function source(v){return 'WITH `rows` AS ('+(v.empty?'WITH all_rows AS ('+sourceRowsText+') SELECT id, at FROM all_rows WHERE FALSE':sourceRowsText)+'), '
  +'ordered AS (FROM rows |> ORDER BY id), marked AS (FROM ordered AS r |> watermark_rows(time: r.AT, late_policy: \''+v.policy+'\', '+v.source+')) '
  +'SELECT id, at, watermark_ms, watermark_late, watermark_decision FROM marked ORDER BY id';}
function control(v){const fields=columns.map(c=>c.name);return {version:'actql/0.1',id:'fixture.row_watermark_'+v.name,
  stages:[{id:'main',inputs:{},steps:[{values:{schema:{id:number,at:number},rows:v.empty?[]:input},as:'rows'},
    {from:'rows',sort:[{field:'id',dir:'asc',nulls:'first'}],as:'ordered'},
    {from:'ordered',watermark_rows:{time:'at',late_policy:v.policy,...v.threshold},as:'marked'},
    {from:'marked',sort:[{field:'id',dir:'asc',nulls:'first'}]},
    {select:fields,as:'out'}],results:{rows:{from:'out',fields}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};}
export const rowWatermarkSourceSuccesses=variants.flatMap(v=>{
  const results={answer:{rows:v.expected,columns}};
  return [{name:'row-watermark-json-'+v.name,format:'json',text:JSON.stringify(control(v)),results,sourceReadCount:0},
    {name:'row-watermark-text-'+v.name,format:'aql-text',text:source(v),results:{main:results.answer},sourceReadCount:0}];
});
const prefix='WITH rows AS ('+rowsText+') FROM rows |> ';
export const rowWatermarkSourceRefusals=[
  ['no-threshold',"watermark_rows(time: at, late_policy: 'mark')"],
  ['both-thresholds',"watermark_rows(time: at, late_policy: 'mark', watermark_ms: 0, max_skew: 1)"],
  ['zero-skew',"watermark_rows(time: at, late_policy: 'mark', max_skew: 0)"],
  ['exact-policy',"watermark_rows(time: at, late_policy: 'MARK', watermark_ms: 0)"],
  ['unknown-time',"watermark_rows(time: missing, late_policy: 'mark', watermark_ms: 0)"],
  ['string-time',"watermark_rows(time: 'at', late_policy: 'mark', watermark_ms: 0)"],
].map(([name,call])=>({name:'row-watermark-'+name,format:'aql-text',text:prefix+call,expectedCode:'ClientProgramInvalidInput'}));

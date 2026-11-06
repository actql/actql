// Authored half-open UTC grid and closed machine control, not product output.
const start='2026-10-12T00:00:00.000Z',end='2026-10-12T00:03:00.000Z';
const columns=[{name:'time',contract:{type:'timestamp',nullable:false}}];
const rows=[{time:start},{time:'2026-10-12T00:01:00.000Z'},{time:'2026-10-12T00:02:00.000Z'}];
const body=`time_series(start: '${start}', end: '${end}', step: '1m')`;
const source=`WITH grid AS (${body}) SELECT time FROM grid ORDER BY time`;
const declarations={begin:{type:'timestamp',nullable:false},finish:{type:'timestamp',nullable:false},tick:{type:'number',nullable:false}};
const parameters={begin:start,finish:end,tick:60000};
const parameterSource='WITH grid AS (time_series(start: @BEGIN, end: @finish, step: @tick)) SELECT time FROM grid ORDER BY time';
function control(name,arguments_,params) {
  return {version:'actql/0.1',id:'fixture.time_series_primary_'+name,...(params?{params}:{}),
    stages:[{id:'main',inputs:{},steps:[{time_series:arguments_,as:'grid'},
      {from:'grid',sort:[{field:'time',dir:'asc',nulls:'first'}]},
      {select:['time'],as:'out'}],results:{rows:{from:'out',fields:['time']}}}],
    results:{answer:{from:{stage:'main',result:'rows'}}}};
}
const success=(name,text,format='aql-text',expected=rows,extra={})=>({name:'time-series-primary-'+name,format,text,
  results:{[format==='json'?'answer':'main']:{rows:expected,columns}},sourceReadCount:0,sourceReadSessionCount:0,...extra});
export const timeSeriesPrimarySuccesses=[
  success('json',JSON.stringify(control('literal',{start,end,step:'1m'})),'json'),
  success('sql',source,'sql'),success('text',source),
  success('bare-text',body+' |> SELECT time |> ORDER BY time'),
  success('empty-json',JSON.stringify(control('empty',{start,end:start,step:'1m'})),'json',[]),
  success('empty-sql',source.replace(end,start),'sql',[]),
  success('parameters-json',JSON.stringify(control('parameters',{start:{$param:'begin'},end:{$param:'finish'},step:{$param:'tick'}},declarations)),
    'json',rows,{parameters}),
  ...['sql','aql-text'].map(format=>success('parameters-'+format,parameterSource,format,rows,{parameterDeclarations:declarations,parameters})),
];
export const timeSeriesPrimaryRefusals=[
  ['missing-step',`WITH grid AS (time_series(start: '${start}', end: '${end}')) SELECT time FROM grid`],
  ['extra-field',`WITH grid AS (time_series(start: '${start}', end: '${end}', step: '1m', timezone: 'UTC')) SELECT time FROM grid`],
  ['duplicate-field',`WITH grid AS (time_series(start: '${start}', end: '${end}', step: '1m', step: 60000)) SELECT time FROM grid`],
  ['unused-reversed',`WITH unused AS (time_series(start: '${end}', end: '${start}', step: '1m')) SELECT 1 AS answer`],
  ['unused-invalid-time',`WITH unused AS (time_series(start: 'not-a-timestamp', end: '${end}', step: '1m')) SELECT 1 AS answer`],
  ['consuming-pipe',`WITH input_rows AS (SELECT 1 AS id) FROM input_rows |> ${body}`],
].map(([name,text])=>({name:'time-series-primary-refusal-'+name,format:'aql-text',text,expectedCode:'ClientProgramInvalidInput'}));
timeSeriesPrimaryRefusals.push({name:'time-series-primary-refusal-nullable-endpoint',format:'sql',text:parameterSource,
  parameterDeclarations:{...declarations,begin:{type:'timestamp',nullable:true}},parameters,expectedCode:'ClientProgramInvalidInput'});

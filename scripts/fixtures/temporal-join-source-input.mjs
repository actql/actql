// Authored from the common as-of/interval laws, without product evaluation.
const number={type:'number',nullable:false};
const left=[{id:1,at:10},{id:2,at:30},{id:3,at:50}];
const right=[{id:7,begin:5,finish:15},{id:8,begin:20,finish:25}];
const leftText='SELECT 1 AS id, 10 AS `at` UNION ALL SELECT 2, 30 UNION ALL SELECT 3, 50';
const rightText='SELECT 7 AS id, 5 AS begin, 15 AS finish UNION ALL SELECT 8, 20, 25';
const projection={id:'left.id',value:'right.id'};
const variants=[
  {name:'asof-left',operation:'asof_join',body:{with:'r',kind:'left',by:[],left_id:'id',left_time:'at',right_time:'begin',direction:'backward',tolerance:12,select:projection},call:"asof_join(with: r, kind: 'left', by: [], left_id: current.id, left_time: current.at, right_time: r.begin, direction: 'backward', tolerance: 12, select: {id: left.id, value: right.id})",rows:[{id:1,value:7},{id:2,value:8},{id:3,value:null}]},
  {name:'asof-inner',operation:'asof_join',body:{with:'r',kind:'inner',by:[],left_id:'id',left_time:'at',right_time:'begin',direction:'backward',tolerance:12,select:projection},call:"asof_join(with: r, kind: 'inner', by: [], left_id: current.id, left_time: current.at, right_time: r.begin, direction: 'backward', tolerance: 12, select: {id: left.id, value: right.id})",rows:[{id:1,value:7},{id:2,value:8}]},
  {name:'interval-left',operation:'interval_join',body:{with:'r',kind:'left',mode:'point_in_interval',on:[],left:{time:'at'},right:{start:'begin',end:'finish'},select:projection,max_output_rows:3},call:"interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: current.at}, right: {start: r.begin, end: r.finish}, select: {id: left.id, value: right.id}, max_output_rows: 3)",rows:[{id:1,value:7},{id:2,value:null},{id:3,value:null}]},
  {name:'interval-inner',operation:'interval_join',body:{with:'r',kind:'inner',mode:'point_in_interval',on:[],left:{time:'at'},right:{start:'begin',end:'finish'},select:projection,max_output_rows:3},call:"interval_join(with: r, kind: 'inner', mode: 'point_in_interval', on: [], left: {time: current.at}, right: {start: r.begin, end: r.finish}, select: {id: left.id, value: right.id}, max_output_rows: 3)",rows:[{id:1,value:7}]},
];
function program(v) {
  return {version:'actql/0.1',id:'fixture.temporal_'+v.name,stages:[{id:'main',inputs:{},steps:[
    {values:{schema:{id:number,at:number},rows:left},as:'l'},
    {values:{schema:{id:number,begin:number,finish:number},rows:right},as:'r'},
    {from:'l',[v.operation]:v.body,as:'matched'},
    {from:'matched',sort:[{field:'id',dir:'asc',nulls:'first'}]},
    {select:['id','value'],as:'out'}],results:{rows:{from:'out',fields:['id','value']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function source(call) {
  return `WITH l AS (${leftText}), r AS (${rightText}), matched AS (FROM l AS \`current\` |> ${call}) SELECT id, value FROM matched ORDER BY id`;
}
export const temporalJoinSourceSuccesses=variants.flatMap(v=>{
  const results={answer:{rows:v.rows,columns:[{name:'id',contract:number},{name:'value',contract:{type:'number',nullable:v.body.kind==='left'}}]}};
  return [{name:'temporal-json-'+v.name,format:'json',text:JSON.stringify(program(v)),results,sourceReadCount:0},
    ...['sql','aql-text'].map(format=>({name:'temporal-'+format+'-'+v.name,format,text:source(v.call),results:{main:results.answer},sourceReadCount:0}))];
});
export const temporalJoinSourceRefusals=[
  ['asof-zero-tolerance',variants[0].call.replace('tolerance: 12','tolerance: 0')],
  ['wrong-left-receiver',variants[0].call.replace('left_time: current.at','left_time: right.at')],
  ['wrong-right-receiver',variants[0].call.replace('right_time: r.begin','right_time: left.begin')],
  ['string-producer',variants[0].call.replace('with: r',"with: 'r'")],
  ['missing-output',variants[0].call.replace(', select: {id: left.id, value: right.id}','')],
  ['reserved-output',variants[0].call.replace('select: {id:', 'select: {SELECT:')],
  ['interval-full',variants[2].call.replace("kind: 'left'","kind: 'full'")],
  ['interval-zero-bound',variants[2].call.replace('max_output_rows: 3','max_output_rows: 0')],
  ['unknown-right-field',variants[2].call.replace('end: r.finish','end: r.missing')],
].map(([name,call])=>({name:'temporal-'+name,format:'aql-text',text:source(call),expectedCode:'ClientProgramInvalidInput'}));

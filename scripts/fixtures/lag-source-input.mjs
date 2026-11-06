// Independent navigation expectations; no product evaluation generates these.
const number = {type:'number',nullable:false};
const nullableNumber = {type:'number',nullable:true};
const input = [{id:1,amount:10},{id:2,amount:30},{id:3,amount:null}];
const columns = [{name:'id',contract:number},{name:'amount',contract:nullableNumber},
  {name:'previous',contract:nullableNumber}];
const rowsText = 'SELECT 1 AS id, 10 AS amount UNION ALL SELECT 2, 30 UNION ALL SELECT 3, CAST(NULL AS FLOAT64)';
const order = [{field:'amount',dir:'desc',nulls:'last'}];
const variants = [
  {name:'default',partition:[],sourcePartition:'[]',previous:[30,null,10]},
  {name:'offset-two',partition:[],sourcePartition:'[]',offset:2,previous:[null,null,30]},
  {name:'repeated-partition',partition:['id','id'],sourcePartition:'[r.ID, id]',previous:[null,null,null]},
  {name:'empty',partition:[],sourcePartition:'[]',empty:true,previous:[]},
];
function control(v) {
  const fields = columns.map(c=>c.name);
  return {version:'actql/0.1',id:'fixture.lag_'+v.name,
    stages:[{id:'main',inputs:{},steps:[
      {values:{schema:{id:number,amount:nullableNumber},rows:v.empty?[]:input},as:'rows'},
      {from:'rows',assert_rows:{unique_by:['id']},as:'keyed'},
      {from:'keyed',lag:{partition_by:v.partition,order_by:order,field:'amount',output:'previous',
        ...(v.offset===undefined?{}:{offset:v.offset})},as:'lagged'},
      {from:'lagged',sort:[{field:'id',dir:'asc',nulls:'first'}]},
      {select:fields,as:'out'}],results:{rows:{from:'out',fields}}}],
    results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function source(v) {
  return 'WITH rows AS ('+(v.empty?'WITH all_rows AS ('+rowsText+') SELECT id, amount FROM all_rows WHERE FALSE':rowsText)+'), '
    +'keyed AS (FROM rows |> ASSERT UNIQUE BY (id)), '
    +'lagged AS (FROM keyed AS r |> lag(partition_by: '+v.sourcePartition
    +", order_by: [{field: r.AMOUNT, dir: 'desc', nulls: 'last'}], field: r.amount, output: previous"
    +(v.offset===undefined?'':', offset: '+v.offset)+')) '
    +'SELECT id, amount, previous FROM lagged ORDER BY id';
}
export const lagSourceSuccesses = variants.flatMap(v=>{
  const results = {answer:{rows:v.empty?[]:input.map((row,i)=>({...row,previous:v.previous[i]})),columns}};
  return [{name:'lag-json-'+v.name,format:'json',text:JSON.stringify(control(v)),results,sourceReadCount:0},
    {name:'lag-text-'+v.name,format:'aql-text',text:source(v),results:{main:results.answer},sourceReadCount:0}];
});
const prefix = 'WITH rows AS ('+rowsText+'), keyed AS (FROM rows |> ASSERT UNIQUE BY (id)) FROM keyed |> ';
export const lagSourceRefusals = [
  ['empty-order',"lag(partition_by: [], order_by: [], field: amount, output: previous)"],
  ['zero-offset',"lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: previous, offset: 0)"],
  ['output-collision',"lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: amount)"],
  ['unknown-field',"lag(partition_by: [], order_by: [{id: 'asc'}], field: missing, output: previous)"],
  ['string-field',"lag(partition_by: [], order_by: [{id: 'asc'}], field: 'amount', output: previous)"],
  ['reserved-output',"lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: SELECT)"],
].map(([name,call])=>({name:'lag-'+name,format:'aql-text',text:prefix+call,expectedCode:'ClientProgramInvalidInput'}));

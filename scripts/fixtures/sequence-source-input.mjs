// Independent finite sequence expectations from declared time/id and pattern laws.
const number={type:'number',nullable:false};
const fields=['first_id','first_time_ms','match_end_ms','match_start_ms','second_id','second_time_ms'];
const columns=fields.map(name=>({name,contract:number}));
const basic=[{id:1,occurred_ms:0,kind:1},{id:2,occurred_ms:10,kind:2}];
const gap=[{id:1,occurred_ms:0,kind:1},{id:2,occurred_ms:5,kind:0},{id:3,occurred_ms:10,kind:2}];
const eq=value=>({eq:[{field:'kind'},{literal:value}]});
const first=second=>({first_id:1,first_time_ms:0,match_end_ms:10,match_start_ms:0,second_id:second,second_time_ms:10});
const variants=[
 {name:'relation',input:basic,contiguity:'adjacent',rows:[first(2)]},
 {name:'events',input:basic,events:true,contiguity:'adjacent',rows:[first(2)]},
 {name:'nullable-case',input:basic,nullableCase:true,contiguity:'adjacent',rows:[first(2)]},
 {name:'gap-adjacent',input:gap,contiguity:'adjacent',rows:[]},
 {name:'gap-subsequence',input:gap,contiguity:'subsequence',rows:[first(3)]},
 {name:'parameters',input:basic,parameters:true,contiguity:'adjacent',rows:[first(2)]},
];
function body(v) {
 return {by:[],id:'id',time:'occurred_ms',pattern:[
  {as:'first',where:v.nullableCase?{case:{when:[{when:eq(1),then:{literal:true}}],else:{literal:null}}}:v.parameters?{eq:[{field:'kind'},{$param:'tag'}]}:eq(1)},
  {as:'second',where:eq(2)}],within:v.parameters?{$param:'span'}:20,overlap:'disallow',contiguity:v.contiguity,max_matches_per_key:2,max_output_rows:v.parameters?{$param:'cap'}:2};
}
const declarations={tag:{type:'number',nullable:false},span:{type:'number',nullable:false},cap:{type:'number',nullable:false}};
function program(v) {
 return {version:'actql/0.1',id:'fixture.sequence_'+v.name,...(v.parameters?{params:declarations}:{}),stages:[{id:'main',inputs:{},steps:[
  {values:{schema:{id:number,occurred_ms:number,kind:number},rows:v.input},as:'records'},
  ...(v.events?[{from:'records',to_events:{id:'id',time:'occurred_ms'},as:'prepared'}]:[]),
  {from:v.events?'prepared':'records',sequence:body(v),as:'matches'},
  {from:'matches',sort:[{field:'first_id',dir:'asc',nulls:'first'},{field:'second_id',dir:'asc',nulls:'first'}]},
  {select:fields,as:'out'}],results:{rows:{from:'out',fields}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
}
function source(v) {
 const rows=v.input.map((r,i)=>`SELECT ${r.id}${i===0?' AS id':''}, ${r.occurred_ms}${i===0?' AS occurred_ms':''}, ${r.kind}${i===0?' AS kind':''}`).join(' UNION ALL ');
 const current=v.events?'prepared':'records';
 const receiver=v.events?'':'e.';
 const predicate=v.nullableCase?`CASE WHEN ${receiver}kind = 1 THEN TRUE ELSE NULL END`:`${receiver}kind = ${v.parameters?'@TAG':'1'}`;
 return `WITH records AS (${rows}), `+(v.events?'prepared AS (FROM records |> to_events(id: id, time: occurred_ms)), ':'')
  +`matches AS (FROM ${current}${v.events?'':' AS e'} |> sequence(by: [], id: ${receiver}id, time: ${receiver}occurred_ms, pattern: [{as: first, where: ${predicate}}, {as: second, where: ${receiver}kind = 2}], within: ${v.parameters?'@span':'20'}, overlap: 'disallow', contiguity: '${v.contiguity}', max_matches_per_key: 2, max_output_rows: ${v.parameters?'@cap':'2'})) SELECT ${fields.join(', ')} FROM matches ORDER BY first_id, second_id`;
}
export const sequenceSourceSuccesses=variants.flatMap(v=>{
 const shared={results:{answer:{rows:v.rows,columns}},sourceReadCount:0,sourceReadSessionCount:0,...(v.parameters?{parameters:{tag:1,span:20,cap:2}}:{})};
 return [{name:'sequence-json-'+v.name,format:'json',text:JSON.stringify(program(v)),...shared},
 ...['sql','aql-text'].map(format=>({name:'sequence-'+format+'-'+v.name,format,text:source(v),...shared,results:{main:shared.results.answer},...(v.parameters?{parameterDeclarations:declarations}:{})}))];
});
const valid=source(variants[0]);
// The v0.1 authored contract defaults grouping/overlap/contiguity. Retain the
// formerly refused missing-overlap input itself, now with independent results.
const defaultResults={results:{answer:{rows:[first(2)],columns}},
 sourceReadCount:0,sourceReadSessionCount:0};
sequenceSourceSuccesses.push({name:'sequence-implicit-overlap',format:'aql-text',
 text:valid.replace(", overlap: 'disallow'",''),...defaultResults,results:{main:defaultResults.results.answer}});
const omittedProgram=program(variants[0]);
const omittedBody=omittedProgram.stages[0].steps.find(step=>step.sequence).sequence;
for(const key of ['by','overlap','contiguity']) delete omittedBody[key];
sequenceSourceSuccesses.push({name:'sequence-json-omitted-defaults',format:'json',
 text:JSON.stringify(omittedProgram),...defaultResults},
 ...['sql','aql-text'].map(format=>({name:'sequence-'+format+'-omitted-defaults',format,
 text:valid.replace('by: [], ','').replace(", overlap: 'disallow'",'')
  .replace(", contiguity: 'adjacent'",''),...defaultResults,results:{main:defaultResults.results.answer}})));
export const sequenceSourceRefusals=[
 ['string-predicate',valid.replace('e.kind = 1',"'e.kind = 1'")],
 ['prior-label-input',valid.replace('e.kind = 2','first_id = 1')],
 ['duplicate-label',valid.replace('as: second','as: first')],
 ['reserved-label',valid.replace('as: first','as: SELECT')],
 ['nonboolean-predicate',valid.replace('e.kind = 1','1')],
 ['zero-within',valid.replace('within: 20','within: 0')],
 ['zero-output-guard',valid.replace('max_output_rows: 2','max_output_rows: 0')],
 ['invalid-overlap',valid.replace("overlap: 'disallow'","overlap: 'invented'")],
 ['json-predicate-adapter',valid.replace('e.kind = 1','{literal: true}')],
].map(([name,text])=>({name:'sequence-'+name,format:'aql-text',text,expectedCode:'ClientProgramInvalidInput'}));

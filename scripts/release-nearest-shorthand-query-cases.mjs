import {selectReleaseNearestCarrierCases} from './release-nearest-carrier-query-cases.mjs';
import {nearestCarrierSourceRows} from './fixtures/nearest-carrier-source-data.mjs';
import {nearestCarrierSchemaWires} from './fixtures/nearest-carrier-installed-source.mjs';
// Independent L3 expectations from the original q=[1,0], a=[1,0], b=[0,1].
// No compiler/runtime output supplies expected values, types or identities.
const scalar = (type, nullable=false) => ({type, nullable});
// The installed declaration enumerates this exact canonical schema wire.
// Its field order is independent of compiler or observed Result output.
const queryColumns = Object.entries(JSON.parse(nearestCarrierSchemaWires.queries))
  .map(([name,contract])=>({name,contract}));
const hit = withBody => ({type:'object',nullable:false,additional_properties:false,fields:{
  query_key:{type:'object',nullable:false,additional_properties:false,fields:{request_id:scalar('string')}},
  candidate_key:{type:'object',nullable:false,additional_properties:false,fields:{item_id:scalar('string')}},
  score:scalar('number'),rank:scalar('number'),...(withBody?{body:scalar('string')}:{}),
}});
const hits = [{query_key:{request_id:'q1'},candidate_key:{item_id:'a'},score:1,rank:1},
  {query_key:{request_id:'q1'},candidate_key:{item_id:'b'},score:0,rank:2}];
const defaults = hits.map(value=>({request_id:'q1',embedding:[1,0],note:null,hit:value}));
const withBodies = hits.map((value,i)=>({...value,body:i===0?'first':'second'}));
const result = (rows,columns)=>({answer:{rows,columns,unordered:false}});
const ordered = ' |> ORDER BY hit.rank';
const base = 'FROM queries |> NEAREST candidates AS c ';
const bodyPrefix = 'WITH questions AS (FROM queries |> SELECT request_id, embedding AS query_vec, note), corpus AS (FROM candidates |> SELECT item_id, embedding, label AS body) FROM questions |> NEAREST corpus ';
const bodyColumns=[queryColumns.find(column=>column.name==='request_id'),{name:'query_vec',contract:queryColumns.find(column=>column.name==='embedding').contract},queryColumns.find(column=>column.name==='note')];
const bodyRows=withBodies.map(value=>({request_id:'q1',query_vec:[1,0],note:null,hit:value}));
// Ordinary JSON Program control, authored independently of text lowering.
const jsonControl={version:'actql/0.1',id:'fixture.nearest_shorthand_control',stages:[{id:'main',inputs:{},steps:[
  {values:{schema:JSON.parse(nearestCarrierSchemaWires.queries),rows:nearestCarrierSourceRows.queries},as:'q'},
  {values:{schema:JSON.parse(nearestCarrierSchemaWires.candidates),rows:nearestCarrierSourceRows.candidates},as:'c'},
  {from:'q',to_vectors:{id:'request_id',vector:'embedding'},as:'qv'},
  {from:'c',to_vectors:{id:'item_id',vector:'embedding'},as:'cv'},
  {from:'cv',nearest:{queries:'qv',metric:'cosine',k:3}},
  {join:{with:'q',kind:'inner',cardinality:'many_to_one',on:[{left:'query_id',right:'request_id'}],select:{query_id:'left.query_id',candidate_id:'left.candidate_id',score:'left.score',rank:'left.rank',request_id:'right.request_id',query_vec:'right.embedding',note:'right.note'}}},
  {join:{with:'c',kind:'inner',cardinality:'many_to_one',on:[{left:'candidate_id',right:'item_id'}],select:{query_id:'left.query_id',candidate_id:'left.candidate_id',score:'left.score',rank:'left.rank',request_id:'left.request_id',query_vec:'left.query_vec',note:'left.note',body:'right.label'}}},
  {derive:{hit:{object:{query_key:{object:{request_id:{field:'query_id'}}},candidate_key:{object:{item_id:{field:'candidate_id'}}},score:{field:'score'},rank:{field:'rank'},body:{field:'body'}}}}},
  {sort:[{field:'rank',dir:'asc',nulls:'first'}],as:'out'},
],results:{rows:{from:'out',fields:[...bodyColumns.map(column=>column.name),'hit']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
export function selectReleaseNearestShorthandCases() {
  const successes = [
    ['default','aql',base+'USING embedding K 2 AS hit'+ordered,result(defaults,[...queryColumns,{name:'hit',contract:hit(false)}])],
    ['explicit-default','sql',base+'QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 2 KEEP (queries.*) AS hit'+ordered,result(defaults,[...queryColumns,{name:'hit',contract:hit(false)}])],
    ['candidate-keep','aql-text',base+'USING embedding K 2 KEEP (c.label) AS hit'+ordered,result(hits.map((value,i)=>({label:i===0?'first':'second',hit:value})),[{name:'label',contract:scalar('string')},{name:'hit',contract:hit(false)}])],
    ['body','aql',bodyPrefix+'USING (query_vec) K 3 AS hit'+ordered,result(bodyRows,[...bodyColumns,{name:'hit',contract:hit(true)}])],
    ['rag-continuation','aql',bodyPrefix+'USING (query_vec) K 3 AS hit |> WHERE hit.rank = 1 |> SELECT note, hit.body AS context',result([{note:null,context:'first'}],[queryColumns.find(column=>column.name==='note'),{name:'context',contract:scalar('string')}])],
    ['typed-vectors','aql','WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM qv |> NEAREST cv USING embedding K 2 AS hit'+ordered,result(defaults,[...queryColumns,{name:'hit',contract:hit(false)}])],
  ].map(([name,format,text,results])=>({name:'nearest-short-'+name,format,text,results,sourceReadCount:2,sourceReadSessionCount:2}));
  successes.push({name:'nearest-short-json-control',format:'json',text:JSON.stringify(jsonControl),
    results:result(bodyRows,[...bodyColumns,{name:'hit',contract:hit(true)}]),sourceReadCount:0,sourceReadSessionCount:0});
  const refusals = [
    ['wildcard-collision',base+'USING embedding K 2 KEEP (*) AS hit'],
    ['result-collision','FROM queries |> SELECT request_id AS hit, embedding |> NEAREST candidates USING embedding K 2 AS hit'],
    ['ambiguous-vector','WITH corpus AS (FROM candidates |> SELECT item_id, embedding, embedding AS alternate) FROM queries |> NEAREST corpus USING embedding K 2 AS hit'],
    ['removed-query-scope',base+'USING embedding K 2 AS hit |> SELECT queries.note'],
  ].map(([name,text])=>({name:'nearest-short-refusal-'+name,format:'aql',text,expectedCode:'ClientProgramInvalidInput'}));
  return {successes,refusals};
}

export async function selectReleaseNearestShorthandMatrix(directory) {
  const original = await selectReleaseNearestCarrierCases(directory);
  const shorthand = selectReleaseNearestShorthandCases();
  return {successes:[...original.successes,...shorthand.successes],refusals:[...original.refusals,...shorthand.refusals]};
}

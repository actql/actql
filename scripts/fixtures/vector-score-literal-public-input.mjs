// Independent canonical-score controls use the same typed Source as the
// adopted aliases. No source installation, schema override or evaluator is
// supplied here; this consumer reuses the ordinary Client assertion boundary.
import {exercisePublicQueryInput} from './public-query-input.mjs';
import {vectorScalarSourceSchema,vectorScalarSourceRows} from './vector-scalar-source-input.mjs';
const columns=[{name:'id',contract:{type:'number',nullable:false}},
 {name:'value',contract:{type:'number',nullable:true}}];
const values={cosine:[0,0,null],dot:[0,0,null],l2:[-5,-Math.sqrt(2),null]};
const control=metric=>({version:'actql/0.1',id:'fixture.vector_score_'+metric,
 stages:[{id:'main',inputs:{},steps:[
 {values:{schema:vectorScalarSourceSchema,rows:vectorScalarSourceRows},as:'vectors'},
 {from:'vectors',derive:{value:{vector_score:{left:{field:'left_vector'},right:{field:'right_vector'},metric}}}},
 {select:['id','value']},{sort:[{field:'id',dir:'asc',nulls:'first'}],as:'out'},
 ],results:{rows:{from:'out',fields:['id','value']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
export const vectorScoreLiteralSuccesses=Object.keys(values).flatMap(metric=>['json','sql','aql-text'].map(format=>({
 name:`vector-score-literal-${metric}-${format}`,format,
 text:format==='json'?JSON.stringify(control(metric)):
 `SELECT id, vector_score(left_vector,right_vector,'${metric}') AS value FROM vectors ORDER BY id`,
 results:{answer:{rows:values[metric].map((value,i)=>({id:i+1,value})),columns}},
 sourceReadSessionCount:format==='json'?0:1,...(format==='json'?{sourceReadCount:0}:{}),
})));
export const vectorScoreLiteralRefusals=[
 ['upper-dot',"'DOT'"],['upper-l2',"'L2'"],['null','NULL'],
 ['parameter','@metric'],['case',"IF(TRUE,'dot','l2')"],['concat',"'do'||'t'"],
].flatMap(([name,metric])=>['sql','aql-text'].map(format=>({
 name:`vector-score-literal-refusal-${name}-${format}`,format,
 text:`SELECT id, vector_score(left_vector,right_vector,${metric}) AS value FROM vectors ORDER BY id`,
 expectedCode:'ClientProgramInvalidInput',
 ...(name==='parameter'?{parameterDeclarations:{metric:{type:'string'}},parameters:{metric:'dot'}}:{}),
})));
export async function exerciseVectorScoreLiteralPublicInput(connect,options,{requestPrefix,observe,completedCase,prepareCase}) {
 return exercisePublicQueryInput(connect,options,{requestPrefix,observe,completedCase,prepareCase,
 successes:vectorScoreLiteralSuccesses,refusals:vectorScoreLiteralRefusals});
}

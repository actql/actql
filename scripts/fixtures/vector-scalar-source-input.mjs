// Prepared independent controls. The text forms require the existing Host
// Source owner to admit this typed Relation as "vectors"; no Vector parameter
// or implicit ARRAY cast is used. Preparation does not prove installed E2E.
export const vectorScalarSourceSchema={id:{type:'number',nullable:false},
  left_vector:{type:'vector',dimensions:2,nullable:false},
  right_vector:{type:'vector',dimensions:2,nullable:true}};
export const vectorScalarSourceRows=[
  {id:1,left_vector:[3,4],right_vector:[0,0]},
  {id:2,left_vector:[1,0],right_vector:[0,1]},
  {id:3,left_vector:[1,1],right_vector:null},
];
const left={field:'left_vector'},right={field:'right_vector'};
const score=metric=>({vector_score:{left,right,metric}});
const definitions=[
  ['cosine','VECTOR_COSINE_SIMILARITY',score('cosine'),[0,0,null]],
  ['dot','VECTOR_INNER_PRODUCT',score('dot'),[0,0,null]],
  ['l2','VECTOR_L2_DISTANCE',{negate:score('l2')},[5,Math.sqrt(2),null]],
  ['concat','VECTOR_CONCAT',{vector_concat:[left,right]},[[3,4,0,0],[1,0,0,1],null]],
];
function control(expression) {
  return {version:'actql/0.1',id:'fixture.vector_scalar',stages:[{id:'main',inputs:{},steps:[
    {values:{schema:vectorScalarSourceSchema,rows:vectorScalarSourceRows},as:'vectors'},
    {from:'vectors',derive:{value:expression}},{select:['id','value']},
    {sort:[{field:'id',dir:'asc',nulls:'first'}],as:'out'},
  ],results:{rows:{from:'out',fields:['id','value']}}}],
  results:{answer:{from:{stage:'main',result:'rows'}}}};
}
export const vectorScalarSourceSuccesses=definitions.flatMap(([name,surface,expression,values])=>{
  const rows=values.map((value,i)=>({id:i+1,value}));
  const columns=[{name:'id',contract:{type:'number',nullable:false}},
    {name:'value',contract:name==='concat'
      ?{type:'vector',dimensions:4,element_type:'f32',nullable:true}
      :{type:'number',nullable:true}}];
  const text=`SELECT id, ${surface}(left_vector,right_vector) AS value FROM vectors ORDER BY id`;
  return ['json','sql','aql-text'].map(format=>({name:`vector-scalar-${name}-${format}`,format,
    text:format==='json'?JSON.stringify(control(expression)):text,
    results:{answer:{rows,columns}},sourceReadSessionCount:format==='json'?0:1,
    ...(format==='json'?{sourceReadCount:0}:{}),
  }));
});
export const vectorScalarSourceRefusals=[
  ['score-arity','VECTOR_INNER_PRODUCT(left_vector)'],
  ['concat-arity','VECTOR_CONCAT(left_vector)'],
  ['array-not-vector','VECTOR_INNER_PRODUCT([1,0],left_vector)'],
  ['dimension-mismatch','VECTOR_INNER_PRODUCT(left_vector,VECTOR_CONCAT(right_vector,right_vector))'],
].flatMap(([name,expression])=>['sql','aql-text'].map(format=>({
  name:`vector-scalar-${name}-${format}`,format,
  text:`SELECT id, ${expression} AS value FROM vectors ORDER BY id`,
  expectedCode:'ClientProgramInvalidInput',
})));

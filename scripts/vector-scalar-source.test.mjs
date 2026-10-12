import test from 'node:test';
import assert from 'node:assert/strict';
import {vectorScalarSourceSchema,vectorScalarSourceRows,vectorScalarSourceSuccesses,vectorScalarSourceRefusals} from './fixtures/vector-scalar-source-input.mjs';
test('prepared vector scalar controls retain typed input, independent metric values and full schema',()=>{
  assert.equal(vectorScalarSourceSuccesses.length,12);
  for(const metric of ['cosine','dot','l2','concat']) {
    const cases=vectorScalarSourceSuccesses.filter(c=>c.name.startsWith(`vector-scalar-${metric}-`));
    assert.equal(cases.length,3);
    assert.deepEqual(cases.map(c=>c.format),['json','sql','aql-text']);
    const control=JSON.parse(cases[0].text);
    assert.deepEqual(control.stages[0].steps[0].values,{schema:vectorScalarSourceSchema,rows:vectorScalarSourceRows});
    assert.deepEqual(control.stages[0].steps[3].sort,[{field:'id',dir:'asc',nulls:'first'}]);
    for(const c of cases) {
      assert.deepEqual(c.results,cases[0].results);
      assert.equal(c.sourceReadSessionCount,c.format==='json'?0:1);
      assert.deepEqual(c.results.answer.columns.map(c=>c.name),['id','value']);
      assert.equal(c.results.answer.rows[2].value,null);
    }
  }
  const l2=vectorScalarSourceSuccesses.find(c=>c.name==='vector-scalar-l2-json');
  assert.deepEqual(l2.results.answer.rows,[{id:1,value:5},{id:2,value:Math.sqrt(2)},{id:3,value:null}]);
  assert.equal(JSON.parse(l2.text).stages[0].steps[1].derive.value.negate.vector_score.metric,'l2');
  const concat=vectorScalarSourceSuccesses.find(c=>c.name==='vector-scalar-concat-json');
  assert.deepEqual(concat.results.answer.rows[0].value,[3,4,0,0]);
  assert.deepEqual(concat.results.answer.columns[1].contract,{type:'vector',dimensions:4,element_type:'f32',nullable:true});
});
test('prepared vector scalar refusals preserve exact common type and arity boundaries',()=>{
  assert.equal(vectorScalarSourceRefusals.length,8);
  assert.equal(new Set([...vectorScalarSourceSuccesses,...vectorScalarSourceRefusals].map(c=>c.name)).size,20);
  for(const c of vectorScalarSourceRefusals) assert.equal(c.expectedCode,'ClientProgramInvalidInput');
  assert.ok(vectorScalarSourceRefusals.some(c=>c.text.includes('[1,0]')));
  assert.ok(vectorScalarSourceRefusals.some(c=>c.text.includes('VECTOR_CONCAT(right_vector,right_vector)')));
});

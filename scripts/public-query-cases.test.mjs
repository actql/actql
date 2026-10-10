import assert from 'node:assert/strict';
import test from 'node:test';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';
import {relationDataSuccesses, relationDataRefusals, queryCompositionSuccesses, queryCompositionRefusals} from './fixtures/public-query-input.mjs';
import {graphSourceSuccesses} from './fixtures/graph-source-input.mjs';
import {pipePivotSuccesses,pipePivotRefusals,fromPivotAcquiredProgram} from './fixtures/pipe-pivot-source-input.mjs';

test('shared Relation controls and Graph source cases have one request each', () => {
  const selected = uniquePublicQueryCases([
    ...relationDataSuccesses, ...graphSourceSuccesses,
  ]);
  assert.equal(selected.length, 42);
  assert.deepEqual(selected.slice(0, 3).map(item => item.name), [
    'data-set-order-reuses-hidden-slot', 'data-quoted-set-order',
    'data-retained-results',
  ]);
  assert.equal(selected.filter(item => item.name.startsWith('keyed-')).length, 35);
  assert.deepEqual(selected.slice(7), graphSourceSuccesses.slice(3));
});

test('duplicate request names cannot hide conflicting source or expectations', () => {
  const original = relationDataSuccesses[0];
  for (const conflicting of [{...original, text: 'SELECT 999 AS id'},
    {...original, results: {nodes: {rows: [{id: 999}]}}}]) {
    assert.throws(() => uniquePublicQueryCases([original, conflicting]),
      /Conflicting public query fixture/u);
  }
});

test('DATA positional fixture keeps NULL duplicates and public output contracts', () => {
  const cases = new Map(relationDataSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('data-anonymous-set-duplicate-order-limit').results.nodes.rows,
    [{id: 1}, {id: 1}]);
  assert.deepEqual(cases.get('data-anonymous-set-null-source').results,
    cases.get('data-anonymous-set-null-json-control').results);
  assert.deepEqual(cases.get('data-anonymous-set-null-source').results.nodes.columns,
    [{name: 'id', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(cases.get('data-anonymous-set-cte-source').results.nodes.rows,
    [{id: 1}, {id: 2}]);
});

test('DATA refusal fixtures distinguish unsupported output names from private references', () => {
  const cases = new Map(relationDataRefusals.map(item => [item.name, item]));
  assert.equal(cases.get('data-anonymous-set-by-name').expectedCode,
    'ClientProgramImplementationLimit');
  assert.equal(cases.get('data-anonymous-set-private-field').expectedCode,
    'ClientProgramInvalidInput');
});

test('FROM PIVOT fixtures retain predicates, explicit JOIN limits and fresh output scopes',()=>{
 const cases=new Map(pipePivotSuccesses.map(item=>[item.name,item]));
 const source=cases.get('pipe-pivot-from-shared-source');
 const control=cases.get('pipe-pivot-from-shared-source-json-control');
 assert.deepEqual(source.sourceRows,control.sourceRows);
 assert.deepEqual(source.expected,[{product:'kale',first:3,second:1}]);
 assert.deepEqual(source.expected,control.expected);
 assert.deepEqual(source.columns,control.columns);
 assert.equal(source.sourceReadSessionCount,1);assert.equal(control.sourceReadSessionCount,1);
 assert.equal(source.sourceReadCount,2);assert.equal(control.sourceReadCount,2);
 assert.deepEqual(fromPivotAcquiredProgram.stages[0].steps[0].filter,
  {gt:[{field:'id'},{literal:0}]});
 assert.ok(cases.get('pipe-pivot-from-left-join-padding').text.includes('MAX_OUTPUT_ROWS 10'));
 assert.deepEqual(cases.get('pipe-pivot-from-left-join-padding').expected,
  [{product:1,marker:100,A:5},{product:2,marker:200,A:null}]);
 assert.deepEqual(cases.get('pipe-pivot-from-projected-identity').expected,
  [{twin:1,A:2},{twin:2,A:2}]);
 assert.equal(pipePivotRefusals.filter(item=>item.name.startsWith('pipe-pivot-refusal-from-')).length,6);
});

test('optional table aliases preserve independent NULL/duplicate and range-value controls',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 const source=cases.get('derived-optional-null-duplicate-set-source');
 const control=cases.get('derived-optional-null-duplicate-json-control');
 assert.deepEqual(source.expected,[{id:2},{id:1},{id:1}]);
 assert.deepEqual(source.expected,control.expected);
 assert.deepEqual(source.columns,control.columns);
 assert.ok(source.text.includes('WHERE id IS NOT NULL'));
 assert.ok(source.text.includes('DESC NULLS FIRST LIMIT 3'));
 const ranged=cases.get('derived-optional-range-snapshot');
 assert.deepEqual(ranged.expected,cases.get('derived-optional-range-snapshot-json-control').expected);
 assert.deepEqual(ranged.expected,[{original:1,current:11,y:20},{original:2,current:12,y:10}]);
 assert.deepEqual(cases.get('derived-optional-captured-range-snapshot').expected,
  [{id:1,original:null,current:99},{id:2,original:20,current:99},{id:3,original:30,current:99},{id:3,original:30,current:99}]);
 assert.equal(cases.get('derived-optional-captured-range-snapshot').sourceReadSessionCount,1);
 assert.equal(queryCompositionRefusals.filter(item=>item.name.startsWith('derived-optional-refusal-')).length,6);
});

test('derived value-table aliases retain scalar/object type and old-name refusal controls',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 const scalar=cases.get('derived-value-scalar-receiver');
 assert.deepEqual(scalar.expected,[{value:null},{value:2},{value:2}]);
 assert.deepEqual(scalar.expected,cases.get('derived-value-scalar-json-control').expected);
 assert.deepEqual(scalar.columns,[{name:'value',contract:{type:'number',nullable:true}}]);
 const object=cases.get('derived-value-object-whole-and-property');
 assert.deepEqual(object.expected,cases.get('derived-value-object-json-control').expected);
 assert.equal(object.columns[0].contract.nullable,true);
 assert.equal(object.columns[0].contract.additional_properties,false);
 assert.equal(Object.hasOwn(object.parameterDeclarations.items.items,'additional_properties'),false);
 assert.equal(Object.hasOwn(JSON.parse(cases.get('derived-value-object-json-control').text).params.items.items,'additional_properties'),false);
 assert.equal(object.columns[0].contract.fields.id.nullable,false);
 assert.equal(object.columns[1].contract.nullable,true);
 assert.deepEqual(cases.get('derived-value-offset-row-columns').columns,
 [{name:'value',contract:{type:'number',nullable:true}},{name:'position',contract:{type:'number',nullable:false}}]);
 assert.equal(queryCompositionRefusals.filter(item=>item.name.startsWith('derived-value-refusal-')).length,4);
});

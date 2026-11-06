import {queryCompositionSuccesses, queryCompositionRefusals, joinedRowControl, joinValueControl, joinOnColumnControl, parenthesizedJoinControl} from './fixtures/public-query-input.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';
import {relationDataSuccesses, relationDataRefusals, pipeResultSuccesses} from './fixtures/public-query-input.mjs';
import {graphSourceSuccesses} from './fixtures/graph-source-input.mjs';
import {pipePivotSuccesses, pipePivotRefusals, pivotArgumentExpressionProgram, fromPivotAcquiredProgram}
  from './fixtures/pipe-pivot-source-input.mjs';

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

test('retained Result SET keeps original values and its quoted current output', () => {
  const item = pipeResultSuccesses.find(value => value.name === 'result-after-set');
  const original = 'FROM records AS old |> SET id = id + 10 |> RESULT changed |> SELECT old.id AS original, id AS current |> ORDER BY original |> RESULT final';
  assert.equal(item.text, original.replace('id AS current', 'id AS `current`'));
  assert.deepEqual(Object.keys(item.results), ['changed', 'final']);
  assert.deepEqual(item.results.final.rows,
    [{original: 1, current: 11}, {original: 2, current: 12},
      {original: 3, current: 13}, {original: 3, current: 13}]);
  assert.equal(item.sourceReadSessionCount, 1);
});

test('WITH positional fixture keeps NULL duplicates and public output contracts', () => {
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

test('WITH refusal fixtures distinguish unsupported output names from private references', () => {
  const cases = new Map(relationDataRefusals.map(item => [item.name, item]));
  assert.equal(cases.get('data-anonymous-set-by-name').expectedCode,
    'ClientProgramImplementationLimit');
  assert.equal(cases.get('data-anonymous-set-private-field').expectedCode,
    'ClientProgramInvalidInput');
});

test('PIVOT expression controls distinguish consumed fields, constants and frozen input slots', () => {
  const cases = new Map(pipePivotSuccesses.map(item => [item.name, item]));
  const source = cases.get('pipe-pivot-argument-expression-consumption');
  const control = cases.get('pipe-pivot-argument-expression-json-control');
  assert.deepEqual(source.expected, [{product: 1, A: 5}]);
  assert.deepEqual(source.columns, control.columns);
  assert.deepEqual(source.expected, control.expected);
  assert.deepEqual(JSON.parse(control.text), pivotArgumentExpressionProgram);
  assert.deepEqual(pivotArgumentExpressionProgram.stages[0].steps[2].pivot.index, ['product']);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-constant').expected,
    [{product: 1, amount: 1, A: 1}, {product: 1, amount: 2, A: 1}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-immutable-range').expected,
    [{product: 1, amount: 7, A: 5}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-current-slot').expected,
    [{product: 1, A: 16}]);
  assert.deepEqual(cases.get('pipe-pivot-argument-expression-property-null-propagation').expected,
    [{product: 1, A: 11}, {product: 2, A: null}, {product: 3, A: null}]);
  assert.equal(pipePivotRefusals.filter(item => item.name.startsWith('pipe-pivot-refusal-argument-expression-')).length, 6);
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

test('joined row fixtures distinguish row identity, null extension and ORDER receiver reuse',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 const control=cases.get('joined-row-json-control');
 const source=cases.get('joined-row-cross-null-duplicates');
 assert.deepEqual(control.expected,source.expected);
 assert.deepEqual(control.columns,source.columns);
 assert.deepEqual(joinedRowControl.stages[0].steps[2].cross_join,
  {with:'right',max_output_rows:10,select:{left_amount:'left.amount',left_id:'left.id',right_id:'right.id'}});
 assert.deepEqual(source.expected.map(row=>row.left_row.id),[1,2,2]);
 assert.deepEqual(cases.get('joined-row-range-column-collision').expected,[{row:{l:7,id:9}}]);
 assert.deepEqual(cases.get('joined-row-left-null-extension').expected[0],
  {left_row:{amount:null,id:1},right_row:{id:null,marker:null}});
 assert.equal(cases.get('joined-row-left-null-extension').columns[1].contract.nullable,false);
 assert.equal(cases.get('joined-row-right-null-extension').columns[0].contract.fields.id.nullable,true);
 const fullUsing=cases.get('joined-row-full-using');
 assert.ok(fullUsing.text.startsWith('WITH lefts AS ('));
 assert.equal(fullUsing.text.match(/ASSERT UNIQUE BY \(id\)/gu).length,2);
 assert.ok(fullUsing.text.includes('FULL JOIN rights r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id'));
 assert.deepEqual(fullUsing.expected.map(row=>[row.left_row.id,row.right_row.id]),[[1,null],[2,2],[null,4]]);
 const alias=cases.get('joined-row-order-alias-not-input-reuse');
 assert.deepEqual(alias.expected.map(row=>row.id),[1,2,2]);
 assert.deepEqual([...alias.expected].sort((a,b)=>a.original-b.original).map(row=>row.id),[2,2,1]);
 assert.equal(cases.get('joined-row-shared-acquired-cte').sourceReadSessionCount,1);
 assert.equal(cases.get('joined-row-shared-acquired-cte').expected.length,6);
 assert.equal(queryCompositionRefusals.filter(item=>item.name.startsWith('joined-row-refusal-')).length,4);
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
 const originalRange='FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10';
 for(const [name,original] of [
  ['range-snapshot','SELECT r.x AS original,x AS current,y FROM ('+originalRange+') ORDER BY original'],
  ['explicit-alias-replaces-ranges','SELECT chosen.x AS current,chosen.y FROM ('+originalRange+') chosen ORDER BY current'],
  ['captured-range-snapshot','SELECT id,r.amount AS original,amount AS current FROM (FROM records |> AS r |> SET amount=99) ORDER BY id'],
 ]) assert.equal(cases.get('derived-optional-'+name).text,original.replace(' AS current',' AS `current`'));
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



test('ordinary row fixtures distinguish NULL fields, immutable bindings and rebound columns',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 const source=cases.get('whole-row-offset-receiver'),control=cases.get('whole-row-json-control');
 assert.deepEqual(source.expected,[{row:{element:2,position:0},value:2,position:0},{row:{element:null,position:1},value:null,position:1},{row:{element:2,position:2},value:2,position:2}]);
 assert.deepEqual(source.expected,control.expected);assert.deepEqual(source.columns,control.columns);
 assert.equal(source.columns[0].contract.nullable,false);assert.equal(source.columns[0].contract.fields.element.nullable,true);
 assert.deepEqual(cases.get('whole-row-immutable-set').expected[1],{row:{element:null,position:1},value:11,position:1});
 assert.deepEqual(cases.get('whole-row-rebound-set').expected[1],{row:{element:11,position:1},value:11,position:1});
 assert.deepEqual(cases.get('whole-row-computed-order').expected.map(r=>r.row.position),[2,1,0]);
 assert.deepEqual(cases.get('whole-row-range-priority').expected[1],{value:{element:null,position:1},position:1});
 assert.equal(cases.get('whole-row-range-priority').columns[0].contract.nullable,false);
 for(const name of ['implicit-output-name','immutable-set','rebound-set','drop-rename-rebind','range-priority','computed-order']) assert.equal(cases.get('whole-row-'+name).format,'aql-text');
 assert.equal(queryCompositionSuccesses.filter(c=>c.name.startsWith('whole-row-')).length,9);
 assert.equal(queryCompositionRefusals.filter(c=>c.name.startsWith('whole-row-refusal-')).length,4);
});



test('range-shadow fixtures distinguish input ranges, ORDER aliases and NULL object columns',()=>{
 const cases=new Map(queryCompositionSuccesses.map(c=>[c.name,c]));
 assert.deepEqual(cases.get('range-shadow-order-alias').expected,[{element:2},{element:1},{element:0}]);
 assert.deepEqual(cases.get('range-shadow-set-removes-range').expected,[{value:10,position:0},{value:11,position:1},{value:12,position:2}]);
 for(const name of ['object-column','null-object-column']) {
  assert.deepEqual(cases.get('range-shadow-'+name).expected,[{value:90}]);
  assert.deepEqual(cases.get('range-shadow-'+name).columns,cases.get('range-shadow-object-column-json-control').columns);
 }
 assert.deepEqual(cases.get('range-shadow-where-row').expected,[{row:{element:null,position:1},position:1},{row:{element:2,position:2},position:2}]);
 assert.equal(queryCompositionSuccesses.filter(c=>c.name.startsWith('range-shadow-')).length,7);
 assert.equal(queryCompositionRefusals.filter(c=>c.name.startsWith('range-shadow-refusal-')).length,2);
});

test('JOIN value receiver fixtures distinguish scalar object and ordinary row kinds',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 assert.deepEqual(cases.get('join-value-json-control').expected,cases.get('join-value-right-null-duplicates').expected);
 assert.deepEqual(cases.get('join-value-json-control').columns,cases.get('join-value-right-null-duplicates').columns);
 assert.deepEqual(joinValueControl.stages[0].steps[4].cross_join,{with:'right',max_output_rows:10,select:{value:'right.element'}});
 assert.deepEqual(cases.get('join-value-right-range-column-collision').expected,[{value:1}]);
 assert.deepEqual(cases.get('join-value-both-scalar-on').expected,[{left_value:2,right_value:2}]);
 assert.equal(cases.get('join-value-right-object').columns[0].contract.nullable,true);
 assert.equal(cases.get('join-value-offset-row').columns[0].contract.nullable,false);
 assert.equal(queryCompositionRefusals.filter(item=>item.name.startsWith('join-value-refusal-')).length,3);
});

test('ON range refusals retain qualified column and USING controls',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 assert.deepEqual(joinOnColumnControl.stages[0].steps[2].join,
  {with:'right',kind:'inner',on:[{left:'l',right:'id'}],max_output_rows:10,select:{id:'left.id'}});
 assert.deepEqual(cases.get('join-on-range-json-column-control').expected,[{id:2}]);
 assert.deepEqual(cases.get('join-on-range-qualified-left').expected,[{id:2}]);
 assert.deepEqual(cases.get('join-on-range-qualified-right').expected,[{id:1}]);
 assert.ok(cases.get('join-on-range-using-column').text.includes('USING(l)'));
 const refusals=queryCompositionRefusals.filter(item=>item.name.startsWith('join-on-range-refusal-'));
 assert.equal(refusals.length,4);
 assert.ok(refusals.every(item=>item.expectedCode==='ClientProgramImplementationLimit'));
 assert.ok(refusals.some(item=>item.text.includes('FROM records JOIN')),
  'the retained public refusal must also prove no acquired Source I/O');
});


test('parenthesized JOIN controls retain equality keys NULLs duplicates and explicit ceilings',()=>{
 const cases=new Map(queryCompositionSuccesses.map(item=>[item.name,item]));
 assert.deepEqual(parenthesizedJoinControl.stages[0].steps[2].join,
  {with:'right',kind:'inner',on:[{left:'id',right:'key'}],max_output_rows:10,select:{id:'left.id',tag:'right.tag'}});
 const expected=[{id:2,tag:20},{id:2,tag:20},{id:2,tag:21},{id:2,tag:21}];
 for(const name of ['json-control','sql-null-duplicates','pipe-conjunction']){
  assert.deepEqual(cases.get('join-parenthesized-'+name).expected,expected);
  assert.deepEqual(cases.get('join-parenthesized-'+name).columns,
   [{name:'id',contract:{type:'number',nullable:true}},{name:'tag',contract:{type:'number',nullable:false}}]);
 }
 for(const name of ['sql-null-duplicates','pipe-conjunction']){
  assert.equal(cases.get('join-parenthesized-'+name).text.split('CAST(NULL AS FLOAT64)').length-1,2,
   'the source declares the same nullable Number key contracts as the independent JSON control');
 }
 assert.ok(cases.get('join-parenthesized-quoted-cte').text.includes('((`L`.id))=(r.id)'));
 assert.ok(cases.get('join-parenthesized-scalar-receivers').text.includes('((l))=(r)'));
 assert.equal(cases.get('join-parenthesized-acquired-source').sourceReadSessionCount,1);
 const refusals=queryCompositionRefusals.filter(item=>item.name.startsWith('join-parenthesized-refusal-'));
 assert.equal(refusals.length,3);
 assert.ok(refusals.every(item=>item.expectedCode==='ClientProgramImplementationLimit'));
});

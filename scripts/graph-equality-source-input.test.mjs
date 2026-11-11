import assert from 'node:assert/strict';import test from 'node:test';
import {graphEqualitySourceSuccesses,graphEqualitySourceRefusals} from './fixtures/graph-equality-source-input.mjs';
// Literal original Source plus independent singleton Boolean law and schema.
const expected={name:'graph-equality-common-unresolved-order',format:'aql-text',text:"WITH n AS (SELECT 1 AS node_key, 7 AS p) , g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> graphs_equal(with: g) |> SELECT equal |> ORDER BY equal |> LIMIT 1 |> RESULT comparison",
 results:{comparison:{rows:[{equal:true}],columns:[{name:'equal',contract:{type:'boolean',nullable:false}}]}},sourceReadCount:0};
test('ordered singleton Graph equality retains original ORDER LIMIT and full independent Boolean Result',()=>{
 assert.equal(graphEqualitySourceRefusals.some(x=>x.name===expected.name),false);
 assert.deepEqual(graphEqualitySourceSuccesses.find(x=>x.name===expected.name),expected);
 const control=graphEqualitySourceSuccesses.find(x=>x.name==='graph-equality-json-control');
 const program=JSON.parse(control.text);assert.deepEqual(program.stages[0].steps[0].values.rows,[{node_key:1,p:7}]);
 assert.deepEqual(program.stages[0].steps[2],{from:'g',graphs_equal:{with:'g'},as:'same'});
 assert.deepEqual(control.results,expected.results);
 assert.equal(graphEqualitySourceSuccesses.filter(x=>x.name===expected.name).length,1);
});

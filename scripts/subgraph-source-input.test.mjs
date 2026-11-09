import assert from 'node:assert/strict';
import test from 'node:test';
import {subgraphSourceSuccesses,subgraphSourceRefusals} from './fixtures/subgraph-source-input.mjs';

// Independently pinned original Source and authored Result oracle; no runtime compiler,
// returned rows or inferred output schema supplies this expectation.
const originalText = "WITH n AS (SELECT 3 AS node_key, CAST(NULL AS FLOAT64) AS p UNION ALL SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, 10 AS p) , e AS (SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 20 AS w UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key, 10 AS w UNION ALL SELECT 12 AS edge_key, 2 AS src_key, 3 AS dst_key, 40 AS w UNION ALL SELECT 13 AS edge_key, 2 AS src_key, 2 AS dst_key, 30 AS w) , g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R PROPERTIES (w)))) , selected AS (FROM g |> node_rows() |> WHERE node_key <= 2 |> SELECT id) FROM g |> subgraph(nodes: {from: selected, id: `id`}) |> node_rows() |> SELECT node_key, p |> ORDER BY node_key |> RESULT answer";
const expected = {name:'subgraph-task-profile-bound',format:'aql-text',text:originalText,
  results:{answer:{rows:[{node_key:1,p:10},{node_key:2,p:20}],columns:[
    {name:'node_key',contract:{type:'number',nullable:false}},
    {name:'p',contract:{type:'number',nullable:true}},
  ]}},sourceReadCount:0};
test('full three-node Subgraph retains original input and independent rows schema under current finite profile',()=>{
  assert.equal(subgraphSourceRefusals.some(x=>x.name===expected.name),false);
  assert.deepEqual(subgraphSourceSuccesses.find(x=>x.name===expected.name),expected);
  const control=subgraphSourceSuccesses.find(x=>x.name==='subgraph-json-nodes');
  const program=JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[0].values.rows,[{node_key:3,p:null},{node_key:2,p:20},{node_key:1,p:10}]);
  assert.deepEqual(program.stages[0].steps[1].values.rows,[
    {edge_key:11,src_key:1,dst_key:2,w:20},{edge_key:10,src_key:1,dst_key:2,w:10},
    {edge_key:12,src_key:2,dst_key:3,w:40},{edge_key:13,src_key:2,dst_key:2,w:30},
  ]);
  assert.deepEqual(control.results,expected.results);
  assert.equal(subgraphSourceSuccesses.filter(x=>x.name===expected.name).length,1);
});

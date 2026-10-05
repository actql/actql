import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {unionGraphScenario} from './fixtures/property-graph-union.mjs';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/property-graph-presence.program.json',import.meta.url),'utf8'));

test('union oracle preserves partial overlap parallel identities and the three sparse states', () => {
  const scenario = unionGraphScenario(fixture,'node_rows');
  const [base,peer,result] = scenario.graphSnapshots.map(([,bytes])=>JSON.parse(bytes));
  assert.equal(peer[4].length,1);
  assert.equal(result[4].length,2);
  assert.deepEqual(result,base);
  assert.deepEqual(result[4].map(edge=>edge.key),[[10,'a'],[11,'a']]);
  assert.deepEqual(result[4][0].src,result[4][1].src);
  assert.deepEqual(result[4][0].dst,result[4][1].dst);
  const rows = scenario.relationSnapshots[0][1];
  assert.equal(Object.hasOwn(rows[0],'p'),false);
  assert.equal(rows[1].p,7);
  assert.equal(rows[2].p,null);
  assert.deepEqual(rows.map(row=>row.id.definition),['M','N','N']);
  assert.deepEqual(rows.map(row=>row.id.key),[[3],[1,'a'],[2,'a']]);
});

test('union oracle keeps all repeated number_sum occurrences and original typed IDs', () => {
  for (const projection of ['node_rows','edge_rows']) {
    const scenario = unionGraphScenario(fixture,projection,{numeric:true});
    assert.deepEqual(scenario.document.stages[0].steps[4].union_graphs.with,['g','g']);
    const [base,result] = scenario.graphSnapshots.map(([,bytes])=>JSON.parse(bytes));
    assert.deepEqual(base[3].slice(1).map(node=>node.props.p),[2,3]);
    assert.deepEqual(result[3].slice(1).map(node=>node.props.p),[6,9]);
    assert.deepEqual(result[3].map(node=>node.id),base[3].map(node=>node.id));
    assert.deepEqual(result[4],base[4]);
    assert.equal(scenario.relationSnapshots.length,projection === 'node_rows' ? 2 : 1);
    if (projection === 'node_rows') assert.deepEqual(scenario.relationSnapshots[0][1].slice(1).map(row=>row.p),[6,9]);
  }
});

test('empty union oracle keeps declaration schemas without inventing a Delta row', () => {
  for (const projection of ['node_rows','edge_rows']) for (const numeric of [false,true]) {
    const scenario = unionGraphScenario(fixture,projection,{numeric,empty:true});
    const steps = scenario.document.stages[0].steps;
    assert.equal(steps.some(step=>Object.hasOwn(step,'apply_graph_delta')),false);
    assert.equal(steps[0].values.schema.p.nullable,true);
    assert.deepEqual(steps[4].union_graphs.with,['g','g']);
    for (const [,bytes] of scenario.graphSnapshots) {
      const snapshot = JSON.parse(bytes);
      assert.deepEqual(snapshot[2].node_definitions.map(def=>def.name),['M','N']);
      assert.deepEqual(snapshot.slice(3),[[],[]]);
    }
    assert.deepEqual(scenario.expected,[]);
    assert(scenario.relationSnapshots.every(([,rows])=>rows.length===0));
  }
});

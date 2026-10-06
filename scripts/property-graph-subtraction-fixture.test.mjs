import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {subtractionScenario} from './fixtures/property-graph-subtraction.mjs';
const fixture = JSON.parse(readFileSync(new URL('./fixtures/property-graph-presence.program.json',import.meta.url)));

test('subtraction authored removal and explicit transformation are not interchangeable', () => {
  const empty = subtractionScenario(fixture,'self-remove');
  assert.deepEqual(JSON.parse(empty.expectedSnapshot).slice(3),[[],[]]);
  const equality = subtractionScenario(fixture,'explicit-equality-keeps-nodes');
  const graph = JSON.parse(equality.expectedSnapshot);
  assert.equal(graph[3].length,3); assert.deepEqual(graph[4],[]);
  assert.equal(equality.expectedRows[0].id.definition,'M');
  assert.equal(Object.hasOwn(equality.expectedRows[0],'p'),false);
  assert.equal(equality.expectedRows[1].p,7); assert.equal(equality.expectedRows[2].p,null);
});
test('subtraction endpoint closure removes edges without resurrecting their deleted node', () => {
  const scenario = subtractionScenario(fixture,'remove-one-node-endpoint-closure');
  const graph = JSON.parse(scenario.expectedSnapshot);
  assert.deepEqual(graph[3].map(record => record.key),[[3],[2,'a']]);
  assert.deepEqual(graph[4],[]);
  assert.deepEqual(scenario.delta.nodes.remove.map(record => record.key),[[3],[2,'a']]);
});
test('subtraction removes only the matching independently keyed parallel edge', () => {
  const scenario = subtractionScenario(fixture,'keep-nodes-remove-one-parallel-edge','edge_rows');
  const graph = JSON.parse(scenario.expectedSnapshot);
  assert.equal(graph[3].length,3);
  assert.deepEqual(graph[4].map(record => record.key),[[11,'a']]);
  assert.deepEqual(scenario.expectedRows.map(row => row.edge_key),[11]);
  assert.deepEqual(scenario.expectedRows[0].src.key,[1,'a']);
  assert.deepEqual(scenario.expectedRows[0].dst.key,[2,'a']);
});
test('subtraction strategy names keep their numeric meaning and one-sided null stays null', () => {
  const sum = subtractionScenario(fixture,'numeric-strategy-is-addition');
  assert.deepEqual(sum.expectedRows.map(row => Object.hasOwn(row,'p') ? row.p : 'absent'),['absent',14,null]);
  assert.equal(JSON.parse(sum.expectedSnapshot)[4].length,2);
  for (const kind of ['shared-payload-conflict','shared-null-numeric-rejected','endpoint-conflict-before-induced-closure']) {
    const rejected = subtractionScenario(fixture,kind);
    assert.equal(typeof rejected.failure,'string');
    assert.equal(Object.hasOwn(rejected,'expectedSnapshot'),false);
    assert.equal(Object.hasOwn(rejected,'expected'),false);
  }
});
test('subtraction empty right input preserves typed keys domain and declaration metadata', () => {
  const scenario = subtractionScenario(fixture,'empty-right');
  const graph = JSON.parse(scenario.expectedSnapshot);
  const right = JSON.parse(scenario.rightSnapshot);
  assert.equal(graph[1],right[1]); assert.deepEqual(graph[2],right[2]);
  assert.deepEqual(right.slice(3),[[],[]]);
  assert.deepEqual(graph[3].map(record => [record.id.definition,record.key]),[['M',[3]],['N',[1,'a']],['N',[2,'a']]]);
  assert.deepEqual(graph[4].map(record => record.key),[[10,'a'],[11,'a']]);
  assert.equal(scenario.document.stages[0].steps[6].subtract_graphs.with,'right');
});

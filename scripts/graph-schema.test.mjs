import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {graphSchemas, checkGraphSchemas} from './graph-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('graph bodies preserve literal options and optional positive component guards', () => {
  const s = graphSchemas();
  assert.equal(s.mean_graphs.additionalProperties, false);
  assert.deepEqual(s.mean_graphs.required, ['with','weights','support','properties']);
  assert.equal(s.mean_graphs.properties.with.uniqueItems, undefined);
  assert.equal(s.mean_graphs.properties.weights.contains.exclusiveMinimum, 0);
  assert.equal(s.shortest_path.additionalProperties, false);
  assert.deepEqual(s.shortest_path.required, ['source','target','direction','max_hops']);
  assert.deepEqual(s.shortest_path.then, {required:['selection']});
  assert.deepEqual(s.shortest_path.else, {not:{required:['selection']}});
  assert.equal(s.shortest_path.properties.max_hops.minimum, 1);
  assert.equal(s.shortest_path.properties.max_paths, undefined);
  assert.equal(s.traverse.additionalProperties, false);
  assert.deepEqual(s.traverse.required, ['start','emit']);
  assert.equal(s.traverse.properties.hops.minItems, 1);
  assert.equal(s.traverse.properties.hops.items.additionalProperties, false);
  assert.equal(s.traverse.oneOf.length, 2);
  assert.equal(s.traverse.properties.max_paths, undefined);
  assert.deepEqual(s.reach.required, ['start','direction','max_depth']);
  assert.equal(s.reach.additionalProperties, false);
  assert.deepEqual(s.reach.properties.max_depth, {type:'integer',minimum:1});
  assert.equal(s.reach.properties.max_paths, undefined);
  assert.deepEqual(s.subgraph.required, ['nodes']);
  assert.equal(s.subgraph.additionalProperties, false);
  assert.equal(s.subgraph.properties.nodes.oneOf.length, 3);
  for (const alternative of s.subgraph.properties.nodes.oneOf) assert.equal(alternative.additionalProperties, false);
  assert.deepEqual(s.subgraph.properties.nodes.oneOf[1].required, ['from','id']);
  for (const name of ['match_nodes','match_edges']) {
    assert.deepEqual(s[name].required, ['fields']);
    assert.equal(s[name].additionalProperties, false);
    assert.equal(s[name].properties.fields.minItems, 1);
    assert.equal(s[name].properties.fields.uniqueItems, true);
  }
  assert.equal(s.match_nodes.oneOf.length, 2);
  assert.equal(s.match_nodes.properties.ids.minItems, 1);
  assert.equal(s.match_nodes.properties.ids.uniqueItems, undefined);
  assert.equal(s.match_edges.properties.types.minItems, undefined);
  assert.equal(s.match_edges.properties.types.uniqueItems, undefined);
  for (const name of ['graphs_equal','graph_diff','graft_graph','subtract_graphs']) {
    assert.deepEqual(s[name].required, ['with']);
    assert.equal(s[name].additionalProperties, false);
    assert.deepEqual(s[name].properties.with, {type:'string',minLength:1});
  }
  assert.deepEqual(s.union_graphs.required, ['with']);
  assert.equal(s.union_graphs.additionalProperties, false);
  assert.deepEqual(s.union_graphs.properties.with, {oneOf:[
    {type:'string',minLength:1},
    {type:'array',minItems:1,items:{type:'string',minLength:1}},
  ]});
  assert.equal(s.graft_graph.properties.merge, undefined);
  for (const name of ['union_graphs','subtract_graphs']) {
    const merge = s[name].properties.merge;
    assert.equal(merge.additionalProperties, false);
    for (const entity of ['node_properties','edge_properties']) {
      assert.equal(merge.properties[entity].minProperties, undefined);
      assert.deepEqual(merge.properties[entity].additionalProperties.enum,
        ['exact_equal','set_union','set_difference','number_sum','number_mean','number_min','number_max']);
    }
  }
  assert.deepEqual(s.normalize_graph, {const:true});
  assert.deepEqual(s.degree.properties.direction.enum, ['in','out','both']);
  assert.deepEqual(s.components.required, ['kind']);
  assert.deepEqual(s.components.properties.kind.enum, ['weak','strong']);
  assert.equal(s.components.properties.max_nodes, undefined);
  assert.equal(s.components.properties.max_output_rows.oneOf[0].minimum, 1);
  assert.equal(s.components.properties.max_output_rows.oneOf[0].maximum, 9007199254740991);
  assert.equal(s.graph_bounds.minProperties, 1);
  assert.equal(s.graph_bounds.additionalProperties, false);
  for (const name of ['max_nodes','max_edges','max_degree']) {
    assert.equal(s.graph_bounds.properties[name].oneOf[0].minimum, 0);
    assert.equal(s.graph_bounds.properties[name].oneOf[0].maximum, 9007199254740991);
  }
});

test('embedded graph schemas and pins reject drift', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkGraphSchemas(registry);
  for (const index of [0,1]) for (const name of Object.keys(graphSchemas())) {
    const copy = structuredClone(registry);
    parameterPrograms(copy)[index].properties.steps.items.properties[name] = {};
    assert.throws(() => checkGraphSchemas(copy));
  }
});

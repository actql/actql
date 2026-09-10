import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {graphSchemas, checkGraphSchemas} from './graph-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('graph bodies preserve literal options and optional positive component guards', () => {
  const s = graphSchemas();
  for (const name of ['graphs_equal','graph_diff']) {
    assert.deepEqual(s[name].required, ['with']);
    assert.equal(s[name].additionalProperties, false);
    assert.deepEqual(s[name].properties.with, {type:'string',minLength:1});
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

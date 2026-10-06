import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {graphSchemas, baseGraphOperationSchemas, checkGraphSchemas} from './graph-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('graph bodies preserve literal options and optional positive component guards', () => {
  const s = baseGraphOperationSchemas();
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

test('current graph schemas require scoped matches and explicit path modes', () => {
  const base = baseGraphOperationSchemas(), current = graphSchemas();
  for (const name of Object.keys(base)) {
    if (['node_rows','edge_rows'].includes(name)) {
      assert.equal(current[name].oneOf.length, 3);
      assert.deepEqual(current[name].oneOf[0], base[name]);
      assert.deepEqual(current[name].oneOf[1], {type:'object',additionalProperties:false,
        required:['definition'],properties:{definition:{type:'string',minLength:1}}});
      assert.deepEqual(current[name].oneOf[2], {type:'object',additionalProperties:false,
        required:['label'],properties:{label:{type:'string',minLength:1}}});
    } else if (['match_nodes','match_edges','traverse'].includes(name)) {
      const keyed = current[name];
      assert.equal(keyed.additionalProperties, false);
      assert.ok(keyed.required.includes(name === 'traverse' ? 'path_mode' : 'definition'));
      assert.equal(base[name].properties.definition, undefined);
      assert.equal(base[name].properties.path_mode, undefined);
    } else assert.deepEqual(current[name], base[name]);
  }
  const c = current.graph;
  assert.equal(c.additionalProperties, false);
  assert.deepEqual(c.required, ['version','nodes','edges']);
  assert.equal(c.properties.version.const, 'actql-graph-constructor/0.1');
  assert.equal(c.properties.domain, undefined);
  for (const kind of ['nodes','edges']) {
    const element = c.properties[kind].items;
    assert.equal(element.additionalProperties, false);
    assert.equal(element.properties.key.minItems, 1);
    assert.equal(element.properties.key.uniqueItems, true);
    assert.equal(element.properties.labels.items.properties.properties.oneOf.length, 4);
    for (const selector of element.properties.labels.items.properties.properties.oneOf) {
      assert.equal(selector.additionalProperties, false);
    }
  }
  assert.deepEqual(c.properties.edges.items.required, ['name','from','key','source','target']);
  for (const role of ['source','target']) {
    assert.equal(c.properties.edges.items.properties[role].additionalProperties, false);
    assert.deepEqual(c.properties.edges.items.properties[role].required, ['definition','key']);
  }
  const traversal = current.traverse;
  assert.deepEqual(traversal.properties.path_mode.enum, ['walk','trail','acyclic']);
  assert.deepEqual(traversal.properties.emit, {enum:['nodes','paths']});
  for (const filter of ['edge_where','node_where']) {
    assert.deepEqual(traversal.properties[filter],
      base.traverse.properties.hops.items.properties[filter]);
    assert.ok(traversal.oneOf[0].not.anyOf.some(term=>term.required[0]===filter));
  }
  assert.deepEqual(traversal.oneOf[1], base.traverse.oneOf[1]);
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

// Independent JSON Schema subset for the closed operation fixtures below.
// Unknown keywords fail rather than silently weakening the registered schema.
function accepts(schema, value) {
  const known = new Set(['type', 'const', 'enum', 'oneOf', 'anyOf', 'not',
    'properties', 'required', 'additionalProperties', 'items', 'uniqueItems',
    'minItems', 'minimum', 'maximum', 'minLength', 'minProperties', 'maxProperties']);
  for (const key of Object.keys(schema)) assert.ok(known.has(key), key);
  if ('const' in schema && !Object.is(value, schema.const)) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.oneOf && schema.oneOf.filter(rule => accepts(rule, value)).length !== 1) return false;
  if (schema.anyOf && !schema.anyOf.some(rule => accepts(rule, value))) return false;
  if (schema.not && accepts(schema.not, value)) return false;
  const object = value !== null && typeof value === 'object' && !Array.isArray(value);
  if (schema.type && !({object, array: Array.isArray(value),
    integer: Number.isSafeInteger(value), string: typeof value === 'string'})[schema.type]) return false;
  if (typeof value === 'string' && [...value].length < (schema.minLength ?? 0)) return false;
  if (typeof value === 'number' &&
      (value < (schema.minimum ?? -Infinity) || value > (schema.maximum ?? Infinity))) return false;
  if (Array.isArray(value)) {
    if (value.length < (schema.minItems ?? 0)) return false;
    if (schema.uniqueItems && new Set(value.map(JSON.stringify)).size !== value.length) return false;
    if (schema.items && !value.every(item => accepts(schema.items, item))) return false;
  }
  if (object) {
    if (Object.keys(value).length < (schema.minProperties ?? 0) ||
        Object.keys(value).length > (schema.maxProperties ?? Infinity)) return false;
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    for (const [key, item] of Object.entries(value)) {
      const rule = schema.properties?.[key];
      if (rule && !accepts(rule, item)) return false;
      if (!rule && schema.additionalProperties === false) return false;
      if (!rule && typeof schema.additionalProperties === 'object' &&
          !accepts(schema.additionalProperties, item)) return false;
    }
  }
  return true;
}

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
const programNames = ['executable_plan', 'plan_document'];
for (const [index, program] of parameterPrograms(registry).entries()) {
  const schemas = program.properties.steps.items.properties;
  test(`${programNames[index]} rejects definition-free MATCH and preserves current selectors`, () => {
    const id = {definition: 'N', domain: 'sha256:' + '0'.repeat(64),
      key_types: [{kind: 'number'}], key: [1]};
    const cases = [
      ['match_nodes', {fields: ['name'], where: 'true'}],
      ['match_nodes', {fields: ['node_id'], ids: [id], bindings: {identity: 'node_id'}}],
      ['match_edges', {fields: ['name']}],
      ['match_edges', {fields: ['edge_id', 'source_id', 'target_id'], types: [],
        where: {eq: [{field: 'active'}, {literal: true}]},
        bindings: {identity: 'edge_id', source: 'source_id', target: 'target_id'}}],
    ];
    for (const [name, body] of cases) {
      assert.equal(accepts(schemas[name], body), false, `${name}: missing definition`);
      const current = {...body, definition: name === 'match_nodes' ? 'N' : 'E'};
      assert.equal(accepts(schemas[name], current), true, name);
      assert.equal(accepts(schemas[name], {...current, label: 'Selected'}), true, name);
      for (const invalid of [{...current, definition: ''}, {...current, definition: 1},
        {...current, fields: []}, {...current, fields: ['name', 'name']},
        {...current, extra: true}, {...current, bindings: {unknown: 'field'}}]) {
        assert.equal(accepts(schemas[name], invalid), false, name);
      }
    }
    assert.equal(accepts(schemas.match_nodes, {definition: 'N', fields: ['name']}), false);
    assert.equal(accepts(schemas.match_nodes,
      {definition: 'N', fields: ['name'], ids: [id], where: 'true'}), false);
  });

  test(`${programNames[index]} requires path_mode for every traversal mode and emission`, () => {
    for (const emit of ['nodes', 'paths']) for (const mode of [
      {direction: 'out', min_hops: 0, max_hops: 3},
      {hops: [{direction: 'out'}]},
    ]) {
      const body = {start: {from: 'starts', id: 'node_id'}, emit, ...mode};
      assert.equal(accepts(schemas.traverse, body), false, 'missing path_mode');
      for (const path_mode of ['walk', 'trail', 'acyclic']) {
        const current = {...body, path_mode};
        assert.equal(accepts(schemas.traverse, current), true);
        assert.equal(accepts(schemas.traverse, {...current, max_output_rows: 1}), true);
        assert.equal(accepts(schemas.traverse, {...current, path_mode: 'simple'}), false);
        assert.equal(accepts(schemas.traverse, {...current, extra: true}), false);
        assert.equal(accepts(schemas.traverse, {...current, max_output_rows: 0}), false);
        for (const filter of ['edge_where', 'node_where']) {
          assert.equal(accepts(schemas.traverse, {...current, [filter]: 'true'}), !('hops' in mode));
          if ('hops' in mode) assert.equal(accepts(schemas.traverse,
            {...current, hops: [{direction: 'out', [filter]: 'true'}]}), true);
        }
      }
    }
  });
}

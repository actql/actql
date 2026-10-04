import assert from 'node:assert/strict';
import test from 'node:test';
import {graphCompositionProgram, graphCompositionTemplates,
  graphCompositionExpectations, graphDefinitionCid,
  graphCompositionRefusalProgram, graphCompositionRefusalTemplates} from
  './fixtures/graph-infer-effect-input.mjs';

for (const family of ['node', 'edge']) {
  test(`${family} composition is a complete authored Program with only a MappingRef binding`, () => {
    const original = structuredClone(graphCompositionTemplates[family]);
    const bound = graphCompositionProgram('mapping:fixture', family);
    assert.equal(bound.stages[2].effects.save.update.mapping, 'mapping:fixture');
    bound.stages[2].effects.save.update.mapping = '__PUBLICATION_MAPPING_REF__';
    assert.deepEqual(bound, original);
    assert.deepEqual(graphCompositionTemplates[family], original);
    assert.throws(() => graphCompositionProgram('', family));
  });

  test(`${family} expectations preserve typed Graph keys, nullable guaranteed property and replay counts`, () => {
    const expected = graphCompositionExpectations(family);
    assert.equal(graphDefinitionCid,
      'sha256:e10869cfed10b18fbe00f13ddd456f4a4b5241199d16a3f31a08b4a53c026437');
    assert.deepEqual(expected.classified.map(row => [row.id, row.note, row.risk]),
      [[1, 7, 'low'], [2, null, 'high']]);
    for (const row of expected.classified) {
      assert.deepEqual(row.graph_identity, {definition: family === 'node' ? 'N' : 'E',
        domain: graphDefinitionCid, key: ['a', row.id],
        key_types: [{kind: 'string'}, {kind: 'number'}]});
    }
    assert.deepEqual(expected.sourceReadSessions, [0, 0, 0, 0]);
    assert.deepEqual(expected.modelInputs, [100, 200]);
    assert.deepEqual(expected.effectWriteCounts, [0, 0, 1, 1]);
    assert.deepEqual(expected.restartBoundaries, ['capture-waiting', 'approval-committed']);
  });
}

for (const variant of ['duplicate-key', 'null-property']) {
  test(`${variant} refusal submits an authored complete Graph Program without repair`, () => {
    const original = structuredClone(graphCompositionRefusalTemplates[variant]);
    const bound = graphCompositionRefusalProgram('mapping:fixture', variant);
    assert.equal(bound.stages[2].effects.save.update.mapping, 'mapping:fixture');
    bound.stages[2].effects.save.update.mapping = '__PUBLICATION_MAPPING_REF__';
    assert.deepEqual(bound, original);
    assert.deepEqual(graphCompositionRefusalTemplates[variant], original);
    assert.throws(() => graphCompositionRefusalProgram('', variant));
    assert.deepEqual(bound.stages[0].inputs, {});
    assert.deepEqual(bound.stages[1].steps.find(step => step.infer).infer,
      graphCompositionTemplates.node.stages[1].steps.find(step => step.infer).infer);
  });
}

test('duplicate Model keys remain distinct Graph identities until the explicit assertion', () => {
  const program = graphCompositionRefusalTemplates['duplicate-key'];
  const [persons, edges, constructor, rows, projection] = program.stages[0].steps;
  assert.deepEqual(persons.values.rows, [
    {person_key:1,tenant_key:'a',note:7}, {person_key:1,tenant_key:'b',note:9}]);
  assert.deepEqual(edges.values.rows, []);
  assert.deepEqual(constructor.property_graph.nodes[0].key, ['tenant_key','person_key']);
  assert.equal(rows.node_rows, true);
  assert.deepEqual(projection.select.slice(0,2), [{graph_identity:'id'}, {id:'person_key'}]);
  assert.deepEqual(program.stages[1].steps[0].assert_rows, {unique_by:['id']});
});

test('NULL refusal asserts a guaranteed nullable property without changing Graph or Model keys', () => {
  const program = graphCompositionRefusalTemplates['null-property'];
  assert.deepEqual(program.stages[0], graphCompositionTemplates.node.stages[0]);
  assert.deepEqual(program.stages[1].steps[0], {assert_rows:{unique_by:['note']}});
  assert.deepEqual(program.stages[1].steps.slice(1), graphCompositionTemplates.node.stages[1].steps);
  assert.deepEqual(program.stages[0].steps[0].values.schema.note, {type:'number',nullable:true});
  assert.equal(program.stages[0].steps[0].values.rows[0].note, null);
});

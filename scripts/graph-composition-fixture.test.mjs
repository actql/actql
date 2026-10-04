import assert from 'node:assert/strict';
import test from 'node:test';
import {graphCompositionProgram, graphCompositionTemplates,
  graphCompositionExpectations, graphDefinitionCid} from
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

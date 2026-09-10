import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {vectorSchemas, checkVectorSchemas} from './vector-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('vector source bodies are closed and distinguish literal and whole-parameter queries', () => {
  const s = vectorSchemas();
  assert.equal(s.nearest.additionalProperties,false);
  assert.deepEqual(s.nearest.required,['queries','metric','k']);
  assert.equal(s.nearest.properties.k.maximum,9007199254740991);
  assert.equal(s.nearest.properties.exact,undefined);
  assert.equal(s.nearest.properties.corpus,undefined);
  assert.deepEqual(s.normalize_vectors, {const:true});
  assert.equal(s.score_vectors.additionalProperties, false);
  assert.deepEqual(s.score_vectors.required, ['query','metric']);
  assert.deepEqual(s.score_vectors.properties.metric.enum, ['cosine','dot','l2']);
  assert.deepEqual(s.score_vectors.properties.query.oneOf[0], {type:'array',minItems:1,items:{type:'number'}});
  assert.deepEqual(s.score_vectors.properties.query.oneOf[1].required, ['$param']);
});

test('embedded vector schemas and pins reject drift', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkVectorSchemas(registry);
  for (const index of [0,1]) for (const name of Object.keys(vectorSchemas())) {
    const copy = structuredClone(registry);
    parameterPrograms(copy)[index].properties.steps.items.properties[name] = {};
    assert.throws(() => checkVectorSchemas(copy));
  }
});

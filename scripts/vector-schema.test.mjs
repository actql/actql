import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {vectorSchemas, checkVectorSchemas} from './vector-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('vector source bodies are closed and distinguish literal and whole-parameter queries', () => {
  const s = vectorSchemas();
  assert.equal(s.text_rank.additionalProperties,false);
  assert.deepEqual(s.text_rank.required,['queries','query_id','query_text','candidate_id','candidate_text','tokenizer','scoring','k']);
  assert.equal(s.text_rank.properties.scoring.properties.bm25.properties.k1.exclusiveMinimum,0);
  assert.equal(s.text_rank.properties.scoring.properties.bm25.properties.b.maximum,1);
  assert.equal(s.text_rank.properties.k.maximum,9007199254740991);
  const [maximum, weighted, rrf] = s.merge_rankings.oneOf;
  assert.equal(maximum.properties.score_policy.const,'max');
  assert.equal(weighted.properties.score_policy.properties.weighted_sum.additionalProperties,false);
  assert.equal(maximum.properties.rank,undefined);
  assert.equal(maximum.properties.by.minItems,undefined);
  assert.equal(maximum.properties.tie_break.minItems,undefined);
  assert.equal(rrf.properties.score,undefined);
  assert.equal(rrf.properties.score_contract,undefined);
  assert.equal(rrf.properties.tie_break,undefined);
  assert.equal(rrf.properties.with.oneOf[1].uniqueItems,undefined);
  assert.equal(rrf.properties.score_policy.properties.rrf.properties.weights.contains.exclusiveMinimum,0);
  assert.equal(s.pool_vectors.additionalProperties,false);
  assert.deepEqual(s.pool_vectors.required,['by','method']);
  assert.equal(s.pool_vectors.properties.by.minItems,1);
  assert.equal(s.pool_vectors.properties.by.uniqueItems,true);
  assert.deepEqual(s.pool_vectors.properties.method.enum,['mean','sum','max']);
  assert.deepEqual(s.pool_vectors.allOf,[{if:{required:['output_id']},then:{properties:{by:{maxItems:1}}}}]);
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

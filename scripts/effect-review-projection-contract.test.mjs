import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {correctedEffectReviewContracts} from './run-publication-contracts.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText,verifyIdentity} from './check-canonical-json.mjs';
import {vectors,expectedCids,legacy,legacyBody,legacyCid,mutations} from
  './fixtures/effect-review-projection-vectors.mjs';

const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
test('Effect review reuses the exact closed strength guard change and ResourceRef owners',()=>{
  const member=registry.artifact_schemas.effect_preview.properties.effects.items;
  const review=registry.artifact_schemas.review_projection;
  const row=review.properties.displayed_rows.items;
  assert.equal(review.required.length,14);assert.equal(review.additionalProperties,false);
  assert.equal(row.additionalProperties,false);
  for(const name of ['preview_strength','target_guard','intended_changes']){
    assert(!row.required.includes(name),'legacy absent bytes remain structurally admitted');
    assert.deepEqual(row.properties[name],name==='preview_strength'
      ?member.properties[name]:member.properties.changes.items.properties[name]);
  }
  assert.deepEqual(row.required,['effect_id','row_preview_cid','target_row_identity','before','after']);
  assert.deepEqual(row.properties.before,{});assert.deepEqual(row.properties.after,{});
  for(const scope of [member.properties.target,
    review.properties.displayed_scope.properties.effects.items.properties.target]){
    assert.equal(scope.oneOf.length,3,'only String, field selector and the closed ResourceRef');
    assert.deepEqual(scope.oneOf.at(-1),registry.schemas.resource_ref);
    assert.equal(scope.oneOf[1].properties.field.type,'string');
  }
});

test('scoped review generation preserves every unrelated adopted schema and old alternatives',()=>{
  const next=correctedEffectReviewContracts(registry);
  assert.deepEqual(next,registry,'read-only review freshness');
  const changed=structuredClone(registry);
  delete changed.artifact_schemas.review_projection.properties.displayed_rows.items.properties.target_guard;
  const refreshed=correctedEffectReviewContracts(changed);
  for(const [name,schema]of Object.entries(registry.artifact_schemas)){
    if(!['effect_preview','review_projection'].includes(name))assert.deepEqual(refreshed.artifact_schemas[name],schema,name);
  }
  assert.deepEqual(refreshed,registry);
  for(const name of ['effect_preview','review_projection'])assert.equal(
    registry.artifact_schema_cids[name],machineCid(registry.artifact_schemas[name]));
});

test('independent Effect review preimages and historical absence have fixed identities',()=>{
  assert.deepEqual(vectors.map(value=>value.cid),expectedCids);
  for(const v of vectors){
    verifyIdentity(v.body,v.cid);assert.equal(canonicalText(v.review),v.reviewWire);
    assert.equal(v.review.displayed_rows[0].preview_strength,v.preview.effects[0].preview_strength);
    for(const name of ['before','after','target_guard','intended_changes'])assert.deepEqual(
      v.review.displayed_rows[0][name],v.preview.effects[0].changes[0][name]);
  }
  verifyIdentity(legacyBody,legacyCid);assert.equal(legacy.review_projection_cid,legacyCid);
  assert.notEqual(legacyCid,expectedCids[0]);
  assert(mutations.length>=35,'all fourteen top fields and original row/scope/policy bindings');
});

test('no-control schema pattern alias retains exact existing finite matcher meaning',()=>{
  const module=readFileSync('scripts/run-publication-protocol.mjs','utf8');
  assert(module.includes("case '^[^\\\\u0000-\\\\u001f\\\\u007f]+(?![\\\\s\\\\S])': return 9;"));
  const exact=/^[^\u0000-\u001f\u007f]+(?![\s\S])/u;
  assert(exact.test('original-e\u0301'));for(const value of ['', 'x\n','x\r','x\u007f'])assert(!exact.test(value));
});

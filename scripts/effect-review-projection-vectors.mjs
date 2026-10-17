import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {vectors,legacy,legacyBody,mutations,scope,policy,claims,originalRun,authoring,expectedCids,legacyCid} from
  './fixtures/effect-review-projection-vectors.mjs';

export function generateEffectReviewVectors(){
  assert.deepEqual(vectors.map(value=>value.cid),expectedCids);
  assert.equal(legacy.review_projection_cid,legacyCid);
  const q=JSON.stringify;
  const original=v=>`  let original = admit_effect_preview_identity(${q(v.previewWire)}, ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, 20000, 2000, 32).unwrap()\n`;
  const args=v=>`original, ${q(v.previewWire)}, ${q(scope)}, ${q(claims)}, ${q(policy)}, 20000, 2000, 32`;
  const array=value=>'['+value.map(q).join(', ')+']';
  const actualArgs=v=>args(v).replace(q(claims),array(claims));
  let source='// Generated from independently authored Effect review preimages.\n';
  for(const v of vectors){
    source+=`\n///|\ntest "original Effect review: ${v.name}" {\n`+original(v)+
      `  let review = project_effect_review_projection(${actualArgs(v)}).unwrap()\n`+
      `  assert_eq(run_evidence_value_json(review), ${q(v.reviewWire)})\n`+
      `  assert_eq(run_evidence_value_identity(review), ${q(v.cid)})\n`+
      `  let admitted = admit_effect_review_projection(original, ${q(v.previewWire)}, ${q(v.reviewWire)}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 20000, 2000, 32).unwrap()\n`+
      `  assert_eq(run_evidence_value_identity(admitted), ${q(v.cid)})\n}\n`;
  }
  const v=vectors[0];
  source+=`\n///|\ntest "original Effect review refuses rehashed omission and foreign evidence" {\n`+original(v)+
    mutations.map(m=>`  // ${m.name}\n  assert_true(admit_effect_review_projection(original, ${q(v.previewWire)}, ${q(m.wire)}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 20000, 2000, 32) is Err(_))\n`).join('')+'}\n';
  source+=`\n///|\ntest "legacy absent review bytes remain structural only not upgraded evidence" {\n`+original(v)+
    `  let legacy = seal_run_evidence_value("review_projection", ${q(canonicalText(legacyBody))}, 20000, 2000, 32).unwrap()\n`+
    `  assert_eq(run_evidence_value_json(legacy), ${q(canonicalText(legacy))})\n`+
    `  assert_eq(run_evidence_value_identity(legacy), ${q(legacy.review_projection_cid)})\n`+
    `  assert_true(admit_effect_review_projection(original, ${q(v.previewWire)}, ${q(canonicalText(legacy))}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 20000, 2000, 32) is Err(ForeignPreview))\n}\n`;
  source+=`\n///|\ntest "original Effect review preserves scope policy and bounded work refusals" {\n`+original(v)+
    `  assert_true(project_effect_review_projection(original, ${q(v.previewWire)}, ${q(scope)}, [], ${q(policy)}, 20000, 2000, 32) is Err(InvalidPolicy))\n`+
    `  assert_true(project_effect_review_projection(original, ${q(v.previewWire)}, ${q(scope)}, ["effect_scope_approved", "effect_scope_approved"], ${q(policy)}, 20000, 2000, 32) is Err(InvalidPolicy))\n`+
    `  assert_true(project_effect_review_projection(original, ${q(v.previewWire)}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 0, 2000, 32) is Err(InvalidLimits))\n`+
    `  assert_true(project_effect_review_projection(original, ${q(v.previewWire)}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 20000, 2, 32) is Err(_))\n`+
    `  assert_true(project_effect_review_projection(original, ${q(v.previewWire.replace(originalRun,'sha256:'+'0'.repeat(64)))}, ${q(scope)}, ${array(claims)}, ${q(policy)}, 20000, 2000, 32) is Err(Preview(RunBindingMismatch)))\n}\n`;
  return execFileSync(process.env.MOON_HOME+'/bin/moonfmt',['-'],{input:source,encoding:'utf8'});
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const path='src/run_publication/effect_review_projection.generated_wbtest.mbt';
  const source=generateEffectReviewVectors();
  if(process.argv.includes('--write'))writeFileSync(path,source);
  else assert.equal(readFileSync(path,'utf8'),source,'Stale independent Effect review vectors');
}

import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText,verifyIdentity,generateTests} from './check-canonical-json.mjs';
const path='portability/corpus/check-environment.json';
const corpus=JSON.parse(readFileSync(path,'utf8'));
assert.equal(corpus.version,'actql-check-environment-vectors/0.1');
const fixtures=[];
for(const c of corpus.cases){
  const preimage={...corpus.base,...c.replace};
  assert.ok(!Object.hasOwn(preimage,'evidence_bundle_cid'));
  if(process.argv.includes('--write-identities')){
    c.expected_preimage=canonicalText(preimage);
    c.expected_cid='sha256:'+createHash('sha256').update(c.expected_preimage).digest('hex');
    c.expected_wire=canonicalText({...preimage,evidence_bundle_cid:c.expected_cid});
  }
  verifyIdentity(preimage,c.expected_cid,c.expected_preimage);
  assert.equal(canonicalText({...preimage,evidence_bundle_cid:c.expected_cid}),c.expected_wire);
  fixtures.push({id:'Check Environment preimage '+c.id,value:preimage,cid:c.expected_cid,text:c.expected_preimage});
}
assert.equal(new Set(corpus.cases.map(c=>c.expected_cid)).size,corpus.cases.length);
if(process.argv.includes('--write-identities'))writeFileSync(path,JSON.stringify(corpus,null,2)+'\n');
const output='src/canonical_json/check_environment.generated_test.mbt';
const text=generateTests(fixtures).replace('scripts/check-canonical-json.mjs','scripts/check-environment-vectors.mjs');
if(process.argv.includes('--write'))writeFileSync(output,text);else assert.equal(readFileSync(output,'utf8'),text);
console.log('4 independent Check Environment preimages verified; not environment admission.');

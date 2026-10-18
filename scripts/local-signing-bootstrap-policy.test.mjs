import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';
import {localProductDefaultAssets, nativeLocalDefaultSigningPolicy} from './native-cli-default-assets.mjs';

const read = path => JSON.parse(readFileSync(new URL('../' + path, import.meta.url)));
const vectors = read('spec/contracts/fixtures/local-signing-bootstrap-policy-vectors.json');
const schema = read('spec/contracts/actql-local-signing-bootstrap-policy.schema.json');
const shape = project(schema);
const valid = new Function(structuralValidatorSource({extended:true}) + '\nreturn valid;')();
const digest = text => 'sha256:' + createHash('sha256').update(text).digest('hex');

test('default signing pinned original has independent exact policy bytes and no issuer permission', () => {
  const original = read('spec/contracts/local-signing-bootstrap-policy.json');
  assert.deepEqual(nativeLocalDefaultSigningPolicy(), original);
  assert.equal(JSON.stringify(original), vectors.policy_wire);
  assert.equal(digest(vectors.policy_wire), vectors.policy_cid);
  assert.equal(valid(original, shape), true);
  assert.equal(vectors.issuer_identity, 'local-signing/' + vectors.initialization_intent_cid);
  assert.equal(vectors.initialization_intent_cid,
    'sha256:d7b077fa3a803302e5a5374ca5dc71ea879876760af126b7e1c0eaf16d9cf46b');
});

test('default signing closed policy rejects changed allowance and fabricated authority', () => {
  const original = JSON.parse(vectors.policy_wire);
  for (const changed of [{...original,max_uses:2}, {...original,max_issue_interval_ms:300001},
    {...original,issuer_authority:'manufactured'}, {...original,allow:true}, null, {}]) {
    assert.equal(valid(changed,shape),false);
  }
  for (const name of Object.keys(original)) {
    const missing = {...original}; delete missing[name];
    assert.equal(valid(missing,shape),false,name);
  }
});

test('independent first-issue vectors cover checked Int64 cap and earlier original validity', () => {
  const max = 9223372036854775807n;
  const expected = (sample,bound) => {
    if (sample < 0n || sample > max - 300000n || bound !== null && bound <= sample) return null;
    return bound === null || bound > sample + 300000n ? sample + 300000n : bound;
  };
  for (const v of vectors.issues) assert.equal(expected(BigInt(v.sampled_at),
    v.original_valid_until === null ? null : BigInt(v.original_valid_until)),BigInt(v.expires_at));
  for (const v of vectors.refused_issues) assert.equal(expected(BigInt(v.sampled_at),
    v.original_valid_until === null ? null : BigInt(v.original_valid_until)),null);
});

test('existing default-asset generator emits policy without changing legacy product asset shape', () => {
  assert.equal(readFileSync(new URL('../src/run_publication_host/client_local_product_assets.generated.mbt',import.meta.url),'utf8'),
    localProductDefaultAssets());
  assert.equal(schema.properties.version.const,'actql-local-signing-bootstrap-policy/0.1');
});

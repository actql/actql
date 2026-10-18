import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {vectorSchemas} from './vector-schema.mjs';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';
const read = path => JSON.parse(readFileSync(path,'utf8'));
const vector = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/composite-vector-bridge/identities.json.gz')));
const at = (root,pointer) => pointer.split('/').slice(1).reduce((value,key)=>value[key],root);

test('complete composite Bridge Program schemas change only the original id role alternative', () => {
  const registry=read('spec/contracts/actql-protocol-schemas.json');
  assert.deepEqual(vectorSchemas().to_vectors,vector.grammar);
  assert.equal(vector.programs.length,2);
  for(const value of vector.programs) {
    verifyIdentity(value.before.body,value.before.cid,value.before.canonicalPreimage);
    verifyIdentity(value.after.body,value.after.cid,value.after.canonicalPreimage);
    assert.deepEqual(at(registry,value.pointer),value.after.body);
    const restored=structuredClone(value.after.body);
    restored.properties.steps.items.properties.to_vectors=value.before.body.properties.steps.items.properties.to_vectors;
    assert.deepEqual(restored,value.before.body);
  }
});

test('composite Bridge manifest retains every prior role except exact source grammar and query rules', () => {
  const before=vector.manifest.before,after=vector.manifest.after;
  const {grammar_manifest_cid:oldCid,...oldBody}=before;
  const {grammar_manifest_cid:newCid,...newBody}=after;
  verifyIdentity(oldBody,oldCid);
  verifyIdentity(newBody,newCid,vector.manifest.afterCanonicalPreimage);
  assert.deepEqual(after,read('spec/manifests/actql-grammar-0.1.json'));
  assert.deepEqual({...after,source_grammar_cid:before.source_grammar_cid,
    query_text_rules_sha256:before.query_text_rules_sha256,grammar_manifest_cid:oldCid},before);
});

test('actual generated structural validator retains ordered composite roles without claiming Carrier admission', () => {
  const validate=new Function(structuralValidatorSource({extended:true})+'return valid;')();
  const schema=project(vector.grammar);
  for(const id of ['tenant',['tenant'],['product_id','tenant'],['tenant','product_id']]) {
    assert(validate({id,vector:'embedding'},schema));
  }
  for(const id of [[],['tenant','tenant'],['tenant',null],[''],1,null,[['tenant']]]) {
    assert(!validate({id,vector:'embedding'},schema));
  }
  assert(!validate({id:['tenant'],vector:'embedding',extra:true},schema));
  for(const value of vector.bridgeNodes)verifyIdentity(value.body,value.cid,value.canonicalPreimage);
  assert.notEqual(vector.bridgeNodes[0].cid,vector.bridgeNodes[1].cid);
});

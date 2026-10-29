import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText,vectors,expectedPins,installationCid,targetCid,targetBody,
  configurationWire,physicalHash,hash,mutations} from './fixtures/effect-local-operation-vectors.mjs';
import {httpEffectRowOutcomeReceiptSchema,effectLocalOperationReceiptSchema,
  effectRowOutcomeReceiptSchema} from './run-publication-contracts.mjs';

test('independent local operation preimages retain semantic and physical identities',()=>{
  assert.deepEqual({installationCid,targetCid,receipts:vectors.map(v=>v.receipt.receipt_cid),
    rows:vectors.map(v=>v.rowReceipt.receipt_cid)},expectedPins);
  assert.equal(installationCid,`sha256:${physicalHash(configurationWire)}`);
  assert.equal(targetCid,hash(targetBody));
  for(const v of vectors){
    assert.equal(hash(v.body),v.receipt.receipt_cid);
    assert.equal(hash(v.rowBody),v.rowReceipt.receipt_cid);
    assert.equal(v.rowBody.response_physical_sha256,physicalHash(v.wire));
    assert.equal(v.rowBody.response_byte_count,Buffer.byteLength(v.wire));
    assert.notEqual(`sha256:${physicalHash(v.wire)}`,v.receipt.receipt_cid);
    assert.equal(canonicalText(JSON.parse(v.wire)),v.wire);
    assert.equal(v.body.typed_outcome_cid,hash(v.outcome));
  }
  assert.ok(Object.hasOwn(vectors[0].outcome.result,'e\u0301'));
  assert.ok(Object.hasOwn(vectors[0].outcome.result,'é'));
});

test('closed local schema is disjoint from the unchanged HTTP arm',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
  const union=registry.artifact_schemas.effect_row_outcome_receipt;
  const local=registry.artifact_schemas.effect_local_operation_receipt;
  assert.equal(machineCid(union.oneOf[0]),
    'sha256:e239b0d9b9229efdc67095bbea81ff8bccc0873a6bc277de7857c7955d8719fd');
  assert.deepEqual(union.oneOf[0],httpEffectRowOutcomeReceiptSchema(registry.schemas.effect_outcome));
  assert.deepEqual(union,effectRowOutcomeReceiptSchema(registry.schemas.effect_outcome));
  assert.deepEqual(local,effectLocalOperationReceiptSchema(registry.schemas.effect_outcome));
  assert.deepEqual(Object.keys(vectors[0].receipt).sort(),[...local.required].sort());
  assert.equal(local.additionalProperties,false);
  assert.deepEqual(local.properties.commit_status.enum,['committed','conflict']);
  assert.deepEqual(local.properties.typed_outcome.oneOf.map(v=>v.properties.state.const),['applied','failed']);
  assert.equal(union.oneOf[1].properties.response_kind.const,'local_operation');
  for(const field of ['credential_use_cid','http_status_code']){
    assert.ok(union.oneOf[0].required.includes(field));
    assert.ok(!Object.hasOwn(union.oneOf[1].properties,field));
  }
  for(const field of ['response_kind','local_operation_receipt_cid']){
    assert.ok(union.oneOf[1].required.includes(field));
    assert.ok(!Object.hasOwn(union.oneOf[0].properties,field));
  }
});

test('independent rehashed refusals change facts rather than corrupting self identity',()=>{
  assert.equal(mutations.length,19);
  for(const m of mutations){
    const {receipt_cid,...body}=JSON.parse(m.wire);
    assert.equal(receipt_cid,hash(body),m.name);
    assert.notEqual(m.wire,vectors[0].wire,m.name);
  }
});

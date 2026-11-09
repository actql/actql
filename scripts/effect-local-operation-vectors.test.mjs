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
  const localUnion=registry.artifact_schemas.effect_local_operation_receipt;
  const local=localUnion.oneOf[0];
  assert.equal(machineCid(union.oneOf[0]),
    'sha256:e239b0d9b9229efdc67095bbea81ff8bccc0873a6bc277de7857c7955d8719fd');
  assert.deepEqual(union.oneOf[0],httpEffectRowOutcomeReceiptSchema(registry.schemas.effect_outcome));
  assert.deepEqual(union,effectRowOutcomeReceiptSchema(registry.schemas.effect_outcome));
  assert.deepEqual(localUnion,effectLocalOperationReceiptSchema(registry.schemas.effect_outcome));
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


test('closed file branch preserves original SQLite and HTTP schema preimages', async()=>{
  const f=await import('./fixtures/effect-file-operation-vectors.mjs');
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
  const local=registry.artifact_schemas.effect_local_operation_receipt;
  assert.equal(machineCid(local.oneOf[0]),'sha256:b02752bd4be29b22e064abf4ffb907332f5be4e58f8e0645d2bc12ef256c6bc5');
  assert.equal(local.oneOf[1].properties.backend_kind.const,'json_file');
  assert.equal(local.oneOf[1].properties.replacement_status.const,'acknowledged');
  assert.equal(local.oneOf[1].additionalProperties,false);
  assert.deepEqual(Object.keys(f.receipt).sort(),local.oneOf[1].required.toSorted());
  assert.deepEqual({targetCid:f.targetCid,receiptCid:f.receipt.receipt_cid,rowCid:f.rowReceipt.receipt_cid},f.expectedPins);
  assert.equal(f.body.replacement_physical_sha256,f.physicalHash(f.replacement));
  assert.equal(f.body.replacement_byte_count,Buffer.byteLength(f.replacement));
  for(const field of ['commit_status','credential_use_cid','authorization_use_cid','approval_use_cid','http_status_code']){
    assert.ok(!Object.hasOwn(local.oneOf[1].properties,field));
  }
  for(const m of f.mutations){const {receipt_cid,...body}=JSON.parse(m.wire);assert.equal(receipt_cid,f.hash(body),m.name);}
});


test('file generation decimal syntax matches the exact UInt64 domain', async()=>{
  const {fileGenerationWordPattern} = await import('./run-publication-contracts.mjs');
  const pattern = new RegExp(fileGenerationWordPattern);
  for (const value of ['0','1','18446744073709551615']) assert.equal(pattern.test(value),true,value);
  for (const value of ['','01','-1','1\n','1\r','18446744073709551616','99999999999999999999']) {
    assert.equal(pattern.test(value),false,JSON.stringify(value));
  }
});

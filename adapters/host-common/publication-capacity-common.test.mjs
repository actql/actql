import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync}from'node:fs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
const control=runtimeCore(moon).publicationControl;
const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:100};
const fixture=JSON.parse(readFileSync(new URL('./fixtures/publication-capacity-golden.json',import.meta.url),'utf8'));
const body=JSON.parse(fixture.binding),chain=Object.fromEntries(Object.entries(fixture.contracts).map(([k,c])=>[k,control.admit(c.name,c.wire,limits)]));
const physical={codecContractCid:body.codec_contract_cid,resultFields:body.result_fields,resultSchemaWire:fixture.schema,materialGenerationCid:body.material_generation_cid,storeAuthorityCid:body.store_authority_cid,rowCount:body.row_count,byteCount:body.byte_count,physicalSha256:body.physical_sha256};
test('shared durable emitter preserves pre-refactor wire and CID; exact/one-short byte boundary',()=>{
 const actual=control.issueDurableResultBinding(chain,physical,limits);assert.equal(actual.wire,fixture.binding);assert.equal(actual.identity,body.durable_result_binding_cid);
 const exact=Buffer.byteLength(actual.wire);assert.equal(control.issueDurableResultBinding(chain,physical,{...limits,maxWireBytes:exact}).wire,fixture.binding);
 assert.throws(()=>control.issueDurableResultBinding(chain,physical,{...limits,maxWireBytes:exact-1}));
});
test('Common occurrence contract ceilings cover actual emitted metadata, large counts and arity',()=>{
 const bounds=control.resultPublicationContractByteBounds([],Buffer.byteLength(fixture.schema),limits);
 assert.equal(bounds.length,4);assert.ok(bounds[0]>=Buffer.byteLength(fixture.contracts.artifact.wire));assert.ok(bounds[2]>=Buffer.byteLength(fixture.contracts.ordering.wire));assert.ok(bounds[3]>=Buffer.byteLength(fixture.binding));
 const cid='sha256:'+'0'.repeat(64),next=control.resultPublicationContractByteBounds([cid,cid],Buffer.byteLength(fixture.schema),limits);assert.equal(next[1]-bounds[1],147);
 const small=control.resultPublicationContractByteBounds([],0,{...limits,maxWireBytes:1});assert.deepEqual(small,[1,1,1,1]);
});

test('actual Common control refuses malformed CID lists before projection',()=>{
 for(const ids of [undefined,null,'not-an-array',[null],['not-a-cid'],['sha256:'+'G'.repeat(64)]]) {
  assert.throws(()=>control.resultPublicationContractByteBounds(ids,100,limits),TypeError);
 }
 assert.equal(control.resultPublicationContractByteBounds([],100,limits).length,4);
});

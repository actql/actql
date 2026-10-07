import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectScalarCode, scalarSites, providerSymbolText} from './provider-callback-code.mjs';
// Independent tiny ARM64 object/link pair. Addresses deliberately differ;
// allocation offsets and callback identity must survive linking and ASLR.
const object = `0000000000000100 <factory>:
 100: mov x0, #0x8
 104: bl 0x104
 104: ARM64_RELOC_BRANCH26 _moonbit_malloc
 108: mov x21, x0
 10c: mov w10, #0x0
 110: stur w10, [x21, #-0x4]
 114: adrp x10, 0x0
 114: ARM64_RELOC_PAGE21 callback
 118: add x10, x10, #0x0
 118: ARM64_RELOC_PAGEOFF12 callback
 11c: str x10, [x21]
 120: ret
`;
const linked = `0000000000002000 <factory>:
 2000: mov x0, #0x8
 2004: bl 0x4000 <_moonbit_malloc>
 2008: mov x21, x0
 200c: mov w10, #0x0
 2010: stur w10, [x21, #-0x4]
 2014: adrp x10, 0x3000 <callback>
 2018: add x10, x10, #0x20
 201c: str x10, [x21]
 2020: ret
`;
const symbols='2000 T factory\n3020 T callback\n4000 T _moonbit_malloc\n5000 T _actql_proof_provider_construction\n';
const facts=()=>[{indexedBytes:100,scalarDynamicCallbacks:1,scalarCodes:[{identity:'1234',codeDelta:'-8160'}]}];
const check=(f=facts(),o=object,l=linked,s=symbols)=>inspectScalarCode(f,s,o,l);
test('live scalar identity is tied to malloc request in object and executed binary',()=>{
  const result=check();
  assert.equal(result.maxPointRequestedBytes,116);
  assert.equal(result.scalarPayloadBytesMeasured,false);
  assert.equal(result.completeConstructorLifetimeUpper,false);
  assert.equal(result.completeParentUpper,false);
  assert.equal(result.observations[0].callbacks[0].requestedBytes,16);
});
test('a common code slide preserves relative identity without treating pointers as bytes',()=>{
  const shifted=symbols.replaceAll(/^(\w+) T/gm,(_,n)=>(BigInt('0x'+n)+0x10000n).toString(16)+' T');
  const l=linked.replaceAll('0x4000','0x14000').replaceAll('0x3000','0x13000');
  assert.equal(check(facts(),object,l,shifted).maxPointRequestedBytes,116);
});
test('code address mismatch and missing anchor do not get guessed extents',()=>{
  const f=facts();f[0].scalarCodes[0].codeDelta='-8161';assert.throws(()=>check(f),/allocation site/);
  assert.throws(()=>check(facts(),object,linked,symbols.replace(/5000.*\n/,'')),/anchor/);
});
test('incomplete or duplicate live identities cannot fill the missing byte component',()=>{
  const f=facts();f[0].scalarCodes=[];assert.throws(()=>check(f),/Missing live/);
  const duplicate=facts();duplicate[0].scalarDynamicCallbacks=2;duplicate[0].scalarCodes.push({...duplicate[0].scalarCodes[0]});
  assert.throws(()=>check(duplicate),/Repeated scalar/);
});
test('descriptor zero alone or code relocation alone is insufficient',()=>{
  for(const [from,to] of [['stur w10, [x21, #-0x4]','stur w10, [x21, #-0x8]'],
    ['str x10, [x21]','str x10, [x21, #0x8]'],['ARM64_RELOC_PAGEOFF12 callback','ARM64_RELOC_PAGEOFF12 other']])
    assert.throws(()=>check(facts(),object.replace(from,to)),/allocation site/);
});
test('changed or unrecognized allocation request cannot become a code-pointer-only extent',()=>{
  assert.throws(()=>scalarSites(object.replace('mov x0, #0x8','mov x0, #0x10')),/request/);
  assert.throws(()=>check(facts(),object.replace('mov x0, #0x8','mov x0, x19')),/allocation site/);
});
test('a matching object with a different executed allocation is rejected',()=>{
  assert.throws(()=>check(facts(),object,linked.replace('mov x0, #0x8','mov x0, #0x10')),/request/);
  assert.throws(()=>check(facts(),object,linked.replace('str x10, [x21]','str x10, [x21, #0x8]')),/executed binary/);
});
test('relocation attached to another instruction and duplicate symbols are rejected',()=>{
  assert.throws(()=>scalarSites(object.replace('104: ARM64','108: ARM64')),/Detached/);
  assert.throws(()=>check(facts(),object,linked,symbols+'3020 T callback\n'),/Duplicate Native symbol/);
});

test('unrelated C translation-unit symbols do not become provider identity collisions',()=>{
  const selected=providerSymbolText('1000 t unrelated\n1100 t unrelated\n2000 T _moonbit_malloc\n3000 T _actql_proof_provider_construction\n4000 t __M0connectors5local_callback\n');
  assert(!selected.includes('unrelated'));
  assert(selected.includes('_moonbit_malloc'));
  assert(selected.includes('__M0connectors5local_callback'));
});

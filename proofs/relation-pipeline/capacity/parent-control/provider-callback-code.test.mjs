import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectScalarCode, scalarSites, providerSymbolText, nativeArtifactPath} from './provider-callback-code.mjs';
import {inspectProviderConstructionPoint} from './provider-construction.mjs';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, realpathSync, existsSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';

// Synthetic file transport only; no object is loaded and no Native tool runs.
function relocatedNativeInput(t) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-native-input-path-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const path='.artifacts/relation-pipeline/current-chain-native/code/original.o';
  const physical=join(root,'extracted/code/original.o'),bytes=Buffer.from([0,255,128,1]);
  mkdirSync(dirname(physical),{recursive:true});writeFileSync(physical,bytes);
  const read=selected=>{assert.equal(selected,path);return readFileSync(physical);};
  return {root,path,physical,bytes,read};
}
test('Native tool input resolves the same relocated original without a producer-root copy',t=>{
  const f=relocatedNativeInput(t),producer=join(f.root,'absent-producer');let calls=0;
  Object.defineProperty(f.read,'resolveArtifact',{value:function(path){
    assert.equal(this,f.read);assert.equal(path,f.path);calls++;return f.physical;
  }});
  assert.equal(nativeArtifactPath(producer,f.read,f.path),f.physical);
  assert.equal(calls,1);assert.equal(existsSync(producer),false);
  assert.deepEqual(readFileSync(f.physical),f.bytes);
});
test('Native tool input preserves the original producer path when its resolver is absent or inherited',t=>{
  const f=relocatedNativeInput(t),physical=join(f.root,f.path);
  mkdirSync(dirname(physical),{recursive:true});writeFileSync(physical,f.bytes);
  assert.equal(nativeArtifactPath(f.root,f.read,f.path),physical);
  Object.setPrototypeOf(f.read,{resolveArtifact(){assert.fail('Inherited resolver must not run');}});
  assert.equal(nativeArtifactPath(f.root,f.read,f.path),physical);
});
test('Native tool input refuses a detached physical file',t=>{
  const f=relocatedNativeInput(t),wrong=join(f.root,'wrong.o');writeFileSync(wrong,'different bytes');
  Object.defineProperty(f.read,'resolveArtifact',{value:()=>wrong});
  assert.throws(()=>nativeArtifactPath(f.root,f.read,f.path),/Detached Native artifact physical input/);
});
test('Native tool input does not fall back after a supplied physical path is missing',t=>{
  const f=relocatedNativeInput(t),ordinary=join(f.root,f.path);
  mkdirSync(dirname(ordinary),{recursive:true});writeFileSync(ordinary,f.bytes);
  Object.defineProperty(f.read,'resolveArtifact',{value:()=>join(f.root,'missing.o')});
  assert.throws(()=>nativeArtifactPath(f.root,f.read,f.path),{code:'ENOENT'});
});
test('Native tool input refuses malformed own resolvers without invoking accessors',t=>{
  const f=relocatedNativeInput(t);
  for(const descriptor of [{value:undefined},{value:1},{value:()=>undefined},
    {get(){assert.fail('Resolver getter must not run');}}]) {
    const read=path=>f.read(path);Object.defineProperty(read,'resolveArtifact',descriptor);
    assert.throws(()=>nativeArtifactPath(f.root,read,f.path),/Invalid Native artifact/);
  }
});
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

import {retainedConstructionFixtureRead} from '../../fixtures/retained-construction-source.mjs';
const read = retainedConstructionFixtureRead;
const constructionFacts = () => [{...facts()[0], kind:'provider construction observation',
  providers:11, records:11, arraySlots:11, callbacks:24, defaultArrays:1,
  indexedBytes:1504, unclassifiedCaptures:0}];
const constructionCode = f => inspectScalarCode(f,symbols,object,linked);
const point = (f=constructionFacts(),code=constructionCode(f)) =>
  inspectProviderConstructionPoint(f,code,read,'native',{retained:true});

test('independent code evidence closes only the same finite constructor point',()=>{
  const result=point();
  assert.equal(result.maxObservedIndexedBytes,1504);
  assert.equal(result.maxPointRequestedBytes,1520);
  assert.equal(result.points[0].scalarRequestedBytes,16);
  assert.deepEqual(result.points[0].scalarAllocationIdentities,['1234']);
  assert.equal(result.pointRequestedBytesEstablished,true);
  assert.equal(result.scalarPayloadBytesObserved,false);
  assert.equal(result.recipe.bytes,2344);
  assert.equal(result.recipe.completeConstructorByteCorrespondence,false);
  assert.equal(result.completeConstructorLifetimeUpper,false);
  assert.equal(result.completeParentUpper,false);
  assert.equal(result.completePipelineUpper,false);
});
test('equal byte totals and callback counts cannot join different observations',()=>{
  for(const change of [f=>f[0].scalarCodes[0].identity='5678',
    f=>f[0].scalarCodes[0].codeDelta='-8159',f=>f[0].callbacks--]) {
    const f=constructionFacts(),code=constructionCode(f);change(f);
    assert.throws(()=>point(f,code),/Different constructor observation input/);
  }
  const f=constructionFacts();f.push({...f[0],scalarCodes:[{identity:'5678',codeDelta:'-8160'}]});
  const code=constructionCode(f);code.observations.reverse();
  assert.throws(()=>point(f,code),/Different constructor observation input/);
});
test('incomplete extents or altered sums cannot be supplied as the audited point',()=>{
  for(const change of [c=>c.observations.pop(),c=>c.observations[0].callbacks=[],
    c=>c.observations[0].callbacks[0].identity='5678',c=>c.observations[0].indexedRequestedBytes++,
    c=>c.observations[0].callbacks[0].requestedBytes++,c=>c.observations[0].scalarRequestedBytes++,
    c=>c.observations[0].pointRequestedBytes++,c=>c.maxPointRequestedBytes++]) {
    const f=constructionFacts(),code=constructionCode(f);change(code);
    assert.throws(()=>point(f,code));
  }
});
test('indexed and scalar components must fit the envelope together',()=>{
  const f=constructionFacts();f[0].indexedBytes=2330;
  assert.throws(()=>point(f),/Point constructor bytes exceed conditional envelope/);
});
test('count-only or stronger-scope claims cannot close compiled point correspondence',()=>{
  for(const change of [c=>c.scalarAllocationRequestsEstablished=false,
    c=>c.scalarPayloadBytesMeasured=true,c=>c.completeConstructorLifetimeUpper=true,
    c=>c.completeParentUpper=true,c=>c.completePipelineUpper=true]) {
    const f=constructionFacts(),code=constructionCode(f);change(code);
    assert.throws(()=>point(f,code));
  }
  assert.throws(()=>inspectProviderConstructionPoint(constructionFacts(),constructionCode(constructionFacts()),read,'js'),/native only/);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './numeric-slot.mjs';
const profile='sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df';
// Symbolic Unit identities isolate slot preimages; these are not checked Programs.
const base={version:'actql-group-numeric-slot/0.1',unit_definition_cid:'sha256:'+'0'.repeat(64),source_ordinal:0,aggregate_name:'sum',reduction_profile_cid:profile};
const bodies=[base,{...base,unit_definition_cid:'sha256:'+'1'.repeat(64)},
  {...base,source_ordinal:1},{...base,aggregate_name:'avg'},
  {...base,aggregate_name:'é~/\n😀'},
  {...base,reduction_profile_cid:'sha256:'+'2'.repeat(64)}];
const vectors=bodies.map(body=>({body,canonical:canonicalText(body),cid:cid(body)}));
const path='portability/corpus/numeric-slot-identities.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(vectors,null,2)+'\n');
const moon='// Generated independent numeric slot preimages.\n'+vectors.map((v,i)=>`\n///|\ntest "numeric slot preimage ${i}" {\n  let input = @json.parse(${JSON.stringify(v.canonical)})\n  let value = @canonical_json.from_json(input, 10000, 100, 100000)\n  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), ${JSON.stringify(v.cid)})\n}\n`).join('');
const moonPath='src/canonical_json/numeric_slot.generated_test.mbt';
if(process.argv.includes('--write'))writeFileSync(moonPath,moon);
assert.equal(readFileSync(moonPath,'utf8'),moon);
test('independent slot vectors bind Unit, ordinal, exact name and admitted profile',()=>{
  assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),vectors);
  assert.equal(new Set(vectors.map(v=>v.cid)).size,vectors.length);
  assert.equal(cid(Object.fromEntries(Object.entries(base).reverse())),cid(base));
});
function shape(v){
  const s=contract.schemas.group_slot;
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==s.required.length)return false;
  return s.required.every(k=>{
    const p=s.properties[k],x=v[k];
    if(p.const)return x===p.const;
    if(p.type==='integer')return Number.isSafeInteger(x)&&x>=p.minimum&&!Object.is(x,-0);
    return typeof x==='string'&&(!p.pattern||new RegExp(p.pattern).test(x))&&(!p.minLength||x.length>=p.minLength);
  });
}
test('slot shape cannot carry future observations or an internal visit identifier',()=>{
  for(const body of bodies)assert(shape(body));
  for(const key of ['input_artifact_cid','value','count','invocation_cid','member_cid','producer_visit','self_cid'])assert(!shape({...base,[key]:0}));
  for(const source_ordinal of [-1,0.5,Number.MAX_SAFE_INTEGER+1,-0])assert(!shape({...base,source_ordinal}));
  for(const aggregate_name of ['',null,0])assert(!shape({...base,aggregate_name}));
  for(const key of Object.keys(base)){const copy={...base};delete copy[key];assert(!shape(copy));}
});
test('shape and self hash alone do not establish the selected slot',()=>{
  const selected=Object.freeze({...base});
  const admits=(body,expected)=>shape(body)&&cid(body)===expected&&canonicalText(body)===canonicalText(selected);
  assert(admits(base,cid(base)));
  for(const body of bodies.slice(1))assert(!admits(body,cid(body)));
});

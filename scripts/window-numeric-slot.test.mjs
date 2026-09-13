import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
import {contract} from './window-numeric-slot.mjs';
const base={aggregate_name:'sum',reduction_profile_cid:'sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df',source_ordinal:0,unit_definition_cid:'sha256:'+'0'.repeat(64),version:'actql-window-numeric-slot/0.1'};
// Hand-authored flat preimages in canonical key order, never lowerer output.
const bodies=[base,{...base,unit_definition_cid:'sha256:'+'1'.repeat(64)},
  {...base,source_ordinal:1},{...base,aggregate_name:'é~/\n😀'},
  {...base,reduction_profile_cid:'sha256:'+'2'.repeat(64)},
  {...base,version:'actql-group-numeric-slot/0.1'}];
const vectors=bodies.map(body=>{const canonical=JSON.stringify(body);return {body,canonical,cid:'sha256:'+createHash('sha256').update(canonical).digest('hex')};});
const path='portability/corpus/window-numeric-slot-identities.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(vectors,null,2)+'\n');
test('window slot preimages separate owners, call coordinates, profiles and domains',()=>{
  assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),vectors);
  assert.equal(new Set(vectors.map(v=>v.cid)).size,vectors.length);
  for(const v of vectors)assert.equal(cid(v.body),v.cid);
  assert.equal(cid(Object.fromEntries(Object.entries(base).reverse())),vectors[0].cid);
});
function shape(v){
  const s=contract.schemas.window_slot;
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==s.required.length)return false;
  return s.required.every(k=>{
    const p=s.properties[k],x=v[k];
    if(p.const)return x===p.const;
    if(p.type==='integer')return Number.isSafeInteger(x)&&x>=p.minimum&&!Object.is(x,-0);
    return typeof x==='string'&&(!p.pattern||new RegExp(p.pattern).test(x))&&(!p.minLength||x.length>=p.minLength);
  });
}
test('window slot shape excludes future observations and other operation domains',()=>{
  for(const body of bodies.slice(0,-1))assert(shape(body));
  assert(!shape(bodies.at(-1)));
  for(const key of ['input_artifact_cid','group_key','window_start','window_end','count','value','attempt','self_cid','producer_visit'])assert(!shape({...base,[key]:0}));
  for(const key of Object.keys(base)){const body={...base};delete body[key];assert(!shape(body));}
  for(const source_ordinal of [-1,-0,0.5,Number.MAX_SAFE_INTEGER+1])assert(!shape({...base,source_ordinal}));
  for(const aggregate_name of ['',null,1])assert(!shape({...base,aggregate_name}));
});

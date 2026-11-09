// Original caller/provider bodies with explicit ports; numerical funding is
// exercised separately on the actual MoonBit constructor and real Ledger.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
const cid=value=>'sha256:'+createHash('sha256').update(canonicalJson(value,{dataKeys:true})).digest('hex');
function find(source,predicate){const found=[];const walk=n=>{if(!n||typeof n!=='object')return;if(predicate(n))found.push(n);for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert.equal(found.length,1);return found[0];}
const host=readFileSync(new URL('./installed-row-effect.mjs',import.meta.url),'utf8'),hostNode=find(host,n=>n.type==='VariableDeclarator'&&n.id.name==='footprintOf');
const load=compileFunction('return '+host.slice(hostNode.init.start,hostNode.init.end),['ownerOf','recipeOf','footprintKinds','cidPattern','text','cid','contractCidOf','fail']);
const provider=readFileSync(new URL('../connectors/hubspot/host/hubspot-update-driver.mjs',import.meta.url),'utf8'),providerNode=find(provider,n=>n.type==='Property'&&n.method===true&&n.key.name==='footprint');
const loadProvider=compileFunction('return function'+provider.slice(providerNode.value.start,providerNode.value.end),['selected','native','origin','portalId','cid']);
test('actual opaque footprint keeps original mapping CID and later Host identity normalization inside original call order',()=>{
  let active=false,selected=0,native=0,normalizations=0;const member={memberIndex:0,kind:'update',resource:'companies',mapping:{primaryIdentity:'id'}},catalog={};
  const origin='https://hubspot.invalid',portalId='7',objectType='companies';
  const owned={footprint:loadProvider(actual=>{assert.equal(active,true);assert.strictEqual(actual,member);selected++;return {catalog};},{hubspotPropertyCatalogObjectType(actual){assert.equal(active,true);assert.strictEqual(actual,catalog);native++;return objectType;}},origin,portalId,cid)};
  const footprint=load(()=>({owned,connectorRegistration:'hubspot'}),()=>({footprintConstruction:{operationIndex:1}}),['opaque'],/^sha256:[a-f0-9]{64}$/u,v=>typeof v==='string'&&v.length>0,value=>{assert.equal(active,false);normalizations++;return cid(value);},()=>'',code=>{throw new Error(code);});
  const work=()=>assert.fail('generic frame used for declared footprint');work.footprint=(m,o,receiver,method,args)=>{assert.equal(m,0);assert.equal(o,1);assert.strictEqual(receiver,owned);assert.strictEqual(method,owned.footprint);active=true;try{return Reflect.apply(method,receiver,args);}finally{active=false;}};
  const result=footprint(member,[],work);assert.equal(selected,1);assert.equal(native,1);assert.equal(normalizations,1);
  assert.equal(result.provider_boundary_cid,cid({origin,portalId,objectType}));assert.equal(result.kind,'opaque');assert.deepEqual(result.provider_object_identity_cids,[]);
});

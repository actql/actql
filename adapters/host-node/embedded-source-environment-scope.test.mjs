import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const opening=ast.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='openInstalledHost');
const outerTry=opening.body.body.find(node=>node.type==='TryStatement');
const text=node=>source.slice(node.start,node.end);
const directDeclaration=name=>outerTry.block.body.find(node=>node.type==='VariableDeclaration'&&
  node.declarations.some(value=>value.id.type==='Identifier'&&value.id.name===name));
for(const name of ['moon','environment','sourcePublication'])assert(directDeclaration(name),name);

// Keep the complete original enclosing function before/after its acquisition
// try, including every outer declaration and callback's actual lexical scope.
// Replace unrelated acquisition work inside that try with explicit originals
// at the SAME declaration scope, not injected outer moon/environment bindings.
// This is a scope/custody fixture, not full Host or resource execution.
let capture,retain;
function visit(node){
  if(!node||typeof node!=='object')return;
  if(node.type==='VariableDeclaration'&&node.declarations.some(value=>value.id.name==='sourceEnvironmentOriginal'))capture=node;
  if(node.type==='IfStatement'&&text(node.test)==='sourceEnvironmentOriginal !== undefined')retain=node;
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==='object')visit(value);
  }
}
visit(outerTry.block);assert(capture&&retain);
assert.equal(outerTry.block.body.some(node=>node.type==='FunctionDeclaration'&&node.id.name==='getPreparedSourceEnvironment'),false);
const body=source.slice(opening.start,outerTry.start)+`try {
 const moon=fixture.moon;
 let environment=fixture.environment,sourcePublication=fixture.publication;
 const installationServices=fixture.services,environmentWire='{}';
 ${text(capture)}
 ${text(retain)}
 return {get slot(){return preparedSourceEnvironment;},retire:retireModelPreparationReferences,
  replaceEnvironment(value){environment=value;},replacePublication(value){sourcePublication=value;},
  stop(){modelRuntimeClosing=true;}};
 }catch(cause){throw cause;}`+source.slice(outerTry.end,opening.end);
const moduleSource=`export function create(fixture){
 const clientOperationError=code=>Object.assign(new Error(code),{code});
 const sourceAliasPublicationOriginal=fixture.original;
 const retireSourceAliasPublicationOriginal=fixture.retire;
 const completeInstalledSourceInitialization=fixture.complete;
 ${body}
 return openInstalledHost({}, {host:{}, fundedPreparation(){throw Error('No Program selected');}, requestPreparation(){throw Error('No Request selected');}, retainReferenceRetirement(callback){fixture.retirement=callback;}});
}`;

test('actual Host enclosing scopes retain original Source material without a legacy execution getter',async()=>{
  const original={moon:{},environment:{},publication:{},preparedEnvironment:{}};
  let reads=0,retired=0;
  original.services={};
  original.complete=(services,installation,prepared,wire)=>{
    assert.strictEqual(services,original.services);assert.strictEqual(prepared,original.preparedEnvironment);
    assert.equal(wire,'{}');
  };
  original.original=(moon,environment,publication)=>{
    assert.strictEqual(moon,original.moon);assert.strictEqual(environment,original.environment);
    assert.strictEqual(publication,original.publication);reads++;
    return {preparedEnvironment:original.preparedEnvironment};
  };
  original.retire=(moon,environment,publication)=>{
    assert.strictEqual(moon,original.moon);assert.strictEqual(environment,original.environment);
    assert.strictEqual(publication,original.publication);retired++;
  };
  const {create}=await import('data:text/javascript;charset=utf-8,'+encodeURIComponent(moduleSource));
  const host=await create(original);
  assert.strictEqual(original.retirement,host.retire);
  assert.strictEqual(host.slot.preparedEnvironment,original.preparedEnvironment);
  assert.equal(reads,1);
  host.replaceEnvironment({});
  assert.strictEqual(host.slot.preparedEnvironment,original.preparedEnvironment);
  host.replaceEnvironment(original.environment);host.replacePublication({});
  assert.strictEqual(host.slot.preparedEnvironment,original.preparedEnvironment);
  host.replacePublication(original.publication);
  host.stop();assert.strictEqual(host.slot.preparedEnvironment,original.preparedEnvironment);
  host.retire();assert.equal(retired,1);assert.equal(host.slot,undefined);
});

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
const getter=outerTry.block.body.filter(node=>node.type==='FunctionDeclaration'&&node.id.name==='getPreparedSourceEnvironment');
const body=source.slice(opening.start,outerTry.start)+`try {
 const moon=fixture.moon;
 let environment=fixture.environment,sourcePublication=fixture.publication;
 ${getter.map(text).join('\n')}
 ${text(capture)}
 ${text(retain)}
 return {get:getPreparedSourceEnvironment,retire:retireModelPreparationReferences,
  replaceEnvironment(value){environment=value;},replacePublication(value){sourcePublication=value;},
  stop(){modelRuntimeClosing=true;}};
 }catch(cause){throw cause;}`+source.slice(outerTry.end,opening.end);
const moduleSource=`export function create(fixture){
 const clientOperationError=code=>Object.assign(new Error(code),{code});
 const sourceAliasPublicationOriginal=fixture.original;
 const retireSourceAliasPublicationOriginal=fixture.retire;
 ${body}
 return openInstalledHost({});
}`;

test('actual Host enclosing scopes bind its prepared Source Environment getter to installed originals',async()=>{
  const original={moon:{},environment:{},publication:{},preparedEnvironment:{}};
  let reads=0,retired=0;
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
  for(let count=0;count<3;count++)assert.strictEqual(host.get(),original.preparedEnvironment);
  assert.equal(reads,1);
  host.replaceEnvironment({});
  assert.throws(host.get,{code:'InstalledPublicSourceEnvironmentChanged'});
  host.replaceEnvironment(original.environment);host.replacePublication({});
  assert.throws(host.get,{code:'InstalledPublicSourceEnvironmentChanged'});
  host.replacePublication(original.publication);
  host.stop();assert.throws(host.get,{code:'ClientHostClosing'});
  host.retire();assert.equal(retired,1);
});

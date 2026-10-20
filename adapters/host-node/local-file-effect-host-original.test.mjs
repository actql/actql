import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual private Host binding with explicit nominal Core/Journal
// ports. This is not ordinary Host, current Common or STORE execution evidence.
const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const host=tree.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='openInstalledHost');
const nodes=[];
function visit(node) {
  if(node===null||typeof node!=='object')return;
  if(typeof node.type==='string')nodes.push(node);
  for(const child of Object.values(node)) {
    if(Array.isArray(child))child.forEach(visit);
    else if(child!==null&&typeof child==='object')visit(child);
  }
}
visit(host.body);
const currents=nodes.filter(node=>node.type==='FunctionDeclaration'&&node.id.name==='assertLocalFileEffectRunOriginal');
const declarations=nodes.filter(node=>node.type==='VariableDeclarator'&&node.id.name==='localFileEffectResources');
assert.equal(currents.length,1);assert.equal(declarations.length,1);
const [current]=currents,[declaration]=declarations;

function fixture() {
  const prepareds=new WeakSet(),alloweds=new WeakMap(),definitions=new WeakSet(),identities=new WeakSet();
  const runs=new Map(),originals=new WeakMap(),calls=[];
  let live=true,owned=true,authorization='authorization',bindFailure;
  const refusal=new Error('ActualHostNotCurrent');
  const assertProjectRuntime=()=>{calls.push('current');if(!live)throw refusal;};
  const limits=Object.freeze({maxFileBytes:16777216,maxRows:100,maxRequestBytes:100000,
    maxResponseBytes:65536,maxEffects:16});
  const saved={runDefinition:{identity:'definition',wire:'original definition'},
    runAdmissionEvidence:{prepared:'prepared',authorization:'authorization'}};
  const handles=()=>{
    const prepared={},allowed={},definition={},identity={};
    prepareds.add(prepared);alloweds.set(allowed,prepared);definitions.add(definition);identities.add(identity);
    return {prepared,allowed,definition,identity};
  };
  const actual=handles();
  const moon={
    clientRequestCallerId(value){assert(identities.has(value));return 'request';},
    clientRequestAuthorityScopeCid(value){assert(identities.has(value));return 'authority';},
    strategyPublicationContractIdentity(value){assert(definitions.has(value));return 'definition';},
    strategyPublicationContractJson(value){assert(definitions.has(value));return 'original definition';},
    strategyRunEvidenceJson:value=>value,
    clientProgramAllowedEffectRunPrepared(value){assert(alloweds.has(value));return 'prepared';},
    clientProgramAllowedEffectRunAuthorization(value){assert(alloweds.has(value));return authorization;},
    clientProgramBindCompiledEffectRun(prepared,allowed,definition){
      calls.push('bind');assert(prepareds.has(prepared));assert(definitions.has(definition));
      if(bindFailure!==undefined)throw bindFailure;
      if(alloweds.get(allowed)!==prepared)throw new Error('ForeignNominalPreparedRun');
      return {$tag:1,_0:{}};
    }};
  const journal={lookupOwnedDefinition(key,actualMoon,control){
    calls.push('journal');assert.strictEqual(actualMoon,moon);assert.equal(control,'control');
    assert.deepEqual(key,{namespaceId:'namespace',authorityScopeCid:'authority',
      requestId:'request',runDefinitionCid:'definition'});
    return owned?saved:undefined;
  }};
  const preparation={assertResultPublicationCurrent:assertProjectRuntime,
    localFilesEffectLimits(value){calls.push('limits');assert.strictEqual(value,moon);return limits;}};
  const port=Function('moon','preparation','journal','control','namespaceId','authorityScopeCid',
    'assertProjectRuntime','localFileEffectRuns','localFileEffectOriginals','clientOperationError','checked',
    `${source.slice(current.start,current.end)}\nreturn ${source.slice(declaration.init.start,declaration.init.end)};`)(
    moon,preparation,journal,'control','namespace','authority',assertProjectRuntime,runs,originals,
    code=>Object.assign(new Error(code),{code}),value=>{assert.equal(value.$tag,1);return value._0;});
  return {port,actual,handles,limits,runs,calls,refusal,
    revoke(){live=false;},missing(){owned=false;},changeAuthorization(){authorization='changed';},
    failBind(value){bindFailure=value;}};
}

test('Local Effect Host binds the winning original Journal and nominal Core Run before using limits',()=>{
  const f=fixture(),original=f.port.bindRunOriginal(f.actual);
  assert.equal(typeof original,'object');assert.equal(f.runs.size,1);
  assert(f.calls.indexOf('journal')<f.calls.indexOf('bind'));
  assert(f.calls.indexOf('bind')<f.calls.indexOf('limits'));
  assert.strictEqual(f.port.limits(original),f.limits);
  assert.strictEqual(f.port.bindRunOriginal(f.actual),original);
  assert.throws(()=>f.port.assertCurrent({...original}),{code:'ForeignInstalledLocalFileEffectRun'});
});

test('Local Effect Host refuses missing saved Run and changed authorization before nominal binding',()=>{
  for(const change of ['missing','changeAuthorization']) {
    const f=fixture();f[change]();
    assert.throws(()=>f.port.bindRunOriginal(f.actual),{code:'ForeignInstalledLocalFileEffectRun'});
    assert.equal(f.calls.includes('bind'),false);assert.equal(f.calls.includes('limits'),false);
    assert.equal(f.runs.size,0);
  }
});

test('Local Effect Host reconstructs validated saved handles but rejects a mismatched prepared original',()=>{
  const f=fixture(),first=f.port.bindRunOriginal(f.actual),restored=f.handles();
  const second=f.port.bindRunOriginal({recovered:{...restored,requestIdentity:restored.identity}});
  assert.notStrictEqual(second,first);assert.strictEqual(f.port.limits(second),f.limits);
  const foreign=f.handles();
  assert.throws(()=>f.port.bindRunOriginal({...f.actual,prepared:foreign.prepared}),/ForeignNominalPreparedRun/);
  assert.equal(f.runs.size,2);
});

test('Local Effect Host preserves original bind failure and refuses resource use after Host retirement',()=>{
  const f=fixture(),cause=new Error('original bind failed');f.failBind(cause);
  assert.throws(()=>f.port.bindRunOriginal(f.actual),error=>error===cause);
  assert.equal(f.runs.size,0);
  const current=fixture(),original=current.port.bindRunOriginal(current.actual);current.revoke();
  assert.throws(()=>current.port.assertCurrent(original),error=>error===current.refusal);
  assert.throws(()=>current.port.limits(original),error=>error===current.refusal);
});

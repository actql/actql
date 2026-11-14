import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';

const source=readFileSync(new URL('../host-common/runtime-core.mjs',import.meta.url),'utf8');
let method;
function walk(node){
  if(node?.type==='Property'&&node.method&&node.key.name==='startInstalledOriginalComposedKeyedPrefix'){
    assert.equal(method,undefined);method=source.slice(node.start,node.end);
  }
  for(const value of Object.values(node??{})){
    if(Array.isArray(value)){for(const item of value)if(item?.type)walk(item);}
    else if(value?.type)walk(value);
  }
}
walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(method);

// Actual thin facade body and explicit private original-map ports. Core's
// real adopted-parent/sequence/current/one-use consumer is tested separately.
function fixture(whole=false){
  const compiled={kind:'infer'},nativeCompiled={},definition={},nativeDefinition={},run={},scope={},graph={},keyed={},result={};
  const originals=[{},{}];let calls=0,borrows=0;
  const captures=originals.map(original=>{
    const capture=whole
      ? {originalCapturedInput(){assert.equal(this,capture);borrows++;return original;}}
      : {originalRowCapture(){assert.equal(this,capture);borrows++;return original;}};
    return {...(whole ? {inputKind:'whole-input'} : {}),capture};
  });
  const compiledRunTokens=new WeakMap([[compiled,nativeCompiled]]);
  const moon={clientProgramStartInstalledOriginalComposedKeyedPrefix(...args){
    assert.equal(whole,false);
    assert.equal(this,moon);assert.deepEqual(args,[run,scope,nativeCompiled,nativeDefinition,graph,keyed,originals]);
    calls++;return {$tag:1,_0:result};
  },clientProgramStartInstalledOriginalComposedKeyedInputPrefix(...args){
    assert.equal(whole,true);
    assert.equal(this,moon);assert.deepEqual(args,[run,scope,nativeCompiled,nativeDefinition,graph,keyed,originals]);
    calls++;return {$tag:1,_0:result};
  }};
  const token=value=>{if(value!==definition)throw new TypeError('Foreign Definition');return nativeDefinition;};
  const start=new Function('moon','compiledRunTokens','token','checked',`return ({${method}}).startInstalledOriginalComposedKeyedPrefix;`)(
    moon,compiledRunTokens,token,checked);
  return {start,compiled,definition,run,scope,graph,keyed,captures,result,moon,
    counts:()=>({calls,borrows})};
}

test('installed keyed prefix facade forwards actual managed original and Row captures without an early segment or scalar grant',()=>{
  const f=fixture();
  assert.equal(f.start(f.run,f.compiled,f.definition,f.graph,f.scope,f.keyed,f.captures),f.result);
  assert.deepEqual(f.counts(),{calls:1,borrows:2});
});

test('installed keyed prefix facade refuses copied compilation and foreign Definition before touching Source originals',()=>{
  const f=fixture();
  assert.throws(()=>f.start(f.run,{...f.compiled},f.definition,f.graph,f.scope,f.keyed,f.captures),/Foreign Client compiled/);
  assert.throws(()=>f.start(f.run,f.compiled,{},f.graph,f.scope,f.keyed,f.captures),/Foreign Definition/);
  f.compiled.kind='pure';
  assert.throws(()=>f.start(f.run,f.compiled,f.definition,f.graph,f.scope,f.keyed,f.captures),/Foreign Client compiled/);
  assert.deepEqual(f.counts(),{calls:0,borrows:0});
});

test('installed keyed prefix facade preserves original undefined capture refusal and typed native refusal without another call',()=>{
  const f=fixture();
  f.captures[0].capture.originalRowCapture=()=>{throw undefined;};
  let failed=false;
  try{f.start(f.run,f.compiled,f.definition,f.graph,f.scope,f.keyed,f.captures);}
  catch(cause){failed=true;assert.equal(cause,undefined);}
  assert.equal(failed,true);assert.deepEqual(f.counts(),{calls:0,borrows:0});
  const g=fixture(),primary={};
  let nativeCalls=0;
  g.moon.clientProgramStartInstalledOriginalComposedKeyedPrefix=()=>{nativeCalls++;return {$tag:0,_0:primary};};
  assert.throws(()=>g.start(g.run,g.compiled,g.definition,g.graph,g.scope,g.keyed,g.captures),
    error=>error.code==='MoonBitHostFailure'&&error.cause===primary);
  assert.equal(nativeCalls,1);assert.equal(g.counts().borrows,2);
});

test('installed Whole keyed prefix borrows its actual live or restored inputs on the same managed original',()=>{
  const f=fixture(true);
  assert.equal(f.start(f.run,f.compiled,f.definition,f.graph,f.scope,f.keyed,f.captures),f.result);
  assert.deepEqual(f.counts(),{calls:1,borrows:2});
  const g=fixture(true);
  assert.throws(()=>g.start(g.run,{...g.compiled},g.definition,g.graph,g.scope,g.keyed,g.captures),/Foreign Client compiled/);
  assert.throws(()=>g.start(g.run,g.compiled,{},g.graph,g.scope,g.keyed,g.captures),/Foreign Definition/);
  assert.deepEqual(g.counts(),{calls:0,borrows:0});
});

test('installed Whole keyed prefix preserves borrow and Core refusals without Query fallback or a second start',()=>{
  const f=fixture(true);
  f.captures[0].capture.originalCapturedInput=()=>{throw undefined;};
  let failed=false;
  try{f.start(f.run,f.compiled,f.definition,f.graph,f.scope,f.keyed,f.captures);}
  catch(cause){failed=true;assert.equal(cause,undefined);}
  assert.equal(failed,true);assert.deepEqual(f.counts(),{calls:0,borrows:0});
  const g=fixture(true),primary={};let nativeCalls=0;
  g.moon.clientProgramStartInstalledOriginalComposedKeyedInputPrefix=()=>{nativeCalls++;return {$tag:0,_0:primary};};
  assert.throws(()=>g.start(g.run,g.compiled,g.definition,g.graph,g.scope,g.keyed,g.captures),
    error=>error.code==='MoonBitHostFailure'&&error.cause===primary);
  assert.equal(nativeCalls,1);assert.equal(g.counts().borrows,2);
  const mixed=fixture(true);
  delete mixed.captures[1].inputKind;
  assert.throws(()=>mixed.start(mixed.run,mixed.compiled,mixed.definition,mixed.graph,mixed.scope,mixed.keyed,mixed.captures),
    /Unsupported mixed original keyed Source inputs/);
  assert.deepEqual(mixed.counts(),{calls:0,borrows:0});
});

test('acquired Effect keeps its retained Model Definition instead of a separately validated Journal handle',()=>{
  const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
  let expression;
  function visit(node){
    if(node?.type==='Property'&&node.key.name==='originalModelPlan'){
      assert.equal(expression,undefined);
      assert.equal(node.value.type,'ObjectExpression');
      expression=source.slice(node.value.start,node.value.end);
    }
    for(const value of Object.values(node??{})){
      if(Array.isArray(value)){for(const item of value)if(item?.type)visit(item);}
      else if(value?.type)visit(value);
    }
  }
  visit(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(expression);
  const select=new Function('managedEffect','facts',`return (${expression});`);
  const f=fixture(),journalDefinition={wire:'same-public-definition'},original=f.definition;
  original.wire=journalDefinition.wire;
  let journalReads=0;
  const facts={get runDefinition(){journalReads++;return journalDefinition;}};
  const managedEffect={model:{compiled:f.compiled},modelRunDefinition:original};
  const plan=select(managedEffect,facts);
  assert.equal(plan.compiled,f.compiled);
  assert.equal(plan.runDefinition,original);
  assert.notEqual(plan.runDefinition,journalDefinition);
  assert.equal(f.start(f.run,plan.compiled,plan.runDefinition,f.graph,f.scope,f.keyed,f.captures),f.result);
  assert.deepEqual(f.counts(),{calls:1,borrows:2});
  assert.equal(journalReads,0);

  const missing=fixture();
  const absent=select({model:{compiled:missing.compiled}},facts);
  assert.equal(absent.runDefinition,undefined);
  assert.throws(()=>missing.start(missing.run,absent.compiled,absent.runDefinition,
    missing.graph,missing.scope,missing.keyed,missing.captures),/Foreign Definition/);
  assert.deepEqual(missing.counts(),{calls:0,borrows:0});
  assert.equal(journalReads,0);
});


function hostInputFacadeFixture(direct) {
  let body;
  const inspect = node => {
    if (node?.type === 'Property' && node.method && node.key.name === 'prepareInstalledOriginalComposedKeyedHostInput') {
      assert.equal(body, undefined); body = source.slice(node.start, node.end);
    }
    for (const value of Object.values(node ?? {})) {
      if (Array.isArray(value)) value.forEach(item => {if (item?.type) inspect(item);});
      else if (value?.type) inspect(value);
    }
  };
  inspect(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(body);
  const compiled = {kind: 'infer'}, nativeCompiled = {}, definition = {}, nativeDefinition = {};
  const managedRun = {}, graph = {}, scope = {}, keyed = {}, host = {}, left = {}, prefix = {};
  const originals = [{}, {}]; let borrows = 0, leftCalls = 0, prefixCalls = 0, actualInputs;
  const captures = originals.map(original => {
    const capture = {originalCapturedInput() {assert.strictEqual(this, capture); borrows++; return original;}};
    return {inputKind: 'whole-input', capture};
  });
  const argumentsMatch = args => {
    assert.deepEqual(args, [managedRun, scope, nativeCompiled, nativeDefinition, graph, keyed, originals, host]);
  };
  const moon = {clientProgramInstalledOriginalComposedKeyedHostInputLeft(...args) {
    assert.strictEqual(this, moon); argumentsMatch(args); actualInputs = args[6]; leftCalls++;
    return {$tag: 1, _0: direct ? left : undefined};
  }, clientProgramStartInstalledOriginalComposedKeyedHostPrefix(...args) {
    assert.strictEqual(this, moon); argumentsMatch(args); assert.strictEqual(args[6], actualInputs); prefixCalls++;
    return {$tag: 1, _0: prefix};
  }};
  const token = value => {assert.strictEqual(value, definition); return nativeDefinition;};
  const method = new Function('moon', 'compiledRunTokens', 'token', 'checked',
    `return ({${body}}).prepareInstalledOriginalComposedKeyedHostInput;`)(moon,
      new WeakMap([[compiled, nativeCompiled]]), token, checked);
  return {invoke: () => method(managedRun, compiled, definition, graph, scope, keyed, captures, host),
    left, prefix, counts: () => ({borrows, leftCalls, prefixCalls})};
}

test('same Host direct input facade preserves original read with one vector and no prefix constructor', () => {
  const f = hostInputFacadeFixture(true), result = f.invoke();
  assert.strictEqual(result.left, f.left); assert.equal(result.prefix, undefined); assert(Object.isFrozen(result));
  assert.deepEqual(f.counts(), {borrows: 2, leftCalls: 1, prefixCalls: 0});
});

test('same Host Step input facade uses the same original vector for the existing prefix constructor', () => {
  const f = hostInputFacadeFixture(false), result = f.invoke();
  assert.strictEqual(result.prefix, f.prefix); assert.equal(result.left, undefined); assert(Object.isFrozen(result));
  assert.deepEqual(f.counts(), {borrows: 2, leftCalls: 1, prefixCalls: 1});
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';

const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion:'latest', sourceType:'module'});
let method;
function walk(node) {
  if (node?.type === 'Property' && node.method && node.key.name === 'prepareKeyedRead') {
    assert.equal(method, undefined); method = source.slice(node.start, node.end);
  }
  for (const value of Object.values(node ?? {})) {
    if (Array.isArray(value)) {for (const item of value) if (item?.type) walk(item);}
    else if (value?.type) walk(value);
  }
}
walk(tree); assert.equal(typeof method, 'string');

// Run the actual selected method with explicit original/current/cleanup ports.
// The test does not issue a Core Plan, Ledger, Source permission or read.
function fixture(project = true) {
  const prepared = {}, declaration = {}, originalRun = {}, view = {}, identity = {}, input = {};
  const operationPlan = {}, original = {}, runtime = {}, scope = {};
  let current = true, plan = operationPlan, planReads = 0;
  const model = {value:originalRun, prepared, request:identity, requestInput:input,
    original, manager:view, runtime, operationPlan, modelScope:scope, closed:false,
    readPlan(parent, p, request) {
      assert.equal(this, runtime); assert.equal(parent, originalRun);
      assert.equal(p, prepared); assert.equal(request, identity); planReads++; return {$tag:1, _0:plan};
    }};
  const run = {effectful:true, purpose:'source-compute', value:originalRun,
    original, request:input, operationPlan, model, children:[]};
  const runFor = p => {assert.equal(p, prepared); if (!current) throw new Error('OriginalNotCurrent'); return run;};
  const closeChild = async child => {
    if (child.closed) return {pending:false};
    if (child.reader !== undefined) {
      await child.reader.close();
      if (child.reader.status().pending) return {pending:true};
    }
    child.closed = true; return {pending:false};
  };
  const prepare = new Function('runFor', 'project', 'bundle', 'view', 'checked', 'fail',
    'captureReader', 'closeChild', 'readBytes', `return ({${method}}).prepareKeyedRead;`)(
    runFor, project, {sources:[{declaration}]}, view, checked,
    code => {throw Object.assign(new Error(code), {code});}, child => assert(child.reader), closeChild,
    (parent, child) => {assert.equal(parent, run); assert.equal(run.children.includes(child), true); return child;});
  return {prepare, prepared, declaration, originalRun, run, model,
    setCurrent:value => {current = value;}, replacePlan:() => {plan = {};}, reads:() => planReads};
}

test('adopted Effect Model keyed child retains same parent and real pending cleanup without reacquisition', async () => {
  const f = fixture(), request = {}, child = f.prepare(f.prepared, f.declaration, f.originalRun, request);
  assert.equal(f.reads(), 1); assert.equal(f.run.children.length, 1);
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, request),
    {code:'InstalledSourcePreparationMismatch'});
  let acknowledged = false, closes = 0;
  const reader = {async close() {closes++;}, status:() => ({pending:!acknowledged})};
  child.retainChild(reader);
  assert.equal((await child.close()).pending, true);
  acknowledged = true; assert.equal((await child.close()).pending, false);
  assert.equal((await child.close()).pending, false); assert.equal(closes, 2);
  assert.equal(f.run.children.length, 1); assert.equal(f.reads(), 1);
});

test('adopted keyed child refuses foreign parent, declaration, retired scope and changed Plan before allocation', () => {
  const f = fixture();
  for (const [run, declaration] of [[{}, f.declaration], [f.originalRun, {}]]) {
    assert.throws(() => f.prepare(f.prepared, declaration, run, {}), {code:'InstalledSourcePreparationMismatch'});
  }
  f.model.modelScopeFinished = true;
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), {code:'InstalledSourcePreparationMismatch'});
  f.model.modelScopeFinished = false; f.replacePlan();
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), {code:'InstalledSourcePreparationMismatch'});
  assert.equal(f.run.children.length, 0);
});

test('adopted keyed child rechecks original current after its Plan callback and retains an acquired child on refusal', async () => {
  const f = fixture(), original = f.model.readPlan;
  f.model.readPlan = function(...args) {const value = Reflect.apply(original, this, args); f.setCurrent(false); return value;};
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), /OriginalNotCurrent/);
  assert.equal(f.run.children.length, 0);
  f.model.readPlan = original; f.setCurrent(true);
  const child = f.prepare(f.prepared, f.declaration, f.originalRun, {});
  f.setCurrent(false);
  let close = 0;
  assert.throws(() => child.retainChild({async close() {close++;}, status:() => ({pending:false})}), /OriginalNotCurrent/);
  assert.equal(f.run.children.length, 1);
  assert.equal((await child.close()).pending, false); assert.equal(close, 1);
});

test('legacy keyed Content retains its existing request history bound', () => {
  const f = fixture(); f.run.effectful = false; f.run.purpose = 'local-content';
  f.run.original = f.originalRun; f.run.required = {attempts:1};
  f.prepare(f.prepared, f.declaration, f.originalRun, {});
  assert.equal(f.reads(), 0);
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), {code:'InstalledSourcePreparationMismatch'});
  assert.equal(f.run.children.length, 1);
});

test('adopted ordinary Mock keyed input borrows the existing same-child byte reader without a Project reader substitution', () => {
  const f = fixture(false), child = f.prepare(f.prepared, f.declaration, f.originalRun, {});
  assert.equal(child.retainChild, undefined);
  assert.equal(child.readOriginalBytes(), f.run.children[0]);
  assert.equal(f.reads(), 1);
  f.run.effectful = false;
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), {code:'InstalledSourcePreparationMismatch'});
  assert.equal(f.run.children.length, 1);
});


function pluralFixture() {
  const f = fixture(false), components = [{}, {}], selections = [{}, {}];
  f.model.modelScope = undefined;
  f.model.model = Object.freeze({components: Object.freeze(components)});
  f.model.modelSelection = Object.freeze({components: Object.freeze(selections)});
  f.model.modelScopes = Object.freeze([{}, {}]);
  f.model.modelMembers = Object.freeze(components.map((model, index) => ({model,
    modelSelection: selections[index], modelScope: f.model.modelScopes[index]})));
  return f;
}

test('plural Effect keyed child borrows the complete same Scope inventory without a first-member proxy', async () => {
  const f = pluralFixture(), request = {};
  const child = f.prepare(f.prepared, f.declaration, f.originalRun, request);
  assert.equal(f.model.modelScope, undefined); assert.equal(f.reads(), 1);
  assert.strictEqual(child.readOriginalBytes(), f.run.children[0]);
  assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, request), {code:'InstalledSourcePreparationMismatch'});
  assert.equal((await child.close()).pending, false);
});

test('plural Effect keyed child refuses missing foreign finished or changed-after-current Scopes before child allocation', () => {
  for (const mutate of [f => {f.model.modelScopes = Object.freeze([f.model.modelScopes[0]]);},
    f => {f.model.modelMembers[1].modelScope = {};},
    f => {f.model.modelMembers[1].modelScopeFinished = true;},
    f => {const original = f.model.readPlan; f.model.readPlan = function(...args) {
      const result = Reflect.apply(original, this, args); f.model.modelMembers[1].modelScope = {}; return result;
    };}]) {
    const f = pluralFixture(); mutate(f);
    assert.throws(() => f.prepare(f.prepared, f.declaration, f.originalRun, {}), {code:'InstalledSourcePreparationMismatch'});
    assert.equal(f.run.children.length, 0);
  }
});

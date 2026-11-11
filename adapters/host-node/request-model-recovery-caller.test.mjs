import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Actual Host assembly with explicit compiler/Request-manager ports. These
// cases issue no operational Ledger, Source read, Model send or cleanup ACK.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const declarations = new Map();
(function visit(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'FunctionDeclaration') declarations.set(node.id.name, node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
})(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
const body = name => {
  const node = declarations.get(name); assert.ok(node);
  return source.slice(node.start, node.end);
};

function fixture({plural = false, failAt, cause} = {}) {
  const prepared = {}, request = {}, compiled = {}, definition = {}, scope = {}, calls = [];
  const graphs = [{}, {}], occurrences = [{}, {}], bounds = [{}, {}];
  const restored = {compiled, runDefinition: definition, graph: plural ? Object.freeze(graphs) : graphs[0]};
  const selection = {graph: restored.graph, restoredRun: restored, occurrence: occurrences[0]};
  if (plural) selection.components = Object.freeze(graphs.map((graph, index) =>
    Object.freeze({graph, occurrence: occurrences[index]})));
  const plan = {compiled, runDefinition: definition, inferGraph: restored.graph};
  const earlyMockInferPlans = new WeakMap();
  const control = {checkRestoredClientInferRunOwner(value, owner) {
    assert.strictEqual(value, restored); assert.strictEqual(owner, prepared);
  }};
  const moon = {
    clientProgramAcquisitionCount(value) {assert.strictEqual(value, prepared); return 1;},
    clientProgramPreparedComposedInferBounds(occurrence, graph) {
      const index = occurrences.indexOf(occurrence); assert.ok(index >= 0);
      assert.strictEqual(graph, graphs[index]); calls.push('original bounds'); return {$tag: 1, _0: bounds[index]};
    },
    clientProgramComposedInferRetainedLimits(value) {
      assert.ok(bounds.includes(value));
      if (failAt === 'bounds') throw cause;
      return [11n, 12n, 13n, 14n, 15n, 16n, 17n, 18n, 19n];
    },
  };
  let originalModel;
  const view = Object.freeze({control, compiled, runDefinition: definition, selection,
    assertRuntimeCurrent() {calls.push('same current');}});
  const preparation = {
    admitResultPublicationRun(owner) {assert.strictEqual(owner, prepared); calls.push('same Result original');},
    modelPublicationCapacity() {assert.fail('No publication borrow during recovery selection');},
    prepareManagedModelRecoveryPlan(runtime, owner, identity, actualPlan, selected, model) {
      assert.strictEqual(runtime, moon); assert.strictEqual(owner, prepared); assert.strictEqual(identity, request);
      assert.strictEqual(actualPlan, plan); assert.strictEqual(selected, selection);
      assert.strictEqual(earlyMockInferPlans.get(prepared).model, model, 'Retain before the first Scope issuer');
      assert.strictEqual(model.compiled, compiled); assert.strictEqual(model.runDefinition, definition);
      originalModel = model;
      if (plural) {
        assert.deepEqual(model.budget, {maxReservations: 34, maxHoldings: 36, maxDelegations: 38});
        model.components.forEach((member, index) => {
          assert.strictEqual(member.group, model); assert.strictEqual(member.graph, graphs[index]);
          assert.strictEqual(member.selection, selection.components[index]);
        });
      }
      else assert.equal(model.budget.readRetainedBytes, 13n);
      calls.push('same Request Scope'); model.scope = scope;
      if (failAt === 'scope') throw cause;
      return view;
    },
  };
  const ports = {moon, control, preparation, earlyMockInferPlans,
    prepareSubmit: {originalInferRun: owner => owner === prepared ? restored : undefined},
    sourceFreeRequestIdentities: new WeakMap([[prepared, {requested: request}]]),
    inferSelections: new WeakMap([[prepared, selection]]),
    checked: value => {assert.equal(value.$tag, 1); return value._0;},
    clientOperationError: code => Object.assign(new Error(code), {code})};
  const select = Function(...Object.keys(ports), body('retainRequestModelBoundsAndBudget') +
    '\nreturn ' + body('prepareInstalledModelRecovery'))(...Object.values(ports));
  return {prepared, plan, selection, view, calls, scope,
    model: () => originalModel ?? earlyMockInferPlans.get(prepared)?.model,
    open: (owner = prepared, actualPlan = plan, selected = selection) => select(owner, actualPlan, selected)};
}

test('restored Model selection keeps the original Request and complete ordered graph inventory without another preparation', () => {
  for (const plural of [false, true]) {
    const f = fixture({plural});
    assert.strictEqual(f.open(), f.view); assert.strictEqual(f.open(), f.view);
    assert.equal(f.calls.filter(value => value === 'same Request Scope').length, 1);
    assert.equal(f.calls.filter(value => value === 'same Result original').length, 2);
    assert.equal(f.calls.filter(value => value === 'original bounds').length, plural ? 2 : 1);
    assert.throws(() => f.open({}, f.plan), /ForeignInstalledModelRecovery/u);
    assert.throws(() => f.open(f.prepared, {...f.plan, compiled: {}}), /ForeignInstalledModelRecovery/u);
    assert.throws(() => f.model().releaseAliases(), /InstalledModelCleanupPending/u);
  }
});

test('failed restored Scope retains its same partial parent and undefined primary without another issuer', () => {
  for (const cause of [undefined, new Error('OriginalScopeIssue')]) {
    const f = fixture({failAt: 'scope', cause});
    for (let attempt = 0; attempt < 2; attempt++) {
      let rejected = false;
      try {f.open();} catch (error) {rejected = true; assert.strictEqual(error, cause);}
      assert.equal(rejected, true);
    }
    assert.strictEqual(f.model().scope, f.scope);
    assert.equal(f.calls.filter(value => value === 'same Request Scope').length, 1);
    assert.equal(f.calls.filter(value => value === 'same Result original').length, 2);
    assert.throws(() => f.model().releaseAliases(), /InstalledModelCleanupPending/u);
    assert.notEqual(f.model().closed, true);
  }
});

test('failed restored budget projection is retained before Scope entry and cannot be selected again', () => {
  const cause = new Error('OriginalBoundsIssue'), f = fixture({failAt: 'bounds', cause});
  for (let attempt = 0; attempt < 2; attempt++) assert.throws(f.open, error => error === cause);
  assert.ok(f.model()); assert.equal(f.calls.filter(value => value === 'same Request Scope').length, 0);
  assert.equal(f.calls.filter(value => value === 'original bounds').length, 1);
});

test('single Model request keeps its original checked Source coordinates at selection before capture', () => {
  let requestNode;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type==='VariableDeclarator' && node.id.name==='requestOf') requestNode=node.init;
    for(const value of Object.values(node)) {
      if(Array.isArray(value))value.forEach(visit);
      else if(value&&typeof value==='object')visit(value);
    }
  })(parse(source,{ecmaVersion:'latest',sourceType:'module'}));
  assert(requestNode);
  const prepared={},identity={},occurrence={},selectedSource={},coordinates=Object.freeze([Object.freeze([4,6,0])]);
  let selected=0;
  const ports={prepareSubmit:{assertOwned(actual){assert.equal(actual,prepared);},kindOf:()=> 'effect_free'},
    moon:{clientProgramAcquisitionCount:()=>1,clientProgramSelectSingleKeyedAcquisition:()=>({$tag:1,_0:undefined}),
      clientProgramSelectedSourceInputKind:()=> 'query',clientProgramSelectedSourceInputRef:()=> 'original-source',
      clientProgramComposedInferOccurrences:()=>({$tag:1,_0:[occurrence]}),clientProgramResultCount:()=>1,clientProgramResultName:()=> 'answer'},
    checked:value=>value._0,sourceProfile:{},originalSourceFreeRequest:()=>identity,earlyContentPlans:new WeakMap(),
    preparation:{managedModelSourceCoordinates:()=>coordinates,selectManagedDomainSourceInput(runtime,p,request,stage,input) {
      assert.equal(p,prepared);assert.equal(request,identity);assert.equal(stage,4);assert.equal(input,6);return selectedSource;
    }},installedSourceFor:()=>({}),runtimeIsOkRequired:value=>value.$tag===1,runtimeField:value=>value._0,
    inferSelections:new WeakMap(),prepareInferSelection(p,o,retain,actualCoordinates) {
      assert.equal(p,prepared);assert.equal(o,occurrence);assert.equal(retain,true);assert.equal(actualCoordinates,coordinates);selected++;
    },clientOperationError:code=>new Error(code)};
  const requestOf=Function(...Object.keys(ports),'return ('+source.slice(requestNode.start,requestNode.end)+');')(...Object.values(ports));
  const result=requestOf({preparedProgram:prepared,requestId:'original-request'});
  assert.equal(result.requested,identity);assert.equal(selected,1);
});

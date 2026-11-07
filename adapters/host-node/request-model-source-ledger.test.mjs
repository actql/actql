// Execute the actual pre-acquisition dispatch branch with explicit native
// Resource/Source ports; no nominal grant or physical Source is issued here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {installNodeInferRun} from './installed-infer-run.mjs';

function mockLedgerFixture({retireDuringBorrow = false} = {}) {
  const mockSource = readFileSync(new URL('../local-node/installed-project-mock.mjs', import.meta.url), 'utf8');
  const functions = new Map();
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration') functions.set(node.id.name, node);
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  })(parse(mockSource, {ecmaVersion: 'latest', sourceType: 'module'}));
  const prepared = {}, request = {}, native = {}, original = {}, scope = {}, ledger = {}, calls = [];
  const control = {checkClientCompiledRunOwner(c, p) {
    assert.strictEqual(c, plan.compiled); assert.strictEqual(p, prepared);
  }};
  const plan = {compiled: {}, runDefinition: {}, inferGraph: {}};
  const selected = {localMock: true, graph: plan.inferGraph, occurrence: {}};
  const records = new Map();
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const sameRun = p => {assert.strictEqual(p, prepared); return records.get(p);};
  const checked = result => {assert.equal(result.$tag, 1); return result._0;};
  const capacities = [{managedRun: native, capacity: {}, transferBytes: 31n, executionBytes: 41n},
    {managedRun: native, capacity: {}, transferBytes: 51n, executionBytes: 61n}];
  const registry = {}, values = {}, fragment = {}, ordered = {}, setup = {}, sources = [{}, {}];
  const moon = {clientProgramAcquisitionCount: () => 2,
    clientProgramOpenInstalledManagedCaptureHost(parent, p, r, actualSources) {
      assert.strictEqual(parent, native); assert.strictEqual(p, prepared); assert.strictEqual(r, request);
      assert.deepEqual(actualSources, sources); calls.push('same Plan Host'); return {$tag: 1, _0: setup};
    },
    clientProgramInstalledManagedRunPrepareLedger(...args) {
      calls.push('original Ledger');
      assert.deepEqual(args, [native, prepared, request, capacities.map(v => v.capacity),
        [31n, 51n], [41n, 61n], registry, values, fragment, ordered]);
      if (retireDuringBorrow) records.get(prepared).model.closed = true;
      return {$tag: 1, _0: ledger};
    }};
  const ports = {current() {}, records, sameRun, fail, checked, moon,
    prepareRequestModel(p, r, model) {
      assert.strictEqual(p, prepared); assert.strictEqual(r, request); calls.push('adopt Model');
      model.scope = scope; model.budget = {}; model.component = {bindOriginal() {}};
      return {original, value: native};
    }};
  const extract = name => {
    const node = functions.get(name); assert(node);
    return Function(...Object.keys(ports), `return (${mockSource.slice(node.start, node.end)});`)(...Object.values(ports));
  };
  const adopt = extract('prepareManagedMockModelRun'), preparation = extract('modelPreparation');
  const run = installNodeInferRun({moon, core: {publicationControl: control}, registry, values, fragment, ordered,
    selections: new Map([[prepared, selected]]), prepareOriginalMockRun(p, actual) {
      assert.strictEqual(p, prepared); assert.strictEqual(actual, plan); return preparation(p, actual);
    }});
  return {prepared, request, native, plan, selected, control, capacities, ledger, calls, records,
    setup, captures: sources.map(value => ({capture: {source: () => value}})),
    view: () => preparation(prepared, plan),
    adopt: () => adopt(prepared, request, control, plan, selected, () => {}),
    borrow: (sourceCapacities = capacities) => run.prepareAcquiredLedger({preparedProgram: prepared, plan, sourceCapacities})};
}

test('Mock Model dispatch uses the same adopted parent and one original two-Source Ledger', () => {
  const f = mockLedgerFixture();
  assert.strictEqual(f.adopt(), f.native); assert.strictEqual(f.adopt(), f.native);
  assert.strictEqual(f.borrow(), f.ledger);
  assert.strictEqual(f.records.get(f.prepared).model.sourceLedger, f.ledger);
  assert.throws(() => f.borrow(), /InstalledModelSourceLedgerAlreadyBorrowed/);
  assert.deepEqual(f.calls, ['adopt Model', 'original Ledger']);
});

test('Mock captured Model opens only its retained Plan after the original Scope is retained', () => {
  const f = mockLedgerFixture(); f.adopt(); const view = f.view();
  assert.throws(() => view.openCapturedHost(f.captures), /InstalledComposedInferHostUnavailable/);
  view.retain();
  assert.throws(() => view.openCapturedHost(f.captures.slice(0, 1)), /InstalledComposedInferHostUnavailable/);
  assert.strictEqual(view.openCapturedHost(f.captures), f.setup);
  assert.throws(() => view.openCapturedHost(f.captures), /InstalledComposedInferHostUnavailable/);
  assert.deepEqual(f.calls, ['adopt Model', 'same Plan Host']);
});

test('Mock Model Ledger refuses a foreign Source and retains post-callback retirement without reborrowing', () => {
  const foreign = mockLedgerFixture(); foreign.adopt();
  assert.throws(() => foreign.borrow([{...foreign.capacities[0], managedRun: {}}, foreign.capacities[1]]),
    /InvalidInstalledMockModelPreparation/);
  assert.deepEqual(foreign.calls, ['adopt Model']);
  const f = mockLedgerFixture({retireDuringBorrow: true}); f.adopt();
  assert.throws(() => f.borrow(), /ForeignInstalledModelPreparation/);
  assert.strictEqual(f.records.get(f.prepared).model.sourceLedger, undefined);
  assert.equal(f.calls.filter(v => v === 'original Ledger').length, 1);
  assert.throws(() => f.borrow(), /InvalidInstalledMockModelPreparation/);
  assert.equal(f.calls.filter(v => v === 'original Ledger').length, 1);
});

test('Mock submit retains the actual returned parent for its existing dispatch comparison', () => {
  const f = mockLedgerFixture();
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const branches = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && text.slice(node.test.start, node.test.end) === 'selectedModel?.localMock') branches.push(node);
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  })(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(branches.length, 1);
  const body = text.slice(branches[0].consequent.start, branches[0].consequent.end);
  const ports = {selectedModel: f.selected, submission: {preparedProgram: f.prepared}, requested: f.request,
    earlyMockInferPlans: new Map([[f.prepared, {plan: f.plan}]]), control: f.control,
    sourceProfile: {prepareManagedMockModelRun(p, r, c, plan, selected) {
      assert.strictEqual(p, f.prepared); assert.strictEqual(r, f.request); assert.strictEqual(c, f.control);
      assert.strictEqual(plan, f.plan); assert.strictEqual(selected, f.selected); return f.adopt();
    }}, preparation: {modelPublicationCapacity() {assert.fail('not borrowed before dispatch');}},
    clientOperationError() {assert.fail('the original plan is present');}};
  const actual = Function(...Object.keys(ports), `let managedSourceRun;${body};return managedSourceRun;`)(...Object.values(ports));
  assert.strictEqual(actual, f.native); assert.deepEqual(f.calls, ['adopt Model']);
});
const source = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
let branch, selection;
const walk = (node, parents = []) => {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'CallExpression' && node.callee?.object?.name === 'runContent' &&
      node.callee.property?.name === 'prepareAcquiredLedger') {
    branch = parents.find(p => p.type === 'IfStatement' &&
      source.slice(p.test.start, p.test.end).includes('generatingContent'));
  }
  if (node.type === 'VariableDeclaration' && node.declarations[0]?.id?.name === 'requestModelAcquired') selection = node;
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(child => walk(child, [node, ...parents]));
    else if (value && typeof value === 'object') walk(value, [node, ...parents]);
  }
};
walk(ast); assert(branch);
const body = (selection ? source.slice(selection.start, selection.end) : '') + '\n' + source.slice(branch.start, branch.end);

test('plain Request Model dispatch borrows its same adopted Source Ledger before physical acquisition', async () => {
  const nativeParent = {}, prepared = {}, plan = {}, request = {}, access = {}, preparedSource = {},
    capacity = Object.freeze({managedRun: nativeParent}), ledger = {}, entry = {};
  const held = {managedRun: nativeParent, plan, preparedSource, preparedSourceAccess: access};
  const calls = [], installedSource = {sourceAccess: access, ledgerCapacity(actual) {
    assert.strictEqual(actual, preparedSource); calls.push('capacity'); return capacity;
  }};
  const ports = {held, entry, preparedProgram: prepared, requested: request, inferring: true,
    generatingContent: false, acquiring: true, multiple: false, keyedSelection: undefined,
    installedSource, checkpoints: undefined, submission: {requestId: 'fixture-request'},
    preparationLease: {}, moon: {},
    prepareAcquisition() {assert.fail('do not reconstruct the retained original Source');},
    retainDispatchPreparationHost(actualEntry, _moon, actualParent, actualPrepared, actualRequest, custody) {
      assert.strictEqual(actualEntry, entry); assert.strictEqual(actualParent, nativeParent);
      assert.strictEqual(actualPrepared, prepared); assert.strictEqual(actualRequest, request);
      assert.equal(custody, true); calls.push('same parent borrow');
    },
    runContent: {prepareAcquiredLedger() {assert.fail('plain Model has no Content prefix');}},
    runInfer: {prepareAcquiredLedger(actual) {
      assert.deepEqual(actual, {preparedProgram: prepared, plan, sourceCapacity: capacity});
      calls.push('same Model Ledger'); return ledger;
    }}};
  const run = Function(...Object.keys(ports), `return (async () => {let ledger;${body};return ledger;})();`);
  assert.strictEqual(await run(...Object.values(ports)), ledger);
  assert.deepEqual(calls, ['same parent borrow', 'capacity', 'same Model Ledger']);
  assert.strictEqual(entry.acquisitionLedger, ledger);
  assert.equal(entry.borrowedSources, true);
});


function modelLedgerFixture({retire = false, throwOriginal = false, cause, multiple = false} = {}) {
  const prepared = {}, compiled = {}, definition = {}, graph = {}, native = {}, request = {}, ledger = {},
    registry = {}, values = {}, fragment = {}, ordered = {}, capacity = {}, calls = [];
  const plan = {compiled, runDefinition: definition, inferGraph: graph};
  const selected = multiple ? {graph, components: Object.freeze([{}, {}])} : {graph, occurrence: {}, originalReadInstallation: {}};
  const managed = {value: native, request, closed: false};
  const model = {graph, compiled, runDefinition: definition, selection: selected, managed, component: {}, scope: {}};
  if (multiple) model.components = Object.freeze(selected.components.map(() => ({component: {}, scope: {}})));
  const sourceCapacity = {managedRun: native, capacity, transferBytes: 512n, executionBytes: 256n};
  const sourceCapacities = multiple ? [sourceCapacity, {managedRun: native, capacity: {}, transferBytes: 31n, executionBytes: 41n}] : [sourceCapacity];
  const moon = {clientProgramAcquisitionCount: () => sourceCapacities.length,
    clientProgramInstalledManagedRunPrepareLedger(...actual) {
      calls.push('original Ledger');
      assert.deepEqual(actual, [native, prepared, request, sourceCapacities.map(value => value.capacity),
        sourceCapacities.map(value => value.transferBytes), sourceCapacities.map(value => value.executionBytes), registry, values, fragment, ordered]);
      if (retire) managed.closed = true;
      if (throwOriginal) throw cause;
      return {$tag: 1, _0: ledger};
    }};
  const control = {checkClientCompiledRunOwner(c, p) {assert.strictEqual(c, compiled); assert.strictEqual(p, prepared);}};
  const run = installNodeInferRun({moon, core: {publicationControl: control}, registry, values, fragment, ordered,
    selections: new WeakMap([[prepared, selected]]),
    prepareOriginalModelRun(p, actualPlan, actualSelected) {
      assert.strictEqual(p, prepared); assert.strictEqual(actualPlan, plan); assert.strictEqual(actualSelected, selected);
      return model;
    }});
  return {model, sourceCapacity, sourceCapacities, ledger, calls,
    borrow: actual => run.prepareAcquiredLedger({preparedProgram: prepared, plan,
      ...(multiple ? {sourceCapacities: actual ?? sourceCapacities} : {sourceCapacity: actual ?? sourceCapacity})})};
}

test('actual installed Model Source getter borrows the same adopted Ledger once without a second Root', () => {
  const f = modelLedgerFixture();
  assert.strictEqual(f.borrow(), f.ledger); assert.strictEqual(f.model.sourceLedger, f.ledger);
  assert.throws(() => f.borrow(), /InstalledModelSourceLedgerAlreadyBorrowed/);
  assert.deepEqual(f.calls, ['original Ledger']);
});

test('actual installed Model Source getter refuses foreign parent and does not resurrect an alias after callback retirement', () => {
  const foreign = modelLedgerFixture();
  assert.throws(() => foreign.borrow({...foreign.sourceCapacity, managedRun: {}}), /InvalidInstalledRequestModelPreparation/);
  assert.deepEqual(foreign.calls, []);
  const f = modelLedgerFixture({retire: true});
  assert.throws(() => f.borrow(), /InvalidInstalledRequestModelPreparation/);
  assert.strictEqual(f.model.sourceLedger, undefined); assert.deepEqual(f.calls, ['original Ledger']);
});

test('actual installed Model Source getter latches the exact original throwable without another native borrow', () => {
  for (const cause of [undefined, null, Object.freeze({issue: 'OriginalSourceLedgerFailure'})]) {
    const f = modelLedgerFixture({throwOriginal: true, cause});
    for (let attempt = 0; attempt < 2; attempt++) {
      let caught = false;
      try {f.borrow();} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
      assert.equal(caught, true);
    }
    assert.equal(Object.hasOwn(f.model, 'sourceLedgerFailure'), true);
    assert.strictEqual(f.model.sourceLedgerFailure, cause); assert.deepEqual(f.calls, ['original Ledger']);
  }
});

const inferSource = readFileSync(new URL('./installed-infer-run.mjs', import.meta.url), 'utf8');
const inferAst = parse(inferSource, {ecmaVersion: 'latest', sourceType: 'module'});
let cleanupBody;
const findCleanup = value => {
  if (!value || typeof value !== 'object') return;
  if (value.type === 'VariableDeclarator' && value.id?.name === 'cleanupOwned') cleanupBody = value.init;
  for (const field of Object.values(value)) {
    if (Array.isArray(field)) field.forEach(findCleanup);
    else if (field && typeof field === 'object') findCleanup(field);
  }
};
findCleanup(inferAst); assert(cleanupBody);

test('same Model cleanup keeps the first nullable physical failure while retaining both original children', async () => {
  for (const primary of [undefined, null]) {
    const events = [], secondary = new Error('later continuation failure');
    const ports = {captureOwner: {custody: {async close() {events.push('capture'); throw primary;}}},
      continuation: {async close() {events.push('continuation'); throw secondary;}}};
    const run = Function(...Object.keys(ports), `let evidenceCopy,composedExecution,operation,token,contentChild,keyedContentChild,originalPreparation;
      let captureReleased=false,captureCloseAttempted=false,continuationReleased=false,continuationCloseAttempted=false;
      const modelController={release(){throw Error('failed child remains retained');}};
      const cleanupPending=()=>true;return (${inferSource.slice(cleanupBody.start, cleanupBody.end)})();`);
    let caught = false;
    try {await run(...Object.values(ports));} catch (actual) {caught = true; assert.strictEqual(actual, primary);}
    assert.equal(caught, true); assert.deepEqual(events, ['capture', 'continuation']);
  }
});


test('fixed Node entry forwards only the original installed cleanup envelope beside its captured runtime composition', async () => {
  const text = readFileSync(new URL('./entry.mjs', import.meta.url), 'utf8');
  const node = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.declaration ?? node).find(node => node.type === 'FunctionDeclaration' && node.id.name === 'createNodeHostEntry');
  assert(node);
  const native = {}, holder = {}, owner = {}, setup = {}, signal = new AbortController().signal;
  const cleanup = Object.freeze({preparationHolder: holder, retainPreflightCleanup(actual) {assert.strictEqual(actual, owner);}});
  const poison = {preparationHolder: {}, retainPreflightCleanup() {assert.fail('Program options are not installed custody');}};
  let loads = 0;
  const install = () => assert.fail('this Source test does not install a runtime');
  const entry = Function('runCapturedStrategyTarget', `return (${text.slice(node.start, node.end)});`)(facts => {
    assert.strictEqual(facts.setup, setup); assert.strictEqual(facts.control.signal, signal);
    assert.strictEqual(facts.cleanup, cleanup); assert.strictEqual(facts.composition.install, install);
    assert.notStrictEqual(facts.cleanup, facts.options.cleanup);
    facts.cleanup.retainPreflightCleanup(owner); return facts;
  })(async () => {loads++; return native;}, install);
  const facts = entry.runCapturedStrategy(setup, {cleanup: poison}, signal, undefined, cleanup);
  assert.equal(loads, 0);
  assert.strictEqual(await facts.composition.loadRuntime(), native);
  assert.strictEqual(await facts.composition.loadRuntime(), native); assert.equal(loads, 1);
});


test('actual composed driver retains the known first nullable component failure rather than a secondary execution projection', async () => {
  const text = readFileSync(new URL('./installed-composed-infer-run.mjs', import.meta.url), 'utf8');
  let failed;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && node.test?.type === 'BinaryExpression' &&
        node.test.left?.object?.name === 'execution' && node.test.left.property?.name === 'status' &&
        node.test.right?.value === 'host-tasks-completed') failed = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(failed);
  const run = Function('children', 'execution', 'modelController', `const runId='fixture-run';return (async () => {${text.slice(failed.start, failed.end)}})();`);
  for (const cause of [undefined, null]) {
    const component = {hasFailure: () => true, failure: () => cause};
    let caught = false;
    try {await run([{component}], {status: 'host-tasks-failed', failure: new Error('secondary execution')},
      {unresolved: () => false});} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
    assert.equal(caught, true);
  }
});


test('complete Model Source getter borrows all original captures from the same adopted Ledger once', () => {
  const f = modelLedgerFixture({multiple: true});
  assert.equal(f.borrow(), f.ledger); assert.equal(f.model.sourceLedger, f.ledger);
  assert.throws(f.borrow, /InstalledModelSourceLedgerAlreadyBorrowed/);
  assert.deepEqual(f.calls, ['original Ledger']);
  const foreign = modelLedgerFixture({multiple: true});
  assert.throws(() => foreign.borrow([foreign.sourceCapacities[0], {...foreign.sourceCapacities[1], managedRun: {}}]),
    /InvalidInstalledRequestModelPreparation/);
  assert.deepEqual(foreign.calls, []);
});

test('complete Model Source getter retains same-parent current loss and sticky original failure without another borrow', () => {
  const changed = modelLedgerFixture({multiple: true, retire: true});
  assert.throws(changed.borrow, /InvalidInstalledRequestModelPreparation/);
  assert.equal(changed.model.sourceLedger, undefined); assert.deepEqual(changed.calls, ['original Ledger']);
  const f = modelLedgerFixture({multiple: true, throwOriginal: true, cause: undefined});
  for (let index = 0; index < 2; index++) {
    let caught = false;
    try {f.borrow();} catch (cause) {assert.equal(cause, undefined); caught = true;}
    assert(caught);
  }
  assert.deepEqual(f.calls, ['original Ledger']);
});


test('actual complete Model Source preparation carries checked nonzero Stage and input coordinates into every original adapter', async () => {
  const host = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(host, {ecmaVersion: 'latest', sourceType: 'module'}), found = new Map();
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && ['modelSourceOccurrence', 'prepareAcquisitions'].includes(node.id?.name)) {
      assert(!found.has(node.id.name)); found.set(node.id.name, node.init);
    }
    for (const child of Object.values(node)) {if (Array.isArray(child)) child.forEach(visit); else if (child && typeof child === 'object') visit(child);}
  };
  visit(ast); assert.equal(found.size, 2);
  const prepared = {}, coordinates = Object.freeze([Object.freeze([4, 1, 0]), Object.freeze([6, 2, 1])]),
    selected = new WeakMap([[prepared, {sourceCoordinates: coordinates}]]), calls = [], sources = [{checkedSource: {sourceRef: 'first'}}, {checkedSource: {sourceRef: 'second'}}], adapters = [{sourceAccess: {}}, {sourceAccess: {}}];
  const node = found.get('modelSourceOccurrence');
  const occurrence = Function('inferSelections', 'return '+host.slice(node.start, node.end))(selected);
  const ports = {moon: {clientProgramAcquisitionCount(p) {assert.equal(p, prepared); return 2;}}, modelSourceOccurrence: occurrence,
    prepareAcquisition(p, access, original) {
      assert.equal(p, prepared); assert.equal(access, undefined);
      assert.deepEqual(original, {stage: coordinates[original.task][0], input: coordinates[original.task][1], task: original.task});
      assert(Object.isFrozen(original)); calls.push(original); return sources[original.task];
    }, installedSourceFor(_profile, ref) {return adapters[ref === 'first' ? 0 : 1];}, sourceProfile: {},
    capturedDuckDBConfiguration() {assert.fail('No reconstruction of unchanged query selection');},
    clientOperationError: code => Object.assign(new Error(code), {code})};
  const construct = found.get('prepareAcquisitions');
  const prepare = Function(...Object.keys(ports), 'return '+host.slice(construct.start, construct.end))(...Object.values(ports));
  const result = await prepare(prepared);
  assert.equal(result.length, 2); assert(Object.isFrozen(result));
  result.forEach((value, index) => {assert.equal(value.prepared, sources[index]); assert.equal(value.adapter, adapters[index]); assert.equal(value.occurrence, calls[index]);});
});

test('actual complete Model dispatcher retains its original Run before borrowing both Source slots and never selects a legacy Ledger', () => {
  let selected;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && source.slice(node.test.start, node.test.end).startsWith('capacities.some(')) {
      assert(!selected); selected = node;
    }
    for (const child of Object.values(node)) {if (Array.isArray(child)) child.forEach(visit); else if (child && typeof child === 'object') visit(child);}
  };
  visit(ast); assert(selected);
  const managed = {}, prepared = {}, request = {}, plan = {}, ledger = {}, entry = {},
    capacities = [{managedRun: managed, capacity: {}}, {managedRun: managed, capacity: {}}], calls = [], held = {managedRun: managed, plan};
  const ports = {capacities, managedRun: managed, held, preparedProgram: prepared, requested: request,
    registry: {}, values: {}, fragment: {}, ordered: {}, entry, preparationLease: {}, inferring: true,
    moon: {clientProgramInstalledManagedRunPrepareLedger() {assert.fail('Use the original Model getter with its sticky custody');},
      clientProgramPrepareMultiCapturedLocalInstalledLedger() {assert.fail('No legacy Model Ledger');}},
    checked: value => value,
    retainDispatchPreparationHost(e, _moon, value, p, r, owned) {
      assert.equal(e, entry); assert.equal(value, managed); assert.equal(p, prepared); assert.equal(r, request);
      assert.equal(owned, true); calls.push('same parent borrow');
    }, runInfer: {prepareAcquiredLedger(args) {
      assert.deepEqual(args, {preparedProgram: prepared, plan, sourceCapacities: capacities});
      calls.push('both original Source slots'); return ledger;
    }}};
  const run = Function(...Object.keys(ports), 'let ledger;'+source.slice(selected.start, selected.end)+';return ledger;');
  assert.equal(run(...Object.values(ports)), ledger); assert.equal(entry.borrowedSources, true);
  assert.deepEqual(calls, ['same parent borrow', 'both original Source slots']);
  capacities[1].managedRun = {};
  assert.throws(() => run(...Object.values(ports)), /InstalledMultiSourceOriginalRunUnavailable/);
  assert.deepEqual(calls, ['same parent borrow', 'both original Source slots']);
});

// Execute the existing installed caller with explicit original Core ports. The
// source-only fixture stops at the real kernel constructor boundary; it grants
// no physical resources and claims neither provider IO nor ordinary success.
function directCapturedModelFixture({taskCount = 1, retireBeforeRead = false, retireDuringSource = false} = {}) {
  const source = readFileSync(new URL('./installed-infer-run.mjs', import.meta.url), 'utf8');
  const declarations = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.declaration ?? node).filter(node => node.type === 'FunctionDeclaration');
  const bodies = ['sourceFreeModelPreparation', 'installNodeInferRun'].map(name => {
    const node = declarations.find(node => node.id.name === name); assert(node);
    return source.slice(node.start, node.end);
  }).join('\n');
  const calls = [], prepared = {}, graph = {}, occurrence = {}, scope = {}, read = {}, ledger = {},
    parent = {}, request = {}, provider = {}, prefix = {}, evidence = {}, capture = {source() {return originalSource;}},
    originalSource = {}, captured = {capture}, managed = {value: parent, request, prepared}, component = {bindOriginal() {
      assert.fail('A direct original Model kernel is not a completed captured DAG task');
    }}, budget = {readRetainedBytes: 11n, readExecutionBytes: 13n,
      modelRetainedBytes: 17n, modelExecutionBytes: 19n};
  const plan = {compiled: {}, runDefinition: {wire: '{"run_id":"direct-model-fixture"}'}, inferGraph: graph};
  const selected = {graph, occurrence, computePrefix: prefix, provider};
  const checkpoints={},submission={},preparedSource={},adapter={},approval={},
    sourceOccurrence=Object.freeze({stage:0,input:0,task:0}),sourceEvidenceWire='original-source-evidence',
    sourceAccess={originalCheckpointApproval:()=>approval},sourceCustody=[];
  let sourceClosed=false;
  const model = {prepared, selection: selected, control: undefined, compiled: plan.compiled,
    runDefinition: plan.runDefinition, graph, scope, budget, component, managed,
    sourceLedger: ledger, publicationCapacity() {return {};}};
  managed.model = model;
  const primary = new Error('actual direct kernel boundary');
  const wrong = new Error('captured DAG route');
  const control = {
    prepareCheckedClientInferOriginalRead(c, d, g, s, b) {
      assert.deepEqual([c, d, g, s, b], [plan.compiled, plan.runDefinition, graph, scope, budget]);
      calls.push('same read'); return read;
    },
    admitComposedInferSources(o, originals, proofs, authority, started, completed) {
      assert.strictEqual(o, occurrence); assert.deepEqual(originals, [captured]);
      assert.deepEqual(proofs, [evidence]); assert.equal(authority, 'authored-authority');
      assert.equal(started, 'authored-start'); assert.equal(completed, 'authored-end');
      calls.push('same Source evidence'); if (retireDuringSource) model.closed = true; return originalSources;
    },
    finishCheckedClientInferOriginalReadScope(c, d, g, s, stopped) {
      assert.deepEqual([c, d, g, s, stopped], [plan.compiled, plan.runDefinition, graph, scope, true]);
      assert.equal(sourceClosed,true,'original Source closure retires before Model Scope');
      calls.push('same Scope finish'); return true;
    },
  };
  model.control = control;
  const originalSources = {};
  const moon = {clientProgramAcquisitionCount: p => {assert.strictEqual(p, prepared); return 1;},
    clientProgramTaskCount: p => {assert.strictEqual(p, prepared); return taskCount;},
    clientProgramResultCount:p=>{assert.equal(p,prepared);return 1;},
    clientProgramResultName:(p,index)=>{assert.equal(p,prepared);assert.equal(index,0);return 'answer';},
    clientProgramInstalledManagedRunModelInputPrefix(run, p) {
      assert.strictEqual(run, parent); assert.strictEqual(p, prepared);
      calls.push('same original prefix'); return {$tag: 1, _0: prefix};
    },
    clientProgramSelectSingleKeyedAcquisition: () => ({$tag: 1, _0: undefined}),
    clientProgramInferPlanBoundary: g => {assert.strictEqual(g, graph); return {_0: 0};}};
  managed.runtime = moon;
  const ports = {runtimeField: (v, i) => v[`_${i}`], checked: v => {assert.equal(v.$tag, 1);return v._0;},
    runInstalledComposedInfers: () => {throw wrong;},
    // Same explicit Source-continuation ports as the fresh singleton caller
    // fixture. They qualify identity/order, not a physical Checkpoint or grant.
    acquiredEffectContinuation(options) {
      assert(cleanup,'retain Model cleanup before Source construction');
      assert.equal(options.checkpoints,checkpoints);assert.equal(options.submission,submission);
      assert.equal(options.moon,moon);assert.equal(options.acquired.prepared,prepared);
      assert.equal(options.acquired.runDefinition,plan.runDefinition);assert.equal(options.acquired.control,control);
      assert.deepEqual(options.declaredResults,['answer']);assert.equal(options.unitId,'composed-source-input');
      assert.equal(options.restore,undefined);assert.equal(options.currentRun(),true);
      const sameSource=item=>{
        assert.equal(item.occurrence,sourceOccurrence);assert.equal(item.preparedSource,preparedSource);
        assert.equal(item.adapter,adapter);
      };
      return {
        accessFor(access,actualOccurrence) {
          assert.equal(access,sourceAccess);assert.equal(actualOccurrence,sourceOccurrence);sourceCustody.push('access');
        },
        async prepared(items) {assert.equal(items.length,1);sameSource(items[0]);sourceCustody.push('prepared');},
        async captured(item,actual,wire,start,end,originalApproval) {
          sameSource(item);assert.equal(actual,captured);assert.equal(wire,sourceEvidenceWire);
          assert.equal(start,'authored-start');assert.equal(end,'authored-end');assert.equal(originalApproval,approval);
          sourceCustody.push('captured');
        },
        async close() {assert.equal(sourceClosed,false);sourceClosed=true;sourceCustody.push('close');return true;},
        beforeRead:()=>assert.fail('no second Source read'),
        retainAll:()=>assert.fail('fixture stops before Model checkpoint publication'),
      };
    },
    retireNodeInferOriginalRead: value => {assert.strictEqual(value, model);
      if (model.read !== undefined) assert.strictEqual(model.read, read);
      calls.push('same read retirement');},
    openNodeInferOperation(options) {
      assert.strictEqual(options.originalPreparation.scope, scope);
      assert.strictEqual(options.originalPreparation.read, read);
      assert.strictEqual(options.provider, provider);
      assert.equal(options.acquiredInput, undefined);
      assert.deepEqual(options.composedInput, {occurrence, prefix, inputs: [], sources: originalSources});
      calls.push('same original kernel'); throw primary;
    }};
  const install = Function(...Object.keys(ports), `${bodies}\nreturn installNodeInferRun;`)(...Object.values(ports));
  let cleanup;
  const run = install({moon, core: {publicationControl: control}, selections: new Map([[prepared, selected]]),
    checkpoints,
    authorityScopeCid: 'authored-authority', modelController: {discover: () => [], release() {}},
    prepareOriginalModelRun(p, actual, s) {
      assert.deepEqual([p, actual, s], [prepared, plan, selected]);
      if (retireBeforeRead) model.closed = true;
      return model;
    }});
  return {calls, primary, wrong, model, sourceCustody, run: () => run({preparedProgram: prepared, plan,submission,
    acquiredInfer: {managedRun: parent, ledger, captured, sourceEvidence: evidence,
      preparedSource,adapter,sourceAccess,occurrence:sourceOccurrence,sourceEvidenceWire,
      captureStartedAt: 'authored-start', captureCompletedAt: 'authored-end'},
    preparationHolder: {}, signal: new AbortController().signal,
    retainExecution(value) {cleanup = value;}}), cleanup: () => cleanup};
}

test('same-stage acquired Model uses its original kernel instead of publishing a captured DAG root', async () => {
  const f = directCapturedModelFixture();
  await assert.rejects(f.run(), error => error === f.primary);
  assert.deepEqual(f.calls, ['same Source evidence', 'same original prefix', 'same read', 'same original kernel']);
  assert.equal(await f.cleanup().close(), true);
  assert.deepEqual(f.calls.slice(-2), ['same read retirement', 'same Scope finish']);
  assert.deepEqual(f.sourceCustody,['access','prepared','captured','close']);
  assert.equal(f.cleanup().cleanupPending(), false);
});


test('separate-stage acquired Model keeps its existing captured DAG route', async () => {
  const f = directCapturedModelFixture({taskCount: 2});
  await assert.rejects(f.run(), error => error === f.wrong);
  assert.deepEqual(f.calls, []);
});

test('retired original same-stage Model cannot issue a read or enter the kernel', async () => {
  const f = directCapturedModelFixture({retireBeforeRead: true});
  await assert.rejects(f.run(), /InvalidInstalledRequestModelPreparation/);
  assert.deepEqual(f.calls, []);
  assert.equal(f.cleanup(), undefined);
});

test('same-stage Source admission reentry preserves the original pending Scope duty', async () => {
  const f = directCapturedModelFixture({retireDuringSource: true});
  await assert.rejects(f.run(), /InvalidInstalledRequestModelPreparation/);
  assert.deepEqual(f.calls, ['same Source evidence']);
  assert.equal(f.cleanup().cleanupPending(), true);
  await assert.rejects(f.cleanup().close(), /InvalidInstalledRequestModelPreparation/);
  assert.equal(f.cleanup().cleanupPending(), true);
  f.model.closed = false; // Explicit fixture makes only its original current again.
  assert.equal(await f.cleanup().cleanup(), true);
  assert.deepEqual(f.calls.slice(-2), ['same read retirement', 'same Scope finish']);
  assert.deepEqual(f.sourceCustody,['access','prepared','captured','close']);
});

function restoredComposedSourceFixture({missing, retireAfterFirst = false} = {}) {
  const source = readFileSync(new URL('./installed-composed-infer-run.mjs', import.meta.url), 'utf8');
  let branch;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && source.slice(node.test.start, node.test.end) ===
        'restoredSourceCount !== undefined && !sourceFree') {
      assert.equal(branch, undefined); branch = node;
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit); else if (child && typeof child === 'object') visit(child);
    }
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(branch);
  const prepared = {}, saved = {}, selected = [{}, {}], metadata = [{}, {}], adapters = [{}, {}],
    accesses = [{}, {}], calls = [], boundary = new Error('same continuation authorization boundary');
  const coordinates = [[4, 1, 0], [6, 2, 1]], token = {snapshot: {sourceContinuation: saved}};
  let current = true;
  const continuation = {
    accessFor(access, occurrence) {assert.equal(access, accesses[occurrence.task]); calls.push('same access');},
    async prepared(originals) {
      assert.deepEqual(originals.map(value => value.preparedSource), metadata);
      assert.deepEqual(originals.map(value => value.adapter), adapters);
      calls.push('same original continuation'); throw boundary;
    },
  };
  const original = {
    sourceCoordinates: coordinates, sourceLedger() {assert.fail('No physical restore before authorization');},
    prepareSource(occurrence, construct) {
      assert.deepEqual([occurrence.stage, occurrence.input, occurrence.task], coordinates[occurrence.task]);
      assert(Object.isFrozen(occurrence)); calls.push('same recovery reservation');
      return construct(selected[occurrence.task]);
    },
  };
  const ports = {restoredSourceCount: 2, sourceFree: false, originalPreparation: original,
    acquiredInfer: undefined, historical: {token}, children: [{token}, {token}],
    checkpoints: {}, submission: {}, declaredResults: [], principalId: 'fixture', signal: new AbortController().signal,
    runId: 'fixture', plan: {runDefinition: {identity: 'fixture'}}, preparedProgram: prepared, moon: {}, control: {},
    assertCurrent() {if (!current) throw boundary;}, canonicalJson: JSON.stringify,
    prepareAcquisition() {assert.fail('No fresh ManagedRun, Source or capture preparation');},
    prepareRetainedCaptureAcquisition(p, occurrence, source) {
      assert.equal(p, prepared); assert.equal(source, selected[occurrence.task]);
      calls.push('retained metadata'); if (retireAfterFirst) current = false;
      return metadata[occurrence.task];
    },
    sourceAdapterFor(value) {return adapters[metadata.indexOf(value)];},
    sourceAccessFor(value) {return accesses[metadata.indexOf(value)];},
    acquiredEffectContinuation(options) {
      assert.equal(options.restore.continuation, saved); assert.equal(options.acquired.prepared, prepared);
      calls.push('retain same continuation'); return continuation;
    },
  };
  if (missing === 'prepareSource') delete original.prepareSource;
  if (missing === 'prepareRetainedCaptureAcquisition') ports.prepareRetainedCaptureAcquisition = undefined;
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const run = new AsyncFunction(...Object.keys(ports),
    `let sourceContinuation;try {${source.slice(branch.consequent.start, branch.consequent.end)}}
     catch(error) {return {error, sourceContinuation};}throw new Error('Expected original boundary');`);
  return {run: () => run(...Object.values(ports)), calls, boundary, continuation};
}

test('restored composed Model uses its existing funded retained Source metadata path', async () => {
  const f = restoredComposedSourceFixture(), result = await f.run();
  assert.equal(result.error, f.boundary); assert.equal(result.sourceContinuation, f.continuation);
  assert.deepEqual(f.calls, ['retain same continuation', 'same recovery reservation', 'retained metadata',
    'same access', 'same recovery reservation', 'retained metadata', 'same access', 'same original continuation']);
});

test('restored composed Source missing ports or current loss never falls back to fresh preparation', async () => {
  for (const missing of ['prepareSource', 'prepareRetainedCaptureAcquisition']) {
    const f = restoredComposedSourceFixture({missing}), result = await f.run();
    assert.equal(result.error.message, 'ModelSourceClosureCustodyUnavailable');
    assert.equal(result.sourceContinuation, undefined); assert.deepEqual(f.calls, []);
  }
  const f = restoredComposedSourceFixture({retireAfterFirst: true}), result = await f.run();
  assert.equal(result.error, f.boundary); assert.equal(result.sourceContinuation, f.continuation);
  assert.deepEqual(f.calls, ['retain same continuation', 'same recovery reservation', 'retained metadata']);
});

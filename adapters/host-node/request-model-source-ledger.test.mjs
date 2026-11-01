// Execute the actual pre-acquisition dispatch branch with explicit native
// Resource/Source ports; no nominal grant or physical Source is issued here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {installNodeInferRun} from './installed-infer-run.mjs';
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


function modelLedgerFixture({retire = false, throwOriginal = false, cause} = {}) {
  const prepared = {}, compiled = {}, definition = {}, graph = {}, native = {}, request = {}, ledger = {},
    registry = {}, values = {}, fragment = {}, ordered = {}, capacity = {}, calls = [];
  const plan = {compiled, runDefinition: definition, inferGraph: graph};
  const selected = {graph, occurrence: {}, originalReadInstallation: {}};
  const managed = {value: native, request, closed: false};
  const model = {graph, compiled, runDefinition: definition, selection: selected, managed, component: {}, scope: {}};
  const sourceCapacity = {managedRun: native, capacity, transferBytes: 512n, executionBytes: 256n};
  const moon = {clientProgramAcquisitionCount: () => 1,
    clientProgramInstalledManagedRunPrepareLedger(...actual) {
      calls.push('original Ledger');
      assert.deepEqual(actual, [native, prepared, request, [capacity], [512n], [256n], registry, values, fragment, ordered]);
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
  return {model, sourceCapacity, ledger, calls,
    borrow: actual => run.prepareAcquiredLedger({preparedProgram: prepared, plan, sourceCapacity: actual ?? sourceCapacity})};
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

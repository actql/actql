import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';
import {boundSourceInventoryFixture} from './fixtures/ordinary-source-binding.fixture.mjs';

// The actual composed caller and continuation execute with explicit physical
// ports. These cases prove original forwarding, not a funded/installed Host.
function fixture({refuseSecond = false, single = false, retainedAdapter = true} = {}) {
  const calls = [], stopped = new Error('AfterOriginalSourceBinding');
  const refused = new Error('OriginalSourceOwnerRefused');
  let custody, setups = 0;
  const sources = boundSourceInventoryFixture().acquisitions.map((entry, index) => {
    const {stage, input, task, installationBinding, ...fields} = entry;
    const occurrence = Object.freeze({stage, input, task});
    const preparedSource = Object.freeze({...fields, occurrence});
    const adapter = Object.freeze({ordinaryRecoveryBinding(actual) {
      assert.strictEqual(this, adapter);
      assert.strictEqual(actual, preparedSource);
      calls.push(index);
      if (single) throw stopped;
      if (refuseSecond && index === 1) throw refused;
      return installationBinding;
    }});
    return {adapter, occurrence, preparedSource, access: {authorization: {}},
      captured: {capture: {source: () => ({index})}}, sourceEvidenceWire: 'original-evidence'};
  });
  const arguments_ = {
    moon: {
      clientProgramResultCount: () => 0,
      clientProgramOpenMultiCapturedComposedInferHost() {
        setups++;
        assert.deepEqual(calls, [0, 1]);
        throw stopped;
      },
    },
    control: {runDefinitionRunId: () => 'original-run'},
    preparedProgram: {}, plan: {runDefinition: {identity: 'original-definition', wire: '{"run_id":"original-run"}'}},
    selected: {components: []}, acquiredInfer: {sources, ledger: {},
      captureStartedAt: '2026-10-20T00:00:00.000Z', captureCompletedAt: '2026-10-20T00:00:01.000Z'},
    modelController: {discover: () => []}, checkpoints: {async retireComputationSources() {}},
    computeConfigurations: {}, signal: new AbortController().signal,
    retainExecution(value) {assert.equal(custody, undefined); custody = value;},
  };
  if (single) {
    arguments_.acquiredInfer = {captured: sources[0].captured, preparedSource: sources[0].preparedSource,
      ...(retainedAdapter ? {adapter: sources[0].adapter} : {}), sourceAccess: sources[0].access};
    arguments_.prepareAcquisition = () => assert.fail('reuse the original preparation');
    arguments_.sourceAccessFor = prepared => {assert.equal(prepared, sources[0].preparedSource); return sources[0].access;};
    arguments_.sourceAdapterFor = prepared => {assert.equal(prepared, sources[0].preparedSource); return sources[0].adapter;};
  }
  return {arguments_, calls, stopped, refused, setups: () => setups, custody: () => custody};
}

test('composed INFER forwards both original Source adapters before installing the driver', async () => {
  const f = fixture();
  await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.stopped);
  assert.deepEqual(f.calls, [0, 1]);
  assert.equal(f.setups(), 1);
  assert.equal(await f.custody().close(), true);
  assert.equal(f.custody().cleanupPending(), false);
});

test('composed INFER preserves the same Source owner refusal before driver work', async () => {
  const f = fixture({refuseSecond: true});
  await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.refused);
  assert.deepEqual(f.calls, [0, 1]);
  assert.equal(f.setups(), 0);
  assert.equal(await f.custody().close(), true);
});

for (const retainedAdapter of [true, false]) {
  test(`single composed INFER keeps its original Source adapter (retained=${retainedAdapter})`, async () => {
    const f = fixture({single: true, retainedAdapter});
    await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.stopped);
    assert.deepEqual(f.calls, [0]); assert.equal(f.setups(), 0);
    assert.equal(await f.custody().close(), true);
  });
}

test('single composed INFER refuses a missing original Source owner before binding or driver work', async () => {
  const f = fixture({single: true, retainedAdapter: false});
  delete f.arguments_.sourceAdapterFor;
  await assert.rejects(runInstalledComposedInfers(f.arguments_), {message: 'InstalledComposedInferSourceOwnerUnavailable'});
  assert.deepEqual(f.calls, []); assert.equal(f.setups(), 0);
  assert.equal(await f.custody().close(), true);
});

test('composed Model journal receives each original component Scope rather than its group holder', async () => {
  const text = readFileSync(new URL('./installed-composed-infer-run.mjs', import.meta.url), 'utf8');
  let childrenInitializer, journalCall;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === 'children') childrenInitializer = node.init;
    if (node.type === 'CallExpression' && node.callee?.object?.name === 'modelController' && node.callee.property?.name === 'open') journalCall = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(childrenInitializer && journalCall);
  const selected = {components: [{}, {}]}, originalComponents = [{scope: {}}, {scope: {}}], originalPreparation = {components: originalComponents};
  const children = Function('selected', 'completeOriginal', 'originalComponents', 'originalPreparation',
    'return '+text.slice(childrenInitializer.start, childrenInitializer.end))(selected, true, originalComponents, originalPreparation);
  const boundary = new Error('original component journal reached');
  for (let index = 0; index < children.length; index++) {
    const child = children[index], operation = {}, preparedCallSet = {};
    child.operation = operation;
    const modelController = {open(options) {
      assert.equal(options.operation, operation); assert.equal(options.selected, selected.components[index]);
      assert.equal(options.originalPreparation, originalComponents[index]);
      assert.notEqual(options.originalPreparation, originalPreparation); throw boundary;
    }};
    const names = ['modelController','child','preparedCallSet','plan','principalId','declaredResults',
      'submission','signal','originalPreparation','existingModel','modelClaim','sourceContinuation'];
    const invoke = Function(...names, 'return (async()=>'+text.slice(journalCall.start, journalCall.end)+')();');
    await assert.rejects(invoke(modelController, child, preparedCallSet, {}, 'fixture', [], {}, undefined,
      originalPreparation, undefined, undefined, undefined), error => error === boundary);
  }
});

test('cold composed segment preparation keeps the actual prepared occurrence and current fences', () => {
  const text = readFileSync(new URL('./installed-composed-infer-run.mjs', import.meta.url), 'utf8');
  let expression;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'prepareInputSegments') {
      assert.equal(expression, undefined); expression = text.slice(node.value.start, node.value.end);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit); else visit(value);
    }
  }
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(expression);
  for (const refusal of [undefined, 'before', 'after', 'lowering']) {
    const selected = {restoredRun: {}}, child = {selection: {occurrence: {}}};
    const prepared = {}, registry = {}, values = {}, fragment = {}, ordered = {}, segments = {_0: {}, _1: {}};
    const failure = new Error('OriginalSegmentsCurrentRefused'), events = [];
    let currentCalls = 0;
    const original = {assertRuntimeCurrent() {
      currentCalls++; events.push('original-current');
      if (refusal === 'before' && currentCalls === 1 || refusal === 'after' && currentCalls === 2) throw failure;
    }};
    const moon = {clientProgramPrepareComposedInferSegments(...actual) {
      assert.deepEqual(actual, [prepared, child.selection.occurrence, registry, values, fragment, ordered]);
      actual.forEach((value, index) => assert.strictEqual(value,
        [prepared, child.selection.occurrence, registry, values, fragment, ordered][index]));
      events.push('lower-once');
      if (refusal === 'lowering') throw failure;
      return {$tag: 1, _0: segments};
    }};
    const invoke = Function('selected', 'child', 'childOriginal', 'assertCurrent', 'checked', 'moon',
      'preparedProgram', 'registry', 'values', 'fragment', 'ordered', `return ${expression};`);
    const args = [selected, child, original, () => events.push('run-current'), result => result._0,
      moon, prepared, registry, values, fragment, ordered];
    const prepare = invoke(...args);
    if (refusal === undefined) {
      assert.strictEqual(prepare(), segments);
      assert.deepEqual(events, ['run-current', 'original-current', 'lower-once', 'original-current', 'run-current']);
    } else assert.throws(prepare, error => error === failure);
    if (refusal === 'before') assert.equal(events.includes('lower-once'), false);
    child.selection.computePrefix = {};
    assert.equal(invoke(...args), undefined, 'retain an already checked prefix without another lowering');
    child.selection.computePrefix = undefined; selected.restoredRun = undefined;
    assert.equal(invoke(...args), undefined, 'fresh input keeps its original installed segment owner');
  }
});

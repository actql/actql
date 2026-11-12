import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';

const source = readFileSync(new URL('../host-node/client-dispatch-owner.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const node = tree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'dispatchFailureSnapshot');
const snapshot = Function(`return (${source.slice(node.start, node.end)});`)();

test('managed advance keeps the exact checked result receiver primary and cleanup while adding closed DATA', () => {
  const result = {}, cleanupHandle = {};
  const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure', cleanupHandle});
  let projects = 0, checks = 0;
  const moon = {strategyModule_local_ManagedAdvanceFailureKind(value) {
    assert.strictEqual(this, moon); assert.strictEqual(value, result); projects++; return 'control_work';
  }};
  assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
    checks++; assert.strictEqual(value, result); throw primary;
  }, 7), error => error === primary);
  assert.equal(checks, 1); assert.equal(projects, 1);
  assert.strictEqual(primary.cleanupHandle, cleanupHandle);
  assert.deepEqual(primary.primaryDiagnostic, {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 7});
  assert(Object.isFrozen(primary.primaryDiagnostic));
  assert.deepEqual(snapshot(primary).primaryDiagnostic, primary.primaryDiagnostic);
});

test('managed advance success does not invoke a failure projector or create diagnostic DATA', () => {
  const result = {}, value = {};
  assert.strictEqual(checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceFailureKind() {
    assert.fail('successful yield or completion is not work refusal');
  }}, result, original => {assert.strictEqual(original, result); return value;}, 0), value);
});

test('managed advance refuses unclassified physical row workspace and foreign diagnostic reasons', () => {
  for (const kind of [undefined, 'execution', 'ExecutionLimit', 'retention', 'row', 'workspace', 'control_work.extra']) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceFailureKind() {return kind;}},
      {}, () => {throw primary;}, 0), error => error === primary);
    assert.equal(primary.primaryDiagnostic, undefined);
  }
  for (const task of [undefined, -1, 1.5, 2147483648]) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceFailureKind() {return 'control_work';}},
      {}, () => {throw primary;}, task), error => error === primary);
    assert.equal(primary.primaryDiagnostic, undefined);
  }
});

test('managed advance optional missing throwing or frozen diagnostics preserve every original thrown value', () => {
  for (const primary of [undefined, null, 7, new Error('untyped'),
    Object.freeze(Object.assign(new Error('frozen'), {code: 'MoonBitHostFailure'}))]) {
    for (const moon of [{}, {strategyModule_local_ManagedAdvanceFailureKind() {throw new Error('optional');}},
      {strategyModule_local_ManagedAdvanceFailureKind() {return 'control_work';}}]) {
      let threw = false;
      try {checkedLocalManagedAdvance(moon, {}, () => {throw primary;}, 0);}
      catch (error) {threw = true; assert.strictEqual(error, primary);}
      assert.equal(threw, true);
    }
  }
});

test('managed advance never invokes an original thrown code accessor', () => {
  let reads = 0;
  const original = Object.defineProperty(new Error('original'), 'code', {get() {reads++; return 'MoonBitHostFailure';}});
  assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceFailureKind() {return 'control_work';}},
    {}, () => {throw original;}, 0), error => error === original);
  assert.equal(reads, 0); assert.equal(original.primaryDiagnostic, undefined);
});

test('dispatch snapshot refuses misleading local-work DATA and retains the existing full Model diagnostic', () => {
  const data = {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 0};
  for (const foreign of [{...data, kind: 'execution'}, {...data, task: -1}, {...data, task: undefined},
    {...data, unit: 0}, {...data, unit: undefined}, {...data, step: 0}, {...data, code: 'Foreign'}]) {
    assert.equal(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: foreign})).primaryDiagnostic, undefined);
  }
  const accessor = Object.defineProperty(new Error('original'), 'primaryDiagnostic', {get() {assert.fail('no getter');}});
  assert.equal(snapshot(accessor).primaryDiagnostic, undefined);
  const model = {code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
    kind: 'original_sources.missing', task: 1, unit: 2, step: 3};
  assert.deepEqual(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: model})).primaryDiagnostic, model);
});

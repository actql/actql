import assert from 'node:assert/strict';
import test from 'node:test';
import './effective-memory-projection.test.mjs';
import {snapshotRequestMemory, localResourceResultReadLimits} from './installed-host-policy.mjs';
import {beginOrdinaryHostControl, ordinaryHostControlInput} from './ordinary-host-control.mjs';
import {openRequestPreparation, cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';
import resources from './ordinary-node-resource-runtime.cjs';

test('installed memory pair is detached once before await and survives equal Saved configuration', async () => {
  const originals = {host: {}, installation: {}, generation: {}, supplier: {}, moduleLifetime: {}};
  let reads = 0, retained = 67108864, execution = 134217728;
  const selected = {get retainedBytes() {reads++; return retained;},
    get executionBytes() {reads++; return execution;}};
  const scope = beginOrdinaryHostControl(originals, {installation: {requestMemory: selected}});
  retained = execution = 1;
  await Promise.resolve();
  const actual = ordinaryHostControlInput(scope, originals).installation.requestMemory;
  assert.deepEqual(actual, {retainedBytes: 67108864, executionBytes: 134217728});
  assert(Object.isFrozen(actual)); assert.notStrictEqual(actual, selected);
  assert.strictEqual(snapshotRequestMemory(actual), actual); assert.equal(reads, 2);
  const policy = {}, calls = [];
  const moon = {clientLocalResourcePolicyOriginal: () => policy,
    clientLocalPreparationResourceLimits(original, r, e) {
      assert.strictEqual(original, policy); calls.push([r, e]);
      return [1n, 1n, 1n, 20000000n, r ?? 536870912n, e ?? 536870912n];
    }, clientLocalResourcePolicyRowCeiling: () => 1000000};
  const first = localResourceResultReadLimits(moon, actual);
  assert.deepEqual(localResourceResultReadLimits(moon, {...actual}), first);
  assert.equal(first.maxRetainedValueBytes, 67108864);
  assert.equal(first.maxRowRetainedValueBytes, 1048576);
  assert.equal(first.maxBatchRetainedValueBytes, 10485760);
  assert.equal(localResourceResultReadLimits(moon).maxRetainedValueBytes, 536870912);
  assert.deepEqual(calls, [[67108864n,134217728n], [67108864n,134217728n], [undefined,undefined]]);
  assert.equal((await scope.close()).pending, false);
});

test('memory snapshot rejects partial and inexact representation without inventing Core positivity rules', () => {
  for (const value of [null, [], {}, {retainedBytes: 1},
    {retainedBytes: 1, executionBytes: '2'}, {retainedBytes: NaN, executionBytes: 2},
    {retainedBytes: Number.MAX_SAFE_INTEGER + 1, executionBytes: 2},
    {retainedBytes: -0, executionBytes: 2}, {retainedBytes: 1, executionBytes: 2, extra: 3}]) {
    assert.throws(() => snapshotRequestMemory(value), {code: 'InvalidInstalledRequestMemory'});
  }
  // The actual Common projection, not this representation bridge, rejects zero/negative limits.
  assert.deepEqual(snapshotRequestMemory({retainedBytes: 0, executionBytes: -1}),
    {retainedBytes: 0, executionBytes: -1});
});

test('same original Resource supplier receives the Core pair once and cannot be reopened or resized', () => {
  // Actual Resource supplier/adapter; Core phase results are explicit doubles.
  // Real Common admission and tariff coverage is in the MoonBit components.
  const policy = {}, parent = {}, input = {}, calls = []; let admission;
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientLocalResourcePolicyOriginal: () => policy,
    clientLocalPreparationResourceLimits(original, r, e) {
      assert.strictEqual(original, policy); calls.push([r, e]); return [100n,100n,100n,1000n,r,e];
    },
    clientProgramPrepareLocalPreparationAdmission(original, actual) {
      assert.strictEqual(actual, input);
      admission = {original, ports: resources.prepareOriginalLocalPreparationPorts(original, actual)};
      return ok(admission);
    },
    clientProgramBeginRequestPreparation(actual, receipt, selected) {
      assert.strictEqual(actual, admission); assert.strictEqual(receipt, input);
      assert.strictEqual(selected, policy); assert.equal(actual.ports.status(0), 0); return ok(parent);
    },
    clientProgramAbortRequestPreparation(actual) {
      assert.strictEqual(actual, parent);
      assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0), 0);
      assert.equal(admission.ports.status(2), 0); return ok(undefined);
    },
  };
  const memory = snapshotRequestMemory({retainedBytes: 67108864, executionBytes: 134217728});
  const state = {context: Object.freeze({runtime: moon, requestMemory: memory})};
  assert.strictEqual(openRequestPreparation(state, input, () => {}, () => false), parent);
  assert.deepEqual(calls, [[67108864n,134217728n]]);
  assert.equal(admission.ports.limit(4), 67108864n);
  assert.equal(admission.ports.limit(5), 134217728n);
  assert.throws(() => openRequestPreparation(state, input, () => {}, () => false),
    {code: 'NodeLocalPreparationAdmissionUnavailable'});
  assert.equal(admission.ports.report(0,0,0,0n,0n,0n,67108865n,0n,0n,67108865n,0,0,0), -42);
  const original = state.original;
  cleanupRequestInput(state);
  assert.equal(resources.ordinaryManagedRunStatus(original).stopped, true);
  assert.equal(state.original, undefined); assert.equal(calls.length, 1);
});

test('Request memory ingress refuses frozen accessors and proxies before callbacks or supplier entry', () => {
  let touched = 0;
  const memoryAccessor = Object.freeze({get retainedBytes() {touched++; return 1;}, executionBytes: 1});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {touched++; throw Error('trap');},
    isExtensible() {touched++; throw Error('trap');}});
  const runtime = {clientLocalResourcePolicyOriginal() {assert.fail('supplier entered');}};
  const contexts = [{runtime, requestMemory: memoryAccessor}, {runtime, requestMemory: proxy},
    {runtime, get requestMemory() {touched++; return undefined;}}];
  for (const context of contexts) assert.throws(() => openRequestPreparation(
    {context}, {}, () => {}, () => false), {code: 'NodeLocalPreparationAdmissionUnavailable'});
  assert.equal(touched, 0);
});

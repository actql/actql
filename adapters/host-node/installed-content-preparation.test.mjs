import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeContentRun} from './installed-content-run.mjs';

function fixture(keyed = false) {
  const preparedProgram = Object.freeze({}), compiled = Object.freeze({});
  const plan = Object.freeze({kind: 'serialization', compiled,
    serializationGraph: Object.freeze({task: 0, step: 1}), runDefinition: Object.freeze({})});
  let currentFailure, constructionFailure, ledgerCount = 0, acquisitions = 0, quotes = 0;
  let currentCalls = 0, failAt;
  const request = {scope: 'sha256:' + 'a'.repeat(64), intent: 'sha256:' + 'b'.repeat(64)},
    ledger = {}, direct = {}, acquisition = {}, capacity = {};
  let retainedRecipe, keyedPreparations = 0, keyedBorrows = 0, keyedFailure;
  const current = () => {
    currentCalls++;
    if (currentFailure !== undefined && (failAt === undefined || currentCalls === failAt)) throw currentFailure;
  };
  const run = installNodeContentRun({moon: {
    clientRequestScopeCid: value => value.scope,
    clientRequestIntentCid: value => value.intent,
    clientProgramAcquisitionCount(value) {assert.strictEqual(value, preparedProgram); return acquisitions;},
    clientProgramAcquisitionLedger(attempts, holdings, transfer, retained, execution, planning) {
      assert.deepEqual([attempts, holdings, transfer, retained, execution, planning], [1, 0, 0n, 13n, 19n, 0]);
      ledgerCount++;
      if (constructionFailure !== undefined) throw constructionFailure;
      return {$tag: 1, _0: Object.freeze({})};
    },
  }, core: {
    contentGenerationControl: {
      workspaceCapacity: () => Object.freeze({retainedBytes: 3n, executionBytes: 5n}),
      prefixCapacity(program, task, step) {
        assert.strictEqual(program, preparedProgram); assert.deepEqual([task, step], [0, 1]);
        quotes++; return Object.freeze({retainedBytes: 13n, executionBytes: 19n});
      },
    },
    publicationControl: {checkClientCompiledRunOwner(value, program) {
      assert.strictEqual(value, compiled); assert.strictEqual(program, preparedProgram);
    }},
  }, registry: '{}', values: '{}', ownerPrincipal: 'fixture', preparedRunRequired: true,
  assertRunCurrent: current,
  ...(keyed ? {prepareKeyedManagedRun(prepared, actualRequest, recipe) {
    assert.strictEqual(prepared, preparedProgram); assert.strictEqual(actualRequest, request);
    assert.equal(recipe.task, 0); assert.equal(recipe.step, 1);
    assert.equal(recipe.prefixRetainedBytes, 13n); assert.equal(recipe.prefixExecutionBytes, 19n);
    assert.equal(Object.isFrozen(recipe), true);
    retainedRecipe = recipe; keyedPreparations++;
    if (keyedFailure !== undefined) throw keyedFailure;
  }, borrowKeyedManagedLedger(prepared, actualRequest, recipe, actualDirect, actualAcquisition, actualCapacity) {
    assert.strictEqual(prepared, preparedProgram); assert.strictEqual(actualRequest, request);
    assert.strictEqual(recipe, retainedRecipe); assert.strictEqual(actualDirect, direct);
    assert.strictEqual(actualAcquisition, acquisition); assert.strictEqual(actualCapacity, capacity);
    keyedBorrows++; return ledger;
  }} : {})});
  return {run, preparedProgram, plan, counts: () => ({ledgerCount, quotes}),
    failCurrent(error) {currentFailure = error;},
    failCurrentAt(count, error) {failAt = count; currentFailure = error;},
    failConstruction(error) {constructionFailure = error;},
    acquisitions(count) {acquisitions = count;},
    request, ledger, direct, acquisition, capacity,
    keyedCounts: () => ({keyedPreparations, keyedBorrows}),
    failKeyed(error) {keyedFailure = error;}};
}

test('ordinary keyed Content borrows its admitted original Run without a standalone Ledger', () => {
  const f = fixture(true);
  f.run.prepareManagedKeyedRun(f); f.run.prepareManagedKeyedRun(f);
  assert.strictEqual(f.run.prepareKeyedLedger({...f, capturedContent: true}), f.ledger);
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 1});
  assert.deepEqual(f.keyedCounts(), {keyedPreparations: 1, keyedBorrows: 1});
  assert.throws(() => f.run.prepareManagedKeyedRun({...f, request: {}}), {message: 'ForeignInstalledContentRun'});
  assert.throws(() => f.run.prepareKeyedLedger({...f, plan: {...f.plan}, capturedContent: true}),
    {message: 'InstalledContentRunPreparationUnavailable'});
});

test('ordinary keyed Content reuses a checked request projection without reissuing the original', () => {
  const f = fixture(true);
  f.run.prepareManagedKeyedRun(f);
  f.run.prepareManagedKeyedRun({...f, request: {...f.request}});
  assert.deepEqual(f.keyedCounts(), {keyedPreparations: 1, keyedBorrows: 0});
  assert.throws(() => f.run.prepareManagedKeyedRun({...f,
    request: {...f.request, intent: 'sha256:' + 'c'.repeat(64)}}), {message: 'ForeignInstalledContentRun'});
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 1});
});

test('ordinary keyed Content never obtains a scalar fallback before its actual preparation', () => {
  const f = fixture(true);
  assert.throws(() => f.run.prepareKeyedLedger({...f, capturedContent: true}),
    {message: 'InstalledContentRunPreparationUnavailable'});
  const missing = fixture();
  assert.throws(() => missing.run.prepareManagedKeyedRun(missing),
    {message: 'InstalledContentRunPreparationUnavailable'});
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 0});
  assert.deepEqual(missing.counts(), {ledgerCount: 0, quotes: 0});
});

test('ordinary keyed Content retains the original preparation failure without reissuing', () => {
  const f = fixture(true), failure = new Error('partial Content admission');
  f.failKeyed(failure);
  assert.throws(() => f.run.prepareManagedKeyedRun(f), error => error === failure);
  f.failKeyed(undefined);
  assert.throws(() => f.run.prepareManagedKeyedRun(f), error => error === failure);
  assert.deepEqual(f.keyedCounts(), {keyedPreparations: 1, keyedBorrows: 0});
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 1});
});

test('ordinary Content prepares the same checked Run once and refuses a copied plan', () => {
  const f = fixture();
  f.run.prepareRun(f);
  f.run.prepareRun(f);
  assert.deepEqual(f.counts(), {ledgerCount: 1, quotes: 1});
  assert.throws(() => f.run.prepareRun({...f, plan: {...f.plan}}), {message: 'ForeignInstalledContentRun'});
  assert.deepEqual(f.counts(), {ledgerCount: 1, quotes: 1});
});

test('ordinary Content refuses unsupported Source shape before constructing its limits', () => {
  const f = fixture(); f.acquisitions(1);
  assert.throws(() => f.run.prepareRun(f), {message: 'InstalledContentRunPreparationUnsupported'});
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 0});
});

test('ordinary Content preserves the original preparation failure without a new Ledger attempt', () => {
  const f = fixture(), original = new Error('OriginalManagedLimitConstructionFailure');
  f.failConstruction(original);
  assert.throws(() => f.run.prepareRun(f), error => error === original);
  f.failConstruction(undefined);
  assert.throws(() => f.run.prepareRun(f), error => error === original);
  assert.deepEqual(f.counts(), {ledgerCount: 1, quotes: 1});
});

test('ordinary Content currentness refuses before quote and cannot be replaced by plan equality', () => {
  const f = fixture(), original = new Error('OriginalHostClosing');
  f.failCurrent(original);
  assert.throws(() => f.run.prepareRun(f), error => error === original);
  assert.deepEqual(f.counts(), {ledgerCount: 0, quotes: 0});
});

test('ordinary Content retains post-construction current failure without issuing a replacement', () => {
  const f = fixture(), original = new Error('OriginalCurrentChangedDuringConstruction');
  f.failCurrentAt(2, original);
  assert.throws(() => f.run.prepareRun(f), error => error === original);
  f.failCurrent(undefined);
  assert.throws(() => f.run.prepareRun(f), error => error === original);
  assert.deepEqual(f.counts(), {ledgerCount: 1, quotes: 1});
});

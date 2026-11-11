import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {ledgerUsageSnapshot, ledgerUsageSnapshotHasPendingResources} from '../host-common/runtime-core.mjs';
import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';

// Execute the actual entry, handoff and cleanup coordination with explicit
// nominal/physical ports. This does not start a Runtime or prove a Host/FD ACK.
function source(path) {
  const text = readFileSync(new URL(path, import.meta.url), 'utf8');
  return {text, tree: parse(text, {ecmaVersion: 'latest', sourceType: 'module'})};
}
const entry = source('./entry.mjs');
const acquired = source('./acquired-effect-computation.mjs');
const strategy = source('../host-common/strategy.mjs');
function select(original, predicate) {
  const found = [];
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (predicate(node)) found.push(node);
    for (const value of Object.values(node)) {
      for (const child of Array.isArray(value) ? value : [value]) visit(child);
    }
  }
  visit(original.tree);
  assert.equal(found.length, 1);
  return found[0];
}
function fn(original, name, ports) {
  const node = select(original, node => node.type === 'FunctionDeclaration' && node.id.name === name);
  return new Function(...Object.keys(ports), `return (${original.text.slice(node.start, node.end)});`)(...Object.values(ports));
}
function variable(original, name) {
  const node = select(original, node => node.type === 'VariableDeclarator' && node.id.name === name);
  return `const ${original.text.slice(node.start, node.end)};`;
}
function effectEntry(runCapturedStrategyTarget) {
  const target = fn(entry, 'runCapturedEffectComputationTarget', {runCapturedStrategyTarget});
  return fn(entry, 'createNodeHostEntry', {runCapturedEffectComputationTarget: target});
}

test('Effect preflight passes the original installed receiver without consuming options as custody', async () => {
  const owner = {}, setup = {}, child = {}, holder = {}, signal = new AbortController().signal;
  const cleanup = Object.freeze({preparationHolder: holder,
    retainPreflightCleanup(actual) {assert.strictEqual(actual, child);}});
  const poison = {get retainPreflightCleanup() {assert.fail('options cannot replace installed custody');}};
  let loads = 0, calls = 0;
  const moon = {clientProgramLocalEffectHostRuntime(actual) {assert.strictEqual(actual, owner);return setup;},
    strategyHostHasEffects(actual) {assert.strictEqual(actual, setup);return true;}};
  const installed = effectEntry(facts => {
    calls++;
    assert.strictEqual(facts.setup, setup);assert.strictEqual(facts.control.signal, signal);
    assert.strictEqual(facts.cleanup, cleanup);assert.notStrictEqual(facts.cleanup, facts.options.cleanup);
    assert.equal(facts.results.publishCheckedResults, false);
    facts.cleanup.retainPreflightCleanup(child);
    return child;
  })(async () => {loads++;return moon;}, () => assert.fail('no runtime installation in this control'));
  assert.strictEqual(await installed.runCapturedEffectComputation(owner, {cleanup: poison}, signal, undefined, cleanup), child);
  assert.deepEqual({loads, calls}, {loads: 1, calls: 1});
});

test('an invalid captured Effect owner cannot issue a preflight cleanup handoff', async () => {
  let handoffs = 0, starts = 0;
  const installed = effectEntry(() => {starts++;})(async () => ({
    clientProgramLocalEffectHostRuntime() {throw new Error('ForeignOriginal');},
  }), () => assert.fail('no installation'));
  await assert.rejects(installed.runCapturedEffectComputation({}, {}, undefined, undefined,
    {retainPreflightCleanup() {handoffs++;}}), /InvalidCapturedEffectComputation/);
  assert.deepEqual({handoffs, starts}, {handoffs: 0, starts: 0});
});

function cleanupFixture({stopUnknown = false, sitePending = false, handoff = true} = {}) {
  const events = [], setup = {}, captured = {}, primary = new Error('OriginalSiteInstallationRefusal');
  const stopFailure = new Error('OriginalStopUnknown');
  let parent, releaseStop = !stopUnknown, releaseSite = !sitePending, savedReceiver, child;
  const active = new Set([setup]), releasedPreflightSetups = new WeakSet();
  class StrategyHostError extends Error {}
  const preflightSetupCleanup = fn(strategy, 'preflightSetupCleanup', {
    StrategyHostError, active, releasedPreflightSetups, ledgerUsageSnapshotHasPendingResources,
  });
  const rejectSetupPreflight = fn(strategy, 'rejectSetupPreflight', {
    preflightSetupCleanup, active,
    ownedStrategyFailure(reason) {return Object.assign(new Error('OwnedPreflightFailure', {cause: reason}),
      {primaryFailure: reason, cleanupErrors: []});},
    failureMember: (value, key) => value?.[key],
  });
  const core = {
    stop(actual) {assert.strictEqual(actual, setup);events.push('stop');if (!releaseStop) throw stopFailure;},
    closeOutputs(actual) {assert.strictEqual(actual, setup);events.push('outputs');},
    usage(actual) {assert.strictEqual(actual, setup);return ledgerUsageSnapshot(ledgerUsageFields.map(() => 0n));},
  };
  const siteCleanup = {status: () => ({pending: !releaseSite}), retry() {events.push('site');}};
  const parameters = {captures: [{async close() {events.push('capture');}}],
    moon: {clientProgramRefreshAcquiredEffectCleanup(actual) {
      assert.strictEqual(actual, setup);assert(releasedPreflightSetups.has(setup));
      events.push('refresh');return true;
    }},
    async cleanupInfer() {return true;}, observeUsage() {},
    sourceContinuation: {async close() {events.push('continuation');}},
    async runCapturedEffectComputation(actual, options, signal, observer, cleanup) {
      assert.strictEqual(actual, setup);events.push('entry');savedReceiver = cleanup?.retainPreflightCleanup;
      if (!handoff) throw primary;
      return rejectSetupPreflight({primary, core, setup, siteCleanup,
        retainPreflightCleanup(owner) {
          child = owner;events.push('handoff');
          assert(parent.cleanupPending());assert(active.has(setup));
          savedReceiver(owner);
        }});
    }, setup, captured,
  };
  const assignment = select(acquired, node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.name === 'execution' &&
    node.expression.right.type === 'AwaitExpression' &&
    node.expression.right.argument.callee?.name === 'runCapturedEffectComputation');
  const body = `let execution,recovery,inferCapture,inferOperation,modelContinuation,modelToken,
    modelGroup,contentFamilyCleanup,contentFamily,contentRecovery,restoredModelOutput,keyedCleanup,
    originalPreparation,originalPreparationRetained=false,restoredModelHostAttempted=false;
    let checkedHost=setup,unresolved=true,pending=true,settled=false,closed=false;
    const managedRun={},configurations={},multiple=false,singleSourceAccess=undefined,signal=undefined;
    ${variable(acquired, 'custody')}
    ${variable(acquired, 'retainPreflightCleanup')}
    return {custody, async start() {try {${acquired.text.slice(assignment.start, assignment.end)}
      unresolved=false;} finally {settled=true;}}};`;
  const harness = new Function(...Object.keys(parameters), body)(...Object.values(parameters));
  parent = harness.custody;
  return {...harness, events, primary, stopFailure,
    release() {releaseStop = true;releaseSite = true;},
    child: () => child, receiver: () => savedReceiver,
    stopped: () => releasedPreflightSetups.has(setup)};
}

test('Effect preflight retains its real setup owner before stop and releases captured Source only after it', async () => {
  const f = cleanupFixture();
  await assert.rejects(f.start(), error => error === f.primary);
  assert.deepEqual(f.events, ['entry', 'handoff', 'stop', 'outputs']);
  assert.equal(await f.custody.cleanup(), false, 'settlement is not first close');
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);assert.equal(f.custody.cleanupPending(), false);
  assert.deepEqual(f.events, ['entry', 'handoff', 'stop', 'outputs', 'capture', 'refresh', 'continuation']);
  assert.equal(await f.custody.cleanup(), true);
  assert.throws(() => f.receiver()({}), /CleanupAlreadyRetained/);
});

for (const mode of ['stopUnknown', 'sitePending']) test(`Effect preflight ${mode} keeps the same Source and pending child`, async () => {
  const f = cleanupFixture({[mode]: true});
  await assert.rejects(f.start(), error => error.primaryFailure === f.primary && error.cleanupHandle === f.child());
  await assert.rejects(f.custody.close());
  if (mode === 'stopUnknown') await assert.rejects(f.custody.cleanup(), error => error === f.stopFailure);
  else await assert.rejects(f.custody.cleanup(), /ExecutionSiteCleanupPending/);
  assert.equal(f.custody.cleanupPending(), true);assert.equal(f.stopped(), false);
  assert(!f.events.includes('capture'));assert(!f.events.includes('refresh'));
  assert.throws(() => f.receiver()({}), /CleanupAlreadyRetained/);
  f.release();assert.equal(await f.custody.cleanup(), true);
  assert.equal(f.custody.cleanupPending(), false);assert.equal(f.stopped(), true);
  assert.equal(f.events.filter(value => value === 'capture').length, 1);
  assert.equal(f.events.filter(value => value === 'outputs').length, 1);
});

test('an exception without the installed preflight handoff cannot release an unresolved Compute', async () => {
  const f = cleanupFixture({handoff: false});
  await assert.rejects(f.start(), error => error === f.primary);
  await f.custody.close();assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.custody.cleanupPending(), true);assert.deepEqual(f.events, ['entry']);
  assert.equal(f.child(), undefined);assert.equal(f.stopped(), false);
});

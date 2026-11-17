import assert from 'node:assert/strict';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {closeManagedFixtureExecution, managedFixtureCleanupDiagnostic} from './managed-fixture-cleanup.mjs';

function fixture(reason = new Error('LocalManagedOutputCleanupPending')) {
  let released = false, closes = 0, cleanups = 0;
  const handle = {status: () => ({pending: !released}),
    retry() { assert.fail('The fixture consumer must use the execution recovery owner'); }};
  const inner = Object.assign(new Error('ManagedExecutionFailed', {cause: reason}),
    {code: 'ManagedExecutionFailed', primaryFailure: reason,
      cleanupErrors: [], cleanupPending: true, cleanupHandle: handle});
  const failure = Object.assign(new Error('ManagedInputReleaseFailed', {cause: inner}),
    {code: 'ManagedInputReleaseFailed', primaryFailure: inner,
      cleanupErrors: [inner], cleanupPending: true, cleanupHandle: handle});
  const execution = {completed: [{task: 1}],
    usage: () => ({attempts: 4n, reservedExecutionBytes: released ? 0n : 128n}),
    async close() { closes++; throw failure; },
    async cleanup() {
      cleanups++;
      if (cleanups === 4) { released = true; inner.cleanupPending = false; }
      return released;
    }, cleanupPending: () => !released};
  return {execution, failure, counts: () => ({closes, cleanups})};
}

test('fixture cleanup retains its first bounded-pending error and uses only explicit recovery', async () => {
  const f = fixture();
  const result = await closeManagedFixtureExecution(f.execution, 60000);
  assert.equal(result.firstCloseFailure, f.failure);
  assert.equal(result.cleanupAttempts, 4);
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 4});
  assert.equal(f.failure.cause.primaryFailure.message, 'LocalManagedOutputCleanupPending');
});

test('fixture cleanup rejects a physical exception hidden under the same outer classification', async () => {
  const f = fixture(new Error('PhysicalReleaseUnavailable'));
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.equal(error.errors[0], f.failure);
    assert.equal(error.errors[1].code, 'ERR_ASSERTION');
    return true;
  });
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 0});
});

test('fixture cleanup retains the original pending failure when explicit recovery rejects', async () => {
  const f = fixture(), recoveryFailure = new Error('RecoveryUnavailable');
  f.execution.cleanup = async () => { throw recoveryFailure; };
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.deepEqual(error.errors, [f.failure, recoveryFailure]);
    return true;
  });
  assert.equal(f.execution.cleanupPending(), true);
  assert.equal(f.counts().closes, 1);
});

test('fixture pending diagnostics retain closed codes without exposing primary values or invoking getters',()=>{
  const primary=Object.assign(new Error('raw rows must not print'),{code:'private-value',actual:'private-key'});
  const classified=Object.assign(new Error('arbitrary message'),{code:'ERR_ASSERTION'});
  assert.equal(managedFixtureCleanupDiagnostic(new AggregateError([primary,classified])), 'AggregateError/Error/ERR_ASSERTION');
  assert.equal(managedFixtureCleanupDiagnostic(undefined),'undefined/none/none');
  let reads=0;const accessor={get code(){reads++;throw Error('must not run');},get errors(){reads++;throw Error('must not run');}};
  assert.equal(managedFixtureCleanupDiagnostic(accessor),'opaque/none/none');assert.equal(reads,0);
  const proxy=new Proxy({}, {getOwnPropertyDescriptor(){throw undefined;}});
  assert.equal(managedFixtureCleanupDiagnostic(proxy),'opaque');
});

function originalFixtureAssertion(file = 'retained-values-chain.test.mjs') {
  try {
    runInNewContext('assert.equal("hidden-row", "hidden-key")', {assert}, {
      filename: `file:///fixture/adapters/connectors/duckdb/node/test/${file}`,
    });
  } catch (error) { return error; }
  assert.fail('the original assertion must fail');
}

test('fixture pending diagnostics identify the original assertion site and operator without operand data', () => {
  const error = originalFixtureAssertion();
  const diagnostic = managedFixtureCleanupDiagnostic(error);
  assert.match(diagnostic, /^ERR_ASSERTION@retained-values-chain\.test\.mjs:\d+:\d+:strictEqual\/none\/none$/u);
  for (const value of ['hidden-row', 'hidden-key', 'file://', '/fixture/']) {
    assert.equal(diagnostic.includes(value), false);
  }
  assert.equal(error.actual, 'hidden-row');
  assert.equal(error.expected, 'hidden-key');
  const second = originalFixtureAssertion('managed-fixture-cleanup.mjs');
  assert.match(managedFixtureCleanupDiagnostic(new AggregateError([error, second])),
    /^AggregateError\/ERR_ASSERTION@retained-values-chain\.test\.mjs:\d+:\d+:strictEqual\/ERR_ASSERTION@managed-fixture-cleanup\.mjs:\d+:\d+:strictEqual$/u);
});

test('fixture assertion sites refuse foreign frames, accessors and custom stack formatters', () => {
  assert.equal(managedFixtureCleanupDiagnostic(originalFixtureAssertion('foreign.mjs')), 'ERR_ASSERTION/none/none');
  let reads = 0;
  const accessor = originalFixtureAssertion();
  Object.defineProperty(accessor, 'stack', {get() { reads++; throw Error('must not run'); }});
  assert.equal(managedFixtureCleanupDiagnostic(accessor), 'ERR_ASSERTION/none/none');
  const message = originalFixtureAssertion();
  Object.defineProperty(message, 'message', {get() { reads++; throw Error('must not run'); }});
  assert.equal(managedFixtureCleanupDiagnostic(message), 'ERR_ASSERTION/none/none');
  const original = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
  const formatted = originalFixtureAssertion();
  try {
    Object.defineProperty(Error, 'prepareStackTrace', {configurable: true,
      get() { reads++; throw Error('must not run'); }});
    assert.equal(managedFixtureCleanupDiagnostic(formatted), 'ERR_ASSERTION/none/none');
    Object.defineProperty(Error, 'prepareStackTrace', {configurable: true,
      value() { reads++; throw Error('must not run'); }});
    assert.equal(managedFixtureCleanupDiagnostic(formatted), 'ERR_ASSERTION/none/none');
  } finally {
    if (original) Object.defineProperty(Error, 'prepareStackTrace', original);
    else delete Error.prepareStackTrace;
  }
  assert.equal(reads, 0);
});

test('fixture assertion sites ignore operand frames, unknown operators and oversized stacks', () => {
  const injected = new assert.AssertionError({actual: 1, expected: 2, operator: 'strictEqual',
    message: 'hidden\n    at file:///fixture/adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs:999:8'});
  assert.equal(managedFixtureCleanupDiagnostic(injected), 'ERR_ASSERTION/none/none');
  const operator = originalFixtureAssertion();
  operator.operator = 'hidden-operator';
  assert.equal(managedFixtureCleanupDiagnostic(operator), 'ERR_ASSERTION/none/none');
  const oversized = originalFixtureAssertion();
  Object.defineProperty(oversized, 'stack', {value: 'x'.repeat(32769)});
  assert.equal(managedFixtureCleanupDiagnostic(oversized), 'ERR_ASSERTION/none/none');
});

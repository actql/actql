import assert from 'node:assert/strict';
import {setTimeout as yieldCleanup} from 'node:timers/promises';
import {types} from 'node:util';

const nativeStackGetter = Object.getOwnPropertyDescriptor(new Error(), 'stack')?.get;
const originalStackFormatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
const assertionOperators = new Set(['strictEqual', 'deepStrictEqual', '==', 'fail', 'match']);
const fixtureFrame = /^\s+at .*\/adapters\/connectors\/duckdb\/node\/test\/(retained-values-chain\.test\.mjs|managed-fixture-cleanup\.mjs):(\d{1,5}):(\d{1,4})\)?$/u;

// Only the two fixture locations and a closed assertion operator escape.
// Never invoke a supplied stack/message accessor or a custom stack formatter.
function fixtureAssertionSite(error) {
  try {
    if (!types.isNativeError(error) || Object.getPrototypeOf(error) !== assert.AssertionError.prototype ||
        Object.getOwnPropertyDescriptor(error, 'code')?.value !== 'ERR_ASSERTION') return '';
    const operator = Object.getOwnPropertyDescriptor(error, 'operator')?.value;
    if (!assertionOperators.has(operator)) return '';
    const formatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
    if ((formatter && !Object.hasOwn(formatter, 'value')) ||
        (originalStackFormatter && !Object.hasOwn(originalStackFormatter, 'value')) ||
        formatter?.value !== originalStackFormatter?.value) return '';
    for (const object of [error, assert.AssertionError.prototype, Error.prototype]) {
      for (const name of ['name', 'message', 'constructor']) {
        const property = Object.getOwnPropertyDescriptor(object, name);
        if (property && !Object.hasOwn(property, 'value')) return '';
      }
    }
    const message = Object.getOwnPropertyDescriptor(error, 'message')?.value;
    if (typeof message !== 'string' || message.length > 32768) return '';
    const descriptor = Object.getOwnPropertyDescriptor(error, 'stack');
    let stack = descriptor?.value;
    if (stack === undefined && nativeStackGetter && descriptor?.get === nativeStackGetter) {
      stack = Reflect.apply(nativeStackGetter, error, []);
    }
    if (typeof stack !== 'string' || stack.length > 32768) return '';
    const header = stack.indexOf(message);
    if (header < 0) return '';
    // Skip the complete original message, including any operand newlines.
    for (const line of stack.slice(header + message.length).split('\n').slice(0, 16)) {
      const frame = fixtureFrame.exec(line);
      if (frame) return `@${frame[1]}:${Number(frame[2])}:${Number(frame[3])}:${operator}`;
    }
  } catch { /* An unavailable location never changes the original failure. */ }
  return '';
}

// Fixture consumer for the existing explicit recovery contract. A bounded
// admission-scratch retirement can outlive close; this is not permission to
// ignore a physical release exception, retry a finalizer, or repeat Compute.
function assertBoundedManagedReleasePending(error) {
  assert.equal(error?.code, 'ManagedInputReleaseFailed');
  assert.equal(error.message, 'ManagedInputReleaseFailed');
  assert.equal(error.cleanupPending, true);
  const failure = error.cause;
  assert.equal(error.primaryFailure, failure);
  assert.equal(failure?.code, 'ManagedExecutionFailed');
  assert.equal(failure.message, 'ManagedExecutionFailed');
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cause, failure.primaryFailure);
  assert.equal(failure.primaryFailure?.message, 'LocalManagedOutputCleanupPending');
  assert.deepEqual(failure.cleanupErrors, []);
  assert.deepEqual(error.cleanupErrors, [failure]);
  assert.equal(typeof error.cleanupHandle?.retry, 'function');
  assert.equal(error.cleanupHandle.status().pending, true);
  return failure.primaryFailure;
}

export async function closeManagedFixtureExecution(execution, timeoutMs) {
  assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 60000);
  const deadline = performance.now() + timeoutMs;
  const attempts = execution.usage().attempts;
  const completed = execution.completed.map(value => value.task);
  let firstCloseFailure, pendingReason;
  try { await execution.close(); }
  catch (error) {
    // Preserve the original error on any unexpected envelope. The caller's
    // finally still closes its separately owned acquisition.
    try { pendingReason = assertBoundedManagedReleasePending(error); }
    catch (classification) {
      throw new AggregateError([error, classification], 'Unexpected fixture release failure');
    }
    firstCloseFailure = error;
  }
  let cleanupAttempts = 0;
  try {
    for (;;) {
      assert.ok(performance.now() < deadline, 'Managed fixture cleanup deadline expired');
      const cleaned = await execution.cleanup();
      cleanupAttempts++;
      assert.ok(performance.now() < deadline, 'Managed fixture cleanup deadline expired');
      assert.equal(execution.usage().attempts, attempts, 'cleanup must not start another attempt');
      assert.deepEqual(execution.completed.map(value => value.task), completed,
        'cleanup must not produce another completion');
      if (cleaned) break;
      assert.equal(execution.cleanupPending(), true);
      await yieldCleanup(10);
    }
    assert.equal(execution.cleanupPending(), false);
    assert.equal(execution.usage().reservedExecutionBytes, 0n);
    if (firstCloseFailure) {
      assert.equal(firstCloseFailure.cause.primaryFailure, pendingReason);
      assert.equal(firstCloseFailure.cause.cause, pendingReason);
      assert.equal(firstCloseFailure.cleanupHandle.status().pending, false);
      assert.deepEqual(firstCloseFailure.cause.cleanupErrors, []);
      console.log('ACTQL_MANAGED_FIXTURE_CLEANUP', JSON.stringify({
        firstCloseFailure: firstCloseFailure.code,
        primaryFailure: pendingReason.message, cleanupAttempts,
      }));
    }
  } catch (error) {
    throw new AggregateError(firstCloseFailure ? [firstCloseFailure, error] : [error],
      'Managed fixture cleanup did not complete');
  }
  return Object.freeze({firstCloseFailure, cleanupAttempts});
}

// Closed fixture diagnostics only. Never emit messages, stacks, assertion
// values or arbitrary error codes from the retained primary/cleanup originals.
export function managedFixtureCleanupDiagnostic(error) {
  const own=(value,key)=>value!==null&&(typeof value==='object'||typeof value==='function')
    ?Object.getOwnPropertyDescriptor(value,key)?.value:undefined;
  const known=new Set(['ManagedInputReleaseFailed','ManagedExecutionFailed',
    'LocalManagedOutputCleanupPending','ExecutionSiteCleanupPending',
    'ERR_ASSERTION','RunHostTaskInvocationRejected','CapturedRunExecutionFailed']);
  const kind=value=>{
    if(value===undefined)return 'undefined';
    if(value===null)return 'null';
    try {
      const code=own(value,'code');if(known.has(code))return code === 'ERR_ASSERTION'
        ? code + fixtureAssertionSite(value) : code;
      const name=own(value,'name');
      if(['AbortError','AssertionError','TypeError','RangeError'].includes(name))return name;
      if(value instanceof AggregateError)return 'AggregateError';
      if(value instanceof Error)return 'Error';
    }catch{return 'opaque';}
    return 'opaque';
  };
  try {
    const errors=own(error,'errors');
    return [kind(error),Array.isArray(errors)?kind(own(errors,'0')):'none',
      Array.isArray(errors)&&errors.length>1?kind(own(errors,String(errors.length-1))):'none'].join('/');
  }catch{return 'opaque';}
}

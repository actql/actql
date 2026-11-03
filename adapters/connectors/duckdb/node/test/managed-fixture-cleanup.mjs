import assert from 'node:assert/strict';
import {setTimeout as yieldCleanup} from 'node:timers/promises';

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
      const code=own(value,'code');if(known.has(code))return code;
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
